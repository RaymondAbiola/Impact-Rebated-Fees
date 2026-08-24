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
import {IImpactRebatedFees} from "./interfaces/IImpactRebatedFees.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";

contract ImpactRebatedFees is BaseHook, IImpactRebatedFees, IUnlockCallback {
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;
    using LPFeeLibrary for uint24;
    using StateLibrary for IPoolManager;

    uint256 public nextReceiptId;
    mapping(uint256 receiptId => Receipt) public receipts;
    mapping(address currency => uint256 amount) public escrowed;
    mapping(PoolId poolId => Observation) public observations;
    mapping(PoolId poolId => PoolKey) public poolKeys;

    error InvalidHookData();
    error NonDynamicFeePool();
    error AlreadySettled();
    error WindowNotElapsed();

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

        PoolId id = key.toId();
        if (poolKeys[id].tickSpacing == 0) poolKeys[id] = key;
        (, int24 tickPost,,) = poolManager.getSlot0(id);
        int56 cumulative = _observe(id, tickPost);

        uint256 receiptId = _recordReceipt(
            Receipt({
                poolId: PoolId.unwrap(id),
                beneficiary: beneficiary,
                swapTimestamp: uint64(block.timestamp),
                zeroForOne: params.zeroForOne,
                settled: false,
                tickPost: tickPost,
                tickCumulative: cumulative,
                escrowAmount: uint128(feeAmount),
                escrowCurrency: Currency.unwrap(feeCurrency)
            }),
            _abs(delta.amount0()),
            _abs(delta.amount1())
        );

        if (feeAmount != 0) {
            poolManager.mint(address(this), CurrencyLibrary.toId(feeCurrency), feeAmount);
            escrowed[Currency.unwrap(feeCurrency)] += feeAmount;
            emit HookFeeEscrowed(Currency.unwrap(feeCurrency), feeAmount, receiptId);
        }
    }

    /// Advance the pool's cumulative tick to now, then record the new tick.
    /// Same shape as the v3 oracle: cumulative carries the *previous* tick over
    /// the time it was live, so a single block cannot move the average.
    function _observe(PoolId id, int24 tickPost) private returns (int56 cumulative) {
        Observation memory obs = observations[id];
        cumulative = obs.tickCumulative;
        if (obs.timestamp != 0) {
            cumulative += int56(obs.lastTick) * int56(uint56(block.timestamp - obs.timestamp));
        }
        observations[id] =
            Observation({timestamp: uint64(block.timestamp), lastTick: tickPost, tickCumulative: cumulative});
    }

    /// Cumulative tick brought forward to the current timestamp.
    function currentTickCumulative(PoolId id) public view returns (int56) {
        Observation memory obs = observations[id];
        if (obs.timestamp == 0) return 0;
        return obs.tickCumulative + int56(obs.lastTick) * int56(uint56(block.timestamp - obs.timestamp));
    }

    function _recordReceipt(Receipt memory receipt, uint128 amount0, uint128 amount1)
        private
        returns (uint256 receiptId)
    {
        receiptId = nextReceiptId++;
        receipts[receiptId] = receipt;
        emit ReceiptRecorded(
            receiptId,
            receipt.poolId,
            receipt.beneficiary,
            receipt.swapTimestamp,
            receipt.tickPost,
            amount0,
            amount1,
            receipt.zeroForOne
        );
    }


    /// Drift since the swap, in ticks. One tick is 1.0001x, so a tick is within
    /// a rounding error of a basis point at the sizes we threshold on.
    function driftOf(uint256 receiptId) public view returns (int256 drift, bool ready) {
        Receipt memory r = receipts[receiptId];
        uint256 elapsed = block.timestamp - r.swapTimestamp;
        ready = elapsed >= Params.SETTLEMENT_WINDOW_SECONDS;
        if (elapsed == 0) return (0, ready);

        int256 mean = (int256(currentTickCumulative(PoolId.wrap(r.poolId))) - int256(r.tickCumulative))
            / int256(elapsed);
        // acquiring token1 pays off when token1 gets scarcer per token0, ie tick falls
        drift = r.zeroForOne ? int256(r.tickPost) - mean : mean - int256(r.tickPost);
    }

    function settle(uint256 receiptId) public {
        _settle(receiptId, true);
    }

    /// Skips anything not ready instead of reverting, so one bad id cannot
    /// take down the whole batch.
    function settleBatch(uint256[] calldata receiptIds) external {
        for (uint256 i; i < receiptIds.length; ++i) {
            _settle(receiptIds[i], false);
        }
    }

    function _settle(uint256 receiptId, bool strict) private {
        Receipt storage r = receipts[receiptId];
        if (r.settled) {
            if (strict) revert AlreadySettled();
            return;
        }

        uint256 elapsed = block.timestamp - r.swapTimestamp;
        if (elapsed < Params.SETTLEMENT_WINDOW_SECONDS) {
            if (strict) revert WindowNotElapsed();
            return;
        }

        (int256 drift,) = driftOf(receiptId);
        bool expired = elapsed >= Params.EXPIRY_SECONDS;
        bool informed = expired || drift > int256(uint256(Params.THETA_BPS));

        uint256 amount = r.escrowAmount;
        address currency = r.escrowCurrency;
        address beneficiary = r.beneficiary;

        r.settled = true;

        uint256 bounty;
        uint256 payout;
        if (amount != 0) {
            bounty = amount * Params.BOUNTY_BPS / 10_000;
            payout = amount - bounty;
            escrowed[currency] -= amount;
            poolManager.unlock(
                abi.encode(receiptId, informed, currency, payout, bounty, beneficiary, msg.sender)
            );
        }

        emit ReceiptSettled(receiptId, beneficiary, informed, drift, currency, payout, bounty, expired);
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        (
            uint256 receiptId,
            bool informed,
            address currency,
            uint256 payout,
            uint256 bounty,
            address beneficiary,
            address keeper
        ) = abi.decode(data, (uint256, bool, address, uint256, uint256, address, address));

        Currency c = Currency.wrap(currency);
        // burning the claim turns the escrow back into a credit we can spend
        poolManager.burn(address(this), CurrencyLibrary.toId(c), payout + bounty);

        if (payout != 0) {
            if (informed) {
                PoolKey memory key = poolKeys[PoolId.wrap(receipts[receiptId].poolId)];
                bool isZero = Currency.unwrap(key.currency0) == currency;
                poolManager.donate(key, isZero ? payout : 0, isZero ? 0 : payout, "");
            } else {
                poolManager.take(c, beneficiary, payout);
            }
        }
        if (bounty != 0) poolManager.take(c, keeper, bounty);
        return "";
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
