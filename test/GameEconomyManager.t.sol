// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MyGameToken.sol";
import "../src/GameTokenVault.sol";
import "../src/GameEconomyManager.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract GameEconomyManagerTest is Test {
    address owner = address(this);
    address player = address(0x1234);

    MyGameToken gameToken;
    GameTokenVault tokenVault;
    GameEconomyManager economyManager;

    function setUp() public {
        // 1. Desplegar MyGameToken
        MyGameToken tokenImpl = new MyGameToken();
        ERC1967Proxy tokenProxy = new ERC1967Proxy(
            address(tokenImpl),
            abi.encodeWithSignature("initialize(string,string,address)", "MyGameToken", "MGT", owner)
        );
        gameToken = MyGameToken(address(tokenProxy));

        // 2. Desplegar GameTokenVault
        GameTokenVault vaultImpl = new GameTokenVault();
        ERC1967Proxy vaultProxy = new ERC1967Proxy(
            address(vaultImpl),
            abi.encodeWithSignature("initialize(address,address)", address(gameToken), owner)
        );
        tokenVault = GameTokenVault(address(vaultProxy));

        // 3. Desplegar GameEconomyManager (configurado con 50% de quema = 5000 basis points)
        GameEconomyManager managerImpl = new GameEconomyManager();
        ERC1967Proxy managerProxy = new ERC1967Proxy(
            address(managerImpl),
            abi.encodeWithSignature(
                "initialize(address,address,uint256,address)",
                address(gameToken),
                address(tokenVault),
                5000, // 50% quema, 50% vault
                owner
            )
        );
        economyManager = GameEconomyManager(address(managerProxy));

        // 4. Otorgar permisos: autorizar al EconomyManager como burner en MyGameToken
        gameToken.setBurner(address(managerProxy), true);

        // 5. Asignar tokens iniciales al jugador de prueba
        gameToken.mint(player, 1000 * 10**18);
    }

    function test_ProcessDeflationaryFee() public {
        uint256 initialTotalSupply = gameToken.totalSupply();
        uint256 feeAmount = 100 * 10**18;

        vm.startPrank(player);
        // El jugador aprueba al manager para gastar sus tokens
        gameToken.approve(address(economyManager), feeAmount);

        // Ejecutar el cobro de la tarifa deflacionaria
        economyManager.processFee(player, feeAmount);
        vm.stopPrank();

        // Verificaciones económicas:
        // 1. El 50% (50 tokens) debe haberse quemado de forma permanente (totalSupply disminuye)
        uint256 expectedBurn = feeAmount / 2;
        assertEq(
            gameToken.totalSupply(),
            initialTotalSupply - expectedBurn,
            "El suministro total debe reducirse exactamente por la quema"
        );

        // 2. El otro 50% (50 tokens) debe encontrarse resguardado en el Vault
        uint256 vaultBalance = gameToken.balanceOf(address(tokenVault));
        assertEq(
            vaultBalance,
            feeAmount / 2,
            "El resto de los tokens deben depositarse en el Vault"
        );
    }
}