// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract Roles is AccessControl {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");

    mapping(address => bool) internal _blacklist;

    function _setupRoles() internal {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(ASSET_MANAGER_ROLE, msg.sender);
    }

    function blacklistAddress(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _blacklist[account] = true;
    }

    function unblacklistAddress(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _blacklist[account] = false;
    }
}