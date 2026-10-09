// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

interface IMercenaryNFT {
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function getMercenaryStats(uint256 tokenId) external view returns (
        uint256 survivalSkill,
        uint256 health,
        uint256 level,
        bool isDeployed
    );
}

interface IMyGameToken is IERC20 {
    function burn(uint256 amount) external;
}

contract PVPTicket is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {

    IMyGameToken public mgtToken;
    IMercenaryNFT public mercenaryNft;
    IERC721 public pvpPass;

    mapping(address => uint256) public lastDailyClaimTime;
    mapping(address => bool) public isTicketBurner;

    uint256 public minPvpLevel;
    uint256 public dailyCooldown;
    uint256 public ticketBuyPrice;

    modifier onlyTicketBurner() {
        _onlyTicketBurner();
        _;
    }

    function _onlyTicketBurner() internal view {
        require(isTicketBurner[ContextUpgradeable._msgSender()] || ContextUpgradeable._msgSender() == owner(), "PVPT: Not an authorized burner");
    }

    function initialize(
        address mgtTokenAddress, 
        address _mercenaryNftAddress, 
        address pvpPassAddress
    ) public initializer {
        __ERC20_init("PVP Ticket", "PVPT");
        __Ownable_init();
        __UUPSUpgradeable_init();

        mgtToken = IMyGameToken(mgtTokenAddress);
        mercenaryNft = IMercenaryNFT(_mercenaryNftAddress);
        pvpPass = IERC721(pvpPassAddress);

        minPvpLevel = 5;
        dailyCooldown = 24 hours;
        ticketBuyPrice = 1000 * 10**18;
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {}

    function setTicketBurner(address _burner, bool _isAllowed) public onlyOwner {
        require(_burner != address(0), "PVPT: Cannot set zero address");
        isTicketBurner[_burner] = _isAllowed;
    }

    function claimDailyTicket(uint256 _mercenaryId) public {
        require(pvpPass.balanceOf(msg.sender) > 0, "PVPT: Combat License required for daily claim.");
        require(mercenaryNft.ownerOf(_mercenaryId) == msg.sender, "PVPT: Not NFT owner.");
        
        (,, uint256 currentLevel, ) = mercenaryNft.getMercenaryStats(_mercenaryId); 
        require(currentLevel >= minPvpLevel, "PVPT: NFT level too low (Min 5) for PvP access.");

        uint256 lastClaim = lastDailyClaimTime[msg.sender];
        uint256 currentTime = block.timestamp;

        require(currentTime >= lastClaim + dailyCooldown, "PVPT: Cooldown period (24h) not finished.");

        _mint(msg.sender, 1 * 10**18);
        lastDailyClaimTime[msg.sender] = currentTime;
    }

    function buyTickets(uint256 amount) public {
        require(pvpPass.balanceOf(msg.sender) > 0, "PVPT: Combat License required to purchase tickets.");

        uint256 totalCost = amount * ticketBuyPrice;

        bool success = mgtToken.transferFrom(msg.sender, address(this), totalCost);
        require(success, "PVPT: MGT transfer failed.");

        mgtToken.burn(totalCost);
        
        _mint(msg.sender, amount * 10**18);
    }

    function burnTickets(address from, uint256 amount) public onlyTicketBurner {
        _burn(from, amount);
    }

    function setMinPvpLevel(uint256 _newLevel) public onlyOwner {
        minPvpLevel = _newLevel;
    }

    function setTicketBuyPrice(uint256 _newPrice) public onlyOwner {
        ticketBuyPrice = _newPrice;
    }
}