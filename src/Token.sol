// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title ID PEPE
/// @notice A fixed supply ERC-20 with 18 decimals and no administrative powers.
contract Token is ERC20 {
    /// @notice Mints all one billion PEPE to the immediate deployer, including a factory.
    constructor() ERC20("ID PEPE", "PEPE") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
