// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SirStructs} from "core/libraries/SirStructs.sol";

/** @notice Helper functions for SIR protocol
 */
interface IAssistant {
    error VaultCanBeCreated();

    enum VaultStatus {
        InvalidVault,
        NoUniswapPool,
        VaultCanBeCreated,
        VaultAlreadyExists
    }

    function getReserves(uint48[] calldata vaultIds) external view returns (SirStructs.Reserves[] memory reserves);

    function priceOfTEA(
        SirStructs.VaultParameters calldata vaultParams
    ) external view returns (uint256 num, uint256 den);

    function priceOfAPE(
        SirStructs.VaultParameters calldata vaultParams
    ) external view returns (uint256 num, uint256 den);

    function getVaultStatus(SirStructs.VaultParameters calldata vaultParams) external view returns (VaultStatus);

    function getAddressAPE(uint48 vaultId) external view returns (address);

    function quoteMint(
        bool isAPE,
        SirStructs.VaultParameters calldata vaultParams,
        uint144 amountCollateral
    ) external view returns (uint256 amountTokens);

    function quoteMintWithDebtToken(
        bool isAPE,
        SirStructs.VaultParameters calldata vaultParams,
        uint256 amountDebtToken
    ) external view returns (uint256 amountTokens, uint256 amountCollateral);

    function quoteBurn(
        bool isAPE,
        SirStructs.VaultParameters calldata vaultParams,
        uint256 amountTokens
    ) external view returns (uint144 amountCollateral);
}
