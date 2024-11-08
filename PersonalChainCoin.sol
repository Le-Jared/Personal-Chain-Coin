// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "./AssetManagement.sol";
import "./Roles.sol";

contract PersonalChainCoin is ERC20, ERC20Burnable, Pausable, AccessControl, ERC20Permit, AssetManagement, Roles {
    constructor(uint256 initialSupply) ERC20("Personal Chain Coin", "PCC") ERC20Permit("Personal Chain Coin") {
        _setupRoles();
        _mint(msg.sender, initialSupply * 10 ** decimals());
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override
    {
        require(!_blacklist[from] && !_blacklist[to], "PersonalChainCoin: Address is blacklisted");
        super._beforeTokenTransfer(from, to, amount);
    }
}