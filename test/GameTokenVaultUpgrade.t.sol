// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GameTokenVault} from "../src/GameTokenVault.sol"; 
import {GameTokenVaultV2} from "../src/GameTokenVaultV2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// --- INTERFAZ MOCK del Token ---
interface IMyGameToken {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function burn(uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
}

// --- MOCK TOKEN ---
contract MockGameToken is IMyGameToken {
    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) public allowances; 
    
    uint256 public totalSupply = type(uint256).max;
    
    bool public shouldFailTransferFrom = false;
    bool public shouldFailTransfer = false;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setBalance(address account, uint256 amount) public { _balances[account] = amount; }
    
    function setFailTransferFrom(bool _shouldFail) public { shouldFailTransferFrom = _shouldFail; }
    function setFailTransfer(bool _shouldFail) public { shouldFailTransfer = _shouldFail; }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        if (shouldFailTransferFrom) return false;
        if (_balances[sender] < amount) return false;
        if (allowances[sender][msg.sender] < amount) return false;
        allowances[sender][msg.sender] -= amount;
        
        _balances[sender] -= amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        if (shouldFailTransfer) return false;
        require(_balances[msg.sender] >= amount, "ERC20: transfer amount exceeds balance");
        _balances[msg.sender] -= amount;
        _balances[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function balanceOf(address account) external view returns (uint256) { return _balances[account]; }
    function burn(uint256 amount) external {
        require(_balances[msg.sender] >= amount, "ERC20: burn amount exceeds balance");
        _balances[msg.sender] -= amount;
    }
}

// -------------------------------------------------------------------

contract GameTokenVaultUpgradeTest is Test {
    address deployer = address(0x1);
    address user1 = address(0x2);
    address nonOwner = address(0x6);

    MockGameToken public mockToken;
    GameTokenVault public implementation; 
    GameTokenVault public proxy; 

    uint256 constant INITIAL_BALANCE = 10000e18;
    uint256 constant STAKE_AMOUNT = 100e18;
    
    // Slot ERC-1967 estándar ("eip1967.proxy.implementation")
    bytes32 constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function setUp() public {
        vm.startPrank(deployer);
        
        mockToken = new MockGameToken();
        mockToken.setBalance(user1, INITIAL_BALANCE);
        
        implementation = new GameTokenVault();

        bytes memory data = abi.encodeWithSelector(
            implementation.initialize.selector,
            address(mockToken),
            deployer
        );

        ERC1967Proxy proxyContract = new ERC1967Proxy(
            address(implementation),
            data
        );
        
        vm.stopPrank();

        proxy = GameTokenVault(address(proxyContract));

        vm.startPrank(user1);
        mockToken.approve(address(proxy), STAKE_AMOUNT); 
        proxy.stake(STAKE_AMOUNT);
        vm.stopPrank();
    }

    function test_Upgrade_ByOwner_Success() public {
        GameTokenVaultV2 implementationV2 = new GameTokenVaultV2(); 
        address newImplementation = address(implementationV2);

        assertEq(proxy.getStakerBalance(user1), STAKE_AMOUNT, "V1 state fail.");
        
        vm.startPrank(deployer);
        proxy.upgradeTo(newImplementation);
        
        GameTokenVaultV2(address(proxy)).initializeV2State();
        vm.stopPrank();

        address currentImpl = address(uint160(uint256(vm.load(address(proxy), IMPLEMENTATION_SLOT))));
        assertEq(currentImpl, newImplementation, "Implementation slot was not updated.");
        
        GameTokenVaultV2 proxyV2 = GameTokenVaultV2(address(proxy)); 
        
        assertEq(proxyV2.getStakerBalance(user1), STAKE_AMOUNT, "V1 state (staked balance) NOT preserved.");
        assertEq(proxyV2.getVersion(), 2, "V2 function failed.");
        assertEq(proxyV2.getNewV2Value(), 42, "New V2 state was not initialized.");
    }
    
    function test_Upgrade_ByNonOwner_Reverts() public {
        address newImplementation = address(new GameTokenVaultV2());
        
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.upgradeTo(newImplementation);
    }
}