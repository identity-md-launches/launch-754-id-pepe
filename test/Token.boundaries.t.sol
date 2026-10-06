// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Token} from "src/Token.sol";

/// @dev A recipient need not implement hooks or accept calls to receive ordinary ERC-20 tokens.
contract RejectingTokenRecipient {
    fallback() external {
        revert("recipient must not be called");
    }
}

/// forge-config: default.fuzz.runs = 1000
contract TokenBoundaryTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);
    Token internal token;

    function setUp() public {
        token = new Token();
    }

    function test_OneBaseUnitRoundTrip() public {
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferCannotOverflowBalances() public {
        bytes memory reason = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
        );
        vm.expectRevert(reason);
        token.transfer(ALICE, type(uint256).max);

        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(reason);
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_LargestFiniteAllowanceIsNotInfinite() public {
        assertTrue(token.approve(SPENDER, type(uint256).max - 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 2);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY - 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_InfiniteAllowanceCanBeReducedAndRevokedAfterUse() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), 0);
        _expectUnapprovedSpend(address(this), SPENDER);

        token.approve(SPENDER, type(uint256).max);
        assertTrue(token.approve(SPENDER, 0));
        _expectUnapprovedSpend(address(this), SPENDER);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    function test_SpentApprovalDoesNotReturnWhenTokensAreRefunded() public {
        token.approve(SPENDER, 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), 1));
        _expectUnapprovedSpend(address(this), SPENDER);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_ApprovalIsScopedToBothOwnerAndSpender() public {
        token.transfer(ALICE, 10);
        token.approve(SPENDER, 10);
        vm.prank(ALICE);
        token.approve(BOB, 10);

        _expectUnapprovedSpend(ALICE, SPENDER);
        _expectUnapprovedSpend(address(this), BOB);
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.allowance(ALICE, BOB), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY - 10);
        assertEq(token.balanceOf(ALICE), 10);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(SPENDER), 0);
    }

    function test_SelfApprovalAndSelfSpendConsumeFiniteAllowance() public {
        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), address(this), 1));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), address(this)), 0);
        _expectUnapprovedSpend(address(this), address(this));
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_FailedSpendCanBeRetriedAfterFundingWithoutRenewingApproval() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.allowance(ALICE, SPENDER), 2);

        token.transfer(ALICE, 2);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 2));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    function test_ZeroDelegatedTransferStillRejectsZeroRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ContractRecipientNeedsNoCallback() public {
        address recipient = address(new RejectingTokenRecipient());
        assertTrue(token.transfer(recipient, 1));
        token.approve(SPENDER, 2);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), recipient, 2));
        assertEq(token.balanceOf(recipient), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedSpendPreservesFiniteApproval(uint256 funded, uint256 requested, uint256 approved) public {
        funded = bound(funded, 0, SUPPLY);
        requested = bound(requested, funded + 1, type(uint256).max - 1);
        approved = bound(approved, requested, type(uint256).max - 1);
        token.transfer(ALICE, funded);
        vm.prank(ALICE);
        token.approve(SPENDER, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, funded, requested)
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, requested);
        assertEq(token.allowance(ALICE, SPENDER), approved);
        assertEq(token.balanceOf(ALICE), funded);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - funded);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitTransfersEqualSingleTransfer(uint256 total, uint256 first) public {
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        Token single = new Token();
        assertTrue(single.transfer(ALICE, total));
        assertTrue(token.transfer(ALICE, first));
        assertTrue(token.transfer(ALICE, total - first));
        assertEq(token.balanceOf(ALICE), total);
        assertEq(token.balanceOf(ALICE), single.balanceOf(ALICE));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DirectAndDelegatedTransfersAgree(uint256 funded, uint256 amount, bool infinite, bool self)
        public
    {
        funded = bound(funded, 0, SUPPLY);
        amount = bound(amount, 0, funded);
        Token direct = new Token();
        direct.transfer(ALICE, funded);
        token.transfer(ALICE, funded);
        address recipient = self ? ALICE : BOB;
        vm.prank(ALICE);
        assertTrue(direct.transfer(recipient, amount));
        vm.prank(ALICE);
        token.approve(SPENDER, infinite ? type(uint256).max : amount);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, recipient, amount));
        assertEq(token.balanceOf(ALICE), direct.balanceOf(ALICE));
        assertEq(token.balanceOf(BOB), direct.balanceOf(BOB));
        assertEq(token.balanceOf(address(this)), direct.balanceOf(address(this)));
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.allowance(ALICE, SPENDER), infinite ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalIsIdempotentAndDoesNotAffectOtherApprovals(uint256 first, uint256 second) public {
        token.approve(SPENDER, first);
        token.approve(ALICE, second);
        vm.prank(ALICE);
        token.approve(SPENDER, second);
        assertTrue(token.approve(SPENDER, first));
        assertEq(token.allowance(address(this), SPENDER), first);
        assertEq(token.allowance(address(this), ALICE), second);
        assertEq(token.allowance(ALICE, SPENDER), second);
        assertEq(token.allowance(SPENDER, address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _expectUnapprovedSpend(address owner, address spender) internal {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, BOB, 1);
    }
}
