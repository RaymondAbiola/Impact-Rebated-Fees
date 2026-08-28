// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {ImpactRebatedFees} from "../src/ImpactRebatedFees.sol";

/// Fires swaps at the deployed pool so the settlement queue has something to
/// show, and settles whatever is ready. Run swaps, wait out the window, settle.
contract Seed is Script {
    ImpactRebatedFees hook;
    PoolSwapTest router;
    PoolKey key;

    function _load() private {
        string memory j = vm.readFile(string.concat("./deployments/", vm.toString(block.chainid), ".json"));
        hook = ImpactRebatedFees(vm.parseJsonAddress(j, ".hook"));
        router = PoolSwapTest(vm.parseJsonAddress(j, ".swapRouter"));
        key = PoolKey({
            currency0: Currency.wrap(vm.parseJsonAddress(j, ".currency0")),
            currency1: Currency.wrap(vm.parseJsonAddress(j, ".currency1")),
            fee: uint24(vm.parseJsonUint(j, ".fee")),
            tickSpacing: int24(int256(vm.parseJsonUint(j, ".tickSpacing"))),
            hooks: IHooks(address(hook))
        });
    }

    function _swap(bool zeroForOne, int256 amount) private {
        router.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amount,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
    }

    function run() external {
        _load();
        uint256 before = hook.nextReceiptId();

        vm.startBroadcast();
        MockERC20(Currency.unwrap(key.currency0)).approve(address(router), type(uint256).max);
        MockERC20(Currency.unwrap(key.currency1)).approve(address(router), type(uint256).max);

        _swap(true, -0.5 ether);
        _swap(false, -0.75 ether);
        _swap(true, -12 ether); // large, moves price, likely to look informed
        _swap(false, -0.25 ether);
        vm.stopBroadcast();

        console.log("receipts before", before);
        console.log("receipts after ", hook.nextReceiptId());
        console.log("escrow token0  ", hook.escrowed(Currency.unwrap(key.currency0)));
        console.log("escrow token1  ", hook.escrowed(Currency.unwrap(key.currency1)));
    }

    /// forge script script/Seed.s.sol --sig "settle()" ...
    function settle() external {
        _load();
        uint256 n = hook.nextReceiptId();
        uint256[] memory ids = new uint256[](n);
        uint256 count;
        for (uint256 i; i < n; ++i) {
            (,,,, bool settled,,,,) = hook.receipts(i);
            (, bool ready) = hook.driftOf(i);
            if (!settled && ready) ids[count++] = i;
        }
        console.log("ready to settle", count, "of", n);
        if (count == 0) return;

        uint256[] memory batch = new uint256[](count);
        for (uint256 i; i < count; ++i) batch[i] = ids[i];

        vm.broadcast();
        hook.settleBatch(batch);
        console.log("settled");
    }
}
