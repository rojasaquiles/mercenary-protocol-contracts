// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

contract GameItems is 
    Initializable,
    ERC1155Upgradeable, 
    OwnableUpgradeable, 
    UUPSUpgradeable 
{
    enum ItemType {
        UNDEFINED,
        STARTER_BASE,
        MARKETPLACE_UPGRADE
    }

    struct ItemData {
        ItemType itemType;
        uint256 statBoost;
        bool isConsumable;
    }
    
    mapping(uint256 => ItemData) public itemData;
    mapping(address => bool) public isMinter;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, string memory uri) public initializer {
        __ERC1155_init(uri);
        __Ownable_init();
        if (initialOwner != address(0) && initialOwner != _msgSender()) {
            _transferOwnership(initialOwner);
        }
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {}

    /// @notice Permite al dueño registrar la configuración de un nuevo ítem ID.
    function registerItemData(
        uint256 id,
        ItemType itemType,
        uint256 statBoost,
        bool isConsumable
    ) public onlyOwner {
        require(itemData[id].itemType == ItemType.UNDEFINED, "Item already registered");
        require(itemType != ItemType.UNDEFINED, "ItemType cannot be UNDEFINED");

        itemData[id] = ItemData({
            itemType: itemType,
            statBoost: statBoost,
            isConsumable: isConsumable
        });
    }

    function setMinter(address minter, bool _isAllowed) public onlyOwner {
        isMinter[minter] = _isAllowed;
    }

    modifier onlyMinter() {
        _onlyMinter();
        _;
    }

    function _onlyMinter() internal view {
        require(
            isMinter[_msgSender()] || _msgSender() == owner(),
            "GameItems: Caller is not a minter or owner"
        );
    }
    
    function _validateMintAccess(uint256 id) internal view {
        ItemType itemType = itemData[id].itemType;
        require(itemType != ItemType.UNDEFINED, "Item is not configured");

        if (itemType == ItemType.STARTER_BASE) {
            require(_msgSender() == owner(), "Only Owner can mint STARTER_BASE items");
        } else if (itemType == ItemType.MARKETPLACE_UPGRADE) {
            require(isMinter[_msgSender()], "Only Minter can mint MARKETPLACE_UPGRADE items");
        }
    }

    function mintItem(address to, uint256 id, uint256 amount, bytes memory data)
        public
    {
        _validateMintAccess(id);
        _mint(to, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        public
        onlyMinter
    {
        _mintBatch(to, ids, amounts, data);
    }

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }
}