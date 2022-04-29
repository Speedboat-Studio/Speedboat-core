// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract OwnableDelegateProxy {}

contract ProxyRegistry {
    mapping(address => OwnableDelegateProxy) public proxies;
}

// @dev SpeedBoat721AllInOne v0 - simple yet.... simple lol (hackathon version) actually quite cost effective
// no privilage, no update, YOLO! (can't rekt if it can do nothing right?)
// I do ran a poll. lotta people wanna have a cheap gas.
contract SpeedBoat721AllInOne is
    Initializable,
    ContextUpgradeable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using StringsUpgradeable for uint256;

    uint256 public price;
    uint256 public maxSupply;
    string private _baseTokenURI;
    uint256 private nextID;
    address private beneficiary;
    address private constant speedBoatFee =
        0x6647a7858a0B3846AbD5511e7b797Fc0a0c63a4b; // I need some food la :)
    uint256 private constant invFee = 50; // invert fee e.g. 50 = 1/50 = 2%

    function initialize(
        string calldata name,
        string calldata symbol,
        string calldata baseTokenURI,
        uint256 _price,
        uint256 _maxSupply,
        address _beneficiary
    ) public initializer {
        __cool721Init(name, symbol, baseTokenURI);
        price = _price;
        maxSupply = _maxSupply;
        beneficiary = _beneficiary;
    }

    function withdraw() public nonReentrant {
        payable(speedBoatFee).transfer(address(this).balance / invFee); // some food for speedboat team
        payable(beneficiary).transfer(address(this).balance);
    }

    function buy() public payable nonReentrant {
        require(nextID < maxSupply, "sold out!");
        require(msg.value >= price, "pay us pls");
        _safeMint(_msgSender(), nextID);
        nextID = nextID + 1;
    }

    function contractURI() external view returns (string memory) {
        string memory baseURI = _baseURI();
        return string(abi.encodePacked(baseURI, "contract_uri"));
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(tokenId), "nonexistent token");

        string memory baseURI = _baseURI();
        return string(abi.encodePacked(baseURI, "uri/", tokenId.toString()));
    }

    function __cool721Init(
        string memory name,
        string memory symbol,
        string memory baseTokenURI
    ) internal initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __ReentrancyGuard_init_unchained();
        __ERC721_init_unchained(name, symbol);
        __ERC721Enumerable_init_unchained();
        _baseTokenURI = baseTokenURI;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    // @dev boring section -------------------
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    )
        internal
        virtual
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * Override isApprovedForAll to whitelist user's OpenSea proxy accounts to enable gas-less listings.
     */
    function isApprovedForAll(address _owner, address operator)
        public
        view
        override(IERC721Upgradeable, ERC721Upgradeable)
        returns (bool)
    {
        if (block.chainid == 4) {
            // rinkerby net
            ProxyRegistry proxyRegistry = ProxyRegistry(
                0xF57B2c51dED3A29e6891aba85459d600256Cf317
            );
            // Whitelist OpenSea proxy contract for easy trading.
            if (address(proxyRegistry.proxies(_owner)) == operator) {
                return true;
            }
        }
        if (block.chainid == 1) {
            // eth mainnet
            ProxyRegistry proxyRegistry = ProxyRegistry(
                0xa5409ec958C83C3f309868babACA7c86DCB077c1
            );
            // Whitelist OpenSea proxy contract for easy trading.
            if (address(proxyRegistry.proxies(_owner)) == operator) {
                return true;
            }
        }
        return super.isApprovedForAll(_owner, operator);
    }

    function airdrop(address[] calldata wallet) public {
        require(msg.sender == owner());
        for (uint256 i = 0; i < wallet.length; i++) {
            _safeMint(_msgSender(), nextID);
            nextID = nextID + 1;
        }
    }

    // @dev just to show who's the boss!
    function owner() public view virtual returns (address) {
        return beneficiary;
    }
}
