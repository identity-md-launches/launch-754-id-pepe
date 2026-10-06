// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Token} from "../src/Token.sol";

/// @dev Transfers stay within this closed actor set, so their sum must equal totalSupply.
contract TokenHandler is Test {
    Token public immutable token;
    address[4] internal actors = [address(0x1001), address(0x1002), address(0x1003), address(0x1004)];
    // These expectations come from requested actions, never from the token's return state.
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Token token_) {
        token = token_;
        expectedBalance[actors[0]] = 1_000_000_000 * 10 ** 18;
    }

    function actor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordMove(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        _approve(actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], amount);
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowanceBefore = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner];
        if (allowanceBefore < available) available = allowanceBefore;
        amount = bound(amount, 0, available);
        address to = actors[toSeed % actors.length];
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        _recordMove(owner, to, amount);
        if (allowanceBefore != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        assertEq(
            token.allowance(owner, spender),
            allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount
        );
    }

    /// @dev Guarantee a positive delegated spend, including full balance and infinite allowance.
    /// All roles can alias: self-transfers must still spend finite allowances.
    function approveAndSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount, bool infinite)
        external
    {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 1, expectedBalance[owner]);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        _recordMove(owner, to, amount);
        if (!infinite) expectedAllowance[owner][spender] = 0;
    }

    function revokeAndAttemptSpend(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, 0);
        _expectRejected(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
    }

    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        amount = bound(amount, expectedBalance[from] + 1, type(uint256).max);
        _expectRejected(
            from,
            abi.encodeCall(token.transfer, (actors[toSeed % actors.length], amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, expectedBalance[from], amount)
        );
    }

    /// @dev Allowance is sufficient, so a later balance failure must undo its attempted debit.
    function spendAboveBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool infinite) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, expectedBalance[owner] + 1, type(uint256).max - 1);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        _expectRejected(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, amount)),
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, owner, expectedBalance[owner], amount
            )
        );
    }

    function spendAboveAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 allowanceSeed) external {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % actors.length];
        uint256 permitted = bound(allowanceSeed, 0, expectedBalance[owner] - 1);
        _approve(owner, spender, permitted);
        _expectRejected(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, permitted + 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, permitted, permitted + 1)
        );
    }

    function spendToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool infinite) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        _expectRejected(
            spender,
            abi.encodeCall(token.transferFrom, (owner, address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    /// @dev Full-balance round trips must be possible after any previous sequence.
    function roundTrip(uint256 fromSeed) external {
        address from = _fundedActor(fromSeed);
        address to = from == actors[0] ? actors[1] : actors[0];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(to), expectedBalance[to] + amount);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        // Net balance and allowance expectations remain unchanged.
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function _recordMove(address from, address to, uint256 amount) internal {
        if (from != to) {
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }

    function _expectRejected(address caller, bytes memory data, bytes memory reason) internal {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(result, reason, "unexpected revert reason");
        // The global model invariant checks every balance and allowance after this call.
    }

    function _fundedActor(uint256 seed) internal view returns (address) {
        uint256 start = seed % actors.length;
        for (uint256 i; i < actors.length; ++i) {
            address candidate = actors[(start + i) % actors.length];
            if (expectedBalance[candidate] > 0) return candidate;
        }
        revert("model lost the fixed supply");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract TokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Token internal token;
    TokenHandler internal handler;

    function setUp() public {
        token = new Token();
        handler = new TokenHandler(token);
        token.transfer(handler.actor(0), SUPPLY);

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.move.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.spend.selector;
        selectors[3] = handler.approveAndSpend.selector;
        selectors[4] = handler.revokeAndAttemptSpend.selector;
        selectors[5] = handler.transferAboveBalance.selector;
        selectors[6] = handler.spendAboveBalance.selector;
        selectors[7] = handler.spendAboveAllowance.selector;
        selectors[8] = handler.spendToZero.selector;
        selectors[9] = handler.roundTrip.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyAndBalancesAreConserved() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actor(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// @dev Conservation alone would miss fees redistributed to another actor or a no-op transfer.
    function invariant_EveryBalanceAndAllowanceMatchesRequestedActions() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actor(i);
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner), "incorrect holder balance");
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actor(j);
                assertEq(
                    token.allowance(owner, spender), handler.expectedAllowance(owner, spender), "incorrect allowance"
                );
            }
            assertEq(token.allowance(owner, address(0)), 0);
        }
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.name(), "ID PEPE");
        assertEq(token.symbol(), "PEPE");
        assertEq(token.decimals(), 18);
    }
}
