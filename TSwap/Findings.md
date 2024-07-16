## Title
[H-1] Users pay 10x the amount they should during exact-output-swaps due to incorrect input amount based on output in `TSwapPool::getInputAmountBasedOnOutput()`.

## Summary
The input amount based on output should be 99.7% of the input after the subtraction of the 0.3% fee. However, according to the function `TSwapPool::getInputAmountBasedOnOutput()`, the input is 1,003%, which is more than 10 times the input before taking fees.

## Vulnerability Details
```javascript

    function getInputAmountBasedOnOutput(
        uint256 outputAmount,
        uint256 inputReserves,
        uint256 outputReserves
    )
        public
        pure
        revertIfZero(outputAmount)
        revertIfZero(outputReserves)
        returns (uint256 inputAmount)
    {
        return
        // @audit wrong input calculation
@>          ((inputReserves * outputAmount) * 10000) /
            ((outputReserves - outputAmount) * 997);
    }
```
<details>
<summary>PoC</summary>
Add the following to a test file.

```javascript
    function setUp() public {
        poolToken = new ERC20Mock();
        weth = new ERC20Mock();
        pool = new TSwapPool(address(poolToken), address(weth), "LTokenA", "LA");

        weth.mint(liquidityProvider, 200e18);
        poolToken.mint(liquidityProvider, 200e18);

        weth.mint(user, 20e18);
        poolToken.mint(user, 20e18);
    }

    function testSwapExactOutput() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(user);
        poolToken.approve(address(pool), 20e18);
        // Before swap:
        // 100 pool token, 100 weth, 100 LP token

        // After we swap, there will be ~99 weth, and ~101 pool token
        // x*y=k
        // 100 * 100 = 10,000
        // x * 99 = 10,000 => x = 101

        // Expected user balance = 20-1 = 19
        // Expected user balance due to vulnerability = 20 - 1 * 10 = 10
        uint256 expectedBalance = 10e18;

        pool.swapExactOutput(poolToken, weth, 1e18, uint64(block.timestamp));
        console.log(poolToken.balanceOf(user));
        console.log(weth.balanceOf(user));
        assert(weth.balanceOf(user) >= 1e18);
        assert(poolToken.balanceOf(user) <= expectedBalance);

    }
```
The test demonstrates how the user is swapping 10.13e18 pool tokens for 1 weth.
![alt text](image.png)
</details>

## Impact
Users are paying ~10x the amounts they should pay during swaps using `TSwapPool::swapExactOutput()`, which means they are losing funds. In addition, this will lead to drastic changes in the 

## Tools Used
Manual review, tests.

## Recommendations
Fix the input calculation in the function `TSwapPool::getInputAmountBasedOnOutput()` as follows:
```diff
    function getInputAmountBasedOnOutput(
        uint256 outputAmount,
        uint256 inputReserves,
        uint256 outputReserves
    )
        public
        pure
        revertIfZero(outputAmount)
        revertIfZero(outputReserves)
        returns (uint256 inputAmount)
    {
+       uint256 numerator = (inputReserves * outputAmount) * 1000;
+       uint256 denumerator = (outputReserves - outputAmount) * 997;
        return
-           ((inputReserves * outputAmount) * 10000) /
-           ((outputReserves - outputAmount) * 997);
+           numerator/denumerator;

    }
```

---
## Title
[M-1] Unfair reward distribution due to frontruning the `TSwapPool::swap_count`.

## Summary
Malicious actors can frontrun `TSwapPool::swap_count` to get the extra token rewarded every 10 swaps.

## Vulnerability Details
Although `TSwapPool::swap_count` is private, it still can be accessed on-chain.
```javascript
    function _swap(
        IERC20 inputToken,
        uint256 inputAmount,
        IERC20 outputToken,
        uint256 outputAmount
    ) private {
        if (
            _isUnknown(inputToken) ||
            _isUnknown(outputToken) ||
            inputToken == outputToken
        ) {
            revert TSwapPool__InvalidToken();
        }

        // update----------------------------------
        swap_count++;

        // @audit frontrun the swap_count to always get the extra token
@>      if (swap_count >= SWAP_COUNT_MAX) {
            swap_count = 0;
            outputToken.safeTransfer(msg.sender, 1_000_000_000_000_000_000);
        }
```

