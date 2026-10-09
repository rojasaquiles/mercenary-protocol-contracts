// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {MyGameToken} from "src/MyGameToken.sol";
import {PVPTicket} from "src/PVPTicket.sol";
import {EliteMercenary} from "src/EliteMercenary.sol";
import {PVPPass} from "src/PVPPass.sol";
import {GameItems} from "src/GameItems.sol";
import {GameTokenVault} from "src/GameTokenVault.sol";
import {PVP_Logic} from "src/PVP_Logic.sol";
import {BattlePass} from "src/BattlePass.sol";
import {PVE_LogicV2} from "src/PVE_LogicV2.sol";

contract DeployGameSystem is Script {

    // Se asigna dinámicamente usando el deployer para que coincida con tu MetaMask/Anvil
    address constant TRUSTED_FORWARDER = 0x835B0D00966952796C9f6580F585D85202860D5b;
    address constant STABLECOIN_ADDRESS = 0x54E4c9e782d4692809a7C105F862A98F79f5F070;

    address public mgtProxy;
    address public pvptProxy;
    address public mercProxy;
    address public passProxy;
    address public itemsProxy;
    address public vaultProxy;
    address public pveProxy;
    address public pvpProxy;
    address public battlePassProxy;
    
    function _deployAndInitialize(
        address implementationAddress, 
        bytes memory initData, 
        string memory contractName
    ) internal returns (address proxyAddress) {
        
        ERC1967Proxy newProxy = new ERC1967Proxy(implementationAddress, hex""); 
        proxyAddress = address(newProxy);

        (bool success, ) = proxyAddress.call(initData);
        require(success, string.concat("ERROR: Inicializacion fallida para ", contractName));
        
        return proxyAddress;
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // Usamos la dirección del deployer como el owner definitivo
        address ownerAddress = deployerAddress;
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. Desplegar e inicializar usando al Deployer como dueño temporal para configurar todo
        // MyGameToken
        MyGameToken mgtImpl = new MyGameToken();
        bytes memory mgtData = abi.encodeWithSelector(mgtImpl.initialize.selector, "My Game Token", "MGT", deployerAddress);
        mgtProxy = _deployAndInitialize(address(mgtImpl), mgtData, "MyGameToken");

        // PVPPass
        PVPPass passImpl = new PVPPass();
        bytes memory passData = abi.encodeWithSelector(passImpl.initialize.selector, "PVP Combat License", "PASS", deployerAddress);
        passProxy = _deployAndInitialize(address(passImpl), passData, "PVPPass");
        
        // GameItems
        GameItems itemsImpl = new GameItems();
        bytes memory itemsData = abi.encodeWithSelector(itemsImpl.initialize.selector, deployerAddress, "https://api.game.com/items/{id}");
        itemsProxy = _deployAndInitialize(address(itemsImpl), itemsData, "GameItems");

        // EliteMercenary
        EliteMercenary mercImpl = new EliteMercenary();
        bytes memory mercData = abi.encodeWithSelector(mercImpl.initialize.selector, deployerAddress, deployerAddress, itemsProxy, deployerAddress);
        mercProxy = _deployAndInitialize(address(mercImpl), mercData, "EliteMercenary");

        // GameTokenVault
        GameTokenVault vaultImpl = new GameTokenVault();
        bytes memory vaultData = abi.encodeWithSelector(vaultImpl.initialize.selector, mgtProxy, deployerAddress);
        vaultProxy = _deployAndInitialize(address(vaultImpl), vaultData, "GameTokenVault");
        
        // PVPTicket
        PVPTicket pvptImpl = new PVPTicket();
        bytes memory pvptData = abi.encodeWithSelector(pvptImpl.initialize.selector, deployerAddress, mgtProxy, mercProxy, passProxy);
        pvptProxy = _deployAndInitialize(address(pvptImpl), pvptData, "PVPTicket");

        // PVE_Logic V2
        PVE_LogicV2 pveImpl = new PVE_LogicV2();
        bytes memory pveData = abi.encodeWithSelector(pveImpl.initialize.selector, deployerAddress, mercProxy);
        pveProxy = _deployAndInitialize(address(pveImpl), pveData, "PVE_LogicV2");

        // PVP_Logic
        PVP_Logic pvpImpl = new PVP_Logic();
        bytes memory pvpData = abi.encodeWithSelector(pvpImpl.initialize.selector, deployerAddress, mgtProxy, pvptProxy, mercProxy, itemsProxy, vaultProxy, STABLECOIN_ADDRESS);
        pvpProxy = _deployAndInitialize(address(pvpImpl), pvpData, "PVP_Logic");

        // BattlePass
        BattlePass battlePassImpl = new BattlePass();
        bytes memory battlePassData = abi.encodeWithSelector(battlePassImpl.initialize.selector, "Battle Pass", "BPS", deployerAddress);
        battlePassProxy = _deployAndInitialize(address(battlePassImpl), battlePassData, "BattlePass");

        // 2. Configuración de permisos y acuñación inicial
        MyGameToken mgt = MyGameToken(mgtProxy);
        EliteMercenary merc = EliteMercenary(mercProxy);
        PVPTicket pvpt = PVPTicket(pvptProxy);
        PVPPass pass = PVPPass(passProxy);
        GameItems items = GameItems(itemsProxy);
        GameTokenVault vault = GameTokenVault(vaultProxy);
        BattlePass battlePass = BattlePass(battlePassProxy);

        // Acuñación inicial de prueba para la cuenta del deployer
        mgt.mint(deployerAddress, 1_000_000 * 10**18);

        merc.setLogicController(pveProxy, true);
        merc.setLogicController(pvpProxy, true);

        mgt.setBurner(pveProxy, true);      
        mgt.setBurner(pvptProxy, true);     
        mgt.setBurner(vaultProxy, true);     

        pvpt.setTicketBurner(pvpProxy, true);

        // 3. Transferencia final de la propiedad al OWNER_ADDRESS definitivo
        if (deployerAddress != ownerAddress) {
            mgt.transferOwnership(ownerAddress);
            pass.transferOwnership(ownerAddress);
            items.transferOwnership(ownerAddress);
            merc.transferOwnership(ownerAddress);
            vault.transferOwnership(ownerAddress);
            pvpt.transferOwnership(ownerAddress);
            PVP_Logic(pvpProxy).transferOwnership(ownerAddress);
        }

        vm.stopBroadcast();
    }
}