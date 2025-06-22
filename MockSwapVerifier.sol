// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SimpleSwap.sol"; 
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// Este es un contrato ERC20 simple que usaremos para simular los LP Tokens.
contract MockLPToken is ERC20, Ownable {
    constructor() ERC20("Mock LP Token", "MLP") Ownable(msg.sender) {}
    
    // Función para que el "dueño" (el MockVerifier) pueda crear nuevos LP tokens.
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount);
    }
}


/**
 * @title MockSwapVerifier
 * @notice Un contrato mock más avanzado para simular el Verificador real.
 */
contract MockSwapVerifier is ISimpleSwapVerifier {
    using SafeMath for uint;

    mapping(bytes32 => address) public pairs;
    mapping(address => uint) public reserves0;
    mapping(address => uint) public reserves1;
    mapping(address => address) public token0;
    mapping(address => address) public token1;

    function _getPairHash(address _tokenA, address _tokenB) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            _tokenA < _tokenB ? _tokenA : _tokenB,
            _tokenA < _tokenB ? _tokenB : _tokenA
        ));
    }

    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) { z = x; x = (y / x + x) / 2; }
        } else if (y != 0) { z = 1; }
    }

    function createPair(address _tokenA, address _tokenB) external returns (address pair) {
        bytes32 pairHash = _getPairHash(_tokenA, _tokenB);
        require(pairs[pairHash] == address(0), "PAIR_EXISTS");
        
        MockLPToken newPairToken = new MockLPToken();
        pair = address(newPairToken);
        
        pairs[pairHash] = pair;
        (token0[pair], token1[pair]) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
    }

    function getPair(address _tokenA, address _tokenB) public view override returns (address pair) {
        pair = pairs[_getPairHash(_tokenA, _tokenB)];
    }

    function getReserves(address _tokenA, address _tokenB) external view override returns (uint reserveA, uint reserveB) {
        address pair = getPair(_tokenA, _tokenB);
        if (pair != address(0)) {
            (uint res0, uint res1) = (reserves0[pair], reserves1[pair]);
            (reserveA, reserveB) = _tokenA == token0[pair] ? (res0, res1) : (res1, res0);
        }
    }

    function addLiquidity(address _tokenA, address _tokenB, uint amountA, uint amountB) external override returns (uint liquidity) {
        address pair = getPair(_tokenA, _tokenB);
        require(pair != address(0), "PAIR_NOT_FOUND");
        
        IERC20(_tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(_tokenB).transferFrom(msg.sender, address(this), amountB);
        
        liquidity = sqrt(amountA.mul(amountB));
        
        MockLPToken(pair).mint(msg.sender, liquidity);
        
        (uint res0, uint res1) = (reserves0[pair], reserves1[pair]);
        (address t0,) = (token0[pair], token1[pair]);

        if(_tokenA == t0) {
            reserves0[pair] = res0.add(amountA);
            reserves1[pair] = res1.add(amountB);
        } else {
            reserves0[pair] = res0.add(amountB);
            reserves1[pair] = res1.add(amountA);
        }
    }
    
    function removeLiquidity(address _tokenA, address _tokenB, uint _liquidity) external override returns (uint amountA, uint amountB) {
        address pair = getPair(_tokenA, _tokenB);
        uint totalSupply = ERC20(pair).totalSupply();
        (uint reserve0, uint reserve1) = (reserves0[pair], reserves1[pair]);

        amountA = _liquidity.mul(reserve0).div(totalSupply);
        amountB = _liquidity.mul(reserve1).div(totalSupply);

        reserves0[pair] = reserves0[pair].sub(amountA);
        reserves1[pair] = reserves1[pair].sub(amountB);

        MockLPToken(pair).burn(msg.sender, _liquidity);
        
        IERC20(token0[pair]).transfer(msg.sender, amountA);
        IERC20(token1[pair]).transfer(msg.sender, amountB);
    }
    
    function swap(address _tokenIn, uint _amountIn, address _tokenOut, uint _amountOutMin) external override {
        (uint reserveIn, uint reserveOut) = this.getReserves(_tokenIn, _tokenOut);
        
        uint amountInWithFee = _amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        uint amountOut = numerator.div(denominator);
        require(amountOut >= _amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");

        // CORRECCIÓN: Simplificamos para evitar "Stack too deep"
        address pair = getPair(_tokenIn, _tokenOut);
        address t0 = token0[pair];
        
        if(_tokenIn == t0) {
            reserves0[pair] = reserves0[pair].add(_amountIn);
            reserves1[pair] = reserves1[pair].sub(amountOut);
        } else {
            reserves1[pair] = reserves1[pair].add(_amountIn);
            reserves0[pair] = reserves0[pair].sub(amountOut);
        }

        IERC20(_tokenIn).transferFrom(msg.sender, address(this), _amountIn);
        IERC20(_tokenOut).transfer(msg.sender, amountOut);
    }
}
