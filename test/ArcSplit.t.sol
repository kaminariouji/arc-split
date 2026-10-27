// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ArcSplit, IERC20} from "../src/ArcSplit.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract ArcSplitTest is Test {
    MockUSDC usdc;
    ArcSplit split;

    address creator = address(0xC0FFEE);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA201);

    bytes32 constant ID = keccak256("invoice-2026-10");

    function setUp() public {
        usdc = new MockUSDC();
        split = new ArcSplit(IERC20(address(usdc)));
        usdc.mint(creator, 1_000_000e6);
        vm.prank(creator);
        usdc.approve(address(split), type(uint256).max);
    }

    function _threePayees() internal view returns (address[] memory p, uint96[] memory s) {
        p = new address[](3);
        s = new uint96[](3);
        p[0] = alice; s[0] = 5000;
        p[1] = bob;   s[1] = 3000;
        p[2] = carol; s[2] = 2000;
    }

    function testSplitsByShares() public {
        (address[] memory p, uint96[] memory s) = _threePayees();
        vm.prank(creator);
        split.createSplit(ID, p, s, 1_000e6);

        assertEq(split.claimable(ID, alice), 500e6);
        assertEq(split.claimable(ID, bob), 300e6);
        assertEq(split.claimable(ID, carol), 200e6);
        assertEq(usdc.balanceOf(address(split)), 1_000e6);
    }

    function testClaimPaysAndZeroes() public {
        (address[] memory p, uint96[] memory s) = _threePayees();
        vm.prank(creator);
        split.createSplit(ID, p, s, 1_000e6);

        vm.prank(alice);
        uint256 got = split.claim(ID);

        assertEq(got, 500e6);
        assertEq(usdc.balanceOf(alice), 500e6);
        assertEq(split.claimable(ID, alice), 0);
        assertEq(usdc.balanceOf(address(split)), 500e6);
    }

    function testDoubleClaimReverts() public {
        (address[] memory p, uint96[] memory s) = _threePayees();
        vm.prank(creator);
        split.createSplit(ID, p, s, 1_000e6);
        vm.prank(alice);
        split.claim(ID);
        vm.prank(alice);
        vm.expectRevert(ArcSplit.NothingToClaim.selector);
        split.claim(ID);
    }

    function testNonPayeeCannotClaim() public {
        (address[] memory p, uint96[] memory s) = _threePayees();
        vm.prank(creator);
        split.createSplit(ID, p, s, 1_000e6);
        vm.prank(address(0xDEAD));
        vm.expectRevert(ArcSplit.NothingToClaim.selector);
        split.claim(ID);
    }

    function testSharesMustSumTo10000() public {
        address[] memory p = new address[](2);
        uint96[] memory s = new uint96[](2);
        p[0] = alice; s[0] = 5000;
        p[1] = bob;   s[1] = 4000;
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(ArcSplit.BadShares.selector, 9000));
        split.createSplit(ID, p, s, 1_000e6);
    }

    function testDuplicatePayeeReverts() public {
        address[] memory p = new address[](2);
        uint96[] memory s = new uint96[](2);
        p[0] = alice; s[0] = 5000;
        p[1] = alice; s[1] = 5000;
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(ArcSplit.DuplicatePayee.selector, alice));
        split.createSplit(ID, p, s, 1_000e6);
    }

    function testRoundingDustGoesToCreator() public {
        address[] memory p = new address[](3);
        uint96[] memory s = new uint96[](3);
        p[0] = alice; s[0] = 3334;
        p[1] = bob;   s[1] = 3333;
        p[2] = carol; s[2] = 3333;

        vm.prank(creator);
        split.createSplit(ID, p, s, 100);

        assertEq(split.claimable(ID, alice), 33);
        assertEq(split.claimable(ID, bob), 33);
        assertEq(split.claimable(ID, carol), 33);

        uint256 before = usdc.balanceOf(creator);
        vm.prank(creator);
        uint256 refund = split.sweepDust(ID);
        assertEq(refund, 1);
        assertEq(usdc.balanceOf(creator) - before, 1);
    }

    function testSweepOnlyCreator() public {
        (address[] memory p, uint96[] memory s) = _threePayees();
        vm.prank(creator);
        split.createSplit(ID, p, s, 1_000e6);
        vm.prank(alice);
        vm.expectRevert(ArcSplit.NotCreator.selector);
        split.sweepDust(ID);
    }

    function testSplitIdCannotBeReused() public {
        (address[] memory p, uint96[] memory s) = _threePayees();
        vm.prank(creator);
        split.createSplit(ID, p, s, 1_000e6);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(ArcSplit.SplitExists.selector, ID));
        split.createSplit(ID, p, s, 1_000e6);
    }

    function testUnclaimedStaysClaimableAfterSweep() public {
        (address[] memory p, uint96[] memory s) = _threePayees();
        vm.prank(creator);
        split.createSplit(ID, p, s, 1_000e6);

        vm.prank(creator);
        split.sweepDust(ID);

        vm.prank(bob);
        uint256 got = split.claim(ID);
        assertEq(got, 300e6);
        assertEq(usdc.balanceOf(bob), 300e6);
    }
}
