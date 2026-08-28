// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {ImpactRebatedFees} from "../src/ImpactRebatedFees.sol";
import {HookMiner} from "../src/HookMiner.sol";

contract HookMinerTest is Test {
    uint160 internal constant FLAGS =
        Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG;

    function test_minesImpactRebatedFeesPermissionAddress() public {
        (address hook, bytes32 salt) = HookMiner.find(
            address(this),
            FLAGS,
            type(ImpactRebatedFees).creationCode,
            abi.encode(IPoolManager(address(0)))
        );

        assertEq(uint160(hook) & Hooks.ALL_HOOK_MASK, FLAGS);
        assertEq(HookMiner.computeAddress(address(this), salt, abi.encodePacked(
            type(ImpactRebatedFees).creationCode, abi.encode(IPoolManager(address(0)))
        )), hook);
    }
}