## Impact
Unfair reward distribution.

## Tools Used
Manual review.

## Recommendations
Make the rwards time-weighted.

---

## Title
[M-2] Possible slippage caused by the absence of a deadline implementation in `TSwapPool::deposit()`.

## Summary
The function `TSwapPool::deposit()` has a `deadline` parameter but it's not used. This implies that the function doesn not check for the deadline for which the transaction is to be completed by as it's supposed to.

## Vulnerability Details
The `TSwapPool::revertIfDeadlinePassed` modifier is not implemented in the `TSwapPool::deposit()` function.

```javascript
    /// @param deadline The deadline for the transaction to be completed by
    function deposit(
        uint256 wethToDeposit,
        uint256 minimumLiquidityTokensToMint,
        uint256 maximumPoolTokensToDeposit,
@>      uint64 deadline
    )
        external
        // @audit no deadline check is implemented
        revertIfZero(wethToDeposit)
        returns (uint256 liquidityTokensToMint)
    {

```

## Impact
The absence of a deadline check can lead to delayed deposit transactions, which may leave room for slippage vulnerability to occur.

## Tools Used
Manual review.

## Recommendations
implement a deadline check.
```diff
function deposit(
        uint256 wethToDeposit,
        uint256 minimumLiquidityTokensToMint,
        uint256 maximumPoolTokensToDeposit,
        uint64 deadline
    )
        external
+       modifier revertIfDeadlinePassed(deadline) 
        revertIfZero(wethToDeposit)
        returns (uint256 liquidityTokensToMint)
    {
```
---

## Title
[L-1] Bad user experience due to incorrect order of event parameters.

## Summary
The parameters of the event `TSwapPool::LiquidityAdded` emitted in the function `TSwapPool::_addLiquidityMintAndTransfer()` are not correctly ordered.

## Vulnerability Details
The event `TSwapPool::LiquidityAdded` emits incorrect values of the pool token to deposit and weth to deposit.

```javascript

    function _addLiquidityMintAndTransfer(
        uint256 wethToDeposit,
        uint256 poolTokensToDeposit,
        uint256 liquidityTokensToMint
    ) private {
        _mint(msg.sender, liquidityTokensToMint);

        // @audit incorrect order of parameters
@>      emit LiquidityAdded(msg.sender, poolTokensToDeposit, wethToDeposit);

    }
```

## Impact
Bad user experience due to confusion and misinterpretation of emitted data. In addition to debugging difficulties and logging issues.

## Tools Used
Manual review.

## Recommendations
Fix the order of the parameters `poolTokensToDeposit` and `wethToDeposit` as shown below.
```diff

    function _addLiquidityMintAndTransfer(
        uint256 wethToDeposit,
        uint256 poolTokensToDeposit,
        uint256 liquidityTokensToMint
    ) private {
        _mint(msg.sender, liquidityTokensToMint);

-       emit LiquidityAdded(msg.sender, poolTokensToDeposit, wethToDeposit);
+       emit LiquidityAdded(msg.sender, wethToDeposit, poolTokensToDeposit);

    }
```

---
## Title 
[L-2] Bad user experience due to incorrect error names.

## Summary
`TSwapPool::TSwapPool__MaxPoolTokenDepositTooHigh` and  `TSwapPool::TSwapPool__MinLiquidityTokensToMintTooLow` names indicate incorrect errors.
When `maximumPoolTokensToDeposit` is less than `poolTokensToDeposit`, then the `maximumPoolTokensToDeposit` is too low and not high. Similarly, when `liquidityTokensToMint` is less than `minimumLiquidityTokensToMint`, then `minimumLiquidityTokensToMint` is too high and not too low.

