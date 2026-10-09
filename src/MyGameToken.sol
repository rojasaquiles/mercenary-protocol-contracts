// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract MyGameToken is
    Initializable,
    ERC20Upgradeable,      
    UUPSUpgradeable,        
    OwnableUpgradeable,    
    PausableUpgradeable    
{
    mapping(address => bool) public isBurner;
    mapping(address => bool) public isMinter;

    uint256[50] private __gap;  

    modifier onlyBurner() {
        _onlyBurner();
        _;
    }

    modifier onlyMinter() {
        _onlyMinter();
        _;
    }

    function _onlyBurner() internal view {
        require(isBurner[_msgSender()] || _msgSender() == owner(), "MyGameToken: Not authorized burner or owner");
    }

    function _onlyMinter() internal view {
        require(isMinter[_msgSender()] || _msgSender() == owner(), "MyGameToken: Not authorized minter or owner");
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory name, string memory symbol, address ownerAddress) public initializer {
        __ERC20_init(name, symbol);
        __UUPSUpgradeable_init(); 
        __Ownable_init();
        
        if (owner() != ownerAddress) {
            _transferOwnership(ownerAddress);
        }
        
        __Pausable_init();
        
        uint256 initialSupply = 1_000_000 * 10 ** decimals();
        _mint(ownerAddress, initialSupply);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {}

    function mint(address to, uint256 amount) public onlyMinter {
        _mint(to, amount);
    }

    function burn(uint256 amount) public onlyBurner {
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) public onlyBurner {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(currentAllowance >= amount, "ERC20: insufficient allowance");
        unchecked {
            _approve(account, _msgSender(), currentAllowance - amount);
        }
        _burn(account, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20Upgradeable) 
        whenNotPaused
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    function setBurner(address _burner, bool _isAllowed) public onlyOwner {
        require(_burner != address(0), "Cannot set zero address as burner");
        isBurner[_burner] = _isAllowed;
    }

    function setMinter(address _minter, bool _isAllowed) public onlyOwner {
        require(_minter != address(0), "Cannot set zero address as minter");
        isMinter[_minter] = _isAllowed;
    }
      
    function pause() public onlyOwner { _pause(); }
    function unpause() public onlyOwner { _unpause(); }
}