// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
 
// Use the package aliases that are configured in this workspace's remappings.
import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {ERC1155} from "solmate/src/tokens/ERC1155.sol";
 
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
 
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
 
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
 
contract PointsHook is BaseHook, ERC1155 {
    constructor(
        IPoolManager _manager
    ) BaseHook(_manager) {}
 
	// Set up hook permissions to return `true`
	// for the two hook functions we are using
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }
 
    // Implement the ERC1155 `uri` function
    function uri(uint256) public view virtual override returns (string memory) {
        return "https://api.example.com/token/{id}";
    }
 
	// Stub implementation of `afterSwap`
	function _afterSwap(
    address,
    PoolKey calldata key,
    SwapParams calldata swapParams,
    BalanceDelta delta,
    bytes calldata hookData
) internal override returns (bytes4, int128) {
    // If this is not an ETH-TOKEN pool with this hook attached, ignore
    if (!key.currency0.isAddressZero()) return (this.afterSwap.selector, 0);
 
    // We only mint points if user is buying TOKEN with ETH
    if (!swapParams.zeroForOne) return (this.afterSwap.selector, 0);
 
    // Mint points equal to 20% of the amount of ETH they spent
    // Since it's a zeroForOne swap:
    // if amountSpecified < 0:
    //      this is an "exact input for output" swap
    //      amount of ETH they spent is equal to |amountSpecified|
    // if amountSpecified > 0:
    //      this is an "exact output for input" swap
    //      amount of ETH they spent is equal to BalanceDelta.amount0()
 
    uint256 ethSpendAmount = uint256(int256(-delta.amount0()));
    uint256 pointsForSwap = ethSpendAmount / 5;
 
    // Mint the points
    _assignPoints(key.toId(), hookData, pointsForSwap);
 
    return (this.afterSwap.selector, 0);
}

    function _assignPoints(
    PoolId poolId,bytes calldata hookData,uint256 points
    )internal{
        if(hookData.length == 0) return;

        address user = abi.decode(hookData,(address));

        if(user == address(0)) return;

        // PoolId is a bytes32 value type, so unwrap it before using it as an ERC1155 token id.
        uint256 poolIdUint = uint256(PoolId.unwrap(poolId));
        _mint(user,poolIdUint,points,"");
    }
}