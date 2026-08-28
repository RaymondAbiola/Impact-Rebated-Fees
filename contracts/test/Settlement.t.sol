// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {ImpactRebatedFees} from "../src/ImpactRebatedFees.sol";
import {IImpactRebatedFees} from "../src/interfaces/IImpactRebatedFees.sol";
import {Params} from "../src/Params.sol";

contract SettlementTest is Test {
    // low 14 bits must be afterSwap | afterSwapReturnsDelta
    address constant HOOK_ADDR = address(uint160(0x8888 << 144) | uint160(0x44));

    PoolManager manager;
    ImpactRebatedFees hook;
    PoolSwapTest swapRouter;
    PoolModifyLiquidityTest liqRouter;
    MockERC20 token0;
    MockERC20 token1;
    PoolKey key;

    function setUp() public {
        manager = new PoolManager(address(this));

        MockERC20 a = new MockERC20("A", "A", 18);
        MockERC20 b = new MockERC20("B", "B", 18);
        (token0, token1) = address(a) < address(b) ? (a, b) : (b, a);

        deployCodeTo("ImpactRebatedFees.sol:ImpactRebatedFees", abi.encode(IPoolManager(address(manager)), address(this)), HOOK_ADDR);
        hook = ImpactRebatedFees(HOOK_ADDR);

        swapRouter = new PoolSwapTest(manager);
        liqRouter = new PoolModifyLiquidityTest(manager);

        token0.mint(address(this), 1_000_000 ether);
        token1.mint(address(this), 1_000_000 ether);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        token0.approve(address(liqRouter), type(uint256).max);
        token1.approve(address(liqRouter), type(uint256).max);

        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 500,
            tickSpacing: 60,
            hooks: IHooks(HOOK_ADDR)
        });
        manager.initialize(key, TickMath.getSqrtPriceAtTick(0));

        liqRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -6000, tickUpper: 6000, liquidityDelta: 100 ether, salt: 0}),
            ""
        );
    }

    function _swap(bool zeroForOne, int256 amount) internal returns (BalanceDelta) {
        return swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amount,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
    }

    function test_swapEscrowsTwentyFiveBpsOfUnspecified() public {
        _swap(true, -1 ether);

        assertEq(hook.nextReceiptId(), 1, "receipt written");
        (,,,,,,, uint128 escrowAmount, address escrowCurrency) = hook.receipts(0);

        // exact input zeroForOne, so the unspecified side is token1
        assertEq(escrowCurrency, address(token1), "escrow in output token");
        assertGt(escrowAmount, 0, "escrow taken");
        assertEq(hook.escrowed(address(token1)), escrowAmount, "escrow tracked");
        assertEq(manager.balanceOf(address(hook), CurrencyLibrary.toId(Currency.wrap(address(token1)))), escrowAmount);
    }

    function test_settleBeforeWindowReverts() public {
        _swap(true, -1 ether);
        vm.expectRevert(ImpactRebatedFees.WindowNotElapsed.selector);
        hook.settle(0);
    }

    function test_quietPoolRefundsTheTrader() public {
        _swap(true, -1 ether);
        (,,,,,,, uint128 escrowAmount,) = hook.receipts(0);

        // nothing else trades, so the tick never drifts
        vm.warp(block.timestamp + Params.SETTLEMENT_WINDOW_SECONDS + 1);

        uint256 before = token1.balanceOf(address(swapRouter));
        hook.settle(0);

        uint256 bounty = uint256(escrowAmount) * Params.BOUNTY_BPS / 10_000;
        assertEq(token1.balanceOf(address(swapRouter)) - before, escrowAmount - bounty, "refunded less bounty");
        assertEq(hook.escrowed(address(token1)), 0, "escrow released");
    }

    function test_cannotSettleTwice() public {
        _swap(true, -1 ether);
        vm.warp(block.timestamp + Params.SETTLEMENT_WINDOW_SECONDS + 1);
        hook.settle(0);
        vm.expectRevert(ImpactRebatedFees.AlreadySettled.selector);
        hook.settle(0);
    }

    function test_priceRunningOnPaysTheLps() public {
        _swap(true, -1 ether);
        (,,,,,,, uint128 escrowAmount,) = hook.receipts(0);

        // keep pushing the tick the same way the first trader was positioned
        vm.warp(block.timestamp + 1);
        _swap(true, -20 ether);

        vm.warp(block.timestamp + Params.SETTLEMENT_WINDOW_SECONDS + 1);
        (int256 drift, bool ready) = hook.driftOf(0);
        assertTrue(ready, "window elapsed");
        assertGt(drift, int256(uint256(Params.THETA_BPS)), "drift past threshold");

        uint256 traderBefore = token1.balanceOf(address(swapRouter));
        uint256 keeperBefore = token1.balanceOf(address(this));
        uint256 escrowBefore = hook.escrowed(address(token1));

        hook.settle(0);

        uint256 bounty = uint256(escrowAmount) * Params.BOUNTY_BPS / 10_000;
        assertEq(token1.balanceOf(address(swapRouter)), traderBefore, "no refund to an informed trader");
        assertEq(token1.balanceOf(address(this)) - keeperBefore, bounty, "keeper paid the bounty");
        // the second swap has its own unsettled receipt, so only this one clears
        assertEq(escrowBefore - hook.escrowed(address(token1)), escrowAmount, "this receipt released");
    }

    /// An informed trader wants their receipt to read benign. Because the
    /// reference is time-weighted across the whole window, a late counter-trade
    /// barely moves it, so buying the verdict back means holding the price for
    /// most of the window rather than paying once at the end.
    function test_lateManipulationCannotBuyBackTheVerdict() public {
        _swap(true, -1 ether);

        vm.warp(block.timestamp + 1);
        _swap(true, -20 ether);

        // sit out almost the whole window, then shove the price back hard
        vm.warp(block.timestamp + Params.SETTLEMENT_WINDOW_SECONDS - 5);
        (int256 driftBefore,) = hook.driftOf(0);
        assertGt(driftBefore, int256(uint256(Params.THETA_BPS)), "informed before the attack");

        uint256 t1Before = token1.balanceOf(address(this));
        _swap(false, -40 ether);
        uint256 spent = t1Before - token1.balanceOf(address(this));

        vm.warp(block.timestamp + 6);
        (int256 driftAfter,) = hook.driftOf(0);

        assertGt(driftAfter, int256(uint256(Params.THETA_BPS)), "verdict survived a 40x late counter-trade");
        assertGt(spent, 0, "attack was not free");

        (,,,,,,, uint128 escrowAmount,) = hook.receipts(0);
        assertGt(spent, uint256(escrowAmount), "attack cost exceeds the escrow it would recover");
    }

    function test_pausedPoolTakesNoEscrow() public {
        hook.setPaused(true);
        _swap(true, -1 ether);
        assertEq(hook.nextReceiptId(), 0, "no receipt while paused");
        assertEq(hook.escrowed(address(token1)), 0);
    }

    function testFuzz_escrowIsAlwaysTwentyFiveBpsOfGross(uint96 amount, bool zeroForOne) public {
        int256 amt = -int256(uint256(bound(amount, 0.001 ether, 5 ether)));
        BalanceDelta delta = _swap(zeroForOne, amt);

        (,,,,,,, uint128 escrowAmount, address escrowCurrency) = hook.receipts(0);
        // exact input: the unspecified side is the output the trader received
        int128 netOut = zeroForOne ? delta.amount1() : delta.amount0();
        assertGt(netOut, 0, "trader received output");
        assertEq(
            escrowCurrency,
            zeroForOne ? address(token1) : address(token0),
            "escrow sits in the output token"
        );

        // the router's delta is already net of the hook fee, so gross it back up
        uint256 gross = uint256(uint128(netOut)) + escrowAmount;
        assertApproxEqAbs(escrowAmount, gross * Params.ESCROW_FEE_BPS / 10_000, 1, "escrow rate");
    }

    function testFuzz_settleOnlyAfterTheWindow(uint32 elapsed) public {
        _swap(true, -1 ether);
        uint256 wait = bound(elapsed, 1, Params.SETTLEMENT_WINDOW_SECONDS * 4);
        vm.warp(block.timestamp + wait);

        if (wait < Params.SETTLEMENT_WINDOW_SECONDS) {
            vm.expectRevert(ImpactRebatedFees.WindowNotElapsed.selector);
            hook.settle(0);
        } else {
            hook.settle(0);
            (,,,, bool settled,,,,) = hook.receipts(0);
            assertTrue(settled);
        }
    }

    function test_gasOverheadOfTheHook() public {
        _swap(true, -1 ether);
        uint256 g = gasleft();
        _swap(true, -1 ether);
        uint256 swapGas = g - gasleft();

        vm.warp(block.timestamp + Params.SETTLEMENT_WINDOW_SECONDS + 1);
        g = gasleft();
        hook.settle(0);
        uint256 settleGas = g - gasleft();

        emit log_named_uint("swap with hook (gas)", swapGas);
        emit log_named_uint("settle (gas)", settleGas);
    }

    function test_settleBatchSettlesEverythingReady() public {
        _swap(true, -1 ether);
        _swap(false, -1 ether);
        _swap(true, -1 ether);
        assertEq(hook.nextReceiptId(), 3);

        vm.warp(block.timestamp + Params.SETTLEMENT_WINDOW_SECONDS + 1);
        uint256[] memory ids = new uint256[](3);
        ids[0] = 0;
        ids[1] = 1;
        ids[2] = 2;
        hook.settleBatch(ids);

        for (uint256 i; i < 3; ++i) {
            (,,,, bool settled,,,,) = hook.receipts(i);
            assertTrue(settled, "receipt left unsettled");
        }
        assertEq(hook.escrowed(address(token0)), 0);
        assertEq(hook.escrowed(address(token1)), 0);
    }

    /// The whole point of the batch path: one bad id must not strand the rest.
    function test_settleBatchSkipsRatherThanReverting() public {
        _swap(true, -1 ether);
        _swap(true, -1 ether);

        vm.warp(block.timestamp + Params.SETTLEMENT_WINDOW_SECONDS + 1);
        hook.settle(0);

        _swap(true, -1 ether); // fresh, window still open
        uint256[] memory ids = new uint256[](3);
        ids[0] = 0; // already settled
        ids[1] = 1; // ready
        ids[2] = 2; // too early
        hook.settleBatch(ids);

        (,,,, bool one,,,,) = hook.receipts(1);
        (,,,, bool two,,,,) = hook.receipts(2);
        assertTrue(one, "ready receipt was skipped");
        assertFalse(two, "early receipt was settled anyway");
    }

    function test_settleBatchToleratesUnknownIds() public {
        _swap(true, -1 ether);
        vm.warp(block.timestamp + Params.SETTLEMENT_WINDOW_SECONDS + 1);

        uint256[] memory ids = new uint256[](2);
        ids[0] = 0;
        ids[1] = 999; // never existed
        hook.settleBatch(ids);

        (,,,, bool settled,,,,) = hook.receipts(0);
        assertTrue(settled);
    }
}
