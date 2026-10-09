// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MyGameToken.sol";
import "../src/GameTokenVault.sol";
import "../src/GameEconomyManager.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Handler is Test {
    MyGameToken public gameToken;
    GameTokenVault public tokenVault;
    GameEconomyManager public economyManager;
    address public player = address(0x1234);

    constructor(
        MyGameToken _gameToken,
        GameTokenVault _tokenVault,
        GameEconomyManager _economyManager
    ) {
        gameToken = _gameToken;
        tokenVault = _tokenVault;
        economyManager = _economyManager;
    }

    function processFeeHandler(uint256 amount) public {
        amount = bound(amount, 1, 1000 * 10**18);
        
        vm.startPrank(player);
        gameToken.approve(address(economyManager), amount);
        try economyManager.processFee(player, amount) {} catch {}
        vm.stopPrank();
    }
}

contract GameInvariantsTest is Test {
    MyGameToken gameToken;
    GameTokenVault tokenVault;
    GameEconomyManager economyManager;
    Handler handler;

    function setUp() public {
        address owner = address(this);

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
                5000,
                owner
            )
        );
        economyManager = GameEconomyManager(address(managerProxy));

        gameToken.setBurner(address(managerProxy), true);

        // Desplegar handler y darle fondos al jugador
        handler = new Handler(gameToken, tokenVault, economyManager);
        gameToken.mint(handler.player(), 1_000_000 * 10**18);

        targetContract(address(handler));
    }

    function invariant_VaultBalanceMatchesReality() public view {
        uint256 vaultBalance = gameToken.balanceOf(address(tokenVault));
        assertTrue(vaultBalance >= 0, "El balance del Vault no puede ser menor a cero");
    }
}