## Vulnerability Details
```javascript

    function deposit(
        uint256 wethToDeposit,
        uint256 minimumLiquidityTokensToMint,
        uint256 maximumPoolTokensToDeposit,
        uint64 deadline
    )
        external
        revertIfZero(wethToDeposit)
        returns (uint256 liquidityTokensToMint)
    {


            // @audit the error should be named "TSwapPool__MaxPoolTokenDepositTooLow" not "TSwapPool__MaxPoolTokenDepositTooHigh"
            if (maximumPoolTokensToDeposit < poolTokensToDeposit) {
@>              revert TSwapPool__MaxPoolTokenDepositTooHigh(
                    maximumPoolTokensToDeposit,
                    poolTokensToDeposit
                );
            }

            // We do the same thing for liquidity tokens. Similar math.
            liquidityTokensToMint =
                (wethToDeposit * totalLiquidityTokenSupply()) /
                wethReserves;
            if (liquidityTokensToMint < minimumLiquidityTokensToMint) {
                // @audit should be "TSwapPool__MinLiquidityTokensToMintTooHigh"
@>              revert TSwapPool__MinLiquidityTokensToMintTooLow(
                    minimumLiquidityTokensToMint,
                    liquidityTokensToMint
                );
            }

```

## Impact
Bad user experience due to confusion and misenterpretation of the error.

## Tools Used
Manual review.

## Recommendations
```diff

    function deposit(
        uint256 wethToDeposit,
        uint256 minimumLiquidityTokensToMint,
        uint256 maximumPoolTokensToDeposit,
        uint64 deadline
    )
        external
        revertIfZero(wethToDeposit)
        returns (uint256 liquidityTokensToMint)
    {



            if (maximumPoolTokensToDeposit < poolTokensToDeposit) {
-               revert TSwapPool__MaxPoolTokenDepositTooHigh(
+               revert TSwapPool__MaxPoolTokenDepositTooLow(
                    maximumPoolTokensToDeposit,
                    poolTokensToDeposit
                );
            }

            // We do the same thing for liquidity tokens. Similar math.
            liquidityTokensToMint =
                (wethToDeposit * totalLiquidityTokenSupply()) /
                wethReserves;
            if (liquidityTokensToMint < minimumLiquidityTokensToMint) {
                // @audit should be "TSwapPool__MinLiquidityTokensToMintTooHigh"
-               revert TSwapPool__MinLiquidityTokensToMintTooLow(
+               revert TSwapPool__MinLiquidityTokensToMintTooHigh(
                    minimumLiquidityTokensToMint,
                    liquidityTokensToMint
                );
            }

```
---
## Title
[I-1] Reduced code readability due to missing naming convention.

## Summary
The state variable `TSwapPool::swap_count` is does not follow the naming conventions.

## Vulnerability Details
```javascript
    uint256 private swap_count = 0;
```

## Impact
Reduced code readibility and increased likelihood of errors.

## Tools Used
Manual review.

## Recommendations
```diff
-   uint256 private swap_count = 0;
+   uint256 private s_swap_count = 0;
```
---
## Title
[G-1] `TSwapPool::swapExactInput` and  `TSwapPool::swapExactOutput` should be external not public.

## Summary
The functions `TSwapPool::swapExactInput` and  `TSwapPool::swapExactOutput` are not called within the smart contracts, therefore, they should be external instead of public.

## Vulnerability Details
```javascript
    // @audit should be external
    function swapExactInput(
        IERC20 inputToken,
        uint256 inputAmount,
        IERC20 outputToken,
        uint256 minOutputAmount,
        uint64 deadline
    )
@>      public
        revertIfZero(inputAmount)
        revertIfDeadlinePassed(deadline)
        returns (uint256 output)
    {
```

