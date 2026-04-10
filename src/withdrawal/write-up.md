# Unchecked return value of low-level `call()` in `L1Gateway.sol` causes permanent loss of withdrawals

## Summary

The `finalizeWithdrawal` function performs an external call to a target address using the low-level `call` opcode within an assembly block. However, it fails to verify the return value (`success`) of this call. Since the withdrawal is marked as finalized **before** the call occurs, any failed execution results in the withdrawal being permanently stuck in a "finalized" state without the intended action (e.g., token release) ever being performed.

## Root cause

In `L1Gateway.sol`, the `finalizeWithdrawal` function marks a leaf as finalized and then executes a low-level call. The result of this call is captured in the `success` variable but is never checked.

```solidity
function finalizeWithdrawal(...) external {
    //...
    finalizedWithdrawals[leaf] = true;
    counter++;
    //...
    bool success;
    assembly {
        success := call(
            gas(),
            target,
            0,
            add(message, 0x20),
            mload(message),
            0,
            0
        ) // call with 0 value. Don't copy returndata.
    }
    // success is never validated — a failed call is silently accepted
    //...
}
```

### When does the `call` fail?

The subcall returns `success = 0` whenever the target reverts. In the standard flow (`L1Gateway → L1Forwarder → TokenBridge`), this occurs when:

| #   | Condition                                                           |
| --- | ------------------------------------------------------------------- |
| 1   | `l2Sender` in the withdrawal data is not the registered `l2Handler` |
| 2   | The message has already been successfully forwarded                 |
| 3   | The withdrawal `target` is the forwarder or gateway itself          |
| 4   | The subcall exhausts the available gas                              |
| 5   | A reentrant call enters `L1Forwarder` while it is still executing   |

## Proof of Concept

- [Coded Poc](../../test/withdrawal/Withdrawal.t.sol)

- **Run**

  ```bash
  forge test --mp test/withdrawal/Withdrawal.t.sol
  ```

- **Output**

  ```bash
  Ran 2 tests for test/withdrawal/Withdrawal.t.sol:WithdrawalChallenge
  [PASS] test_assertInitialState() (gas: 50741)
  [PASS] test_withdrawal() (gas: 458103)
  Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 5.93ms (4.94ms CPU time)

  Ran 1 test suite in 9.44ms (5.93ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
  ```

## Recommended Mitigation

Check the `success` return value of the low-level call and revert if it is `false`.

```diff
  assembly {
      success := call(
          gas(),
          target,
          0,
          add(message, 0x20),
          mload(message),
          0,
          0
      ) // call with 0 value. Don't copy returndata.
  }
+   if (!success) revert CallFailed();
```
