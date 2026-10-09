// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MyGameToken.sol";
import "../src/GameItems.sol";
import "../src/EliteMercenary.sol";
import "../src/BattlePass.sol";
import "../src/PVPPass.sol";
import "../src/GameTokenVault.sol";
import "../src/GameEconomyManager.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Interfaces locales para interactuar con los contratos sin causar colisiones de nombres
interface IPVPTicket {
    function initialize(address mgtTokenAddress, address _mercenaryNftAddress, address pvpPassAddress) external;
    function claimDailyTicket(uint256 _mercenaryId) external;
    function balanceOf(address account) external view returns (uint256);
    function setTicketBurner(address _burner, bool _isAllowed) external;
}

interface IPVE_LogicV2 {
    function initialize(address initialOwner, address _mercenaryNft) external;
    function createMission(uint256 missionId, uint256 minLevel, uint256 duration, uint256 xpReward, uint256 cooldown) external;
    function startMission(uint256 _mercenaryId, uint256 _missionId) external;
    function completeMission(uint256 _mercenaryId) external;
    function xp(uint256 tokenId) external view returns (uint256);
}

interface IPVP_Logic {
    function initialize(
        address mgtTokenAddress,
        address pvpTicketAddress,
        address mercenaryNftAddress,
        address gameItemsAddress,
        address _treasuryAddress,
        address usdStablecoinAddress
    ) external;
    function startPvpBattle(uint256 _mercenaryId) external;
    function endPvpBattle(uint256 _mercenaryId, uint256 _finalHealth, bool _didWin) external;
}

