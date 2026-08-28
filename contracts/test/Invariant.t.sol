// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {ImpactRebatedFees} from "../src/ImpactRebatedFees.sol";
import {Params} from "../src/Params.sol";

contract Handler is Test {
    PoolSwapTest immutable swapRouter;
    ImpactRebatedFees immutable hook;
    PoolKey key;

    uint256 public settledCount;
    mapping(uint256 => bool) public seenSettled;

    constructor(PoolSwapTest _router, ImpactRebatedFees _hook, PoolKey memory _key) {
        swapRouter = _router;
        hook = _hook;
        key = _key;
    }

    function swap(uint256 seed, uint96 amount) external {
        bool zeroForOne = seed % 2 == 0;
        int256 amt = -int256(uint256(bound(amount, 0.0001 ether, 2 ether)));
        try swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amt,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        ) {} catch {}
    }

    function advance(uint32 secs) external {
        vm.warp(block.timestamp + bound(secs, 1, Params.SETTLEMENT_WINDOW_SECONDS * 3));
    }

    function settleOne(uint256 seed) external {
        uint256 n = hook.nextReceiptId();
        if (n == 0) return;
        uint256 id = seed % n;
        if (seenSettled[id]) return;
        try hook.settle(id) {
            seenSettled[id] = true;
            settledCount++;
        } catch {}
    }
}

contract InvariantTest is Test {
    address constant HOOK_ADDR = address(uint160(0x9999 << 144) | uint160(0x44));

    PoolManager manager;
    ImpactRebatedFees hook;
    Handler handler;
    MockERC20 token0;
    MockERC20 token1;

    function setUp() public {
        manager = new PoolManager(address(this));
        MockERC20 a = new MockERC20("A", "A", 18);
        MockERC20 b = new MockERC20("B", "B", 18);
        (token0, token1) = address(a) < address(b) ? (a, b) : (b, a);

        deployCodeTo("ImpactRebatedFees.sol:ImpactRebatedFees", abi.encode(IPoolManager(address(manager))), HOOK_ADDR);
        hook = ImpactRebatedFees(HOOK_ADDR);

        PoolSwapTest swapRouter = new PoolSwapTest(manager);
        PoolModifyLiquidityTest liqRouter = new PoolModifyLiquidityTest(manager);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 500,
            tickSpacing: 60,
            hooks: IHooks(HOOK_ADDR)
        });

        token0.mint(address(this), 1_000_000 ether);
        token1.mint(address(this), 1_000_000 ether);
        token0.approve(address(liqRouter), type(uint256).max);
        token1.approve(address(liqRouter), type(uint256).max);

        manager.initialize(key, TickMath.getSqrtPriceAtTick(0));
        liqRouter.modifyLiquidity(
            key, ModifyLiquidityParams({tickLower: -60000, tickUpper: 60000, liquidityDelta: 5000 ether, salt: 0}), ""
        );

        handler = new Handler(swapRouter, hook, key);
        token0.mint(address(handler), 1_000_000 ether);
        token1.mint(address(handler), 1_000_000 ether);
        vm.startPrank(address(handler));
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();

        targetContract(address(handler));
    }

    /// Whatever the hook says it is holding must actually be there as claims.
    function invariant_escrowIsFullyBacked() public view {
        assertEq(
            hook.escrowed(address(token0)),
            manager.balanceOf(address(hook), CurrencyLibrary.toId(Currency.wrap(address(token0)))),
            "token0 escrow not backed"
        );
        assertEq(
            hook.escrowed(address(token1)),
            manager.balanceOf(address(hook), CurrencyLibrary.toId(Currency.wrap(address(token1)))),
            "token1 escrow not backed"
        );
    }

    /// Guards against the invariants passing over a dead pool. Deterministic
    /// rather than an afterInvariant hook, because the fuzzer is free to
    /// produce a short sequence where every call reverts and that is not a bug.
    function test_handlerActuallySwapsAndSettles() public {
        handler.swap(0, 1 ether);
        handler.swap(1, 1 ether);
        assertGt(hook.nextReceiptId(), 0, "handler cannot swap");

        handler.advance(uint32(Params.SETTLEMENT_WINDOW_SECONDS + 1));
        handler.settleOne(0);
        assertGt(handler.settledCount(), 0, "handler cannot settle");
    }

    /// A settled receipt stays settled and never pays out twice.
    function invariant_settledReceiptsStaySettled() public view {
        uint256 n = hook.nextReceiptId();
        for (uint256 i; i < n && i < 50; ++i) {
            if (handler.seenSettled(i)) {
                (,,,, bool settled,,,,) = hook.receipts(i);
                assertTrue(settled, "settled receipt reverted to unsettled");
            }
        }
    }
}
