// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MyGameToken.sol";
import "../src/GameTokenVault.sol";
import "../src/GameEconomyManager.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract GameEconomyManagerFuzzTest is Test {
    address owner = address(this);
    address player = address(0x1234);

    MyGameToken gameToken;
    GameTokenVault tokenVault;
    GameEconomyManager economyManager;

    function setUp() public {
        MyGameToken tokenImpl = new MyGameToken();
        ERC1967Proxy tokenProxy = new ERC1967Proxy(
            address(tokenImpl),
            abi.encodeWithSignature("initialize(string,string,address)", "MyGameToken", "MGT", owner)
        );
        gameToken = MyGameToken(address(tokenProxy));

        GameTokenVault vaultImpl = new GameTokenVault();
        ERC1967Proxy vaultProxy = new ERC1967Proxy(
            address(vaultImpl),
            abi.encodeWithSignature("initialize(address,address)", address(gameToken), owner)
        );
        tokenVault = GameTokenVault(address(vaultProxy));

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

        gameToken.setBurner(address(managerProxy), true);
    }

    /// @notice Fuzz test para procesar tarifas con cualquier cantidad aleatoria válida de tokens
    function testFuzz_ProcessFee(uint256 feeAmount) public {
        // Acotar el monto de la tarifa para evitar desbordamientos lógicos absurdos (ej: entre 1 token y 1 millón de tokens)
        feeAmount = bound(feeAmount, 1 * 10**18, 1_000_000 * 10**18);

        // Darle fondos al jugador
        gameToken.mint(player, feeAmount);

        uint256 initialTotalSupply = gameToken.totalSupply();

        vm.startPrank(player);
        gameToken.approve(address(economyManager), feeAmount);
        economyManager.processFee(player, feeAmount);
        vm.stopPrank();

        uint256 expectedBurn = feeAmount / 2;
        uint256 expectedVault = feeAmount - expectedBurn;

        // Verificar que las matematicas del manager sean siempre exactas sin importar el monto
        assertEq(gameToken.totalSupply(), initialTotalSupply - expectedBurn, "La quema en fuzz fallo");
        assertEq(gameToken.balanceOf(address(tokenVault)), expectedVault, "El vault en fuzz fallo");
    }
}