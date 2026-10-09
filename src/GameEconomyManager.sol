// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IGameToken {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function burnFrom(address account, uint256 amount) external;
    function transfer(address recipient, uint256 amount) external;
}

contract GameEconomyManager is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    IGameToken public gameToken;
    address public gameTokenVault;

    // Porcentaje de quema basado en base 10000 (Ej: 500 = 5%, 2500 = 25%, 5000 = 50%)
    uint256 public burnFeeBasisPoints; 

    event DeflationaryFeeProcessed(address indexed payer, uint256 totalPaid, uint256 burnedAmount, uint256 vaultAmount);
    event BurnRateUpdated(uint256 newRate);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _gameToken,
        address _gameTokenVault,
        uint256 _burnFeeBasisPoints,
        address initialOwner
    ) external initializer {
        require(_gameToken != address(0), "Invalid token");
        require(_gameTokenVault != address(0), "Invalid vault");
        require(_burnFeeBasisPoints <= 10000, "Rate cannot exceed 100%");

        __Ownable_init();
        __UUPSUpgradeable_init();

        if (owner() != initialOwner) {
            _transferOwnership(initialOwner);
        }

        gameToken = IGameToken(_gameToken);
        gameTokenVault = _gameTokenVault;
        burnFeeBasisPoints = _burnFeeBasisPoints;
    }

    /**
     * @notice Procesa un pago de tarifa aplicando la regla deflacionaria inmutable.
     * @param payer El jugador que paga la tarifa.
     * @param totalAmount Cantidad total de tokens pagados.
     */
    function processFee(address payer, uint256 totalAmount) external {
        require(totalAmount > 0, "Amount must be > 0");

        // 1. Calcular cuánto se va a quemar de forma nativa e inmutable
        uint256 burnAmount = (totalAmount * burnFeeBasisPoints) / 10000;
        uint256 vaultAmount = totalAmount - burnAmount;

        // 2. Quemar directamente los tokens desde la cuenta del usuario (requiere aprobación previa en el token)
        if (burnAmount > 0) {
            gameToken.burnFrom(payer, burnAmount);
        }

        // 3. Enviar el resto al Vault para tesorería/recompensas futuras
        if (vaultAmount > 0) {
            bool success = gameToken.transferFrom(payer, gameTokenVault, vaultAmount);
            require(success, "Vault transfer failed");
        }

        emit DeflationaryFeeProcessed(payer, totalAmount, burnAmount, vaultAmount);
    }

    function setBurnFeeBasisPoints(uint256 _newRate) external onlyOwner {
        require(_newRate <= 10000, "Rate cannot exceed 100%");
        burnFeeBasisPoints = _newRate;
        emit BurnRateUpdated(_newRate);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}