// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title ISimpleSwapVerifier
 * @notice The interface for the course's Verifier contract.
 */
interface ISimpleSwapVerifier {
    function addLiquidity(address tokenA, address tokenB, uint amountA, uint amountB) external returns (uint liquidity);
    function removeLiquidity(address tokenA, address tokenB, uint liquidity) external returns (uint amountA, uint amountB);
    function swap(address tokenIn, uint amountIn, address tokenOut, uint amountOutMin) external;
    function getReserves(address tokenA, address tokenB) external view returns (uint reserveA, uint reserveB);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

/**
 * @title SimpleSwap
 * @author Guillermo Siaira
 * @notice Implements the core functionalities of a decentralized exchange router.
 */
contract SimpleSwap {
    using SafeMath for uint;

    /**
     * @notice The address of the verifier contract used for liquidity and swap operations.
     */
    address public verifier;

    /**
     * @notice Initializes the SimpleSwap contract with the address of the verifier contract.
     * @param _verifierAddress The address of the verifier contract used for liquidity and swap operations.
     */
    constructor(address _verifierAddress) {
        verifier = _verifierAddress;
    }

    /**
     * @notice Calculates the amount of tokenB required to match the value of a given amount of tokenA based on pool reserves.
     * @param amountA The amount of tokenA to be provided.
     * @param reserveA The current reserve of tokenA in the pool.
     * @param reserveB The current reserve of tokenB in the pool.
     * @return amountB The calculated amount of tokenB proportional to amountA.
     */
    function _quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, "SimpleSwap: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY");
        amountB = amountA.mul(reserveB).div(reserveA);
    }
    
    /**
     * @notice Calculates the amount of output tokens received for a given input amount and pool reserves.
     * @dev Applies a 0.3% fee (997/1000) to the input amount as per the constant product formula.
     * @param amountIn The amount of input tokens to be swapped.
     * @param reserveIn The current reserve of the input token in the pool.
     * @param reserveOut The current reserve of the output token in the pool.
     * @return amountOut The calculated amount of output tokens to be received.
     */
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure returns (uint amountOut) {
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY");
        
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator.div(denominator);
    }

    /**
     * @notice Adds liquidity to an ERC-20 token pair pool.
     * @dev Calculates optimal token amounts based on pool reserves and mints LP tokens to the recipient. If the pool is empty, uses desired amounts; otherwise, ensures proportional deposits.
     * @param tokenA The address of the first token in the pair.
     * @param tokenB The address of the second token in the pair.
     * @param amountADesired The desired amount of tokenA to add.
     * @param amountBDesired The desired amount of tokenB to add.
     * @param amountAMin The minimum acceptable amount of tokenA to add.
     * @param amountBMin The minimum acceptable amount of tokenB to add.
     * @param to The address that will receive the LP tokens.
     * @param deadline The timestamp by which the transaction must be mined.
     * @return amountA The actual amount of tokenA added to the pool.
     * @return amountB The actual amount of tokenB added to the pool.
     * @return liquidity The amount of LP tokens minted.
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity) {
        require(deadline >= block.timestamp, "SimpleSwap: EXPIRED");

        (uint reserveA, uint reserveB) = ISimpleSwapVerifier(verifier).getReserves(tokenA, tokenB);

        if (reserveA == 0 && reserveB == 0) {
            amountA = amountADesired;
            amountB = amountBDesired;
        } else {
            uint amountBOptimal = _quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "SimpleSwap: INSUFFICIENT_B_AMOUNT");
                amountA = amountADesired;
                amountB = amountBOptimal;
            } else {
                uint amountAOptimal = _quote(amountBDesired, reserveB, reserveA);
                require(amountAOptimal <= amountADesired, "SimpleSwap: LOGIC_ERROR");
                require(amountAOptimal >= amountAMin, "SimpleSwap: INSUFFICIENT_A_AMOUNT");
                amountA = amountAOptimal;
                amountB = amountBDesired;
            }
        }

        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);

        IERC20(tokenA).approve(verifier, amountA);
        IERC20(tokenB).approve(verifier, amountB);

        liquidity = ISimpleSwapVerifier(verifier).addLiquidity(tokenA, tokenB, amountA, amountB);

        address pair = ISimpleSwapVerifier(verifier).getPair(tokenA, tokenB);
        require(pair != address(0), "SimpleSwap: PAIR_NOT_FOUND");
        
        uint lpBalance = IERC20(pair).balanceOf(address(this));
        if (lpBalance > 0) {
           IERC20(pair).transfer(to, lpBalance);
        }
    }

    /**
     * @notice Removes liquidity from an ERC-20 token pair pool.
     * @dev Burns LP tokens and transfers the corresponding amounts of tokenA and tokenB to the recipient.
     * @param tokenA The address of the first token in the pair.
     * @param tokenB The address of the second token in the pair.
     * @param liquidity The amount of LP tokens to burn.
     * @param amountAMin The minimum acceptable amount of tokenA to receive.
     * @param amountBMin The minimum acceptable amount of tokenB to receive.
     * @param to The address that will receive the tokens.
     * @param deadline The timestamp by which the transaction must be mined.
     * @return amountA The amount of tokenA received.
     * @return amountB The amount of tokenB received.
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB) {
        require(deadline >= block.timestamp, "SimpleSwap: EXPIRED");

        address pair = ISimpleSwapVerifier(verifier).getPair(tokenA, tokenB);
        require(pair != address(0), "SimpleSwap: PAIR_NOT_FOUND");
        
        IERC20(pair).transferFrom(msg.sender, address(this), liquidity);
        IERC20(pair).approve(verifier, liquidity);
        
        (amountA, amountB) = ISimpleSwapVerifier(verifier).removeLiquidity(tokenA, tokenB, liquidity);

        require(amountA >= amountAMin, "SimpleSwap: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "SimpleSwap: INSUFFICIENT_B_AMOUNT");

        IERC20(tokenA).transfer(to, amountA);
        IERC20(tokenB).transfer(to, amountB);
    }

    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible.
     * @dev Supports direct swaps (single token pair). The path array must contain exactly two token addresses.
     * @param amountIn The amount of input tokens to swap.
     * @param amountOutMin The minimum acceptable amount of output tokens to receive.
     * @param path An array of token addresses representing the swap path (input token, output token).
     * @param to The address that will receive the output tokens.
     * @param deadline The timestamp by which the transaction must be mined.
     * @return amounts An array containing the input amount and the output amount.
     */
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(path.length >= 2, "SimpleSwap: INVALID_PATH");
        require(deadline >= block.timestamp, "SimpleSwap: EXPIRED");

        amounts = new uint[](path.length);
        amounts[0] = amountIn;

        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[0]).approve(verifier, amountIn);
        
        ISSimpleSwapVerifier(verifier).swap(path[0], amountIn, path[1], amountOutMin);

        uint amountOut = IERC20(path[1]).balanceOf(address(this));
        require(amountOut >= amountOutMin, "SimpleSwap: INSUFFICIENT_OUTPUT_AMOUNT");
        amounts[1] = amountOut;

        IERC20(path[1]).transfer(to, amountOut);
    }

    /**
     * @notice Calculates the price of tokenA in terms of tokenB based on pool reserves.
     * @dev Returns the price with 18 decimals of precision (multiplied by 1e18).
     * @param tokenA The address of the token to price.
     * @param tokenB The address of the token in which the price is denominated.
     * @return price The price of tokenA in terms of tokenB.
     */
    function getPrice(address tokenA, address tokenB) external view returns (uint price) {
        (uint reserveA, uint reserveB) = ISimpleSwapVerifier(verifier).getReserves(tokenA, tokenB);
        require(reserveA > 0, "SimpleSwap: NO_RESERVES");
        price = reserveB.mul(1e18).div(reserveA);
    }
}