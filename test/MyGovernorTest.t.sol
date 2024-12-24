// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console2} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Box} from "../src/Box.sol";
import {Timelock} from "../src/Timelock.sol";
import {GovToken} from "../src/GovToken.sol";

contract MyGovernorTest is Test {
    MyGovernor governor;
    Box box;
    Timelock timelock;
    GovToken govToken;

    address public USER = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    uint256 public constant MIN_DELAY = 3600; // 1 hour after a vote passes
    uint256 public constant VOTING_DELAY = 7400; // updated
    uint256 public constant VOTING_PERIOD = 50400;

    address[] proposers;
    address[] executors;

    uint256[] values;
    bytes[] calldatas;
    address[] targets;

    function setUp() public {
        govToken = new GovToken();
        govToken.mint(USER, INITIAL_SUPPLY);

        vm.startPrank(USER);
        govToken.delegate(USER);
        vm.stopPrank();

        //timelock = new Timelock(MIN_DELAY, proposers, executors);
        timelock = new Timelock(MIN_DELAY, proposers, executors, address(this));
        governor = new MyGovernor(govToken, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        //bytes32 adminRole = timelock.TIMELOCK_ADMIN_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        vm.startPrank(address(this));
        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        //timelock.revokeRole(adminRole, USER); ---
        timelock.revokeRole(adminRole, address(this));
        vm.stopPrank();

        // box = new Box();
        // box.transferOwnership(address(timelock));
        box = new Box(address(timelock));
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 420;
        string memory description = "Update box value to 420 for clout";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);

        calldatas.push(encodedFunctionCall);
        values.push(0);
        targets.push(address(box));

        // 1. Propose
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // View the State
        console2.log("Proposal State 1: ", uint256(governor.state(proposalId)));
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);
        console2.log("Proposal State 2: ", uint256(governor.state(proposalId)));

        // 2. Vote
        string memory reason = "420 is cool number. Cool number for cool people.";

        vm.prank(USER);
        governor.castVoteWithReason(proposalId, 1, reason); // 1 is voting for
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // 3. Queue the Proposal
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        // 4. Execute the Proposal
        governor.execute(targets, values, calldatas, descriptionHash);

        console2.log("Box Value: ", box.getNumber());
        assert(box.getNumber() == valueToStore);
    }
}
