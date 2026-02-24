// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";

import {FeeModifier} from "../src/FeeModifier.sol";
import {BaseTest} from "./utils/BaseTest.sol";

contract FeeModifierTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0;
    Currency currency1;

    PoolKey poolKey;

    FeeModifier feeModifier;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // Deploys all required artifacts.
        deployArtifactsAndLabel();

        (currency0, currency1) = deployCurrencyPair();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(poolManager); // Add all the necessary constructor arguments from the hook
        deployCodeTo("feeModifier.sol:FeeModifier", constructorArgs, flags);
        feeModifier = FeeModifier(flags);

        // Create the pool
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(feeModifier));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
    }

    function testFeeModifierHooks() public {
        assertEq(feeModifier.beforeSwapCount(poolId), 0);

        // Perform a test swap //
        uint256 amountIn = 1e18;
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), -int256(amountIn));

        assertEq(feeModifier.beforeSwapCount(poolId), 1);
    }

    function testFeeOverride() public {
        //swap on a dynamic fee pool i.e - verify the return uint24 has 23 se nd val is 10

        PoolKey memory dynamicPoolKey = PoolKey(
            currency0,
            currency1,
            LPFeeLibrary.DYNAMIC_FEE_FLAG, // ← this marks it as dynamic fee pool
            60,
            IHooks(feeModifier)
        );
        poolManager.initialize(dynamicPoolKey, Constants.SQRT_PRICE_1_1);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = positionManager.mint(
            dynamicPoolKey,
            tickLower,
            tickUpper,
            100e18,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );

        // Step 3: Swap WITHOUT hook (baseline - use static pool)
        uint256 amountIn = 1e18;
        BalanceDelta deltaWithout = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey, // ← static fee pool (3000 BPS)
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        // Step 4: Swap WITH hook (dynamic fee pool, hook adds +10 BPS)
        BalanceDelta deltaWith = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: dynamicPoolKey, // ← dynamic fee pool, hook fires
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        // Step 5: Verify - with +10 BPS fee, you get LESS output
        // amount1 is negative (you receive it), more negative = less received
        assertGt(deltaWith.amount1(), deltaWithout.amount1());
    }

    function testFuzz_CountAlwaysIncrements(uint256 amountIn) public {
        // bound() clamps the random value to a safe range
        // without this, foundry might try amountIn = 0 or type(uint256).max
        amountIn = bound(amountIn, 1000, 1e18);

        uint256 countBefore = feeModifier.beforeSwapCount(poolId);

        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        // No matter what amountIn was, count went up by exactly 1
        assertEq(feeModifier.beforeSwapCount(poolId), countBefore + 1);
    }

    //curently we reurn 0 delta -> verfy swap amounts r unchanged
    //verify if u add non-zero delta -> pool correctly adjust the balances
    function testDelta() public {
        uint256 amountIn = 1e18;

        // Step 1: swap with ZERO_DELTA (current hook)
        // amount0 should be exactly -amountIn
        // nothing extra taken
        BalanceDelta zeroDeltaSwap = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        // Prove ZERO_DELTA didn't touch amounts
        // pool took exactly what we sent, nothing more
        assertEq(int256(zeroDeltaSwap.amount0()), -int256(amountIn));
    }

    function testMultipleSwapsCountIncrement() public {
        // before any swap
        assertEq(feeModifier.beforeSwapCount(poolId), 0);

        uint256 amountIn = 1e18;

        // 1st swap
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        assertEq(feeModifier.beforeSwapCount(poolId), 1); // ← after 1st

        // 2nd swap
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        assertEq(feeModifier.beforeSwapCount(poolId), 2); // ← after 2nd

        // 3rd swap
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        assertEq(feeModifier.beforeSwapCount(poolId), 3); // ← after 3rd
    }

    function testSmallAmountSwap() public {
        uint256 tinyAmountIn = 1000; // 1000 wei, not 1 token

        // Should not revert
        BalanceDelta smallSwap = swapRouter.swapExactTokensForTokens({
            amountIn: tinyAmountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        // Hook still fired even for tiny swap
        assertEq(feeModifier.beforeSwapCount(poolId), 1);

        // amount0 is still exactly -tinyAmountIn
        // (ZERO_DELTA means hook didn't touch amounts)
        assertEq(int256(smallSwap.amount0()), -int256(tinyAmountIn));
    }

    // function testLargeAmountSwap() public {
    //     // type(uint128).max is large but won't overflow int256
    //     // realistically you'd never have this many tokens
    //     // but good to verify no unexpected revert
    //     uint256 largeAmountIn = 1e30; // 1 trillion tokens (18 decimals)

    //     // Need enough liquidity first
    //     // setUp() only adds 100e18, so we need more
    //     // Add extra liquidity here
    //     (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
    //         Constants.SQRT_PRICE_1_1,
    //         TickMath.getSqrtPriceAtTick(tickLower),
    //         TickMath.getSqrtPriceAtTick(tickUpper),
    //         type(uint128).max // max liquidity
    //     );
    //     positionManager.mint(
    //         poolKey,
    //         tickLower,
    //         tickUpper,
    //         type(uint128).max,
    //         amount0Expected + 1,
    //         amount1Expected + 1,
    //         address(this),
    //         block.timestamp,
    //         Constants.ZERO_BYTES
    //     );

    //     // Now swap large amount
    //     BalanceDelta largeSwap = swapRouter.swapExactTokensForTokens({
    //         amountIn: largeAmountIn,
    //         amountOutMin: 0,
    //         zeroForOne: true,
    //         poolKey: poolKey,
    //         hookData: Constants.ZERO_BYTES,
    //         receiver: address(this),
    //         deadline: block.timestamp + 1
    //     });

    //     // Hook still fired
    //     assertEq(feeModifier.beforeSwapCount(poolId), 1);

    //     // amount0 still exactly -largeAmountIn
    //     assertEq(int256(largeSwap.amount0()), -int256(largeAmountIn));
    // }
}