contract FullGameLoopSimulationTest is Test {
    address owner = address(this);
    address player = address(0x1234);
    address treasury = address(0x9999);

    MyGameToken gameToken;
    MyGameToken stablecoin;
    GameItems gameItems;
    EliteMercenary mercenary;
    BattlePass battlePass;
    PVPPass pvpPass;
    IPVPTicket pvpTicket;
    GameTokenVault tokenVault;
    GameEconomyManager economyManager;
    IPVE_LogicV2 pveLogic;
    IPVP_Logic pvpLogic;

    uint256 knifeItemId = 101;
    uint256 rewardItemId = 201;

    function setUp() public {
        // 1. Despliegue de MyGameToken
        MyGameToken tokenImpl = new MyGameToken();
        ERC1967Proxy tokenProxy = new ERC1967Proxy(
            address(tokenImpl),
            abi.encodeWithSignature("initialize(string,string,address)", "MyGameToken", "MGT", owner)
        );
        gameToken = MyGameToken(address(tokenProxy));

        // 2. Despliegue de Stablecoin
        MyGameToken stableImpl = new MyGameToken();
        ERC1967Proxy stableProxy = new ERC1967Proxy(
            address(stableImpl),
            abi.encodeWithSignature("initialize(string,string,address)", "USD Stablecoin", "USDC", owner)
        );
        stablecoin = MyGameToken(address(stableProxy));

        // 3. Despliegue de GameItems
        GameItems itemsImpl = new GameItems();
        ERC1967Proxy itemsProxy = new ERC1967Proxy(
            address(itemsImpl),
            abi.encodeWithSignature("initialize(address,string)", owner, "https://api.game.com/item/")
        );
        gameItems = GameItems(address(itemsProxy));

        // 4. Despliegue de EliteMercenary
        EliteMercenary mercImpl = new EliteMercenary();
        ERC1967Proxy mercProxy = new ERC1967Proxy(
            address(mercImpl),
            abi.encodeWithSignature("initialize(address,address,address,address)", owner, owner, address(gameItems), owner)
        );
        mercenary = EliteMercenary(address(mercProxy));

        // 5. Despliegue de BattlePass
        BattlePass bpImpl = new BattlePass();
        ERC1967Proxy bpProxy = new ERC1967Proxy(
            address(bpImpl),
            abi.encodeWithSignature("initialize(address,string)", owner, "https://api.game.com/pass/")
        );
        battlePass = BattlePass(address(bpProxy));

        // 6. Despliegue de PVPPass
        PVPPass pvpPassImpl = new PVPPass();
        ERC1967Proxy pvpPassProxy = new ERC1967Proxy(
            address(pvpPassImpl),
            abi.encodeWithSignature("initialize(string,string,address)", "PVP Pass", "PVPP", owner)
        );
        pvpPass = PVPPass(address(pvpPassProxy));

        // 7. Despliegue de GameTokenVault
        GameTokenVault vaultImpl = new GameTokenVault();
        ERC1967Proxy vaultProxy = new ERC1967Proxy(
            address(vaultImpl),
            abi.encodeWithSignature("initialize(address,address)", address(gameToken), owner)
        );
        tokenVault = GameTokenVault(address(vaultProxy));

        // 8. Despliegue de GameEconomyManager (50% quema, 50% vault)
        GameEconomyManager managerImpl = new GameEconomyManager();
        ERC1967Proxy managerProxy = new ERC1967Proxy(
            address(managerImpl),
            abi.encodeWithSignature(
                "initialize(address,address,uint256,address)",
                address(gameToken),
                address(tokenVault),
                5000,
                owner
            )
        );
        economyManager = GameEconomyManager(address(managerProxy));

        // 9. Despliegue mediante deployCode para contratos lógicos externos
        address pvpTicketImplAddr = deployCode("PVPTicket.sol:PVPTicket");
        ERC1967Proxy pvpTicketProxy = new ERC1967Proxy(
            pvpTicketImplAddr,
            abi.encodeWithSignature("initialize(address,address,address)", address(gameToken), address(mercenary), address(pvpPass))
        );
        pvpTicket = IPVPTicket(address(pvpTicketProxy));

        address pveImplAddr = deployCode("PVE_LogicV2.sol:PVE_LogicV2");
        ERC1967Proxy pveProxy = new ERC1967Proxy(
            pveImplAddr,
            abi.encodeWithSignature("initialize(address,address)", owner, address(mercenary))
        );
        pveLogic = IPVE_LogicV2(address(pveProxy));

        address pvpImplAddr = deployCode("PVP_Logic.sol:PVP_Logic");
        ERC1967Proxy pvpProxy = new ERC1967Proxy(
            pvpImplAddr,
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address)",
                address(gameToken),
                address(pvpTicket),
                address(mercenary),
                address(gameItems),
                treasury,
                address(stablecoin)
            )
        );
        pvpLogic = IPVP_Logic(address(pvpProxy));

        // Configuración de permisos cruzados válidos en los contratos originales
        gameItems.setMinter(owner, true);
        gameItems.setMinter(address(pvpProxy), true);

        gameToken.setBurner(owner, true);
        gameToken.setBurner(address(pvpTicketProxy), true);
        gameToken.setBurner(address(economyManager), true); // Autorizar al manager económico para quemar

        // --- AUTORIZACIÓN DE MINTEO PARA PVP_Logic (PROXY) ---
        gameToken.setMinter(address(pvpProxy), true);

        mercenary.setLogicController(owner, true);
        mercenary.setLogicController(address(pveProxy), true);
        mercenary.setLogicController(address(pvpProxy), true);

        pvpTicket.setTicketBurner(address(pvpProxy), true);
    }

    function test_EndToEnd_GameLoop() public {
        gameItems.registerItemData(knifeItemId, GameItems.ItemType.MARKETPLACE_UPGRADE, 10, false);
        gameItems.registerItemData(rewardItemId, GameItems.ItemType.MARKETPLACE_UPGRADE, 25, false);

        pveLogic.createMission(1, 5, 1 hours, 100, 30 minutes);

        battlePass.mint(player);
        pvpPass.safeMint(player, "uri_pvp_pass");

        uint256 playerMercenaryId = mercenary.recruitMercenary(player, 50);
        mercenary.setLevel(playerMercenaryId, 5);

        gameToken.mint(player, 10000 * 10**18);
        stablecoin.mint(player, 1000 * 10**18);

        // 1. Reclamar ticket diario
        vm.startPrank(player);
        vm.warp(block.timestamp + 25 hours);
        pvpTicket.claimDailyTicket(playerMercenaryId);
        vm.stopPrank();

        assertEq(pvpTicket.balanceOf(player), 1 * 10**18, "Ticket reclamado con exito");

        // 2. Misión PVE
        vm.startPrank(player);
        pveLogic.startMission(playerMercenaryId, 1);
        vm.warp(block.timestamp + 1 hours + 1 minutes);
        pveLogic.completeMission(playerMercenaryId);
        vm.stopPrank();

        assertEq(pveLogic.xp(playerMercenaryId), 100, "XP de mision PVE otorgada");

        // 3. Simular procesamiento de tarifa deflacionaria mediante el GameEconomyManager
        uint256 feeAmount = 200 * 10**18;
        uint256 initialSupply = gameToken.totalSupply();

        vm.startPrank(player);
        gameToken.approve(address(economyManager), feeAmount);
        economyManager.processFee(player, feeAmount);
        vm.stopPrank();

        // Validaciones económicas deflacionarias
        assertEq(gameToken.totalSupply(), initialSupply - (feeAmount / 2), "La quema redujo el suministro total");
        assertEq(gameToken.balanceOf(address(tokenVault)), feeAmount / 2, "El Vault recibio su parte correspondiente");

        // 4. Batalla PVP
        vm.startPrank(player);
        stablecoin.approve(address(pvpLogic), 50 * 10**18);
        pvpLogic.startPvpBattle(playerMercenaryId);
        vm.stopPrank();

        pvpLogic.endPvpBattle(playerMercenaryId, 80, true);

        // 5. Verificaciones finales del bucle de juego
        assertEq(gameItems.balanceOf(player, rewardItemId), 1, "Item de recompensa entregado");
        
        (, uint256 finalHealth, uint256 finalLevel,) = mercenary.getMercenaryStats(playerMercenaryId);
        assertEq(finalHealth, 80, "Salud actualizada tras PVP");
        assertEq(finalLevel, 6, "Nivel incrementado tras victoria PVP");
    }
}