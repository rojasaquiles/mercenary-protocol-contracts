// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MyGameToken} from "./MyGameToken.sol";

/// @title MyGameTokenV2
/// @notice V2 del token del juego para OpenZeppelin v4.9.5.
contract MyGameTokenV2 is MyGameToken {
    /// @notice Devuelve el número de versión de la implementación
    function version() public pure returns (uint256) {
        return 2;
    }
}