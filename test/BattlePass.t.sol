// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BattlePass} from "src/BattlePass.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol"; 

contract BattlePassTest is Test {
    using Strings for uint256; 

    address deployer = address(0x1);
    address user1 = address(0x2);
    address nonOwner = address(0x6);

    BattlePass public implementation;
    BattlePass public proxy; 

    string public constant NAME = "PVP Battle Pass";
    string public constant SYMBOL = "PVPB";
    string public constant BASE_URI = "ipfs://pass/";

    function setUp() public {
        vm.startPrank(deployer);

        implementation = new BattlePass();

        bytes memory data = abi.encodeWithSelector(
            implementation.initialize.selector,
            deployer, 
            BASE_URI 
        );

        ERC1967Proxy proxyContract = new ERC1967Proxy(
            address(implementation), 
            data
        );
        
        vm.stopPrank();

        proxy = BattlePass(address(proxyContract));
    }

    function test_Deployment_Success() public view {
        assertEq(proxy.name(), NAME, unicode"Nombre incorrecto");
        assertEq(proxy.symbol(), SYMBOL, unicode"Símbolo incorrecto");
        assertEq(proxy.owner(), deployer, unicode"Owner incorrecto");
    }

    function test_TokenURI_CorrectFormat() public {
        vm.prank(deployer);
        uint256 tokenId = proxy.mint(user1);
        
        assertEq(proxy.tokenURI(tokenId), string(abi.encodePacked(BASE_URI, tokenId.toString())), unicode"Token URI incorrecto");
    }

    function test_Minting_ByOwner_Success() public returns (uint256) {
        vm.prank(deployer);
        uint256 tokenId = proxy.mint(user1);
        
        assertEq(tokenId, 1, unicode"Primer token ID debe ser 1");
        assertEq(proxy.balanceOf(user1), 1, unicode"Balance incorrecto después de mint");
        assertEq(proxy.ownerOf(tokenId), user1, unicode"Owner del token incorrecto");
        
        return tokenId;
    }

    function test_Minting_ByNonOwner_Reverts() public {
        vm.prank(nonOwner);
        
        // Formato exacto de revert para OpenZeppelin v4
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.mint(user1);
    }

    function test_SetBaseURI_ByOwner_Success() public {
        string memory newUri = "ipfs://new-pass/";
        vm.prank(deployer);
        proxy.setBaseURI(newUri);

        vm.prank(deployer);
        uint256 tokenId = proxy.mint(user1); 
        
        assertEq(proxy.tokenURI(tokenId), string(abi.encodePacked(newUri, tokenId.toString())), unicode"Base URI no se actualizó correctamente");
    }

    function test_SetBaseURI_ByNonOwner_Reverts() public {
        string memory newUri = "ipfs://new-pass/";
        
        vm.prank(nonOwner);
        // Formato exacto de revert para OpenZeppelin v4
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.setBaseURI(newUri);
    }
}