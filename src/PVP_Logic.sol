// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol"; 

interface IMyGameToken is IERC20 {
    function mint(address to, uint256 amount) external;
}

interface IPvpTicket {
    function burnTickets(address from, uint256 amount) external; 
}

interface IMercenaryController {
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function getMercenaryStats(uint256 tokenId) external view returns (
        uint256 survivalSkill,
        uint256 health,
        uint256 level,
        bool isDeployed
    );
    function setHealth(uint256 _tokenId, uint256 _newHealth) external;
    function setLevel(uint256 _tokenId, uint256 _newLevel) external;
}

interface IGameItems {
    function mintItem(address to, uint256 id, uint256 amount, bytes memory data) external;
}

contract PVP_Logic is 
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable
{
    IMyGameToken public mgtToken;
    IPvpTicket public pvpTicket;
    IMercenaryController public mercenaryNft;
    IGameItems public gameItems;
    IERC20 public usdStablecoin; 
    address public treasuryAddress;

    struct BattleStats {
        uint256 mercenaryId;
        uint256 currentHealth;
        uint256 combatPower;
    }

    mapping(address => BattleStats) public activeChallenges;

    uint256 public pvpEntryTicketCost; 
    uint256 public pvpEntryFeeUsd; 
    
    uint256 public baseMgtReward;
    uint256 public treasuryMgtFeePercentage; 

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address mgtTokenAddress,
        address pvpTicketAddress,
        address mercenaryNftAddress,
        address gameItemsAddress,
        address _treasuryAddress,
        address usdStablecoinAddress
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __Pausable_init();

        mgtToken = IMyGameToken(mgtTokenAddress);
        pvpTicket = IPvpTicket(pvpTicketAddress);
        mercenaryNft = IMercenaryController(mercenaryNftAddress);
        gameItems = IGameItems(gameItemsAddress);
        treasuryAddress = _treasuryAddress;
        usdStablecoin = IERC20(usdStablecoinAddress);

        pvpEntryTicketCost = 1;
        pvpEntryFeeUsd = 10 * 10**18;
        baseMgtReward = 50 * 10**18;
        treasuryMgtFeePercentage = 10;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function startPvpBattle(uint256 _mercenaryId) public whenNotPaused {
        require(mercenaryNft.ownerOf(_mercenaryId) == msg.sender, "PVP: Not owner of NFT.");
        require(activeChallenges[msg.sender].mercenaryId == 0, "PVP: Player already in a active challenge.");

        (, uint256 currentHealth, , ) = mercenaryNft.getMercenaryStats(_mercenaryId);
        require(currentHealth > 0, "PVP: Mercenary health is zero.");

        bool success = usdStablecoin.transferFrom(msg.sender, treasuryAddress, pvpEntryFeeUsd);
        require(success, "PVP: Stablecoin fee transfer failed. Check allowance.");

        pvpTicket.burnTickets(msg.sender, pvpEntryTicketCost);

        uint256 combatPower = _calculateCombatPower(_mercenaryId);

        activeChallenges[msg.sender] = BattleStats({
            mercenaryId: _mercenaryId,
            currentHealth: currentHealth,
            combatPower: combatPower
        });
    }

    function endPvpBattle(
        uint256 _mercenaryId,
        uint256 _finalHealth,
        bool _didWin
    ) public onlyOwner whenNotPaused { 
        address playerAddress = mercenaryNft.ownerOf(_mercenaryId);
        
        require(activeChallenges[playerAddress].mercenaryId == _mercenaryId, "PVP: No active challenge for this mercenary.");
        require(_finalHealth <= 100, "PVP: Final health cannot exceed 100.");

        mercenaryNft.setHealth(_mercenaryId, _finalHealth);

        if (_didWin) {
            uint256 totalReward = baseMgtReward;
            uint256 treasuryFee = (totalReward * treasuryMgtFeePercentage) / 100;
            uint256 playerReward = totalReward - treasuryFee;
            
            mgtToken.mint(playerAddress, playerReward);
            mgtToken.mint(treasuryAddress, treasuryFee); 
            
            uint256 rewardItemId = 201;
            gameItems.mintItem(playerAddress, rewardItemId, 1, "");
            
            (,, uint256 currentLevel,) = mercenaryNft.getMercenaryStats(_mercenaryId);
            mercenaryNft.setLevel(_mercenaryId, currentLevel + 1);
        }
        
        delete activeChallenges[playerAddress];
    }
    
    function _calculateCombatPower(uint256 _mercenaryId) internal view returns (uint256) { 
        (uint256 skill,,,) = mercenaryNft.getMercenaryStats(_mercenaryId);
        return skill * 10; 
    }

    // ================================================================
    //                        ADMIN SETTERS
    // ================================================================

    function setTreasuryAddress(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "PVP: Zero address not allowed");
        treasuryAddress = _newAddress;
    }
    
    function setTreasuryFeePercentage(uint256 _newPercentage) public onlyOwner {
        require(_newPercentage <= 100, "PVP: Percentage cannot exceed 100");
        treasuryMgtFeePercentage = _newPercentage;
    }
    
    function setUsdStablecoinAddress(address _newAddress) public onlyOwner { 
        require(_newAddress != address(0), "PVP: Zero address not allowed");
        usdStablecoin = IERC20(_newAddress); 
    }

    function setPvpTicketContract(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "PVP: Zero address not allowed");
        pvpTicket = IPvpTicket(_newAddress);
    }

    function setMercenaryContract(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "PVP: Zero address not allowed");
        mercenaryNft = IMercenaryController(_newAddress);
    }

    function setGameItemsContract(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "PVP: Zero address not allowed");
        gameItems = IGameItems(_newAddress);
    }
    
    function setPvpEntryTicketCost(uint256 _newCost) public onlyOwner {
        pvpEntryTicketCost = _newCost;
    }
    
    function setPvpEntryFeeUsd(uint256 _newFee) public onlyOwner {
        pvpEntryFeeUsd = _newFee;
    }
    
    function setBaseMgtReward(uint256 _newReward) public onlyOwner {
        baseMgtReward = _newReward;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}