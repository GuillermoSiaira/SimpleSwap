// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockERC20
 * @notice A simple ERC20 token for testing purposes. 
 *         The deployer becomes owner and can mint additional tokens.
 */
contract MockERC20 is ERC20, Ownable {
    /**
     * @notice Constructor that sets token name, symbol and optional initial supply.
     * @param name        Name of the token (e.g. "Token A").
     * @param symbol      Symbol of the token (e.g. "TKA").
     * @param initialSupply Amount of tokens to mint immediately to deployer (in wei units).
     */
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply
    ) ERC20(name, symbol) {
        // Ownable's constructor automatically sets owner = msg.sender
        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply);
        }
    }

    /**
     * @notice Mint new tokens to an address. Only callable by owner.
     * @param to     Recipient address.
     * @param amount Number of tokens to mint (in wei units).
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
