SimpleSwap - A DeFi Router Implementation
Project Overview
This repository contains SimpleSwap.sol, a smart contract that functions as a router for a decentralized exchange (DEX). The project was developed as a final assignment for the ETH Kipu course, module 3. It replicates the core logic and functionalities of a Uniswap v2 Router, designed to interact with a specific Verifier contract that simulates the roles of a Factory and Pair in a real DEX ecosystem.

The implementation demonstrates a comprehensive understanding of key DeFi concepts, secure inter-contract communication patterns, and gas optimization best practices on EVM-compatible blockchains.

Core Concepts Implemented
This project showcases a solid understanding of several crucial Solidity and smart contract development concepts:

DeFi Primitives: Implementation of fundamental DeFi operations:

addLiquidity

removeLiquidity

swapExactTokensForTokens

Inter-Contract Communication: The router effectively communicates with a separate Verifier contract by using Interfaces (ISimpleSwapVerifier, IERC20), ensuring a decoupled and standard-compliant architecture.

ERC20 Token Handling: Secure management of multiple ERC20 tokens, correctly implementing the critical approve and transferFrom flow to handle user funds safely.

Security Patterns: Strict adherence to the Checks-Effects-Interactions pattern, especially in functions that handle token transfers, to mitigate vulnerabilities like re-entrancy attacks.

Mathematical Logic: Correct implementation of the Constant Product Formula (x * y = k) and its variations for calculating swap output amounts (getAmountOut) and displaying prices (getPrice).

Gas Optimization: Conscious decisions were made throughout the development to ensure the contract is as gas-efficient as possible. Key techniques include:

Using view and pure Functions: Functions like getPrice and getAmountOut do not modify the state, allowing users to call them off-chain for free (via a node) to gather information without paying gas.

Minimizing Storage Writes: State-changing operations (SSTORE), which are the most expensive in terms of gas, are kept to a minimum. Calculations are performed in memory first, and state variables are only updated when necessary.

Efficient Data Location: The calldata keyword is used for external function parameters that are only read (e.g., the path array in swapExactTokensForTokens). This is cheaper than using memory as it avoids creating a copy of the data in memory.

Short-Circuiting with require: Placing validation checks at the beginning of functions ensures that the transaction fails early if conditions aren't met. This refunds the remaining gas to the user and avoids wasting it on unnecessary computation.

NatSpec Documentation: All public and external functions are fully documented using the Ethereum Natural Language Specification (NatSpec) for clarity, maintainability, and automatic documentation generation.

Mathematical and Core Logic Analysis
This section breaks down the key mathematical and logical formulas that power the SimpleSwap router.

The Fundamental Principle: x * y = k
The heart of a Uniswap v2 liquidity pool is the constant product formula, where x is the reserve of Token A, y is the reserve of Token B, and k is a constant. This formula governs all core operations.

Function: _quote(amountA, reserveA, reserveB)
This internal utility function is the simplest expression of the pool's price ratio. It answers the question: "To match the value of amountA of the first token, how much of the second token is proportionally required?"

Formula: amountB = (amountA * reserveB) / reserveA

Purpose: It's used by addLiquidity to calculate the optimal token amounts to deposit without shifting the price.

Function: getPrice(tokenA, tokenB)
This function provides the current exchange rate between two tokens. It builds upon _quote to offer a standardized price.

Formula: price = (1e18 * reserveB) / reserveA

Logic: It calculates the price of one full unit of tokenA in terms of tokenB. The 1e18 is used to handle Solidity's lack of floating-point numbers and represent the price with 18 decimals of precision, which is standard for tokens.

Function: getAmountOut(amountIn, reserveIn, reserveOut)
This is the core swap calculation, which determines the output of a trade. It's based on the constant product formula but includes a 0.3% trading fee.

Logic: A 0.3% fee means only 99.7% of the input amount is used for the swap, represented as the fraction 997 / 1000.

Breakdown:

amountInWithFee = amountIn * 997

numerator = amountInWithFee * reserveOut

denominator = (reserveIn * 1000) + amountInWithFee

amountOut = numerator / denominator

Result: This ensures the constant product is maintained, the fee is collected for liquidity providers, and the calculation remains safe within integer arithmetic.

Logic within: addLiquidity
The addLiquidity function contains crucial decision-making logic to ensure liquidity is added at the correct ratio, preventing the provider from altering the pool's price.

Check for Existing Liquidity: It first checks if the pool is empty (reserveA == 0 && reserveB == 0). If it is, it accepts the user's desired amounts as the initial ratio.

Calculate Optimal Amounts: If the pool already has liquidity, it uses _quote to determine the perfect ratio. It first calculates amountBOptimal based on the user's amountADesired.

Decision Path:

If the user provided enough tokenB (amountBDesired >= amountBOptimal), the contract takes all of amountADesired and only the amountBOptimal of tokenB.

If the user did not provide enough tokenB, the contract recalculates using amountBDesired as the fixed point to determine the amountAOptimal it should take.

Purpose: This logic ensures that the user always provides liquidity proportional to the current reserves, preserving the existing price.

Author
Guillermo Siaira