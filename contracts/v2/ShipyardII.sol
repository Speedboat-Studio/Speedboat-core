// SPDX-License-Identifier: MIT
// author: yoyoismee.eth -- it's opensource but also feel free to send me coffee/beer.
//  ╔═╗┌─┐┌─┐┌─┐┌┬┐┌┐ ┌─┐┌─┐┌┬┐┌─┐┌┬┐┬ ┬┌┬┐┬┌─┐
//  ╚═╗├─┘├┤ ├┤  ││├┴┐│ │├─┤ │ └─┐ │ │ │ ││││ │
//  ╚═╝┴  └─┘└─┘─┴┘└─┘└─┘┴ ┴ ┴o└─┘ ┴ └─┘─┴┘┴└─┘

pragma solidity 0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "./quartermaster.sol";
import "./lighthouse.sol";
import "./ISBShipable.sol";
import "./paymentUtil.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Shipyard is Ownable {
    event NewShip(string reserveName, address newShip, string shipType);

    mapping(bytes32 => address) public shipImplementation;
    mapping(bytes32 => string) public shipTypes;

    Quartermaster public quarterMaster;
    Lighthouse public lighthouse;

    string public constant MODEL = "SBII-shipyard-test";

    constructor() {}

    function setSail(
        string calldata shipType,
        string calldata reserveName,
        bytes calldata initArg
    ) external payable returns (address) {
        bytes32 key = keccak256(abi.encodePacked(shipType));
        require(shipImplementation[key] != address(0), "not exist");
        Quartermaster.Fees memory fees = quarterMaster.getFees(shipType);

        paymentUtil.processPayment(fees.token, fees.onetime);

        address clone = ClonesUpgradeable.clone(shipImplementation[key]);
        ISBShipable(clone).initialize(initArg, fees.bip, address(this));
        lighthouse.registerContract(
            reserveName,
            clone,
            shipTypes[key],
            msg.sender
        );
        emit NewShip(reserveName, clone, shipTypes[key]);
        return clone;
    }

    function getPrice(string calldata shipType)
        public
        view
        returns (Quartermaster.Fees memory)
    {
        return quarterMaster.getFees(shipType);
    }

    function addBlueprint(
        string memory shipName,
        string memory shipType,
        address implementation
    ) public onlyOwner {
        bytes32 key = keccak256(abi.encodePacked(shipName));
        shipImplementation[key] = implementation;
        shipTypes[key] = shipType;
    }

    function removeBlueprint(string memory shipName) public onlyOwner {
        shipImplementation[keccak256(abi.encodePacked(shipName))] = address(0);
    }

    function withdraw(address tokenAddress) public onlyOwner {
        if (tokenAddress == address(0)) {
            payable(msg.sender).transfer(address(this).balance);
        } else {
            IERC20 token = IERC20(tokenAddress);
            token.transfer(msg.sender, token.balanceOf(address(this)));
        }
    }

    function setQM(address qm) public onlyOwner {
        quarterMaster = Quartermaster(qm);
    }

    function setLH(address lh) public onlyOwner {
        lighthouse = Lighthouse(lh);
    }

    receive() external payable {}

    fallback() external payable {}
}
