// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MyGameToken} from "../src/MyGameToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MyGameTokenTest is Test {
    address deployer = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address burnerContract = address(0x4);
    address nonOwner = address(0x5);

    MyGameToken public implementation;
    MyGameToken public proxy;

    string public constant NAME = "MyGameToken";
    string public constant SYMBOL = "MGT";
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant MINT_AMOUNT = 100 ether;
    uint256 public constant BURN_AMOUNT = 50 ether;

    function setUp() public {
        vm.startPrank(deployer);

        implementation = new MyGameToken();

        bytes memory data = abi.encodeWithSelector(
            implementation.initialize.selector,
            NAME,
            SYMBOL,
            deployer
        );

        ERC1967Proxy proxyContract = new ERC1967Proxy(
            address(implementation), 
            data
        );
        
        vm.stopPrank();

        proxy = MyGameToken(address(proxyContract));
        
        vm.prank(deployer);
        proxy.setBurner(burnerContract, true);
        
        vm.prank(deployer);
        proxy.mint(user1, MINT_AMOUNT);
    }

    function test_Deployment_Success() public view {
        assertEq(proxy.name(), NAME, unicode"Nombre incorrecto");
        assertEq(proxy.symbol(), SYMBOL, unicode"Símbolo incorrecto");
        assertEq(proxy.owner(), deployer, unicode"Owner incorrecto");
        
        assertEq(proxy.totalSupply(), INITIAL_SUPPLY + MINT_AMOUNT, unicode"Total Supply incorrecto");
        assertEq(proxy.balanceOf(deployer), INITIAL_SUPPLY, unicode"Balance inicial del owner incorrecto");
        assertTrue(proxy.isBurner(burnerContract), unicode"Burner no se estableció en setUp");
    }

    function test_Minting_ByOwner_Success() public {
        uint256 mintMore = 50 ether;
        vm.prank(deployer);
        proxy.mint(user2, mintMore);
        
        assertEq(proxy.balanceOf(user2), mintMore, unicode"Minting falló");
        assertEq(proxy.totalSupply(), INITIAL_SUPPLY + MINT_AMOUNT + mintMore, unicode"Total Supply no se actualizó");
    }

    function test_Minting_ByNonOwner_Reverts() public {
        vm.prank(nonOwner);
        vm.expectRevert("MyGameToken: Not authorized minter or owner");
        proxy.mint(user2, MINT_AMOUNT);
    }
    
    function test_Transfer_Success() public {
        uint256 transferAmount = 10 ether;
        vm.startPrank(user1);
        proxy.transfer(user2, transferAmount);
        vm.stopPrank();
        
        assertEq(proxy.balanceOf(user1), MINT_AMOUNT - transferAmount, unicode"Balance del remitente incorrecto");
        assertEq(proxy.balanceOf(user2), transferAmount, unicode"Balance del receptor incorrecto");
    }
    
    function test_Transfer_InsufficientBalance_Reverts() public {
        uint256 requested = 1 ether;
        vm.prank(user2);
        
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        proxy.transfer(user1, requested);
    }
    
    function test_Approve_TransferFrom_Success() public {
        uint256 transferAmount = 10 ether;
        
        vm.prank(user1);
        proxy.approve(user2, transferAmount);
        assertEq(proxy.allowance(user1, user2), transferAmount, unicode"Allowance incorrecto");
        
        vm.prank(user2);
        proxy.transferFrom(user1, deployer, transferAmount);
        
        assertEq(proxy.balanceOf(user1), MINT_AMOUNT - transferAmount, unicode"Balance del dueño incorrecto");
        assertEq(proxy.balanceOf(deployer), INITIAL_SUPPLY + transferAmount, unicode"Balance del receptor incorrecto");
        assertEq(proxy.allowance(user1, user2), 0, unicode"Allowance no se redujo");
    }
    
    function test_TransferFrom_InsufficientAllowance_Reverts() public {
        uint256 allowed = 10 ether;
        uint256 requested = 11 ether;
        
        vm.prank(user1);
        proxy.approve(user2, allowed);
        
        vm.prank(user2);
        vm.expectRevert("ERC20: insufficient allowance");
        proxy.transferFrom(user1, deployer, requested);
    }

    function test_SetBurner_ByOwner_Success() public {
        vm.prank(deployer);
        proxy.setBurner(user2, true);
        assertTrue(proxy.isBurner(user2), unicode"El usuario 2 debería ser Burner");
        
        vm.prank(deployer);
        proxy.setBurner(user2, false);
        assertFalse(proxy.isBurner(user2), unicode"El usuario 2 no debería ser Burner");
    }
    
    function test_SetBurner_ZeroAddress_Reverts() public {
        vm.prank(deployer);
        vm.expectRevert("Cannot set zero address as burner");
        proxy.setBurner(address(0), true);
    }

    function test_SetBurner_ByNonOwner_Reverts() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.setBurner(user1, true);
    }
    
    function test_Burn_ByOwner_Success() public {
        uint256 ownerBalanceBefore = proxy.balanceOf(deployer);
        
        vm.prank(deployer);
        proxy.burn(BURN_AMOUNT);
        
        assertEq(proxy.balanceOf(deployer), ownerBalanceBefore - BURN_AMOUNT, unicode"Balance del Owner incorrecto después de quemar");
        assertEq(proxy.totalSupply(), INITIAL_SUPPLY + MINT_AMOUNT - BURN_AMOUNT, unicode"Total Supply incorrecto después de quemar");
    }
    
    function test_Burn_ByBurner_Success() public {
        uint256 balanceBefore = proxy.balanceOf(burnerContract);
        vm.prank(deployer);
        proxy.mint(burnerContract, MINT_AMOUNT); 
        
        vm.prank(burnerContract);
        proxy.burn(BURN_AMOUNT);
        
        assertEq(proxy.balanceOf(burnerContract), balanceBefore + MINT_AMOUNT - BURN_AMOUNT, unicode"Balance del Burner incorrecto después de quemar");
    }
    
    function test_Burn_ByNonBurner_Reverts() public {
        vm.prank(user2);
        vm.expectRevert("MyGameToken: Not authorized burner or owner");
        proxy.burn(1);
    }
    
    function test_BurnFrom_Success() public {
        vm.prank(user1);
        proxy.approve(burnerContract, BURN_AMOUNT);
        
        vm.prank(burnerContract); 
        proxy.burnFrom(user1, BURN_AMOUNT);
        
        assertEq(proxy.balanceOf(user1), MINT_AMOUNT - BURN_AMOUNT, unicode"Balance de user1 incorrecto");
        assertEq(proxy.allowance(user1, burnerContract), 0, unicode"Allowance no se redujo");
    }
    
    function test_BurnFrom_InsufficientAllowance_Reverts() public {
        uint256 allowed = BURN_AMOUNT - 1;
        uint256 requested = BURN_AMOUNT;
        
        vm.prank(user1);
        proxy.approve(burnerContract, allowed);
        
        vm.prank(burnerContract); 
        vm.expectRevert("ERC20: insufficient allowance");
        proxy.burnFrom(user1, requested);
    }

    function test_Pause_Unpause_ByOwner_Success() public {
        vm.prank(deployer);
        proxy.pause();
        assertTrue(proxy.paused(), unicode"No se pausó");
        
        vm.prank(deployer);
        proxy.unpause();
        assertFalse(proxy.paused(), unicode"No se despausó");
    }
    
    function test_Pause_ByNonOwner_Reverts() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.pause();
    }
    
    function test_Transfer_WhenPaused_Reverts() public {
        vm.prank(deployer);
        proxy.pause();
        
        vm.prank(user1);
        vm.expectRevert("Pausable: paused");
        proxy.transfer(user2, 1);
    }
}