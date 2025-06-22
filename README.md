### **Mathematical Logic Analysis:** getAmountOut

One of the most critical functions in a Uniswap-style router is getAmountOut. This function determines how many output tokens (tokenOut) a user will receive in exchange for an exact amount of input tokens (tokenIn). Its logic is based on the "Constant Product" principle of Automated Market Makers (AMMs), with a slight modification to include a fee.

#### **1\. The Fundamental Principle:** x \* y \= k

The heart of a Uniswap v2 liquidity pool is the constant product formula, where x is the reserve of Token A, y is the reserve of Token B, and k is a constant. Before and after a swap, the value of k must remain the same (or increase due to fees).

Without fees, the equation governing a swap is:

(reserve\_A \+ amountIn) \* (reserve\_B \- amountOut) \= reserve\_A \* reserve\_B

Where amountIn is the amount of Token A entering the pool and amountOut is the amount of Token B leaving it.

#### **2\. Incorporating the 0.3% Fee**

Uniswap v2 charges a fixed 0.3% fee on every swap, which remains in the pool to reward liquidity providers. To implement this without using decimal numbers, fractional arithmetic is used.

A 0.3% fee implies that only **99.7%** of the amountIn is actually used for the exchange. This is represented as the fraction 997 / 1000.

The formula implemented in the contract is broken down as follows:

1. uint amountInWithFee \= amountIn.mul(997);  
   This calculates the portion of the input token that effectively participates in the exchange, after deducting the fee. It's multiplied by 997 to prepare for the fractional calculation.  
2. uint numerator \= amountInWithFee.mul(reserveOut);  
   This calculates the numerator of the formula, which is the adjusted input amount multiplied by the reserve of the output token.  
3. uint denominator \= reserveIn.mul(1000).add(amountInWithFee);  
   This calculates the denominator. The new reserve of the input token will be the original reserve (reserveIn) plus the amount being added (amountInWithFee). To maintain the correct mathematical proportion (since amountInWithFee was multiplied by 997), reserveIn is multiplied by 1000 before the addition.  
4. amountOut \= numerator.div(denominator);  
   Finally, the division is performed to get the amount of output tokens the user will receive.

## **This implementation ensures that the constant product is maintained, the fee is applied correctly, and all calculations are performed safely using only integers, avoiding the complexities and risks of floating-point arithmetic.**

