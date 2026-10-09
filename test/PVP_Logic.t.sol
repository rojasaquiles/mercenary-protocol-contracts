// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PVP_Logic} from "../src/PVP_Logic.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockPvpTicket {
    mapping(address => uint256) public tickets;

    function mint(address to, uint256 amount) external {
        tickets[to] += amount;
    }

    function burnTickets(address from, uint256 amount) external {
        require(tickets[from] >= amount, "Not enough tickets");
        tickets[from] -= amount;
    }
}

contract MockMercenaryController {
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => uint256) public health;
    mapping(uint256 => uint256) public level;

    function setMockMercenary(uint256 id, address owner, uint256 h, uint256 lvl) external {
        ownerOf[id] = owner;
        health[id] = h;
        level[id] = lvl;
    }

    function getMercenaryStats(uint256 tokenId) external view returns (uint256, uint256, uint256, bool) {
        return (10, health[tokenId], level[tokenId], false);
    }

    function setHealth(uint256 tokenId, uint256 newHealth) external {
        health[tokenId] = newHealth;
    }

    function setLevel(uint256 tokenId, uint256 newLevel) external {
        level[tokenId] = newLevel;
    }
}

contract MockGameItems {
    function mintItem(address, uint256, uint256, bytes memory) external {}
}

