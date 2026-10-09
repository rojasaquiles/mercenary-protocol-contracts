// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MyGameToken} from "../src/MyGameToken.sol";
import {MyGameTokenV2} from "../src/MyGameTokenV2.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol"; 

contract MyGameTokenUpgradeTest is Test {
    MyGameToken public proxyV1;
    MyGameTokenV2 public implementationV2;
    address public owner;
    address public nonOwner;

    string private constant NAME = "MyGameToken";
    string private constant SYMBOL = "MGT";

    function setUp() public {
        owner = makeAddr("owner");
        nonOwner = makeAddr("nonOwner");
        vm.deal(owner, 10 ether);

        // 1. Desplegar la implementación V1
        MyGameToken implementationV1 = new MyGameToken();

        // 2. Preparar el calldata del inicializador
        bytes memory data = abi.encodeCall(MyGameToken.initialize, (NAME, SYMBOL, owner));

        // 3. Desplegar el Proxy UUPS con UnsafeUpgrades
        address proxyAddress = UnsafeUpgrades.deployUUPSProxy(
            address(implementationV1),
            data
        );
        
        // 4. Mapear el ABI de V1 al proxy
        proxyV1 = MyGameToken(proxyAddress);

        // 5. Desplegar la implementación V2
        implementationV2 = new MyGameTokenV2();
    }

    function test_Upgrade_ByOwner_Success() public {
        // --- PRE-CONDICIONES (ESTADO V1) ---
        uint256 initialSupply = proxyV1.balanceOf(owner);
        assertEq(initialSupply, 1_000_000 * 10 ** 18, unicode"La V1 no se inicializó correctamente.");
        assertEq(proxyV1.name(), NAME, unicode"El nombre de la V1 es incorrecto.");

        vm.startPrank(owner);
        
        // --- ACCIÓN: ACTUALIZAR A V2 ---
        UnsafeUpgrades.upgradeProxy(
            address(proxyV1),
            address(implementationV2),
            ""
        );

        // --- POST-CONDICIONES (ESTADO V2) ---
        assertEq(proxyV1.balanceOf(owner), initialSupply, unicode"El balance se perdió.");
        assertEq(proxyV1.owner(), owner, unicode"La propiedad se perdió.");

        MyGameTokenV2 proxyV2 = MyGameTokenV2(address(proxyV1));
        assertEq(proxyV2.version(), 2, unicode"La actualización a V2 falló.");

        vm.stopPrank();
    }

    function test_Upgrade_ByNonOwner_Reverts() public {
        vm.startPrank(nonOwner);
        
        // En OpenZeppelin v4.9.5 la función es upgradeTo(address)
        bytes memory upgradeData = abi.encodeWithSignature(
            "upgradeTo(address)", 
            address(implementationV2)
        );

        // Esperamos que revierta con el mensaje de error de Ownable de OZ v4.9.5
        vm.expectRevert("Ownable: caller is not the owner");
        (bool success, ) = address(proxyV1).call(upgradeData);
        
        assertTrue(success, unicode"El call debió ejecutar y revertir con el mensaje esperado.");
        
        vm.stopPrank();
    }
}