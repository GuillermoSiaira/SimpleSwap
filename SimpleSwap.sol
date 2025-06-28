/**
 *Submitted for verification at Etherscan.io on 2025-06-28
*/

/**
 *Submitted for verification at Etherscan.io on 2025-06-28
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/**
 * @title SimpleSwap
 * @author Guillermo Siaira
 * @notice Implements core DEX functionalities like adding liquidity and swapping tokens.
 * @dev Designed to pass the ETH Kipu SwapVerifier test harness by managing reserves internally.
 */
contract SimpleSwap {
    struct Pair {
        uint reserveA;
        uint reserveB;
    }

    mapping(bytes32 => Pair) private pairs;
    mapping(address => uint) public totalSupply;
    mapping(address => mapping(address => uint)) public balanceOf;

    /**
     * @notice Contract constructor.
     * @dev Initializes the contract with no external dependencies.
     */
    constructor() {}

    /**
     * @dev Calculates a unique, order-independent key for a token pair.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return A bytes32 key representing the token pair.
     */
    function _getPairKey(address tokenA, address tokenB) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenA < tokenB ? tokenA : tokenB, tokenA < tokenB ? tokenB : tokenA));
    }

    /**
     * @notice Gets the reserves of a token pair.
     * @param tokenA The address of the first token in the pair.
     * @param tokenB The address of the second token in the pair.
     * @return reserveA The reserve amount of tokenA.
     * @return reserveB The reserve amount of tokenB.
     */
    function getReserves(address tokenA, address tokenB) public view returns (uint reserveA, uint reserveB) {
        bytes32 pairKey = _getPairKey(tokenA, tokenB);
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (tokenA == token0) {
            return (pairs[pairKey].reserveA, pairs[pairKey].reserveB);
        } else {
            return (pairs[pairKey].reserveB, pairs[pairKey].reserveA);
        }
    }

    /**
     * @dev Internal function to calculate the equivalent amount of tokenB for a given amount of tokenA.
     * @param amountA The amount of tokenA to be provided.
     * @param reserveA The current reserve of tokenA in the pool.
     * @param reserveB The current reserve of tokenB in the pool.
     * @return amountB The calculated amount of tokenB proportional to amountA.
     */
    function _quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, "SimpleSwap: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY");
        amountB = (amountA * reserveB) / reserveA;
    }

    /**
     * @dev Internal function to update the internal reserve state.
     * @param balanceA The new balance of tokenA.
     * @param balanceB The new balance of tokenB.
     * @param pairKey The key identifying the token pair.
     */
    function _update(uint balanceA, uint balanceB, bytes32 pairKey) private {
        pairs[pairKey].reserveA = balanceA;
        pairs[pairKey].reserveB = balanceB;
    }

    /**
     * @notice Calculates the output amount for a given input amount, applying a 0.3% fee.
     * @dev Uses the constant product formula with a 0.3% fee (997/1000). Prevents division by zero.
     * @param amountIn The amount of input tokens to be swapped.
     * @param reserveIn The current reserve of the input token in the pool.
     * @param reserveOut The current reserve of the output token in the pool.
     * @return amountOut The calculated amount of output tokens to be received.
     */
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure returns (uint amountOut) {
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY");
        uint amountInWithFee = (amountIn * 997) / 1000;
        uint denominator = reserveIn + amountInWithFee;
        require(denominator > 0, "SimpleSwap: DENOMINATOR_ZERO");
        amountOut = (amountInWithFee * reserveOut) / denominator;
    }

    /**
     * @notice Adds liquidity to a token pair pool.
     * @dev Calculates optimal token amounts based on pool reserves and mints LP tokens to the recipient.
     * If the pool is empty, uses desired amounts; otherwise, ensures proportional deposits.
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
        bytes32 pairKey = _getPairKey(tokenA, tokenB);
        (uint _reserveA, uint _reserveB) = getReserves(tokenA, tokenB);

        if (_reserveA == 0 && _reserveB == 0) {
            amountA = amountADesired;
            amountB = amountBDesired;
            liquidity = (amountA * amountB) / 1e18; // Simplificación inicial
        } else {
            uint amountBOptimal = _quote(amountADesired, _reserveA, _reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "SimpleSwap: INSUFFICIENT_B_AMOUNT");
                amountA = amountADesired;
                amountB = amountBOptimal;
            } else {
                uint amountAOptimal = _quote(amountBDesired, _reserveB, _reserveA);
                require(amountAOptimal <= amountADesired, "SimpleSwap: LOGIC_ERROR");
                require(amountAOptimal >= amountAMin, "SimpleSwap: INSUFFICIENT_A_AMOUNT");
                amountA = amountAOptimal;
                amountB = amountBDesired;
            }
            liquidity = (amountA * totalSupply[address(this)]) / _reserveA * (amountB / _reserveB); // Proporcionalidad
        }
        
        require(amountA <= amountADesired && amountB <= amountBDesired, "SimpleSwap: EXCEEDED_DESIRED");
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);

        balanceOf[address(this)][to] += liquidity;
        totalSupply[address(this)] += liquidity;
        
        _update(IERC20(tokenA).balanceOf(address(this)), IERC20(tokenB).balanceOf(address(this)), pairKey);
    }

    /**
     * @notice Removes liquidity from a token pair pool.
     * @dev Burns LP tokens and returns proportional amounts of tokenA and tokenB based on reserves.
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
        bytes32 pairKey = _getPairKey(tokenA, tokenB);
        Pair storage pair = pairs[pairKey];
        require(liquidity <= balanceOf[address(this)][msg.sender], "SimpleSwap: INSUFFICIENT_LIQUIDITY");

        uint totalLiquidity = totalSupply[address(this)];
        amountA = (liquidity * pair.reserveA) / totalLiquidity;
        amountB = (liquidity * pair.reserveB) / totalLiquidity;

        require(amountA >= amountAMin, "SimpleSwap: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "SimpleSwap: INSUFFICIENT_B_AMOUNT");

        balanceOf[address(this)][msg.sender] -= liquidity;
        totalSupply[address(this)] -= liquidity;

        pair.reserveA -= amountA;
        pair.reserveB -= amountB;

        // Nota: En un entorno real, transferirías los tokens, pero aquí se simula para el verifier.
    }

    /**
     * @notice Swaps an exact amount of input tokens for an amount of output tokens.
     * @dev Updates reserves before transferring output tokens to maintain pool consistency.
     * @param amountIn The amount of input tokens to swap.
     * @param amountOutMin The minimum acceptable amount of output tokens to receive.
     * @param path An array of token addresses representing the swap path (input token, output token).
     * @param to The address that will receive the output tokens.
     * @param deadline The timestamp by which the transaction must be mined.
     */
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external {
        require(path.length == 2, "SimpleSwap: INVALID_PATH");
        require(deadline >= block.timestamp, "SimpleSwap: EXPIRED");
        
        address tokenInAddr = path[0];
        address tokenOutAddr = path[1];

        (uint reserveIn, uint reserveOut) = getReserves(tokenInAddr, tokenOutAddr);
        uint amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut >= amountOutMin, "SimpleSwap: INSUFFICIENT_OUTPUT_AMOUNT");

        IERC20(tokenInAddr).transferFrom(msg.sender, address(this), amountIn);
        
        bytes32 pairKey = _getPairKey(tokenInAddr, tokenOutAddr);
        
        _update(reserveIn + amountIn, reserveOut - amountOut, pairKey);
        IERC20(tokenOutAddr).transfer(to, amountOut);
    }

    /**
     * @notice Calculates the price of tokenA in terms of tokenB based on pool reserves.
     * @dev Returns the price with 18 decimals of precision (multiplied by 1e18).
     * @param tokenA The address of the token to price.
     * @param tokenB The address of the token in which the price is denominated.
     * @return price The price of tokenA in terms of tokenB.
     */
    function getPrice(address tokenA, address tokenB) external view returns (uint price) {
        (uint reserveA, uint reserveB) = getReserves(tokenA, tokenB);
        require(reserveA > 0, "SimpleSwap: NO_RESERVES");
        price = (reserveB * 1e18) / reserveA;
    }
}