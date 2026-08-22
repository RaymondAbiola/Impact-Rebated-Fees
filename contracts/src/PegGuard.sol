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
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";

contract PegGuard is BaseHook, IPegGuard {
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;
    using LPFeeLibrary for uint24;

    uint256 public nextReceiptId;
    mapping(uint256 receiptId => Receipt) public receipts;
    mapping(address currency => uint256 amount) public escrowed;

    error InvalidHookData();
    error NonDynamicFeePool();

    function previewEscrowFee(uint256 unspecifiedAmount) external pure returns (uint256) {
        return unspecifiedAmount * Params.ESCROW_FEE_BPS / 10_000;
    }

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
        uint256 feeAmount = _handleSwap(sender, key, params, delta, hookData);
        return (IHooks.afterSwap.selector, int128(uint128(feeAmount)));
    }

    function _handleSwap(address sender, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata hookData)
        private
        returns (uint256 feeAmount)
    {
        address beneficiary = sender;
        if (hookData.length == 32) beneficiary = abi.decode(hookData, (address));
        else if (hookData.length != 0) revert InvalidHookData();

        (Currency feeCurrency, uint128 swapAmount) = _unspecifiedAmount(key, params, delta);
        feeAmount = uint256(swapAmount) * Params.ESCROW_FEE_BPS / 10_000;
        uint128 amount0 = _abs(delta.amount0());
        uint128 amount1 = _abs(delta.amount1());
        bytes32 poolId = PoolId.unwrap(key.toId());
        uint64 swapBlock = uint64(block.number);

        Receipt memory receipt = Receipt({
            poolId: poolId,
            beneficiary: beneficiary,
            swapBlock: swapBlock,
            amount0: amount0,
            amount1: amount1,
            escrowCurrency: Currency.unwrap(feeCurrency),
            escrowAmount: uint128(feeAmount),
            zeroForOne: params.zeroForOne,
            settled: false
        });
        uint256 receiptId = _recordReceipt(receipt);
        if (feeAmount != 0) {
            poolManager.mint(address(this), CurrencyLibrary.toId(feeCurrency), feeAmount);
            escrowed[Currency.unwrap(feeCurrency)] += feeAmount;
            emit HookFeeEscrowed(Currency.unwrap(feeCurrency), feeAmount, receiptId);
        }
    }

    function _recordReceipt(Receipt memory receipt) private returns (uint256 receiptId) {
        receiptId = nextReceiptId++;
        receipts[receiptId] = receipt;
        emit ReceiptRecorded(
            receiptId,
            receipt.poolId,
            receipt.beneficiary,
            receipt.swapBlock,
            receipt.amount0,
            receipt.amount1,
            receipt.zeroForOne
        );
    }

    function _unspecifiedAmount(PoolKey calldata key, SwapParams calldata params, BalanceDelta delta)
        private
        pure
        returns (Currency currency, uint128 amount)
    {
        bool specifiedTokenIs0 = (params.amountSpecified < 0 == params.zeroForOne);
        int128 raw;
        if (specifiedTokenIs0) {
            currency = key.currency1;
            raw = delta.amount1();
        } else {
            currency = key.currency0;
            raw = delta.amount0();
        }
        amount = uint128(uint256(raw < 0 ? -int256(raw) : int256(raw)));
    }

    function _abs(int128 value) private pure returns (uint128) {
        return uint128(uint256(value < 0 ? -int256(value) : int256(value)));
    }
}
