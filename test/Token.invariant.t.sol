// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Token} from "../src/Token.sol";

/// @dev Transfers stay within this closed actor set, so their sum must equal totalSupply.
contract TokenHandler is Test {
    Token public immutable token;
    address[4] internal actors = [address(0x1001), address(0x1002), address(0x1003), address(0x1004)];

    constructor(Token token_) {
        token = token_;
    }

    function actor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        vm.prank(actors[ownerSeed % actors.length]);
        assertTrue(token.approve(actors[spenderSeed % actors.length], amount));
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowanceBefore = token.allowance(owner, spender);
        uint256 available = token.balanceOf(owner);
        if (allowanceBefore < available) available = allowanceBefore;
        amount = bound(amount, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, actors[toSeed % actors.length], amount));
        assertEq(
            token.allowance(owner, spender),
            allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount
        );
    }
}

contract TokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Token internal token;
    TokenHandler internal handler;

    function setUp() public {
        token = new Token();
        handler = new TokenHandler(token);
        token.transfer(handler.actor(0), SUPPLY);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.move.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.spend.selector;
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
}
