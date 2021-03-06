// SPDX-License-Identifier: MIT
// author: yoyoismee.eth -- it's opensource but also feel free to send me coffee/beer.
//  ╔═╗┌─┐┌─┐┌─┐┌┬┐┌┐ ┌─┐┌─┐┌┬┐┌─┐┌┬┐┬ ┬┌┬┐┬┌─┐
//  ╚═╗├─┘├┤ ├┤  ││├┴┐│ │├─┤ │ └─┐ │ │ │ ││││ │
//  ╚═╝┴  └─┘└─┘─┴┘└─┘└─┘┴ ┴ ┴o└─┘ ┴ └─┘─┴┘┴└─┘

pragma solidity 0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./ISBMintable.sol";
import "./ISBRandomness.sol";
import "./ISBShipable.sol";
import "./paymentUtil.sol";

// @dev speedboat v2 erc721 = SBII721
contract SBII721 is
    Initializable,
    ContextUpgradeable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlEnumerableUpgradeable,
    ISBMintable,
    ISBShipable
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using StringsUpgradeable for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    string public constant MODEL = "SBII-721-test";
    uint256 private lastID;

    struct Round {
        uint128 price;
        uint32 quota;
        uint16 amountPerUser;
        bool isActive;
        bool isPublic;
        bool isMerkleMode; // merkleMode will override price, amountPerUser, and TokenID if specify
        bool exist;
        address tokenAddress; // 0 for base asset
    }

    struct Conf {
        bool allowNFTUpdate;
        bool allowConfUpdate;
        bool allowContract;
        bool allowPrivilege;
        bool randomAccessMode;
        bool allowTarget;
        bool allowLazySell;
        uint64 maxSupply;
    }

    Conf public config;
    string[] roundNames;

    mapping(bytes32 => EnumerableSetUpgradeable.AddressSet) private walletList;
    mapping(bytes32 => bytes32) private merkleRoot;
    mapping(bytes32 => Round) private roundData;
    mapping(uint256 => bool) private nonceUsed;

    mapping(bytes32 => mapping(address => uint256)) mintedInRound;

    string private _baseTokenURI;
    address private feeReceiver;
    uint256 private bip;
    address public beneficiary;

    ISBRandomness public randomness;

    function listRole()
        external
        pure
        returns (string[] memory names, bytes32[] memory code)
    {
        names = new string[](2);
        code = new bytes32[](2);

        names[0] = "MINTER";
        names[1] = "ADMIN";

        code[0] = MINTER_ROLE;
        code[1] = DEFAULT_ADMIN_ROLE;
    }

    function grantRoles(bytes32 role, address[] calldata accounts) public {
        for (uint256 i = 0; i < accounts.length; i++) {
            super.grantRole(role, accounts[i]);
        }
    }

    function revokeRoles(bytes32 role, address[] calldata accounts) public {
        for (uint256 i = 0; i < accounts.length; i++) {
            super.revokeRole(role, accounts[i]);
        }
    }

    function setBeneficiary(address _beneficiary)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(beneficiary == address(0), "already set");
        // require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "admin only");
        beneficiary = _beneficiary;
    }

    function setMaxSupply(uint64 _maxSupply)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(config.maxSupply == 0, "already set");
        // require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "admin only");
        config.maxSupply = _maxSupply;
    }

    function listRoleWallet(bytes32 role)
        public
        view
        returns (address[] memory roleMembers)
    {
        uint256 count = getRoleMemberCount(role);
        roleMembers = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            roleMembers[i] = getRoleMember(role, i);
        }
    }

    function listToken(address wallet)
        public
        view
        returns (uint256[] memory tokenList)
    {
        tokenList = new uint256[](balanceOf(wallet));
        for (uint256 i = 0; i < balanceOf(wallet); i++) {
            tokenList[i] = tokenOfOwnerByIndex(wallet, i);
        }
    }

    function listRounds() public view returns (string[] memory) {
        return roundNames;
    }

    function roundInfo(string memory roundName)
        public
        view
        returns (Round memory)
    {
        return roundData[keccak256(abi.encodePacked(roundName))];
    }

    function massMint(address[] calldata wallets, uint256[] calldata amount)
        public
    {
        require(config.allowPrivilege, "df");
        require(hasRole(MINTER_ROLE, msg.sender), "require permission");
        for (uint256 i = 0; i < wallets.length; i++) {
            _mintNext(wallets[i], amount[i]);
        }
    }

    function mintNext(address reciever, uint256 amount) public override {
        require(config.allowPrivilege, "df");
        require(hasRole(MINTER_ROLE, msg.sender), "require permission");
        _mintNext(reciever, amount);
    }

    function _mintNext(address reciever, uint256 amount) internal {
        if (config.maxSupply != 0) {
            require(totalSupply() + amount <= config.maxSupply);
        }
        if (!config.randomAccessMode) {
            for (uint256 i = 0; i < amount; i++) {
                _mint(reciever, lastID + 1 +i);
            }
            lastID += amount;

        } else {
            for (uint256 i = 0; i < amount; i++) {
                _mint(reciever, _random(msg.sender, i));
            }
        }
    }

    function _random(address ad, uint256 num) internal returns (uint256) {
        return
            uint256(randomness.getRand(keccak256(abi.encodePacked(ad, num))));
    }

    function updateURI(string memory newURI)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "admin only");
        require(config.allowNFTUpdate, "not available");
        _baseTokenURI = newURI;
    }

    function mintTarget(address reciever, uint256 target) public override {
        require(config.allowPrivilege, "df");
        require(hasRole(MINTER_ROLE, msg.sender), "require permission");
        _mintTarget(reciever, target);
    }

    function _mintTarget(address reciever, uint256 target) internal {
        require(config.allowTarget, "df");
        require(config.randomAccessMode, "df");
        if (config.maxSupply != 0) {
            require(totalSupply() + 1 <= config.maxSupply);
        }
        _mint(reciever, target);
    }

    function requestMint(Round storage thisRound, uint256 amount) internal {
        require(thisRound.isActive, "not active");
        require(thisRound.quota >= amount, "out of stock");
        if (!config.allowContract) {
            require(tx.origin == msg.sender, "not allow contract");
        }
        thisRound.quota -= uint32(amount);
    }

    /// magic overload

    function mint(string memory roundName, uint256 amount)
        public
        payable
        nonReentrant
    {
        bytes32 key = keccak256(abi.encodePacked(roundName));
        Round storage thisRound = roundData[key];

        requestMint(thisRound, amount);

        // require(thisRound.isActive, "not active");
        // require(thisRound.quota >= amount, "out of stock");
        // if (!config.allowContract) {
        //     require(tx.origin == msg.sender, "not allow contract");
        // }
        // thisRound.quota -= uint32(amount);

        require(!thisRound.isMerkleMode, "wrong data");

        if (!thisRound.isPublic) {
            require(walletList[key].contains(msg.sender));
            require(
                mintedInRound[key][msg.sender] + amount <=
                    thisRound.amountPerUser,
                "out of quota"
            );
            mintedInRound[key][msg.sender] += amount;
        } else {
            require(amount <= thisRound.amountPerUser, "nope"); // public round can mint multiple time
        }

        paymentUtil.processPayment(
            thisRound.tokenAddress,
            thisRound.price * amount
        );

        _mintNext(msg.sender, amount);
    }

    function mint(
        string memory roundName,
        address wallet,
        uint256 amount,
        uint256 tokenID,
        uint256 nonce,
        uint256 pricePerUnit,
        address denominatedAsset,
        bytes32[] memory proof
    ) public payable {
        bytes32 key = keccak256(abi.encodePacked(roundName));

        Round storage thisRound = roundData[key];

        requestMint(thisRound, amount);

        // require(thisRound.isActive, "not active");
        // require(thisRound.quota >= amount, "out of quota");
        // thisRound.quota -= uint32(amount);

        require(thisRound.isMerkleMode, "invalid");

        bytes32 data = hash(
            wallet,
            amount,
            tokenID,
            nonce,
            pricePerUnit,
            denominatedAsset,
            address(this),
            block.chainid
        );
        require(_merkleCheck(data, merkleRoot[key], proof), "fail merkle");

        _useNonce(nonce);
        if (wallet != address(0)) {
            require(wallet == msg.sender, "nope");
        }

        require(amount * tokenID == 0, "pick one"); // such a lazy check lol

        if (amount > 0) {
            paymentUtil.processPayment(denominatedAsset, pricePerUnit * amount);
            _mintNext(wallet, amount);
        } else {
            paymentUtil.processPayment(denominatedAsset, pricePerUnit);
            _mintTarget(wallet, tokenID);
        }
    }

    function mint(
        address wallet,
        uint256 amount,
        uint256 tokenID,
        uint256 nonce,
        uint256 pricePerUnit,
        address denominatedAsset,
        bytes memory signature
    ) public payable {
        bytes32 data = hash(
            wallet,
            amount,
            tokenID,
            nonce,
            pricePerUnit,
            denominatedAsset,
            address(this),
            block.chainid
        );

        require(config.allowLazySell, "not available");
        require(config.allowPrivilege, "not available");

        require(_verifySig(data, signature));

        _useNonce(nonce);
        if (wallet != address(0)) {
            require(wallet == msg.sender, "nope");
        }

        require(amount * tokenID == 0, "pick one"); // such a lazy check lol

        if (amount > 0) {
            paymentUtil.processPayment(denominatedAsset, pricePerUnit * amount);
            _mintNext(wallet, amount);
        } else {
            paymentUtil.processPayment(denominatedAsset, pricePerUnit);
            _mintTarget(wallet, tokenID);
        }
    }

    /// magic overload end

    // this is 721 version. in 20 or 1155 will use the same format but different interpretation
    // wallet = 0 mean any
    // tokenID = 0 mean next
    // amount will overide tokenID
    // denominatedAsset = 0 mean chain token (e.g. eth)
    // chainID is to prevent replay attack

    function hash(
        address wallet,
        uint256 amount,
        uint256 tokenID,
        uint256 nonce,
        uint256 pricePerUnit,
        address denominatedAsset,
        address refPorject,
        uint256 chainID
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    wallet,
                    amount,
                    tokenID,
                    nonce,
                    pricePerUnit,
                    denominatedAsset,
                    refPorject,
                    chainID
                )
            );
    }

    function _toSignedHash(bytes32 data) internal pure returns (bytes32) {
        return ECDSA.toEthSignedMessageHash(data);
    }

    function _verifySig(bytes32 data, bytes memory signature)
        public
        view
        returns (bool)
    {
        return
            hasRole(MINTER_ROLE, ECDSA.recover(_toSignedHash(data), signature));
    }

    function _merkleCheck(
        bytes32 data,
        bytes32 root,
        bytes32[] memory merkleProof
    ) internal pure returns (bool) {
        return MerkleProof.verify(merkleProof, root, data);
    }

    /// ROUND

    function newRound(
        string memory roundName,
        uint128 _price,
        uint32 _quota,
        uint16 _amountPerUser,
        bool _isActive,
        bool _isPublic,
        bool _isMerkle,
        address _tokenAddress
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        // require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "admin only");
        bytes32 key = keccak256(abi.encodePacked(roundName));

        require(!roundData[key].exist, "already exist");
        roundNames.push(roundName);
        roundData[key] = Round({
            price: _price,
            quota: _quota,
            amountPerUser: _amountPerUser,
            isActive: _isActive,
            isPublic: _isPublic,
            isMerkleMode: _isMerkle,
            tokenAddress: _tokenAddress,
            exist: true
        });
    }

    function triggerRound(string memory roundName, bool _isActive)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "admin only");
        bytes32 key = keccak256(abi.encodePacked(roundName));
        roundData[key].isActive = _isActive;
    }

    function setMerkleRoot(string memory roundName, bytes32 root)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "admin only");
        bytes32 key = keccak256(abi.encodePacked(roundName));
        merkleRoot[key] = root;
    }

    function updateRound(
        string memory roundName,
        uint128 _price,
        uint32 _quota,
        uint16 _amountPerUser,
        bool _isPublic
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        // require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "admin only");
        bytes32 key = keccak256(abi.encodePacked(roundName));
        roundData[key].price = _price;
        roundData[key].quota = _quota;
        roundData[key].amountPerUser = _amountPerUser;
        roundData[key].isPublic = _isPublic;
    }

    function addRoundWallet(string memory roundName, address[] memory wallets)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "admin only");
        bytes32 key = keccak256(abi.encodePacked(roundName));
        for (uint256 i = 0; i < wallets.length; i++) {
            walletList[key].add(wallets[i]);
        }
    }

    function removeRoundWallet(
        string memory roundName,
        address[] memory wallets
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        // require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "admin only");
        bytes32 key = keccak256(abi.encodePacked(roundName));
        for (uint256 i = 0; i < wallets.length; i++) {
            walletList[key].remove(wallets[i]);
        }
    }

    function getRoundWallet(string memory roundName)
        public
        view
        returns (address[] memory)
    {
        return walletList[keccak256(abi.encodePacked(roundName))].values();
    }

    function isQualify(address wallet, string memory roundName)
        public
        view
        returns (bool)
    {
        Round memory x = roundInfo(roundName);
        if (!x.isActive) {
            return false;
        }
        if (x.quota == 0) {
            return false;
        }
        bytes32 key = keccak256(abi.encodePacked(roundName));
        if (!x.isPublic && !walletList[key].contains(wallet)) {
            return false;
        }
        if (mintedInRound[key][wallet] >= x.amountPerUser) {
            return false;
        }
        return true;
    }

    function listQualifiedRound(address wallet)
        public
        view
        returns (string[] memory)
    {
        string[] memory valid = new string[](roundNames.length);
        for (uint256 i = 0; i < roundNames.length; i++) {
            if (isQualify(wallet, roundNames[i])) {
                valid[i] = roundNames[i];
            }
        }
        return valid;
    }

    function burnNonce(uint256[] calldata nonces)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "admin only");
        require(config.allowPrivilege, "df");

        for (uint256 i = 0; i < nonces.length; i++) {
            nonceUsed[nonces[i]] = true;
        }
    }

    function resetNonce(uint256[] calldata nonces)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "admin only");
        require(config.allowPrivilege, "df");

        for (uint256 i = 0; i < nonces.length; i++) {
            nonceUsed[nonces[i]] = false;
        }
    }

    function _useNonce(uint256 nonce) internal {
        require(!nonceUsed[nonce], "used");
        nonceUsed[nonce] = true;
    }

    /// ROUND end ///

    function initialize(
        bytes calldata initArg,
        uint128 _bip,
        address _feeReceiver
    ) public initializer {
        feeReceiver = _feeReceiver;
        bip = _bip;

        (
            string memory name,
            string memory symbol,
            string memory baseTokenURI,
            address owner,
            bool _allowNFTUpdate,
            bool _allowConfUpdate,
            bool _allowContract,
            bool _allowPrivilege,
            bool _randomAccessMode,
            bool _allowTarget,
            bool _allowLazySell
        ) = abi.decode(
                initArg,
                (
                    string,
                    string,
                    string,
                    address,
                    bool,
                    bool,
                    bool,
                    bool,
                    bool,
                    bool,
                    bool
                )
            );

        __721Init(name, symbol);
        _setupRole(DEFAULT_ADMIN_ROLE, owner);
        _setupRole(MINTER_ROLE, owner);

        _baseTokenURI = baseTokenURI;
        config = Conf({
            allowNFTUpdate: _allowNFTUpdate,
            allowConfUpdate: _allowConfUpdate,
            allowContract: _allowContract,
            allowPrivilege: _allowPrivilege,
            randomAccessMode: _randomAccessMode,
            allowTarget: _allowTarget,
            allowLazySell: _allowLazySell,
            maxSupply: 0
        });
    }

    function updateConfig(
        bool _allowNFTUpdate,
        bool _allowConfUpdate,
        bool _allowContract,
        bool _allowPrivilege,
        bool _allowTarget,
        bool _allowLazySell
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(config.allowConfUpdate);
        // require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "admin only");
        config.allowNFTUpdate = _allowNFTUpdate;
        config.allowConfUpdate = _allowConfUpdate;
        config.allowContract = _allowContract;
        config.allowPrivilege = _allowPrivilege;
        config.allowTarget = _allowTarget;
        config.allowLazySell = _allowLazySell;
    }

    function withdraw(address tokenAddress) public nonReentrant {
        address reviver = beneficiary;
        if (beneficiary == address(0)) {
            require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "admin only");
            reviver = msg.sender;
        }
        if (tokenAddress == address(0)) {
            payable(feeReceiver).transfer(
                (address(this).balance * bip) / 10000
            );
            payable(reviver).transfer(address(this).balance);
        } else {
            IERC20 token = IERC20(tokenAddress);
            token.safeTransfer(
                feeReceiver,
                (token.balanceOf(address(this)) * bip) / 10000
            );
            token.safeTransfer(reviver, token.balanceOf(address(this)));
        }
    }

    function setRandomness(address _randomness)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "admin only");
        randomness = ISBRandomness(_randomness);
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

    // @dev boring section -------------------

    function __721Init(string memory name, string memory symbol) internal {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __ReentrancyGuard_init_unchained();
        __ERC721_init_unchained(name, symbol);
        __ERC721Enumerable_init_unchained();
        __AccessControlEnumerable_init_unchained();
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

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
        override(
            ERC721Upgradeable,
            ERC721EnumerableUpgradeable,
            AccessControlEnumerableUpgradeable
        )
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
