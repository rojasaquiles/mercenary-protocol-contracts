// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

interface IEliteMercenary {
    function ownerOf(uint256 tokenId) external view returns (address);
    function getMercenaryStats(uint256 _tokenId) external view returns (
        uint256 survivalSkill,
        uint256 health,
        uint256 level,
        bool isDeployed
    );
    function setHealth(uint256 _tokenId, uint256 _newHealth) external;
    function setLevel(uint256 _tokenId, uint256 _newLevel) external;
    function setSurvivalSkill(uint256 _tokenId, uint256 _newSkill) external;
    function setIsDeployed(uint256 _tokenId, bool _deployed) external;
}

contract PVE_LogicV2 is
    OwnableUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    IEliteMercenary public mercenaryNFT;

    struct Mission {
        uint256 minLevel;
        uint256 duration;
        uint256 xpReward;
        uint256 cooldown;
        bool active;
    }

    struct ActiveMission {
        uint256 missionId;
        uint256 startTime;
        uint256 completionTime;
    }

    mapping(uint256 => Mission) public missions;
    mapping(uint256 => ActiveMission) public activeMissions; // mercenaryId => ActiveMission
    mapping(uint256 => uint256) public lastMissionCompletion; // mercenaryId => timestamp
    mapping(uint256 => uint256) public xp; // mercenaryId => total XP

    event MissionStarted(uint256 indexed mercenaryId, uint256 indexed missionId, uint256 completionTime);
    event MissionCompleted(uint256 indexed mercenaryId, uint256 indexed missionId, uint256 xpGained, bool success);
    event MissionCreated(uint256 indexed missionId, uint256 minLevel, uint256 duration, uint256 xpReward, uint256 cooldown);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address _mercenaryNFT) public initializer {
        __Ownable_init();
        _transferOwnership(initialOwner);
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        require(_mercenaryNFT != address(0), "Invalid NFT address");
        mercenaryNFT = IEliteMercenary(_mercenaryNFT);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function createMission(
        uint256 _missionId,
        uint256 _minLevel,
        uint256 _duration,
        uint256 _xpReward,
        uint256 _cooldown
    ) external onlyOwner {
        require(_missionId > 0, "Invalid mission ID");
        require(_duration > 0, "Duration must be > 0");

        missions[_missionId] = Mission({
            minLevel: _minLevel,
            duration: _duration,
            xpReward: _xpReward,
            cooldown: _cooldown,
            active: true
        });

        emit MissionCreated(_missionId, _minLevel, _duration, _xpReward, _cooldown);
    }

    function startMission(uint256 _mercenaryId, uint256 _missionId) external whenNotPaused nonReentrant {
        require(mercenaryNFT.ownerOf(_mercenaryId) == msg.sender, "Not the owner of mercenary");
        
        Mission memory mission = missions[_missionId];
        require(mission.active, "Mission is not active");

        (, uint256 health, uint256 level, bool isDeployed) = mercenaryNFT.getMercenaryStats(_mercenaryId);
        
        require(!isDeployed, "Mercenary is already deployed");
        require(health > 0, "Mercenary is dead or exhausted");
        require(level >= mission.minLevel, "Mercenary level too low");

        uint256 availableAt = lastMissionCompletion[_mercenaryId] + mission.cooldown;
        require(block.timestamp >= availableAt, "PVE: Mercenary on cooldown");

        uint256 completion = block.timestamp + mission.duration;
        activeMissions[_mercenaryId] = ActiveMission({
            missionId: _missionId,
            startTime: block.timestamp,
            completionTime: completion
        });

        mercenaryNFT.setIsDeployed(_mercenaryId, true);

        emit MissionStarted(_mercenaryId, _missionId, completion);
    }

    function completeMission(uint256 _mercenaryId) external whenNotPaused nonReentrant {
        require(mercenaryNFT.ownerOf(_mercenaryId) == msg.sender, "Not the owner of mercenary");
        
        ActiveMission memory active = activeMissions[_mercenaryId];
        require(active.startTime > 0, "No active mission");
        require(block.timestamp >= active.completionTime, "Mission not finished yet");

        Mission memory mission = missions[active.missionId];

        delete activeMissions[_mercenaryId];

        mercenaryNFT.setIsDeployed(_mercenaryId, false);
        lastMissionCompletion[_mercenaryId] = block.timestamp;

        xp[_mercenaryId] += mission.xpReward;

        emit MissionCompleted(_mercenaryId, active.missionId, mission.xpReward, true);
    }

    function getCooldownEnd(uint256 _mercenaryId, uint256 _missionId) external view returns (uint256) {
        return lastMissionCompletion[_mercenaryId] + missions[_missionId].cooldown;
    }

    function isAvailable(uint256 _mercenaryId, uint256 _missionId) external view returns (bool) {
        (,,, bool isDeployed) = mercenaryNFT.getMercenaryStats(_mercenaryId);
        if (isDeployed) return false;
        return block.timestamp >= (lastMissionCompletion[_mercenaryId] + missions[_missionId].cooldown);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}