// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/HempOffGridDAO.sol";

contract HempOffGridDAOTest is Test {
    HempOffGridDAO dao;
    address user1 = address(0x1111);
    address updateWallet = 0xaF570ce3b32D765b1236635B0f541a7487A1fB8e;

    function setUp() public {
        dao = new HempOffGridDAO();
        vm.deal(user1, 100 ether);
    }

    function testConstantsAndBindings() public view {
        assertEq(dao.OBS_TOKEN_ADDRESS(), 0x2D8760e2877148d239a54952A458710553B2B54b);
        assertEq(dao.DESIGNATED_UPDATE_WALLET(), updateWallet);
        assertEq(dao.updateWallet(), updateWallet);
        assertEq(dao.THRESHOLD_DAI(), 5_000_000_000 * 1e18);
    }

    function testMonthlyLPIssuanceAndExpiration() public {
        vm.startPrank(user1);
        dao.claimMonthlyLP();
        assertEq(dao.getEffectiveLPBalance(user1), 100 * 1e18);

        vm.warp(block.timestamp + 32 days);
        assertEq(dao.getEffectiveLPBalance(user1), 0, "LP tokens should expire at the end of the month");
        vm.stopPrank();
    }

    function testProposalCreationThreshold() public {
        vm.startPrank(user1);
        dao.claimMonthlyLP();
        uint256 proposalId = dao.createProposal("Hemp Uniform Distribution", payable(address(0x999)), 1000 * 1e18, 3);
        assertEq(proposalId, 0);
        vm.stopPrank();
    }

    function testRevocableUpdateAndImmutability() public {
        vm.startPrank(updateWallet);
        bytes32 mockPqcHash = keccak256(abi.encodePacked("DilithiumPublicKeyAndBiometricsTemplate"));
        dao.setupRoomieRobotAndLock(address(0x789), mockPqcHash);
        assertEq(dao.roomieBot(), address(0x789));

        dao.revokeAndUpdatePermissions();
        assertTrue(dao.isImmutable());
        assertEq(dao.updateWallet(), address(0));
        vm.stopPrank();
    }
}
