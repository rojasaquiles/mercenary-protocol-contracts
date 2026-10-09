// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {GameTokenVault} from "./GameTokenVault.sol";

contract GameTokenVaultV2 is GameTokenVault {
    uint256 public newV2Value;

    function initializeV2State() external onlyOwner {
        newV2Value = 42;
    }

    function getVersion() external pure returns (uint256) {
        return 2;
    }

    function getNewV2Value() external view returns (uint256) {
        return newV2Value;
    }
}