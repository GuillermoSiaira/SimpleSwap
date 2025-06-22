// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title ISimpleSwapVerifier
 * @notice Interfaz para el contrato Verificador del curso.
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
 * @author Guillermo Siara
 * @notice Implementa las funcionalidades de un router de exchange descentralizado.
 */
contract SimpleSwap {
    using SafeMath for uint;

    address public verifier;

    constructor(address _verifierAddress) {
        verifier = _verifierAddress;
    }

    /**
     * @notice Calcula la cantidad óptima de un token basada en el otro.
     */
    function _quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, "SimpleSwap: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY");
        amountB = amountA.mul(reserveB).div(reserveA);
    }
    
    /**
     * @notice Calcula la cantidad de salida para una cantidad de entrada y reservas dadas.
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
     * @notice Añade liquidez a un par de tokens ERC-20.
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
        
        IERC20(pair).transfer(to, IERC20(pair).balanceOf(address(this)));
    }

    /**
     * @notice Retira liquidez de un pool.
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
     * @notice Intercambia una cantidad exacta de tokens de entrada por tantos tokens de salida como sea posible.
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
     * @notice Obtiene el precio de tokenA en términos de tokenB.
     */
    function getPrice(address tokenA, address tokenB) external view returns (uint price) {
        (uint reserveA, uint reserveB) = ISimpleSwapVerifier(verifier).getReserves(tokenA, tokenB);
        require(reserveA > 0, "SimpleSwap: NO_RESERVES");
        price = reserveB.mul(1e18).div(reserveA);
    }
}
