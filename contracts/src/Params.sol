// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library Params {
    uint256 internal constant BASE_FEE_BPS = 5;
    uint256 internal constant ESCROW_FEE_BPS = 25;
    uint256 internal constant SETTLEMENT_WINDOW_SECONDS = 120;
    uint256 internal constant THETA_BPS = 10;

    // Uniswap v4 LP fees are expressed in hundredths of a basis point.
    uint24 internal constant BASE_FEE = uint24(BASE_FEE_BPS * 100);
}
