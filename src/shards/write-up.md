# Asymmetric conversion math, wrong rounding direction, and inverted time checks in `cancel()` allow buyers to instantly drain marketplace reserves

## Summary

The `cancel()` function in `ShardsNFTMarketplace.sol` contains three critical flaws that allow an attacker to mathematically synthesize and extract an outsized refund. First, a flawed time check permits immediate cancellation instead of enforcing the required waiting period. Second, `fill()` and `cancel()` use contradictory rounding directions (rounding down the cost, but rounding up the refund). Finally, and most severely, the refund math in `cancel()` calculates value symmetrically as if 1 shard equals 1 USDC, completely disregarding the original `offer.price` and `offer.totalShards` ratio that was correctly applied during `fill()`. This combined divergence allows attackers to purchase fractional shards for `0` DVT and immediately `cancel` them for a positive, amplified DVT payout, draining the contract.

## Root Cause

### 1. Inverted Cancel Time Constraints

The `cancel()` function attempts to enforce that a buyer must wait `TIME_BEFORE_CANCEL` before a purchase can be cancelled, up to a maximum period of `CANCEL_PERIOD_LENGTH`.

```solidity
function cancel(uint64 offerId, uint256 purchaseIndex) external {
    //...
    if (
        purchase.timestamp + CANCEL_PERIOD_LENGTH < block.timestamp ||
        block.timestamp > purchase.timestamp + TIME_BEFORE_CANCEL
    ) revert BadTime();
    //...
}
```

The comparison `block.timestamp > purchase.timestamp + TIME_BEFORE_CANCEL` is inverted. This means the function only accepts cancellations _before_ the waiting period actually elapses, completely neutralizing the enforced delay and allowing instant atomic `fill()` and `cancel()` operations within the same transaction.

### 2. Asymmetric Shard Valuation Math

The exact cost to purchase shards in `fill()` incorporates the `offer.price` and `offer.totalShards` context. However, the refund generated inside `cancel()` uses a hardcoded formulation that implicitly assumes 1 shard = 1 USDC (`1e6`):

```solidity
function fill(...) external returns (uint256 purchaseIndex) {
    //...
    pamentToken.transferFrom(
        msg.sender,
        address(this),
        want.mulDivDown(
            _toDVT(offer.price, _currentRate),
            offer.totalShards
        )
    );
    //...
}
```

```solidity
function cancel(...) external {
    //...
    paymentToken.transfer(
        buyer,
        purchase.shards.mulDivUp(purchase.rate, 1e6)
    );
    //...
}
```

### 3. Exploitable Rounding Mismatch

Compounding the semantic divergence is the difference in rounding directions:

- `fill()` uses `mulDivDown`, allowing fractional `want` values to evaluate to `0` cost.
- `cancel()` uses `mulDivUp`, guaranteeing a non-zero payout.

Together with the inverted time delay, an attacker can atomically cycle 0-cost fills that instantly refund huge DVT amounts.

## Proof of Concept

- [Coded PoC](../../test/shards/Shards.t.sol)
- **Run**

  ```bash
  forge test --mp test/shards/Shards.t.sol -vv
  ```

- **Output**

  ```bash
  Ran 2 tests for test/shards/Shards.t.sol:ShardsChallenge
  [PASS] test_assertInitialState() (gas: 80141)
  [PASS] test_shards() (gas: 342522)
  Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 2.53ms (797.30µs CPU time)
  ```

## Recommended Mitigation

Correct the time delay comparison to enforce that the current time is strictly greater than or equal to the minimum waiting period, ensure consistent rounding (protocol-favorable), and use the exact same price extrapolation algorithm for refunds as was used for purchases.
