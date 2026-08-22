// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IPegGuard {
    struct Receipt {
        bytes32 poolId;
        address beneficiary;
        uint64 swapBlock;
        uint128 amount0;
        uint128 amount1;
        address escrowCurrency;
        uint128 escrowAmount;
        bool zeroForOne;
        bool settled;
    }

    event ReceiptRecorded(
        uint256 indexed receiptId,
        bytes32 indexed poolId,
        address indexed beneficiary,
        uint64 swapBlock,
        uint128 amount0,
        uint128 amount1,
        bool zeroForOne
    );

    event HookFeeEscrowed(address indexed currency, uint256 amount, uint256 indexed receiptId);
}