```javascript
    // @audit should be external
    function swapExactOutput(
        IERC20 inputToken,
        IERC20 outputToken,
        uint256 outputAmount,
        uint64 deadline
    )
@>      public
        revertIfZero(outputAmount)
        revertIfDeadlinePassed(deadline)
        returns (uint256 inputAmount)
    {

```

## Impact
Gas inefficiency.

## Tools Used
Manual review, slither.

## Recommendations
```diff
    // @audit should be external
    function swapExactInput(
        IERC20 inputToken,
        uint256 inputAmount,
        IERC20 outputToken,
        uint256 minOutputAmount,
        uint64 deadline
    )
-       public
+       external
        revertIfZero(inputAmount)
        revertIfDeadlinePassed(deadline)
        returns (uint256 output)
    {
```

```diff
    // @audit should be external
    function swapExactOutput(
        IERC20 inputToken,
        IERC20 outputToken,
        uint256 outputAmount,
        uint64 deadline
    )
-       public
+       external
        revertIfZero(outputAmount)
        revertIfDeadlinePassed(deadline)
        returns (uint256 inputAmount)
    {

```
---
## Title
[I-2] Reduced code readability due to incorrect natspec comments.

## Summary
The natspec comments in `TSwapPool::_addLiquidityMintAndTransfer()` mention the function `addLiquidity` which doesn't exisit instead of `deposit`.

## Vulnerability Details
```javascript
@>  /// @dev This is a sensitive function, and should only be called by addLiquidity
    /// @param wethToDeposit The amount of WETH the user is going to deposit
    /// @param poolTokensToDeposit The amount of pool tokens the user is going to deposit
    /// @param liquidityTokensToMint The amount of liquidity tokens the user is going to mint
    function _addLiquidityMintAndTransfer(
        uint256 wethToDeposit,
        uint256 poolTokensToDeposit,
        uint256 liquidityTokensToMint
    ) private {
```

## Impact
Confusion and lack of code readibility.

## Tools Used
Manual review.

## Recommendations`
Fix the function name.
```diff
-   /// @dev This is a sensitive function, and should only be called by addLiquidity
+   /// @dev This is a sensitive function, and should only be called by deposit
    /// @param wethToDeposit The amount of WETH the user is going to deposit
    /// @param poolTokensToDeposit The amount of pool tokens the user is going to deposit
    /// @param liquidityTokensToMint The amount of liquidity tokens the user is going to mint
    function _addLiquidityMintAndTransfer(
        uint256 wethToDeposit,
        uint256 poolTokensToDeposit,
        uint256 liquidityTokensToMint
    ) private {
```

---
## Title
[I-3] Lack of code readability due to the usage of magic numbers.

## Summary
The values `1_000_000_000_000_000_000` in `TSwapPool::_swap` is a magic number and can be replaced by a contant instead for a more readable code.

## Vulnerability Details
```javascript
    function _swap(
        IERC20 inputToken,
        uint256 inputAmount,
        IERC20 outputToken,
        uint256 outputAmount
    ) private {
        //...

        // @audit frontrun the swap_count to always get the extra token
        if (swap_count >= SWAP_COUNT_MAX) {
            swap_count = 0;
            // @audit magic number
@>          outputToken.safeTransfer(msg.sender, 1_000_000_000_000_000_000);
        }
```

## Impact
Confusion and lack of code readability.

## Tools Used
Manual review.

## Recommendations
Replace the magic number with a constant.
```diff
+    uint256 private constant REWARD = 1e18;

    //...

    function _swap(
        IERC20 inputToken,
        uint256 inputAmount,
        IERC20 outputToken,
        uint256 outputAmount
    ) private {
        //...

        // @audit frontrun the swap_count to always get the extra token
        if (swap_count >= SWAP_COUNT_MAX) {
            swap_count = 0;
            // @audit magic number
-           outputToken.safeTransfer(msg.sender, 1_000_000_000_000_000_000);
+           outputToken.safeTransfer(msg.sender, REWARD);
        }
```



