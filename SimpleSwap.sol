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

    address public verifier;

    constructor(address _verifierAddress) {
        verifier = _verifierAddress;
    }

    /**
     * @notice Calculates the optimal amount of one token based on the other.
     */
    function _quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, "SimpleSwap: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY");
        amountB = amountA.mul(reserveB).div(reserveA);
    }
    
    /**
     * @notice Calculates the output amount for a given input amount and reserves.
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
     * @notice Adds liquidity to an ERC-20 pair pool.
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
        
        // This logic assumes the LP tokens are minted to this contract.
        // It then transfers them to the final recipient `to`.
        uint lpBalance = IERC20(pair).balanceOf(address(this));
        if (lpBalance > 0) {
           IERC20(pair).transfer(to, lpBalance);
        }
    }

    /**
     * @notice Removes liquidity from a pool.
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
        
        ISimpleSwapVerifier(verifier).swap(path[0], amountIn, path[1], amountOutMin);

        uint amountOut = IERC20(path[1]).balanceOf(address(this));
        require(amountOut >= amountOutMin, "SimpleSwap: INSUFFICIENT_OUTPUT_AMOUNT");
        amounts[1] = amountOut;

        IERC20(path[1]).transfer(to, amountOut);
    }

    /**
     * @notice Gets the price of tokenA in terms of tokenB.
     */
    function getPrice(address tokenA, address tokenB) external view returns (uint price) {
        (uint reserveA, uint reserveB) = ISimpleSwapVerifier(verifier).getReserves(tokenA, tokenB);
        require(reserveA > 0, "SimpleSwap: NO_RESERVES");
        price = reserveB.mul(1e18).div(reserveA);
    }
}
