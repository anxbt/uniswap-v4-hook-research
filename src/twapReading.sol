//read cumilative price/tick data from the pool on a regular basis
// compute short window average(TWAP)
//compare against spot
//derive simple volatility metric

//Goal understand price mechanics


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

contract TwapReading is BaseHook {
    using PoolIdLibrary for PoolKey;

    // State: unique per pool
    mapping(PoolId => uint256 count) public beforeSwapCount;
    mapping(PoolId => Observation[]) public observations;

    struct Observation {
        uint32 timestamp;
        int24 tick;
    }

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

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
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
    
    // Record tick observation after every swap
    function _afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        PoolId poolId = key.toId();
        // Convert PoolKey calldata to memory for getSlot0
        (, int24 currentTick,,) = StateLibrary.getSlot0(poolManager, poolId);
        uint32 nowTs = uint32(block.timestamp);
        observations[poolId].push(Observation({timestamp: nowTs, tick: currentTick}));
        return (BaseHook.afterSwap.selector, 0);
    }

    // Compute TWAP for a short window (e.g., 30 min)
    function getShortTWAP(PoolId poolId, uint32 window) external view returns (int24 twap) {
        Observation[] storage obs = observations[poolId];
        if (obs.length < 2) return 0;
        uint32 nowTs = uint32(block.timestamp);
        // Find the oldest observation within the window
        for (uint256 i = obs.length; i > 0; i--) {
            if (nowTs - obs[i-1].timestamp >= window) {
                // TWAP = (current tick - old tick) / (now - old)
                int24 currentTick = obs[obs.length-1].tick;
                int24 oldTick = obs[i-1].tick;
                uint32 dt = nowTs - obs[i-1].timestamp;
                int256 dtInt = int256(uint256(dt));
                return int24((int256(currentTick) - int256(oldTick)) / dtInt);
            }
        }
        // If no old observation found, fallback to latest
        return obs[obs.length-1].tick;
    }
}
