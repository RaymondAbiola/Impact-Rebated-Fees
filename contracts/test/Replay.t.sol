// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {ImpactRebatedFees} from "../src/ImpactRebatedFees.sol";
import {IImpactRebatedFees} from "../src/interfaces/IImpactRebatedFees.sol";
import {Params} from "../src/Params.sol";

/// Lets the test drive the accumulator directly with a recorded tick series.
contract ReplayHarness is ImpactRebatedFees {
    constructor(IPoolManager m) ImpactRebatedFees(m) {}

    function observe(PoolId id, int24 tick) external returns (int56) {
        return _observe(id, tick);
    }

    function seed(uint256 id, PoolId poolId, uint64 ts, int24 tickPost, int56 cum, bool zeroForOne) external {
        receipts[id] = Receipt({
            poolId: PoolId.unwrap(poolId),
            beneficiary: address(0xBEEF),
            swapTimestamp: ts,
            zeroForOne: zeroForOne,
            settled: false,
            tickPost: tickPost,
            tickCumulative: cum,
            escrowAmount: 0,
            escrowCurrency: address(0)
        });
    }
}

contract ReplayTest is Test {
    address constant HOOK_ADDR = address(uint160(0x7777 << 144) | uint160(0xC4));
    PoolId constant POOL = PoolId.wrap(bytes32(uint256(1)));

    ReplayHarness hook;

    uint256[] seriesTs;
    int256[] seriesTick;
    uint256[] caseTs;
    int256[] caseTickPost;
    uint256[] caseZeroForOne;
    uint256[] caseSettleAt;
    int256[] caseDrift;
    uint256[] caseInformed;

    function setUp() public {
        PoolManager manager = new PoolManager(address(this));
        deployCodeTo("Replay.t.sol:ReplayHarness", abi.encode(IPoolManager(address(manager))), HOOK_ADDR);
        hook = ReplayHarness(HOOK_ADDR);

        string memory json = vm.readFile("../analysis/out/replay.json");
        seriesTs = vm.parseJsonUintArray(json, ".seriesTimestamp");
        seriesTick = vm.parseJsonIntArray(json, ".seriesTick");
        caseTs = vm.parseJsonUintArray(json, ".caseSwapTimestamp");
        caseTickPost = vm.parseJsonIntArray(json, ".caseTickPost");
        caseZeroForOne = vm.parseJsonUintArray(json, ".caseZeroForOne");
        caseSettleAt = vm.parseJsonUintArray(json, ".caseSettleAt");
        caseDrift = vm.parseJsonIntArray(json, ".caseExpectedDrift");
        caseInformed = vm.parseJsonUintArray(json, ".caseExpectedInformed");
    }

    /// Walks the real tick series forward, seeding a receipt whenever a case
    /// starts and checking drift when its window closes. Same timeline, so the
    /// accumulator sees exactly what it would on chain.
    function test_driftMatchesTheOfflineReference() public {
        uint256 base = 1_000_000;
        uint256 checked;

        for (uint256 i; i < seriesTs.length; ++i) {
            vm.warp(base + seriesTs[i]);
            int56 cum = hook.observe(POOL, int24(seriesTick[i]));

            for (uint256 c; c < caseTs.length; ++c) {
                if (caseTs[c] == seriesTs[i]) {
                    hook.seed(c, POOL, uint64(base + caseTs[c]), int24(caseTickPost[c]), cum, caseZeroForOne[c] == 1);
                }
            }

            uint256 next = i + 1 < seriesTs.length ? seriesTs[i + 1] : type(uint256).max;
            for (uint256 c; c < caseTs.length; ++c) {
                if (caseSettleAt[c] >= seriesTs[i] && caseSettleAt[c] < next && caseTs[c] <= seriesTs[i]) {
                    vm.warp(base + caseSettleAt[c]);
                    (int256 drift, bool ready) = hook.driftOf(c);
                    assertEq(drift, caseDrift[c], "drift disagrees with reference");
                    assertTrue(ready, "window should be closed");
                    assertEq(drift > int256(uint256(Params.THETA_BPS)), caseInformed[c] == 1, "verdict disagrees");
                    checked++;
                }
            }
            vm.warp(base + seriesTs[i]);
        }

        assertGt(checked, 20, "not enough cases exercised");
        emit log_named_uint("cases cross-checked", checked);
    }
}
