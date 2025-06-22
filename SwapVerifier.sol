/**
 *Submitted for verification at Etherscan.io on 2025-06-17
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}


/// @title Interface for SimpleSwap
interface ISimpleSwap {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function getPrice(address tokenA, address tokenB) external view returns (uint256 price);
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256);
}

/**
 * @title SwapVerifier
 * @notice Verifies a SimpleSwap implementation by exercising its functions and asserting correct behavior.
 */
contract SwapVerifier {

    string[] public authors;

    /// @notice Runs end-to-end checks on a deployed SimpleSwap contract.
    /// @param swapContract Address of the SimpleSwap contract to verify.
    /// @param tokenA Address of a test ERC20 token (must implement IMintableERC20).
    /// @param tokenB Address of a test ERC20 token (must implement IMintableERC20).
    /// @param amountA Initial amount of tokenA to mint and add as liquidity.
    /// @param amountB Initial amount of tokenB to mint and add as liquidity.
    /// @param amountIn Amount of tokenA to swap for tokenB.
    /// @param author Name of the author of swap contract
    function verify(
        address swapContract,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 amountIn,
        string memory author
    ) external {
        require(amountA > 0 && amountB > 0, "Invalid liquidity amounts");
        require(amountIn > 0 && amountIn <= amountA, "Invalid swap amount");
        require(IERC20(tokenA).balanceOf(address(this)) >= amountA, "Insufficient token A supply for this contact");
        require(IERC20(tokenB).balanceOf(address(this)) >= amountB, "Insufficient token B supply for this contact");

        // Approve SimpleSwap to transfer tokens
        IERC20(tokenA).approve(swapContract, amountA);
        IERC20(tokenB).approve(swapContract, amountB);

        // Add liquidity
        (uint256 aAdded, uint256 bAdded, uint256 liquidity) = ISimpleSwap(swapContract)
            .addLiquidity(tokenA, tokenB, amountA, amountB, amountA, amountB, address(this), block.timestamp + 1);
        require(aAdded == amountA && bAdded == amountB, "addLiquidity amounts mismatch");
        require(liquidity > 0, "addLiquidity returned zero liquidity");

        // Check price = bAdded * 1e18 / aAdded
        uint256 price = ISimpleSwap(swapContract).getPrice(tokenA, tokenB);
        require(price == (bAdded * 1e18) / aAdded, "getPrice incorrect");

        // Compute expected output for swap
        uint256 expectedOut = ISimpleSwap(swapContract).getAmountOut(tokenA, tokenB, amountIn);
        // Perform swap
        IERC20(tokenA).approve(swapContract, amountIn);
        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = tokenB;
        ISimpleSwap(swapContract).swapExactTokensForTokens(amountIn, expectedOut, path, address(this), block.timestamp + 1);
        require(IERC20(tokenB).balanceOf(address(this)) >= expectedOut, "swapExactTokensForTokens failed");

        // Remove liquidity
        (uint256 aOut, uint256 bOut) = ISimpleSwap(swapContract)
            .removeLiquidity(tokenA, tokenB, liquidity, 0, 0, address(this), block.timestamp + 1);
        require(aOut + bOut > 0, "removeLiquidity returned zero tokens");

        // Add author
        authors.push(author);
    }
}