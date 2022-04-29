// SPDX-License-Identifier: MIT
// author: yoyoismee.eth -- it's opensource but also feel free to send me coffee/beer.
//  ╔═╗┌─┐┌─┐┌─┐┌┬┐┌┐ ┌─┐┌─┐┌┬┐┌─┐┌┬┐┬ ┬┌┬┐┬┌─┐
//  ╚═╗├─┘├┤ ├┤  ││├┴┐│ │├─┤ │ └─┐ │ │ │ ││││ │
//  ╚═╝┴  └─┘└─┘─┴┘└─┘└─┘┴ ┴ ┴o└─┘ ┴ └─┘─┴┘┴└─┘

pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract Quartermaster is AccessControl {
    bytes32 public constant QUATERMASTER_ROLE = keccak256("QUATERMASTER");
    string public constant MODEL = "SBII-Quartermaster-test";

    struct Fees {
        uint128 onetime;
        uint128 bip;
        address token;
    }
    event updateFees(uint128 onetime, uint128 bip, address token);
    mapping(bytes32 => Fees) serviceFees;

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(QUATERMASTER_ROLE, msg.sender);
    }

    function setFees(
        string memory key,
        uint128 _onetime,
        uint128 _bip,
        address _token
    ) public onlyRole(QUATERMASTER_ROLE) {
        serviceFees[keccak256(abi.encode(key))] = Fees({
            onetime: _onetime,
            bip: _bip,
            token: _token
        });
        emit updateFees(_onetime, _bip, _token);
    }

    function getFees(string memory key) public view returns (Fees memory) {
        return serviceFees[keccak256(abi.encode(key))];
    }
}
