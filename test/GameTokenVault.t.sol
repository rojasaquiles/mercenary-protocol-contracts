// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IERC20Minimal {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function burn(uint256 amount) external;
}

contract GameTokenVault is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    IERC20Minimal public gameToken;

    mapping(address => uint256) private _stakedBalances;
    uint256 public totalStakedSupply;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardDistributed(address indexed user, uint256 amount);
    event TokenBurned(uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _gameToken, address initialOwner) external initializer {
        require(_gameToken != address(0), "Invalid token address");
        require(initialOwner != address(0), "Invalid owner address");

        __Ownable_init();
        __UUPSUpgradeable_init();

        // Transferimos el ownership al initialOwner si el caller no es la direccion deseada
        if (owner() != initialOwner) {
            _transferOwnership(initialOwner);
        }

        gameToken = IERC20Minimal(_gameToken);
    }

    function stake(uint256 amount) external {
        require(address(gameToken) != address(0), "Token not initialized");
        require(amount > 0, "Amount must be > 0");

        bool success = gameToken.transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer failed for staking");

        _stakedBalances[msg.sender] += amount;
        totalStakedSupply += amount;

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        require(_stakedBalances[msg.sender] >= amount, "Insufficient staked balance");

        _stakedBalances[msg.sender] -= amount;
        totalStakedSupply -= amount;

        bool success = gameToken.transfer(msg.sender, amount);
        require(success, "Transfer failed for unstaking");

        emit Unstaked(msg.sender, amount);
    }

    function distributeReward(address user, uint256 amount) external onlyOwner {
        require(user != address(0), "Invalid user address");
        require(amount > 0, "Amount must be > 0");

        bool success = gameToken.transfer(user, amount);
        require(success, "Reward transfer failed");

        emit RewardDistributed(user, amount);
    }

    function burnToken(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be > 0");

        gameToken.burn(amount);

        emit TokenBurned(amount);
    }

    function getStakerBalance(address staker) external view returns (uint256) {
        return _stakedBalances[staker];
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}