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

    /** @notice It returns the ideal price of TEA if there were no fees for withdrawing.
        @notice To get the price as [units of Collateral][per unit of TEA], divide num by den.
     */
    function priceOfTEA(
        SirStructs.VaultParameters calldata vaultParams
    ) external view returns (uint256 num, uint256 den);

    /** @notice It returns the ideal price of APE if there were no fees for withdrawing.
        @notice To get the price as [units of Collateral][per unit of APE], divide num by den.
     */
    function priceOfAPE(
        SirStructs.VaultParameters calldata vaultParams
    ) external view returns (uint256 num, uint256 den);

    function getVaultStatus(SirStructs.VaultParameters calldata vaultParams) external view returns (VaultStatus);

    function getAddressAPE(uint48 vaultId) external view returns (address);
}
