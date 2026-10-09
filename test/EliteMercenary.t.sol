// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EliteMercenary} from "src/EliteMercenary.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract EliteMercenaryTest is Test {
    address deployer = address(0x1);
    address user1 = address(0x2);
    address logicController = address(0x5);
    address gameItemsMock = address(0x7);
    address royaltyReceiver = address(0x8);
    address nonOwner = address(0x6);
    address newController = address(0x9);

    EliteMercenary public implementation;
    EliteMercenary public proxy;

    uint256 public constant INITIAL_SKILL = 50;

    function setUp() public {
        vm.startPrank(deployer);

        implementation = new EliteMercenary();

        bytes memory data = abi.encodeWithSelector(
            implementation.initialize.selector,
            deployer,
            logicController,
            gameItemsMock,
            royaltyReceiver
        );

        ERC1967Proxy proxyContract = new ERC1967Proxy(
            address(implementation), 
            data
        );
        
        vm.stopPrank();

        proxy = EliteMercenary(address(proxyContract));
    }

    function test_Deployment_Success() public view {
        assertEq(proxy.owner(), deployer, unicode"Owner incorrecto");
        assertTrue(proxy.isLogicController(logicController), unicode"Controller no inicializado");
        assertEq(proxy.gameItemsAddress(), gameItemsMock, unicode"Dirección de GameItems incorrecta");
    }

    function test_Recruit_ByOwner_Success() public returns (uint256) {
        vm.prank(deployer);
        uint256 tokenId = proxy.recruitMercenary(user1, INITIAL_SKILL);
        
        assertEq(tokenId, 1, unicode"Primer token ID debe ser 1");
        assertEq(proxy.balanceOf(user1), 1, unicode"Balance incorrecto después de recruit");
        assertEq(proxy.ownerOf(tokenId), user1, unicode"Owner del token incorrecto");
        
        (uint256 skill, uint256 health, uint256 level,) = proxy.getMercenaryStats(tokenId);
        assertEq(skill, INITIAL_SKILL, unicode"Skill inicial incorrecto");
        assertEq(health, 100, unicode"Salud inicial incorrecta");
        assertEq(level, 1, unicode"Nivel inicial incorrecto");

        return tokenId;
    }

    function test_Recruit_ByNonOwner_Reverts() public {
        vm.prank(nonOwner);
        
        // Formato de revert en OZ v4 para Ownable
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.recruitMercenary(user1, INITIAL_SKILL);
    }
    
    function test_SetStats_ByLogicController_Success() public {
        vm.prank(deployer);
        uint256 tokenId = proxy.recruitMercenary(user1, INITIAL_SKILL);
        
        vm.prank(logicController);
        proxy.setHealth(tokenId, 50);
        
        vm.prank(logicController);
        proxy.setLevel(tokenId, 2);
        
        (, uint256 health, uint256 level,) = proxy.getMercenaryStats(tokenId);
        assertEq(health, 50, unicode"Actualización de salud fallida");
        assertEq(level, 2, unicode"Actualización de nivel fallida");
    }

    function test_SetStats_ByNonController_Reverts() public {
        vm.prank(deployer);
        uint256 tokenId = proxy.recruitMercenary(user1, INITIAL_SKILL);
        
        vm.prank(nonOwner);
        vm.expectRevert(unicode"MercenaryNFT: Unauthorized controller");
        proxy.setHealth(tokenId, 50);
    }

    function test_SetEquipment_WithOwnedItem_Success() public {
        vm.prank(deployer);
        uint256 mercenaryId = proxy.recruitMercenary(user1, INITIAL_SKILL);
        uint256 itemId = 10;
        uint8 slotWeapon = 1;
        
        uint256[] memory oneBalance = new uint256[](1);
        oneBalance[0] = 1; 
        
        vm.mockCall(
            gameItemsMock, 
            bytes4(keccak256("balanceOfBatch(address[],uint256[])")),
            abi.encode(oneBalance)
        );
        
        vm.prank(user1);
        proxy.setEquipment(mercenaryId, itemId, slotWeapon);
        
        (uint256 equippedWeaponId,) = proxy.getEquippedItems(mercenaryId);
        assertEq(equippedWeaponId, itemId, unicode"El arma no se equipó correctamente");
    }

    function test_SetEquipment_WithUnownedItem_Reverts() public {
        vm.prank(deployer);
        uint256 mercenaryId = proxy.recruitMercenary(user1, INITIAL_SKILL);
        uint256 itemId = 20;
        uint8 slotWeapon = 1;
        
        uint256[] memory zeroBalance = new uint256[](1);
        zeroBalance[0] = 0; 

        vm.mockCall(
            gameItemsMock, 
            bytes4(keccak256("balanceOfBatch(address[],uint256[])")),
            abi.encode(zeroBalance)
        );
        
        vm.prank(user1);
        vm.expectRevert(unicode"MercNFT: Item not owned by the player.");
        proxy.setEquipment(mercenaryId, itemId, slotWeapon);
    }

    function test_SetEquipment_WhenDeployed_Reverts() public {
        vm.prank(deployer);
        uint256 mercenaryId = proxy.recruitMercenary(user1, INITIAL_SKILL);

        vm.prank(logicController);
        proxy.setIsDeployed(mercenaryId, true);

        vm.prank(user1);
        vm.expectRevert(unicode"MercNFT: Cannot change equipment while deployed.");
        proxy.setEquipment(mercenaryId, 10, 1);
    }

    function test_Transfer_WhenDeployed_Reverts() public {
        vm.prank(deployer);
        uint256 mercenaryId = proxy.recruitMercenary(user1, INITIAL_SKILL);

        vm.prank(logicController);
        proxy.setIsDeployed(mercenaryId, true);

        vm.prank(user1);
        vm.expectRevert(unicode"MercNFT: Cannot transfer deployed mercenary.");
        proxy.transferFrom(user1, address(0x3), mercenaryId);
    }

    function test_SetLogicController_Success() public {
        vm.prank(deployer);
        proxy.setLogicController(newController, true);

        assertTrue(proxy.isLogicController(newController), unicode"Nuevo controller no fue añadido");

        vm.prank(deployer);
        proxy.setLogicController(newController, false);
        assertFalse(proxy.isLogicController(newController), unicode"Controller no fue removido");
    }

    function test_SetLogicController_RevertsByNonOwner() public {
        vm.prank(nonOwner);
        
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.setLogicController(newController, true);
    }
    
    function test_SetGameItemsAddress_RevertsByNonOwner() public {
        address newGameItems = address(0xAA);

        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.setGameItemsAddress(newGameItems);
    }

    function test_SetSurvivalSkill_ByController_Success() public {
        vm.prank(deployer);
        uint256 tokenId = proxy.recruitMercenary(user1, INITIAL_SKILL);
        uint256 NEW_SKILL = 150;

        vm.prank(logicController);
        proxy.setSurvivalSkill(tokenId, NEW_SKILL);

        (uint256 skill,,,) = proxy.getMercenaryStats(tokenId);
        assertEq(skill, NEW_SKILL, unicode"Survival Skill no se actualizó");
    }

    function test_SetIsDeployed_ByController_Success() public {
        vm.prank(deployer);
        uint256 tokenId = proxy.recruitMercenary(user1, INITIAL_SKILL);

        vm.prank(logicController);
        proxy.setIsDeployed(tokenId, true);
        (,,, bool deployedTrue) = proxy.getMercenaryStats(tokenId);
        assertTrue(deployedTrue, unicode"isDeployed no se puso en true");

        vm.prank(logicController);
        proxy.setIsDeployed(tokenId, false);
        (,,, bool deployedFalse) = proxy.getMercenaryStats(tokenId);
        assertFalse(deployedFalse, unicode"isDeployed no se puso en false");
    }
}