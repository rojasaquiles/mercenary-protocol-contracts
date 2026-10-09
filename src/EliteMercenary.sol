// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC721RoyaltyUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721RoyaltyUpgradeable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

interface IGameItems {
    function balanceOfBatch(address[] calldata owners, uint256[] calldata ids) external view returns (uint256[] memory balances);
}

contract EliteMercenary is
    ERC721Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ERC721RoyaltyUpgradeable
{
    using Strings for uint256;

    uint256 private _tokenIdCounter;

    struct MercenaryData {
        uint256 survivalSkill;
        uint256 health;
        uint256 level;
        bool isDeployed;
    }

    mapping(uint256 => MercenaryData) public mercenaryStats;
    mapping(address => bool) public isLogicController; 

    address public gameItemsAddress;
    mapping(uint256 => uint256) public equippedWeapon;
    mapping(uint256 => uint256) public equippedArmor;
    
    uint96 private constant DEFAULT_ROYALTY_FEE_BPS = 750;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner, 
        address _initialLogicController, 
        address _gameItemsAddress, 
        address _royaltyReceiverAddress
    ) public initializer {
        __ERC721_init("EliteMercenary", "MERC");
        
        // OpenZeppelin v4: __Ownable_init() sin argumentos + _transferOwnership
        __Ownable_init();
        _transferOwnership(initialOwner);

        __ERC721Royalty_init();
        __UUPSUpgradeable_init();

        isLogicController[_initialLogicController] = true;
        gameItemsAddress = _gameItemsAddress;
        _tokenIdCounter = 1;

        _setDefaultRoyalty(_royaltyReceiverAddress, DEFAULT_ROYALTY_FEE_BPS);
    }
    
    function _burn(uint256 tokenId) internal virtual override(ERC721Upgradeable, ERC721RoyaltyUpgradeable) {
        super._burn(tokenId);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {}
    
    modifier onlyLogicController() {
        _onlyLogicController();
        _;
    }

    function _onlyLogicController() internal view {
        require(
            isLogicController[ContextUpgradeable._msgSender()] || ContextUpgradeable._msgSender() == owner(),
            "MercenaryNFT: Unauthorized controller"
        );
    }

    function setLogicController(address _newController, bool _isAllowed) external onlyOwner {
        require(_newController != address(0), "Cannot set zero address");
        isLogicController[_newController] = _isAllowed;
    }

    function recruitMercenary(address player, uint256 initialSkill) public onlyOwner returns (uint256) {
        uint256 tokenId = _tokenIdCounter;
        _safeMint(player, tokenId);
        _tokenIdCounter++;
        mercenaryStats[tokenId] = MercenaryData({
            survivalSkill: initialSkill,
            health: 100,
            level: 1,
            isDeployed: false
        });
        return tokenId;
    }
    
    function getMercenaryStats(uint256 _tokenId) public view returns (
        uint256 survivalSkill,
        uint256 health,
        uint256 level,
        bool isDeployed
    ) {
        MercenaryData storage data = mercenaryStats[_tokenId];
        return (data.survivalSkill, data.health, data.level, data.isDeployed);
    }
    
    function setHealth(uint256 _tokenId, uint256 _newHealth) external onlyLogicController {
        mercenaryStats[_tokenId].health = _newHealth;
    }

    function setLevel(uint256 _tokenId, uint256 _newLevel) external onlyLogicController {
        mercenaryStats[_tokenId].level = _newLevel;
    }
    
    function setSurvivalSkill(uint256 _tokenId, uint256 _newSkill) external onlyLogicController {
        mercenaryStats[_tokenId].survivalSkill = _newSkill;
    }
    
    function setIsDeployed(uint256 _tokenId, bool _deployed) external onlyLogicController {
        mercenaryStats[_tokenId].isDeployed = _deployed;
    }

    function setGameItemsAddress(address _newAddress) external onlyOwner {
        require(_newAddress != address(0), "Cannot set zero address");
        gameItemsAddress = _newAddress;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // En OZ v4 se verifica la existencia con _requireMinted
        _requireMinted(tokenId);
        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    function setEquipment(
        uint256 _mercenaryId, 
        uint256 _itemId, 
        uint8 _slot
    ) public {
        require(ownerOf(_mercenaryId) == msg.sender, "MercNFT: Caller is not the owner.");
        require(!mercenaryStats[_mercenaryId].isDeployed, "MercNFT: Cannot change equipment while deployed.");

        if (_itemId != 0) {
            IGameItems gameItems = IGameItems(gameItemsAddress);
            uint256[] memory ids = new uint256[](1);
            address[] memory owners = new address[](1);
            ids[0] = _itemId;
            owners[0] = msg.sender;
            
            uint256[] memory balances = gameItems.balanceOfBatch(owners, ids);
            require(balances[0] > 0, "MercNFT: Item not owned by the player.");
        }
        
        if (_slot == 1) {
            equippedWeapon[_mercenaryId] = _itemId;
        } else if (_slot == 2) {
            equippedArmor[_mercenaryId] = _itemId;
        } else {
            revert("MercNFT: Invalid slot.");
        }
    }
    
    function getEquippedItems(uint256 _mercenaryId)
        public 
        view 
        returns (uint256 weaponId, uint256 armorId)
    {
        return (equippedWeapon[_mercenaryId], equippedArmor[_mercenaryId]);
    }

    // Bloquear transferencia de NFT si está en misión (isDeployed) - Sintaxis OZ v4
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal override {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);

        if (from != address(0) && to != address(0)) {
            require(!mercenaryStats[firstTokenId].isDeployed, "MercNFT: Cannot transfer deployed mercenary.");
        }
    }
    
    function supportsInterface(bytes4 interfaceId) public view override(ERC721Upgradeable, ERC721RoyaltyUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}