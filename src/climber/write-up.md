# Climber Level Write-up

## Summary

The Climber challenge involves exploiting a vulnerable timelock contract to upgrade a vault implementation and drain its funds. The vulnerability lies in the ability to execute malicious operations and then schedule them to bypass intended delay and authorization checks.

## Root cause

The `ClimberTimelock` contract does not validate that operations are scheduled **before** but **after** execution.

```solidity
function execute(...) {
   //...
   for (uint8 i = 0; i < targets.length; ++i) {
      targets[i].functionCallWithValue(dataElements[i], values[i]);
   }

   if (getOperationState(id) != OperationState.ReadyForExecution) {
      revert NotReadyForExecution(id);
   }
   //...
}
```

## Proof of Concept

[Climber.t.sol](../../test/climber/Climber.t.sol)

## Recommended Mitigation

**Validate Scheduled Operations:**
Ensure that operations are scheduled before execution.

```solidity
if (getOperationState(id) != OperationState.ReadyForExecution) {
   revert NotReadyForExecution(id);
}

for (uint8 i = 0; i < targets.length; ++i) {
   targets[i].functionCallWithValue(dataElements[i], values[i]);
}
```
