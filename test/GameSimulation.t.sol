// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MyGameToken.sol";
import "../src/GameItems.sol";
import "../src/EliteMercenary.sol";
import "../src/BattlePass.sol";
import "../src/PVPPass.sol";
import "../src/GameTokenVault.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract GameSimulationTest is Test {
    address owner = address(this);
    address player = address(0x1234);
    address treasury = address(0x9999);
    address stablecoin = address(0x8888);

    MyGameToken gameToken;
    GameItems gameItems;
    EliteMercenary mercenary;
    BattlePass battlePass;
    PVPPass pvpPass;
    GameTokenVault tokenVault;

    uint256 knifeItemId = 101;
    uint256 rewardItemId = 201;

    function setUp() public {
        // 1. Despliegue de implementaciones y proxies ERC1967 usando abi.encodeWithSignature
        
        // MyGameToken
        MyGameToken tokenImpl = new MyGameToken();
        ERC1967Proxy tokenProxy = new ERC1967Proxy(
            address(tokenImpl),
            abi.encodeWithSignature("initialize(string,string,address)", "MyGameToken", "MGT", owner)
        );
        gameToken = MyGameToken(address(tokenProxy));

        // GameItems
        GameItems itemsImpl = new GameItems();
        ERC1967Proxy itemsProxy = new ERC1967Proxy(
            address(itemsImpl),
            abi.encodeWithSignature("initialize(address,string)", owner, "https://api.game.com/item/")
        );
        gameItems = GameItems(address(itemsProxy));

        // EliteMercenary
        EliteMercenary mercImpl = new EliteMercenary();
        ERC1967Proxy mercProxy = new ERC1967Proxy(
            address(mercImpl),
            abi.encodeWithSignature("initialize(address,address,address,address)", owner, owner, address(gameItems), owner)
        );
        mercenary = EliteMercenary(address(mercProxy));

        // BattlePass
        BattlePass bpImpl = new BattlePass();
        ERC1967Proxy bpProxy = new ERC1967Proxy(
            address(bpImpl),
            abi.encodeWithSignature("initialize(address,string)", owner, "https://api.game.com/pass/")
        );
        battlePass = BattlePass(address(bpProxy));

        // PVPPass
        PVPPass pvpPassImpl = new PVPPass();
        ERC1967Proxy pvpPassProxy = new ERC1967Proxy(
            address(pvpPassImpl),
            abi.encodeWithSignature("initialize(string,string,address)", "PVP Pass", "PVPP", owner)
        );
        pvpPass = PVPPass(address(pvpPassProxy));

        // GameTokenVault
        GameTokenVault vaultImpl = new GameTokenVault();
        ERC1967Proxy vaultProxy = new ERC1967Proxy(
            address(vaultImpl),
            abi.encodeWithSignature("initialize(address,address)", address(gameToken), owner)
        );
        tokenVault = GameTokenVault(address(vaultProxy));

        // Configuración de permisos iniciales
        gameItems.setMinter(owner, true);
        gameToken.setBurner(owner, true);
        mercenary.setLogicController(owner, true);
    }

    function test_FullGameLoop_Simulation() public {
        gameItems.registerItemData(knifeItemId, GameItems.ItemType.MARKETPLACE_UPGRADE, 10, false);
        gameItems.registerItemData(rewardItemId, GameItems.ItemType.MARKETPLACE_UPGRADE, 25, false);

        battlePass.mint(player);
        pvpPass.safeMint(player, "uri_pvp_pass");

        uint256 playerMercenaryId = mercenary.recruitMercenary(player, 50);
        mercenary.setLevel(playerMercenaryId, 5);

        gameToken.mint(player, 5000 * 10**18);

        assertTrue(playerMercenaryId > 0, "Mercenario del jugador creado con exito");
        assertEq(mercenary.ownerOf(playerMercenaryId), player, "El jugador es duenio del mercenario");
        assertEq(pvpPass.balanceOf(player), 1, "El jugador posee el pase PVP");
        assertEq(gameToken.balanceOf(player), 5000 * 10**18, "Balance inicial de MGT correcto");
    }
}