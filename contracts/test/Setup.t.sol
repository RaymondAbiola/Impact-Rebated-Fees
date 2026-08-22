// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {BaseHook} from "@uniswap/hooks/base/BaseHook.sol";

// never deployed, just proves the BaseHook inheritance chain compiles
contract CompileProbe is BaseHook {
    constructor(IPoolManager _pm) BaseHook(_pm) {}

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
}

contract SetupTest is Test {
    IPoolManager manager;

    function setUp() public {
        manager = new PoolManager(address(this));
    }

    function test_poolManagerDeploys() public view {
        assertTrue(address(manager) != address(0));
    }

    function test_hookFlagsResolve() public pure {
        assertTrue(Hooks.BEFORE_SWAP_FLAG != 0);
        assertTrue(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG != 0);
    }
}
