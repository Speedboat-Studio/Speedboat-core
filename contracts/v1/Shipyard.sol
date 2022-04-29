// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "./SpeedBoat721AllInOne.sol";

contract Shipyard {
    event NewShip(
        string name,
        string symbol,
        string baseTokenURI,
        uint256 price,
        uint256 maxSupply,
        address beneficiary,
        address indexed _contract
    );
    address public immutable tokenImplementation;

    constructor() {
        tokenImplementation = address(new SpeedBoat721AllInOne());
    }

    // @dev deploy new NFT + sell. basic
    // @param name NFT name (721 standard)
    // @param symbol NFT symbol (721 standard)
    // @param baseTokenURI NFT baseTokenURI (721 standard)
    // @param price - selling price per NFT. in wei
    // @param _maxSupply - max NFT to be sell
    // @param _beneficiary - who take the mooney. (can be user's or contract e.g. payment splitter)
    function setSail(
        string calldata name,
        string calldata symbol,
        string calldata baseTokenURI,
        uint256 _price,
        uint256 _maxSupply,
        address _beneficiary
    ) external returns (address) {
        address clone = ClonesUpgradeable.clone(tokenImplementation);
        SpeedBoat721AllInOne(clone).initialize(
            name,
            symbol,
            baseTokenURI,
            _price,
            _maxSupply,
            _beneficiary
        );
        emit NewShip(
            name,
            symbol,
            baseTokenURI,
            _price,
            _maxSupply,
            _beneficiary,
            address(clone)
        );
        return clone;
    }
}