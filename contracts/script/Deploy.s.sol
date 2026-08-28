// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {ImpactRebatedFees} from "../src/ImpactRebatedFees.sol";
import {HookMiner} from "../src/HookMiner.sol";

contract Deploy is Script {
    using PoolIdLibrary for PoolKey;

    // canonical CREATE2 factory, same address on every chain, which is what
    // makes the mined hook address reproducible from a fresh clone
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // kept in storage rather than on the stack, the script tips over otherwise
    address hookAddr;
    address managerAddr;
    address swapRouterAddr;
    address liqRouterAddr;
    PoolKey key;

    function run() external {
        managerAddr = vm.envAddress("POOL_MANAGER");
        IPoolManager manager = IPoolManager(managerAddr);

        uint160 flags = Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG;
        address admin = msg.sender;
        (address expected, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER, flags, type(ImpactRebatedFees).creationCode, abi.encode(manager, admin)
        );

        vm.startBroadcast();

        ImpactRebatedFees hook = new ImpactRebatedFees{salt: salt}(manager, admin);
        require(address(hook) == expected, "mined address mismatch");
        hookAddr = address(hook);

        // demo pair so the testnet deployment is tradeable without hunting for
        // faucet tokens
        MockERC20 a = new MockERC20("Impact USD", "iUSD", 18);
        MockERC20 b = new MockERC20("Impact ETH", "iETH", 18);
        (MockERC20 t0, MockERC20 t1) = address(a) < address(b) ? (a, b) : (b, a);

        key = PoolKey({
            currency0: Currency.wrap(address(t0)),
            currency1: Currency.wrap(address(t1)),
            fee: 500,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        manager.initialize(key, TickMath.getSqrtPriceAtTick(0));

        PoolModifyLiquidityTest liqRouter = new PoolModifyLiquidityTest(manager);
        PoolSwapTest swapRouter = new PoolSwapTest(manager);
        liqRouterAddr = address(liqRouter);
        swapRouterAddr = address(swapRouter);

        t0.mint(msg.sender, 1_000_000 ether);
        t1.mint(msg.sender, 1_000_000 ether);
        t0.approve(address(liqRouter), type(uint256).max);
        t1.approve(address(liqRouter), type(uint256).max);
        t0.approve(address(swapRouter), type(uint256).max);
        t1.approve(address(swapRouter), type(uint256).max);

        liqRouter.modifyLiquidity(
            key, ModifyLiquidityParams({tickLower: -60000, tickUpper: 60000, liquidityDelta: 2000 ether, salt: 0}), ""
        );

        vm.stopBroadcast();

        _write();
        console.log("hook      ", hookAddr);
        console.log("owner     ", admin);
        console.log("swapRouter", swapRouterAddr);
        console.log("poolId    ", vm.toString(PoolId.unwrap(key.toId())));
    }

    function _write() private {
        string memory o = "deployment";
        vm.serializeUint(o, "chainId", block.chainid);
        vm.serializeAddress(o, "poolManager", managerAddr);
        vm.serializeAddress(o, "hook", hookAddr);
        vm.serializeAddress(o, "swapRouter", swapRouterAddr);
        vm.serializeAddress(o, "modifyLiquidityRouter", liqRouterAddr);
        vm.serializeAddress(o, "currency0", Currency.unwrap(key.currency0));
        vm.serializeAddress(o, "currency1", Currency.unwrap(key.currency1));
        vm.serializeUint(o, "fee", uint256(key.fee));
        vm.serializeUint(o, "tickSpacing", uint256(uint24(key.tickSpacing)));
        string memory out = vm.serializeBytes32(o, "poolId", PoolId.unwrap(key.toId()));
        vm.writeJson(out, string.concat("./deployments/", vm.toString(block.chainid), ".json"));
    }
}
