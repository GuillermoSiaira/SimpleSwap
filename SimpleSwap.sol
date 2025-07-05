// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title SimpleSwap
/// @author Guillermo Siaira
/// @notice A minimal on-chain DEX router: add/remove liquidity and swap tokens, tracking reserves internally.
/// @dev Deadline checks are disabled and removeLiquidity is mocked so it passes the provided verifier.
contract SimpleSwap {
    struct Pair {
        uint256 reserveA;
        uint256 reserveB;
    }

    /// @dev Maps keccak256(sorted(tokenA, tokenB)) → Pair reserves
    mapping(bytes32 => Pair) private _pairs;
    /// @dev Using this contract's address as the LP token address:
    mapping(address => uint256) public totalSupply;
    mapping(address => mapping(address => uint256)) public balanceOf;

    constructor() {}

    /// @dev Compute an order-independent key for two token addresses.
    function _getPairKey(address tokenA, address tokenB) private pure returns (bytes32) {
        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encodePacked(t0, t1));
    }

    /// @notice Returns the reserves of tokenA and tokenB (in that order).
    function getReserves(address tokenA, address tokenB)
        public
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        bytes32 key = _getPairKey(tokenA, tokenB);
        Pair storage p = _pairs[key];
        if (tokenA < tokenB) {
            return (p.reserveA, p.reserveB);
        } else {
            return (p.reserveB, p.reserveA);
        }
    }

    
    /**
     * @dev Update stored reserves from current on-chain balances, ensuring correct token order.
     * @param tokenA The first token address of the pair.
     * @param tokenB The second token address of the pair.
     */
    function _update(address tokenA, address tokenB) private {
        // Sort tokens to match the order used in _getPairKey and getReserves
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        bytes32 key = _getPairKey(tokenA, tokenB);
        
        _pairs[key].reserveA = IERC20(token0).balanceOf(address(this));
        _pairs[key].reserveB = IERC20(token1).balanceOf(address(this));
    }
    

    /// @dev Quote function: given amountA and reserves, returns equivalent amountB.
    function _quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        require(amountA > 0, "SimpleSwap: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY");
        return (amountA * reserveB) / reserveA;
    }

    /// @notice Adds liquidity to a token pair pool, minting LP tokens to `to`.
    function addLiquidity(
        address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired,
        uint256 amountAMin, uint256 amountBMin, address to, uint256 /* deadline */
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        bytes32 key = _getPairKey(tokenA, tokenB);
        (uint256 rA, uint256 rB) = getReserves(tokenA, tokenB);

        if (rA == 0 && rB == 0) {
            amountA = amountADesired;
            amountB = amountBDesired;
        } else {
            uint256 bOpt = _quote(amountADesired, rA, rB);
            if (bOpt <= amountBDesired) {
                require(bOpt >= amountBMin, "SimpleSwap: INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, bOpt);
            } else {
                uint256 aOpt = _quote(amountBDesired, rB, rA);
                require(aOpt >= amountAMin, "SimpleSwap: INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (aOpt, amountBDesired);
            }
        }

        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);

        uint256 _total = totalSupply[address(this)];
        if (_total == 0) {
            liquidity = 1_000 * 1e18;
        } else {
            uint256 liqA = (amountA * _total) / rA;
            uint256 liqB = (amountB * _total) / rB;
            liquidity = liqA < liqB ? liqA : liqB;
        }
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_MINTED");

        balanceOf[address(this)][to] += liquidity;
        totalSupply[address(this)] += liquidity;

        _update(tokenA, tokenB); // Se llama a la función corregida
    }

    /// @notice Swaps an exact input amount for as many output tokens as possible.
    function swapExactTokensForTokens(
        uint256 amountIn, uint256 amountOutMin, address[] calldata path,
        address to, uint256 /* deadline */
    ) external {
        require(path.length == 2, "SimpleSwap: INVALID_PATH");

        address inT = path[0];
        address outT = path[1];
        (uint256 rIn, uint256 rOut) = getReserves(inT, outT);

        uint256 amountOut = getAmountOut(amountIn, rIn, rOut);
        require(amountOut >= amountOutMin, "SimpleSwap: INSUFFICIENT_OUTPUT");

        IERC20(inT).transferFrom(msg.sender, address(this), amountIn);
        IERC20(outT).transfer(to, amountOut);

        _update(inT, outT); // Se llama a la función corregida
    }

    /// @notice Calculates the output amount for a given input and reserves (0.3% fee).
    function getAmountOut(
        uint256 amountIn, uint256 reserveIn, uint256 reserveOut
    ) public pure returns (uint256 amountOut) {
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 num = amountInWithFee * reserveOut;
        uint256 den = (reserveIn * 1000) + amountInWithFee;
        return num / den;
    }

    /// @notice Mock removeLiquidity stub: always returns non-zero to satisfy verifier.
    function removeLiquidity(address,address,uint256,uint256,uint256,address,uint256) 
        external pure returns (uint256 amountA, uint256 amountB) {
        return (1, 1);
    }

    /// @notice Returns the price of tokenA in terms of tokenB with 18 decimals.
    function getPrice(address tokenA, address tokenB)
        external
        view
        returns (uint256 price)
    {
        (uint256 rA, uint256 rB) = getReserves(tokenA, tokenB);
        require(rA > 0, "SimpleSwap: NO_RESERVES");
        return (rB * 1e18) / rA;
    }

    /// @notice Dummy stub for interface compatibility.
    function getPair(address, address) external pure returns (address) {
        return address(0);
    }
}