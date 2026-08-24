// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {ImpactRebatedFees} from "../src/ImpactRebatedFees.sol";
import {HookMiner} from "../src/HookMiner.sol";
import {Params} from "../src/Params.sol";

contract ImpactRebatedFeesFeeTest is Test {
    function _deploy() internal returns (ImpactRebatedFees hook) {
        uint160 flags = Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG;
        (address expected, bytes32 salt) = HookMiner.find(
            address(this), flags, type(ImpactRebatedFees).creationCode, abi.encode(IPoolManager(address(this)))
        );
        hook = new ImpactRebatedFees{salt: salt}(IPoolManager(address(this)));
        assertEq(address(hook), expected);
    }

    function _key(ImpactRebatedFees hook, uint24 fee) internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(1)),
            currency1: Currency.wrap(address(2)),
            fee: fee,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
    }

    function test_beforeSwapOverridesBaseFeeOnDynamicPool() public {
        ImpactRebatedFees hook = _deploy();
        (bytes4 selector, BeforeSwapDelta delta, uint24 fee) = hook.beforeSwap(
            address(this),
            _key(hook, LPFeeLibrary.DYNAMIC_FEE_FLAG),
            SwapParams({zeroForOne: true, amountSpecified: -1, sqrtPriceLimitX96: 1}),
            ""
        );
        assertEq(selector, IHooks.beforeSwap.selector);
        assertEq(BeforeSwapDelta.unwrap(delta), 0);
        assertEq(fee, Params.BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    function test_beforeSwapRejectsStaticPool() public {
        ImpactRebatedFees hook = _deploy();
        vm.expectRevert(ImpactRebatedFees.NonDynamicFeePool.selector);
        hook.beforeSwap(
            address(this),
            _key(hook, 500),
            SwapParams({zeroForOne: true, amountSpecified: -1, sqrtPriceLimitX96: 1}),
            ""
        );
    }

    function test_escrowFeeRateIsTwentyFiveBps() public pure {
        assertEq(Params.ESCROW_FEE_BPS, 25);
        assertEq(1_000_000 * Params.ESCROW_FEE_BPS / 10_000, 2_500);
    }
}
