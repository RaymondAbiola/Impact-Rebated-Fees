// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {ImpactRebatedFees} from "../src/ImpactRebatedFees.sol";
import {Params} from "../src/Params.sol";

contract AdminTest is Test {
    address constant HOOK_ADDR = address(uint160(0x6666 << 144) | uint160(0x44));
    address constant STRANGER = address(0xBAD);

    PoolManager manager;
    ImpactRebatedFees hook;
    PoolSwapTest swapRouter;
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
        PoolModifyLiquidityTest liqRouter = new PoolModifyLiquidityTest(manager);

        key = PoolKey({
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
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);

        manager.initialize(key, TickMath.getSqrtPriceAtTick(0));
        liqRouter.modifyLiquidity(
            key, ModifyLiquidityParams({tickLower: -60000, tickUpper: 60000, liquidityDelta: 5000 ether, salt: 0}), ""
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

    function test_deployerOwnsTheHook() public view {
        assertEq(hook.owner(), address(this));
    }

    function test_strangerCannotPause() public {
        vm.prank(STRANGER);
        vm.expectRevert(ImpactRebatedFees.Unauthorized.selector);
        hook.setPaused(true);
    }

    function test_strangerCannotSetMinEscrow() public {
        vm.prank(STRANGER);
        vm.expectRevert(ImpactRebatedFees.Unauthorized.selector);
        hook.setMinEscrow(address(token1), 1);
    }

    function test_strangerCannotTakeOwnership() public {
        vm.prank(STRANGER);
        vm.expectRevert(ImpactRebatedFees.Unauthorized.selector);
        hook.setOwner(STRANGER);
    }

    function test_ownershipTransfers() public {
        hook.setOwner(STRANGER);
        assertEq(hook.owner(), STRANGER);

        vm.expectRevert(ImpactRebatedFees.Unauthorized.selector);
        hook.setPaused(true);

        vm.prank(STRANGER);
        hook.setPaused(true);
        assertTrue(hook.paused());
    }

    /// A swap whose escrow would be below the floor writes no receipt at all,
    /// so nobody pays gas settling dust.
    function test_minEscrowSuppressesTinyReceipts() public {
        hook.setMinEscrow(address(token1), type(uint128).max);
        _swap(true, -1 ether);
        assertEq(hook.nextReceiptId(), 0, "receipt written below the floor");
        assertEq(hook.escrowed(address(token1)), 0);

        hook.setMinEscrow(address(token1), 0);
        _swap(true, -1 ether);
        assertEq(hook.nextReceiptId(), 1, "receipt missing above the floor");
    }
}
