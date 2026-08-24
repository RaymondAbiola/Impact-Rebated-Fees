// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IImpactRebatedFees {
    /// Snapshot of a pool's price history. One slot.
    struct Observation {
        uint64 timestamp;
        int24 lastTick;
        int56 tickCumulative;
    }

    /// What settlement needs later. Swap amounts are emitted, not stored.
    struct Receipt {
        bytes32 poolId;
        address beneficiary;
        uint64 swapTimestamp;
        bool zeroForOne;
        bool settled;
        int24 tickPost;
        int56 tickCumulative;
        uint128 escrowAmount;
        address escrowCurrency;
    }

    event ReceiptRecorded(
        uint256 indexed receiptId,
        bytes32 indexed poolId,
        address indexed beneficiary,
        uint64 swapTimestamp,
        int24 tickPost,
        uint128 amount0,
        uint128 amount1,
        bool zeroForOne
    );

    event HookFeeEscrowed(address indexed currency, uint256 amount, uint256 indexed receiptId);

    event ReceiptSettled(
        uint256 indexed receiptId,
        address indexed beneficiary,
        bool informed,
        int256 driftTicks,
        address currency,
        uint256 payout,
        uint256 bounty,
        bool expired
    );
}
