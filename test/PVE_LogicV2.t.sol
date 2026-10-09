// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EliteMercenary} from "../src/EliteMercenary.sol";
import {PVE_LogicV2} from "../src/PVE_LogicV2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PVE_LogicV2Test is Test {
    EliteMercenary public mercenaryNft;
    PVE_LogicV2 public pveLogic;

    address public owner = address(1);
    address public player = address(2);
    uint256 public mercenaryId;
    uint256 public missionId = 1;

    function setUp() public {
        vm.startPrank(owner);

        // Desplegar EliteMercenary con Proxy ERC1967 (OpenZeppelin v4)
        EliteMercenary mercImpl = new EliteMercenary();
        bytes memory mercData = abi.encodeWithSelector(
            EliteMercenary.initialize.selector,
            owner,
            address(this),
            address(0),
            owner
        );
        ERC1967Proxy mercProxy = new ERC1967Proxy(address(mercImpl), mercData);
        mercenaryNft = EliteMercenary(address(mercProxy));

        // Desplegar PVE_LogicV2 con Proxy ERC1967 (OpenZeppelin v4)
        PVE_LogicV2 pveImpl = new PVE_LogicV2();
        bytes memory pveData = abi.encodeWithSelector(
            PVE_LogicV2.initialize.selector,
            owner,
            address(mercenaryNft)
        );
        ERC1967Proxy pveProxy = new ERC1967Proxy(address(pveImpl), pveData);
        pveLogic = PVE_LogicV2(address(pveProxy));

        // Asignar controlador
        mercenaryNft.setLogicController(address(pveLogic), true);

        // Crear Misión 1 (minLevel: 1, duration: 1 hour, xpReward: 100, cooldown: 1 day)
        pveLogic.createMission(missionId, 1, 1 hours, 100, 1 days);

        // Reclutar mercenario para el jugador
        mercenaryId = mercenaryNft.recruitMercenary(player, 50);

        vm.stopPrank();
    }

    function test_StartMission_Success() public {
        vm.warp(block.timestamp + 2 days);

        vm.prank(player);
        pveLogic.startMission(mercenaryId, missionId);

        (,,, bool isDeployed) = mercenaryNft.getMercenaryStats(mercenaryId);
        assertTrue(isDeployed);
    }

    function test_StartMission_NonOwner_Reverts() public {
        vm.warp(block.timestamp + 2 days);

        vm.prank(address(0xDEAD));
        vm.expectRevert("Not the owner of mercenary");
        pveLogic.startMission(mercenaryId, missionId);
    }

    function test_SettleMission_Success() public {
        vm.warp(block.timestamp + 2 days);

        vm.prank(player);
        pveLogic.startMission(mercenaryId, missionId);

        vm.warp(block.timestamp + 1 hours + 1);

        vm.prank(player);
        pveLogic.completeMission(mercenaryId);

        assertEq(pveLogic.xp(mercenaryId), 100);

        (,,, bool isDeployed) = mercenaryNft.getMercenaryStats(mercenaryId);
        assertFalse(isDeployed);
    }

    function test_CreateMission_InvalidInputs_Reverts() public {
        vm.startPrank(owner);
        vm.expectRevert("Invalid mission ID");
        pveLogic.createMission(0, 1, 1 hours, 100, 1 days);

        vm.expectRevert("Duration must be > 0");
        pveLogic.createMission(2, 1, 0, 100, 1 days);
        vm.stopPrank();
    }

    function test_StartMission_LowHealth_Reverts() public {
        vm.warp(block.timestamp + 2 days);

        vm.prank(owner);
        mercenaryNft.setHealth(mercenaryId, 0);

        vm.prank(player);
        vm.expectRevert("Mercenary is dead or exhausted");
        pveLogic.startMission(mercenaryId, missionId);
    }

    function test_StartMission_Cooldown_Reverts() public {
        vm.warp(block.timestamp + 2 days);

        vm.prank(player);
        pveLogic.startMission(mercenaryId, missionId);

        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(player);
        pveLogic.completeMission(mercenaryId);

        vm.prank(player);
        vm.expectRevert("PVE: Mercenary on cooldown");
        pveLogic.startMission(mercenaryId, missionId);
    }

    function test_CompleteMission_EarlyOrNoMission_Reverts() public {
        vm.warp(block.timestamp + 2 days);

        vm.prank(player);
        vm.expectRevert("No active mission");
        pveLogic.completeMission(mercenaryId);

        vm.prank(player);
        pveLogic.startMission(mercenaryId, missionId);

        vm.prank(player);
        vm.expectRevert("Mission not finished yet");
        pveLogic.completeMission(mercenaryId);
    }

    function test_GettersAndPausable() public {
        uint256 cdEnd = pveLogic.getCooldownEnd(mercenaryId, missionId);
        assertEq(cdEnd, 1 days);

        vm.warp(block.timestamp + 2 days);
        bool available = pveLogic.isAvailable(mercenaryId, missionId);
        assertTrue(available);

        vm.prank(owner);
        pveLogic.pause();

        vm.prank(player);
        vm.expectRevert("Pausable: paused");
        pveLogic.startMission(mercenaryId, missionId);

        vm.prank(owner);
        pveLogic.unpause();
    }

    function test_AuthorizeUpgrade() public {
        address newImpl = address(new PVE_LogicV2());

        // 1. Un usuario no owner debe fallar con error de autorización
        vm.prank(player);
        vm.expectRevert();
        pveLogic.upgradeTo(newImpl);

        // 2. El owner realiza el upgrade exitosamente invocando upgradeTo
        vm.prank(owner);
        pveLogic.upgradeTo(newImpl);

        // 3. Verificación adicional de que el storage slot ERC-1967 realmente cambió
        bytes32 implSlot = vm.load(
            address(pveLogic),
            0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
        );
        assertEq(address(uint160(uint256(implSlot))), newImpl);
    }

    function test_StartMission_LowLevel_Reverts() public {
        vm.startPrank(owner);
        pveLogic.createMission(2, 10, 1 hours, 100, 1 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        vm.prank(player);
        vm.expectRevert("Mercenary level too low");
        pveLogic.startMission(mercenaryId, 2);
    }

    function test_StartMission_InvalidMission_Reverts() public {
        vm.warp(block.timestamp + 2 days);

        vm.prank(player);
        vm.expectRevert("Mission is not active");
        pveLogic.startMission(mercenaryId, 999);
    }
}