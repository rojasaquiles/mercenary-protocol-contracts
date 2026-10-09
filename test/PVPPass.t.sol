// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PVPPass} from "../src/PVPPass.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PVPPassTest is Test {
    address deployer = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address nonOwner = address(0x6);

    PVPPass public implementation;
    PVPPass public proxy;

    string public constant NAME = "PVP Pass";
    string public constant SYMBOL = "PVPP";
    string public constant MOCK_URI = "ipfs://test/token/1";
    
    function setUp() public {
        vm.startPrank(deployer);

        implementation = new PVPPass();

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

        proxy = PVPPass(address(proxyContract));
    }
    
    function test_Deployment_Success() public view {
        assertEq(proxy.name(), NAME, unicode"Nombre incorrecto");
        assertEq(proxy.symbol(), SYMBOL, unicode"Símbolo incorrecto");
        assertEq(proxy.owner(), deployer, unicode"Owner incorrecto");
        assertFalse(proxy.paused(), unicode"No debe empezar pausado");
    }

    function test_Minting_ByOwner_Success() public {
        vm.prank(deployer);
        uint256 tokenId = proxy.safeMint(user1, MOCK_URI);
        
        assertEq(tokenId, 0, unicode"Primer token ID debe ser 0");
        assertEq(proxy.balanceOf(user1), 1, unicode"Balance incorrecto después de mint");
        assertEq(proxy.ownerOf(tokenId), user1, unicode"Owner del token incorrecto");
        assertEq(proxy.tokenURI(tokenId), MOCK_URI, unicode"URI incorrecta");
    }

    function test_Minting_ByNonOwner_Reverts() public {
        vm.prank(nonOwner);
        
        // En OpenZeppelin v4, el revert lanza este string literal
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.safeMint(user1, MOCK_URI);
    }
    
    function test_Minting_WhenPaused_Reverts() public {
        vm.prank(deployer);
        proxy.pause();
        
        assertTrue(proxy.paused(), unicode"El contrato debe estar pausado");
        
        vm.prank(deployer); 
        
        // En OpenZeppelin v4, Pausable lanza el string "Pausable: paused"
        vm.expectRevert("Pausable: paused");
        proxy.safeMint(user2, MOCK_URI);
        
        vm.prank(deployer); 
        proxy.unpause();
        assertFalse(proxy.paused(), unicode"El contrato debe estar despausado");
    }
}