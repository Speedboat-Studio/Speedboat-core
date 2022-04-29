// SPDX-License-Identifier: MIT
// author: yoyoismee.eth -- it's opensource but also feel free to send me coffee/beer.
//  ╔═╗┌─┐┌─┐┌─┐┌┬┐┌┐ ┌─┐┌─┐┌┬┐┌─┐┌┬┐┬ ┬┌┬┐┬┌─┐
//  ╚═╗├─┘├┤ ├┤  ││├┴┐│ │├─┤ │ └─┐ │ │ │ ││││ │
//  ╚═╝┴  └─┘└─┘─┴┘└─┘└─┘┴ ┴ ┴o└─┘ ┴ └─┘─┴┘┴└─┘

pragma solidity 0.8.13;
import "@openzeppelin/contracts/access/AccessControl.sol";

contract Lighthouse is AccessControl {
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER");
    string public constant MODEL = "SBII-Lighthouse-test";

    event newContract(address ad, string name, string contractType);
    mapping(string => mapping(string => address)) public projectAddress;
    mapping(string => address) public nameOwner;
    mapping(address => string[]) private registeredProject;

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function listRegistered(address wallet)
        public
        view
        returns (string[] memory)
    {
        return registeredProject[wallet];
    }

    function registerContract(
        string memory name,
        address target,
        string memory contractType,
        address requester
    ) public onlyRole(DEPLOYER_ROLE) {
        if (nameOwner[name] == address(0)) {
            nameOwner[name] = requester;
            registeredProject[requester].push(name);
        } else {
            require(nameOwner[name] == requester, "taken");
        }
        require(projectAddress[name][contractType] == address(0), "taken");
        projectAddress[name][contractType] = target;
        emit newContract(target, name, contractType);
    }

    function giveUpContract(string memory name, string memory contractType)
        public
    {
        require(nameOwner[name] == msg.sender, "not your name");
        projectAddress[name][contractType] = address(0);
    }

    function giveUpName(string memory name) public {
        require(nameOwner[name] == msg.sender, "not your name");
        nameOwner[name] = address(0);
    }

    function yeetContract(string memory name, string memory contractType)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        projectAddress[name][contractType] = address(0);
    }

    function yeetName(string memory name) public onlyRole(DEFAULT_ADMIN_ROLE) {
        nameOwner[name] = address(0);
    }
}
