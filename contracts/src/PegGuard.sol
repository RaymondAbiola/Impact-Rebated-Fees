// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@uniswap/hooks/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Params} from "./Params.sol";
import {IPegGuard} from "./interfaces/IPegGuard.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

contract PegGuard is BaseHook, IPegGuard {
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;
    using LPFeeLibrary for uint24;

    uint256 public nextReceiptId;
    mapping(uint256 receiptId => Receipt) public receipts;

    error InvalidHookData();
    error NonDynamicFeePool();

    uint160 public constant HOOK_FLAGS =
        Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG;

    constructor(IPoolManager manager) BaseHook(manager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
        internal
        pure
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (!key.fee.isDynamicFee()) revert NonDynamicFeePool();
        return (
            IHooks.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            Params.BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG
        );
    }

    function _afterSwap(address sender, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata hookData)
        internal
        override
        returns (bytes4, int128)
    {
        address beneficiary = sender;
        if (hookData.length == 32) beneficiary = abi.decode(hookData, (address));
        else if (hookData.length != 0) revert InvalidHookData();

        uint256 receiptId = nextReceiptId++;
        receipts[receiptId] = Receipt({
            poolId: PoolId.unwrap(key.toId()),
            beneficiary: beneficiary,
            swapBlock: uint64(block.number),
            amount0: _abs(delta.amount0()),
            amount1: _abs(delta.amount1()),
            zeroForOne: params.zeroForOne,
            settled: false
        });
        emit ReceiptRecorded(
            receiptId,
            PoolId.unwrap(key.toId()),
            beneficiary,
            uint64(block.number),
            _abs(delta.amount0()),
            _abs(delta.amount1()),
            params.zeroForOne
        );
        return (IHooks.afterSwap.selector, 0);
    }

    function _abs(int128 value) private pure returns (uint128) {
        return uint128(uint256(value < 0 ? -int256(value) : int256(value)));
    }
}
