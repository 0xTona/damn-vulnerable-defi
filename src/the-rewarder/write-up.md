# Delayed bitmap update in `TheRewarderDistributor.claimRewards` allows single-transaction replay

## Summary

The `claimRewards` function fails to validate claim uniqueness within a single transaction, allowing attackers to reuse a valid Merkle proof multiple times.

## Root cause

The vulnerability is caused by a flawed gas optimization that batches multiple claims together. Instead of updating the contract's state after processing each claim, the contract accumulates them in memory and updates the state only once at the end.

When processing consecutive claims for the same token, the contract tracks the claimed batch by ORing its `bitPosition` into a local `bitsSet` variable. However, because bitwise OR is idempotent (`1 | 1 = 1`), providing the same `bitPosition` multiple times simply yields the same `bitsSet` value. The function `_setClaimed()`, which checks storage to prevent replay attacks, is only invoked after the loop finishes or when the token changes.

Crucially, the token transfer and Merkle proof verification happen inside the loop for every single claim. An attacker can exploit this by submitting an array of identical claims. The contract will verify the proof and transfer the tokens for each identical entry. Because the state is checked only at the end based on the masked `bitsSet`, the contract fails to detect the duplicated claims, allowing a massive single-transaction replay attack.

- `claimRewards()`(./TheRewarderDistributor.sol#L81-L118)

```solidity
function claimRewards(...) external {
    //...
    if (token != inputTokens[inputClaim.tokenIndex]) {
        if (address(token) != address(0)) {
            //Only check for claimed once per batch
@>          if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
        }

        token = inputTokens[inputClaim.tokenIndex];
        bitsSet = 1 << bitPosition; // set bit at given position
        amount = inputClaim.amount;
    } else {
        //Delay check for claimed here
@>      bitsSet = bitsSet | 1 << bitPosition;
        amount += inputClaim.amount;
    }
    //...
}
```

## Proof of Concept

- [TheRewarder.t.sol](../../test/the-rewarder/TheRewarder.t.sol)
- Run:
  ```bash
  forge test --mt test_theRewarder -vv
  ```
- Result:

  ```bash
  Ran 1 test for test/the-rewarder/TheRewarder.t.sol:TheRewarderChallenge
  [PASS] test_theRewarder() (gas: 1005359819)
  Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 1.97s (1.96s CPU time)

  Ran 1 test suite in 1.97s (1.97s CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
  ```

## Recommended Mitigation

Move the `_setClaimed()` call inside the loop to verify every claim individually.
