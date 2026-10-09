// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GameItems} from "src/GameItems.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract GameItemsTest is Test {
    address deployer = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address minter = address(0x4);
    address operator = address(0x5);
    address nonOwner = address(0x6);

    GameItems public implementation;
    GameItems public proxy;

    string public constant URI = "ipfs://game-items/{id}.json";
    string public constant NEW_URI = "ipfs://new-items/{id}.json";
    
    uint256[] public tokenIds = [1, 2, 3];
    uint256[] public mintAmounts = [100, 50, 25];
    
    uint256 constant STARTER_ID = 101;
    uint256 constant MARKET_ID = 202;

    function setUp() public {
        vm.startPrank(deployer);

        implementation = new GameItems();

        bytes memory data = abi.encodeWithSelector(
            implementation.initialize.selector,
            deployer,
            URI     
        );

        ERC1967Proxy proxyContract = new ERC1967Proxy(
            address(implementation), 
            data
        );
        
        vm.stopPrank();

        proxy = GameItems(address(proxyContract));
        
        vm.prank(deployer);
        proxy.setMinter(minter, true);

        vm.prank(deployer);
        proxy.registerItemData(
            STARTER_ID,
            GameItems.ItemType.STARTER_BASE,
            10,
            false
        );

        vm.prank(deployer);
        proxy.registerItemData(
            MARKET_ID,
            GameItems.ItemType.MARKETPLACE_UPGRADE,
            50,
            true
        );
    }
    
    function test_Deployment_Success() public view {
        assertEq(proxy.owner(), deployer, unicode"Owner incorrecto");
        assertTrue(keccak256(bytes(proxy.uri(1))) == keccak256(abi.encodePacked(URI)), unicode"URI base incorrecta");
    }

    function test_MintBatch_ByOwner_Success() public {
        vm.prank(deployer);
        proxy.mintBatch(user1, tokenIds, mintAmounts, "");
        
        assertEq(proxy.balanceOf(user1, tokenIds[0]), mintAmounts[0], unicode"Balance de Item 1 incorrecto");
        assertEq(proxy.balanceOf(user1, tokenIds[1]), mintAmounts[1], unicode"Balance de Item 2 incorrecto");
        assertEq(proxy.balanceOf(user1, tokenIds[2]), mintAmounts[2], unicode"Balance de Item 3 incorrecto");
    }

    function test_MintBatch_ByNonOwner_Reverts() public {
        vm.prank(nonOwner);
        vm.expectRevert(unicode"GameItems: Caller is not a minter or owner");
        proxy.mintBatch(user1, tokenIds, mintAmounts, "");
    }
    
    function test_RegisterItemData_Success() public view {
        (
            GameItems.ItemType itemType, 
            uint256 statBoost, 
            bool isConsumable
        ) = proxy.itemData(STARTER_ID);

        assertEq(uint256(itemType), uint256(GameItems.ItemType.STARTER_BASE), unicode"ItemType incorrecto");
        assertEq(statBoost, 10, unicode"StatBoost incorrecto");
        assertFalse(isConsumable, unicode"isConsumable incorrecto");
    }
    
    function test_RegisterItemData_AlreadyRegistered_Reverts() public {
        vm.prank(deployer);
        vm.expectRevert(unicode"Item already registered");
        proxy.registerItemData(STARTER_ID, GameItems.ItemType.STARTER_BASE, 1, false);
    }
    
    function test_RegisterItemData_UndefinedType_Reverts() public {
        vm.prank(deployer);
        vm.expectRevert(unicode"ItemType cannot be UNDEFINED");
        proxy.registerItemData(999, GameItems.ItemType.UNDEFINED, 1, false);
    }

    function test_SetMinter_Success() public view {
        assertTrue(proxy.isMinter(minter), unicode"Minter no se estableció");
        assertFalse(proxy.isMinter(user1), unicode"El usuario es minter incorrectamente");
    }

    function test_SetMinter_ByNonOwner_Reverts() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.setMinter(user1, true);
    }

    function test_MintItem_STARTER_BASE_ByOwner_Success() public {
        vm.prank(deployer);
        proxy.mintItem(user1, STARTER_ID, 5, "");
        assertEq(proxy.balanceOf(user1, STARTER_ID), 5, unicode"Mint de STARTER_BASE falló");
    }

    function test_MintItem_STARTER_BASE_ByNonOwner_Reverts() public {
        vm.prank(user2);
        vm.expectRevert(unicode"Only Owner can mint STARTER_BASE items");
        proxy.mintItem(user1, STARTER_ID, 1, "");
    }
    
    function test_MintItem_MARKETPLACE_UPGRADE_ByMinter_Success() public {
        vm.prank(minter);
        proxy.mintItem(user2, MARKET_ID, 10, "");
        assertEq(proxy.balanceOf(user2, MARKET_ID), 10, unicode"Mint de MARKETPLACE_UPGRADE falló");
    }
    
    function test_MintItem_MARKETPLACE_UPGRADE_ByNonMinter_Reverts() public {
        vm.prank(user2);
        vm.expectRevert(unicode"Only Minter can mint MARKETPLACE_UPGRADE items");
        proxy.mintItem(user1, MARKET_ID, 1, "");
    }
    
    function test_MintItem_Unconfigured_Reverts() public {
        vm.prank(deployer);
        vm.expectRevert(unicode"Item is not configured");
        proxy.mintItem(user1, 999, 1, "");
    }

    function test_SetApprovalForAll_Success() public {
        vm.prank(user1);
        proxy.setApprovalForAll(operator, true);
        assertTrue(proxy.isApprovedForAll(user1, operator), unicode"Aprobación falló");
    }
    
    function test_SafeTransferFrom_Success() public {
        uint256 transferAmount = 10;
        vm.prank(deployer);
        proxy.mintItem(user1, STARTER_ID, 20, "");
        
        vm.startPrank(user1);
        proxy.safeTransferFrom(user1, user2, STARTER_ID, transferAmount, "");
        vm.stopPrank();
        
        assertEq(proxy.balanceOf(user1, STARTER_ID), 10, unicode"Balance del remitente incorrecto");
        assertEq(proxy.balanceOf(user2, STARTER_ID), 10, unicode"Balance del receptor incorrecto");
    }
    
    function test_SafeBatchTransferFrom_ByOperator_Success() public {
        uint256[] memory batchIds = new uint256[](2);
        batchIds[0] = STARTER_ID;
        batchIds[1] = MARKET_ID;

        uint256[] memory batchAmounts = new uint256[](2);
        batchAmounts[0] = 5;
        batchAmounts[1] = 10;
        
        vm.prank(deployer);
        proxy.mintItem(user1, STARTER_ID, 10, "");
        vm.prank(minter);
        proxy.mintItem(user1, MARKET_ID, 20, "");
        
        vm.prank(user1);
        proxy.setApprovalForAll(operator, true);
        
        vm.prank(operator);
        proxy.safeBatchTransferFrom(user1, user2, batchIds, batchAmounts, "");
        
        assertEq(proxy.balanceOf(user1, STARTER_ID), 5, unicode"Balance restante del remitente 1 incorrecto");
        assertEq(proxy.balanceOf(user2, STARTER_ID), 5, unicode"Balance del receptor 1 incorrecto");
        assertEq(proxy.balanceOf(user1, MARKET_ID), 10, unicode"Balance restante del remitente 2 incorrecto");
        assertEq(proxy.balanceOf(user2, MARKET_ID), 10, unicode"Balance del receptor 2 incorrecto");
    }

    function test_SetURI_ByOwner_Success() public {
        vm.prank(deployer);
        proxy.setURI(NEW_URI);
        assertTrue(keccak256(bytes(proxy.uri(1))) == keccak256(abi.encodePacked(NEW_URI)), unicode"URI no se actualizó");
    }

    function test_SetURI_ByNonOwner_Reverts() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.setURI(NEW_URI);
    }
}