contract PVP_LogicTest is Test {
    PVP_Logic public pvpProxy;
    MockERC20 public mgtToken;
    MockERC20 public usdToken;
    MockPvpTicket public pvpTicket;
    MockMercenaryController public mercenaryNft;
    MockGameItems public gameItems;

    address owner = address(0x1);
    address treasury = address(0x2);
    address player = address(0x3);
    uint256 mercenaryId = 1;

    function setUp() public {
        vm.startPrank(owner);

        mgtToken = new MockERC20();
        usdToken = new MockERC20();
        pvpTicket = new MockPvpTicket();
        mercenaryNft = new MockMercenaryController();
        gameItems = new MockGameItems();

        PVP_Logic implementation = new PVP_Logic();
        bytes memory data = abi.encodeCall(
            PVP_Logic.initialize,
            (
                address(mgtToken),
                address(pvpTicket),
                address(mercenaryNft),
                address(gameItems),
                treasury,
                address(usdToken)
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        pvpProxy = PVP_Logic(address(proxy));

        vm.stopPrank();

        // Setup Player
        usdToken.mint(player, 100 * 10**18);
        pvpTicket.mint(player, 10);
        mercenaryNft.setMockMercenary(mercenaryId, player, 100, 1);

        vm.prank(player);
        usdToken.approve(address(pvpProxy), type(uint256).max);
    }

    function test_StartAndEndBattle_Victory_Success() public {
        vm.prank(player);
        pvpProxy.startPvpBattle(mercenaryId);

        (uint256 mercId, uint256 hp, uint256 power) = pvpProxy.activeChallenges(player);
        assertEq(mercId, mercenaryId);
        assertEq(hp, 100);
        assertEq(power, 100);

        vm.prank(owner);
        pvpProxy.endPvpBattle(mercenaryId, 80, true);

        (uint256 clearedMercId, , ) = pvpProxy.activeChallenges(player);
        assertEq(clearedMercId, 0);
    }

    function test_StartAndEndBattle_Defeat_Success() public {
        vm.prank(player);
        pvpProxy.startPvpBattle(mercenaryId);

        vm.prank(owner);
        pvpProxy.endPvpBattle(mercenaryId, 0, false);

        (uint256 clearedMercId, , ) = pvpProxy.activeChallenges(player);
        assertEq(clearedMercId, 0);
    }

    function test_StartBattle_Reverts_IfAlreadyInChallenge() public {
        vm.prank(player);
        pvpProxy.startPvpBattle(mercenaryId);

        vm.prank(player);
        vm.expectRevert("PVP: Player already in a active challenge.");
        pvpProxy.startPvpBattle(mercenaryId);
    }

    function test_StartBattle_Reverts_IfHealthIsZero() public {
        uint256 deadMercenaryId = 2;
        mercenaryNft.setMockMercenary(deadMercenaryId, player, 0, 1);

        vm.prank(player);
        vm.expectRevert("PVP: Mercenary health is zero.");
        pvpProxy.startPvpBattle(deadMercenaryId);
    }

    function test_StartBattle_NonOwner_Reverts() public {
        vm.prank(address(0x999));
        vm.expectRevert("PVP: Not owner of NFT.");
        pvpProxy.startPvpBattle(mercenaryId);
    }

    function test_EndPvpBattle_Reverts_IfNotInChallenge() public {
        vm.prank(owner);
        vm.expectRevert("PVP: No active challenge for this mercenary.");
        pvpProxy.endPvpBattle(mercenaryId, 80, true);
    }

    function test_EndPvpBattle_Reverts_IfHealthExceedsMax() public {
        vm.prank(player);
        pvpProxy.startPvpBattle(mercenaryId);

        vm.prank(owner);
        vm.expectRevert("PVP: Final health cannot exceed 100.");
        pvpProxy.endPvpBattle(mercenaryId, 101, true);
    }

    function test_EndPvpBattle_Reverts_IfNotOwner() public {
        vm.prank(player);
        pvpProxy.startPvpBattle(mercenaryId);

        vm.prank(player);
        vm.expectRevert();
        pvpProxy.endPvpBattle(mercenaryId, 80, true);
    }

    function test_Setters_Success() public {
        vm.startPrank(owner);

        pvpProxy.setTreasuryAddress(address(0x999));
        assertEq(pvpProxy.treasuryAddress(), address(0x999));

        pvpProxy.setTreasuryFeePercentage(15);
        assertEq(pvpProxy.treasuryMgtFeePercentage(), 15);

        pvpProxy.setUsdStablecoinAddress(address(0x888));
        assertEq(address(pvpProxy.usdStablecoin()), address(0x888));

        pvpProxy.setPvpEntryTicketCost(2);
        assertEq(pvpProxy.pvpEntryTicketCost(), 2);

        pvpProxy.setPvpEntryFeeUsd(20 * 10**18);
        assertEq(pvpProxy.pvpEntryFeeUsd(), 20 * 10**18);

        pvpProxy.setBaseMgtReward(100 * 10**18);
        assertEq(pvpProxy.baseMgtReward(), 100 * 10**18);

        pvpProxy.setPvpTicketContract(address(0x777));
        assertEq(address(pvpProxy.pvpTicket()), address(0x777));

        pvpProxy.setMercenaryContract(address(0x666));
        assertEq(address(pvpProxy.mercenaryNft()), address(0x666));

        pvpProxy.setGameItemsContract(address(0x555));
        assertEq(address(pvpProxy.gameItems()), address(0x555));

        vm.stopPrank();
    }

    function test_Setters_Reverts_InvalidValues() public {
        vm.startPrank(owner);

        vm.expectRevert("PVP: Zero address not allowed");
        pvpProxy.setTreasuryAddress(address(0));

        vm.expectRevert("PVP: Percentage cannot exceed 100");
        pvpProxy.setTreasuryFeePercentage(101);

        vm.expectRevert("PVP: Zero address not allowed");
        pvpProxy.setUsdStablecoinAddress(address(0));

        vm.expectRevert("PVP: Zero address not allowed");
        pvpProxy.setPvpTicketContract(address(0));

        vm.expectRevert("PVP: Zero address not allowed");
        pvpProxy.setMercenaryContract(address(0));

        vm.expectRevert("PVP: Zero address not allowed");
        pvpProxy.setGameItemsContract(address(0));

        vm.stopPrank();
    }

    function test_Setters_Reverts_IfNotOwner() public {
        vm.startPrank(player);

        vm.expectRevert();
        pvpProxy.setTreasuryAddress(address(0x999));

        vm.expectRevert();
        pvpProxy.setTreasuryFeePercentage(10);

        vm.expectRevert();
        pvpProxy.setUsdStablecoinAddress(address(0x888));

        vm.expectRevert();
        pvpProxy.setPvpEntryTicketCost(5);

        vm.expectRevert();
        pvpProxy.setPvpEntryFeeUsd(50 * 10**18);

        vm.expectRevert();
        pvpProxy.setBaseMgtReward(200 * 10**18);

        vm.stopPrank();
    }

    function test_PauseAndUnpause_Success() public {
        vm.prank(owner);
        pvpProxy.pause();

        vm.prank(player);
        vm.expectRevert();
        pvpProxy.startPvpBattle(mercenaryId);

        vm.prank(owner);
        pvpProxy.unpause();

        vm.prank(player);
        pvpProxy.startPvpBattle(mercenaryId);
    }

    function test_Pause_Reverts_IfNotOwner() public {
        vm.prank(player);
        vm.expectRevert();
        pvpProxy.pause();
    }

    function test_AuthorizeUpgrade_Success() public {
        vm.startPrank(owner);
        PVP_Logic newImplementation = new PVP_Logic();
        pvpProxy.upgradeTo(address(newImplementation));
        vm.stopPrank();
    }

    function test_AuthorizeUpgrade_Reverts_IfNotOwner() public {
        PVP_Logic newImplementation = new PVP_Logic();
        vm.prank(player);
        vm.expectRevert();
        pvpProxy.upgradeTo(address(newImplementation));
    }
}