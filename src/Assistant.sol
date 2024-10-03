// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVault} from "core/interfaces/IVault.sol";
import {SirStructs} from "core/libraries/SirStructs.sol";
import {SystemConstants} from "core/libraries/SystemConstants.sol";
import {Fees} from "core/libraries/Fees.sol";
import {FullMath} from "core/libraries/FullMath.sol";
import {IWETH9, IERC20} from "core/interfaces/IWETH9.sol";
import {Addresses} from "core/libraries/Addresses.sol";
import {UniswapPoolAddress} from "core/libraries/UniswapPoolAddress.sol";
import {AddressClone} from "core/libraries/AddressClone.sol";

import "forge-std/console.sol";

/** @notice Helper functions for SIR protocol
 */
contract Assistant {
    error VaultCanBeCreated();

    enum VaultStatus {
        InvalidVault,
        NoUniswapPool,
        VaultCanBeCreated,
        VaultAlreadyExists
    }

    IVault public immutable VAULT;

    constructor(address vault_) {
        VAULT = IVault(vault_);
    }

    function getReserves(uint48[] calldata vaultIds) external view returns (SirStructs.Reserves[] memory reserves) {
        reserves = new SirStructs.Reserves[](vaultIds.length);
        SirStructs.VaultParameters memory vaultParams;
        for (uint256 i = 0; i < vaultIds.length; i++) {
            vaultParams = VAULT.paramsById(vaultIds[i]);
            reserves[i] = VAULT.getReserves(vaultParams);
        }
    }

    /** @notice It returns the ideal price of TEA if there were no fees for withdrawing.
        @notice To get the price as [units of Collateral][per unit of TEA], divide num by den.
     */
    function priceOfTEA(
        SirStructs.VaultParameters calldata vaultParams
    ) external view returns (uint256 num, uint256 den) {
        // Get current reserves
        SirStructs.Reserves memory reserves = VAULT.getReserves(vaultParams);
        num = reserves.reserveLPers;

        // Get supply of TEA
        SirStructs.VaultState memory vaultState = VAULT.vaultStates(vaultParams);
        den = VAULT.totalSupply(vaultState.vaultId);
    }

    /** @notice It returns the ideal price of APE if there were no fees for withdrawing.
        @notice To get the price as [units of Collateral][per unit of APE], divide num by den.
     */
    function priceOfAPE(
        SirStructs.VaultParameters calldata vaultParams
    ) external view returns (uint256 num, uint256 den) {
        // Get current reserves
        SirStructs.Reserves memory reserves = VAULT.getReserves(vaultParams);
        num = reserves.reserveApes;

        // Get supply of APE
        SirStructs.VaultState memory vaultState = VAULT.vaultStates(vaultParams);
        den = IERC20(getAddressAPE(vaultState.vaultId)).totalSupply();
    }

    function getVaultStatus(SirStructs.VaultParameters calldata vaultParams) external view returns (VaultStatus) {
        // Check if the token addresses are a smart contract
        if (vaultParams.collateralToken.code.length == 0) return VaultStatus.InvalidVault;
        if (vaultParams.debtToken.code.length == 0) return VaultStatus.InvalidVault;

        // Check if the token returns total supply
        (bool success, ) = vaultParams.collateralToken.staticcall(abi.encodeWithSelector(IERC20.totalSupply.selector));
        if (!success) return VaultStatus.InvalidVault;
        (success, ) = vaultParams.debtToken.staticcall(abi.encodeWithSelector(IERC20.totalSupply.selector));
        if (!success) return VaultStatus.InvalidVault;

        // Check if the leverage tier is valid
        if (
            vaultParams.leverageTier < SystemConstants.MIN_LEVERAGE_TIER ||
            vaultParams.leverageTier > SystemConstants.MAX_LEVERAGE_TIER
        ) return VaultStatus.InvalidVault;

        // Check if a Uniswap pool exists
        if (
            !_checkFeeTierExists(vaultParams, 100) &&
            !_checkFeeTierExists(vaultParams, 500) &&
            !_checkFeeTierExists(vaultParams, 3000) &&
            !_checkFeeTierExists(vaultParams, 10000)
        ) return VaultStatus.NoUniswapPool;

        // Check if vault already exists
        SirStructs.VaultState memory vaultState = VAULT.vaultStates(vaultParams);
        if (vaultState.vaultId == 0) return VaultStatus.VaultCanBeCreated;
        return VaultStatus.VaultAlreadyExists;
    }

    function getAddressAPE(uint48 vaultId) public view returns (address) {
        return AddressClone.getAddress(address(VAULT), vaultId);
    }

    /*////////////////////////////////////////////////////////////////
                            SIMULATION FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /** @dev Static function so we do not need to save on SLOADs
        @dev If quoteMint reverts, mint will revert as well; vice versa is not true.
        @return amountTokens that would be minted for a given amount of collateral
     */
    function quoteMint(
        bool isAPE,
        SirStructs.VaultParameters calldata vaultParams,
        uint144 amountCollateral
    ) external view returns (uint256 amountTokens) {
        // Get all the parameters
        SirStructs.SystemParameters memory systemParams = VAULT.systemParams();
        SirStructs.VaultState memory vaultState = VAULT.vaultStates(vaultParams);
        if (vaultState.vaultId == 0) revert VaultCanBeCreated();

        // Get current reserves
        SirStructs.Reserves memory reserves = VAULT.getReserves(vaultParams);

        if (isAPE) {
            // Compute how much collateral actually gets deposited
            uint256 feeNum;
            uint256 feeDen;
            if (vaultParams.leverageTier >= 0) {
                feeNum = 10000; // baseFee is uint16, leverageTier is int8, so feeNum does not require more than 24 bits
                feeDen = 10000 + (uint256(systemParams.baseFee) << uint8(vaultParams.leverageTier));
            } else {
                uint256 temp = 10000 << uint8(-vaultParams.leverageTier);
                feeNum = temp;
                feeDen = temp + uint256(systemParams.baseFee);
            }

            // Get collateralIn
            uint256 collateralIn = (uint256(amountCollateral) * feeNum) / feeDen;

            // Get supply of APE
            address ape = getAddressAPE(vaultState.vaultId);
            uint256 supplyAPE = IERC20(ape).totalSupply();

            // Calculate tokens
            amountTokens = supplyAPE == 0
                ? collateralIn + reserves.reserveApes
                : FullMath.mulDiv(supplyAPE, collateralIn, reserves.reserveApes);
        } else {
            // Get current tax
            uint8 tax = VAULT.vaultTax(vaultState.vaultId);

            // Compute how much collateral actually gets deposited
            SirStructs.Fees memory fees = Fees.hiddenFeeTEA(amountCollateral, systemParams.lpFee, tax);
            reserves.reserveLPers += fees.collateralFeeToGentlemen;

            // Get supply of TEA
            uint256 supplyTEA = VAULT.totalSupply(vaultState.vaultId);

            // POL
            uint256 amountPOL = supplyTEA == 0
                ? _amountFirstMint(vaultParams.collateralToken, fees.collateralFeeToProtocol + reserves.reserveLPers)
                : FullMath.mulDiv(supplyTEA, fees.collateralFeeToProtocol, reserves.reserveLPers);
            supplyTEA += amountPOL;

            // LPer fees
            reserves.reserveLPers += fees.collateralFeeToProtocol;

            // Calculate tokens
            amountTokens = supplyTEA == 0
                ? _amountFirstMint(vaultParams.collateralToken, fees.collateralInOrWithdrawn + reserves.reserveLPers)
                : FullMath.mulDiv(supplyTEA, fees.collateralInOrWithdrawn, reserves.reserveLPers);
        }
    }

    /** @dev Static function so we do not need to save on SLOADs
        @dev If quoteBurn reverts, burn in Vault.sol will revert as well; vice versa is not true.
        @return amountCollateral that would be obtained by burning a given amount of collateral
     */
    function quoteBurn(
        bool isAPE,
        SirStructs.VaultParameters calldata vaultParams,
        uint256 amountTokens
    ) external view returns (uint144 amountCollateral) {
        // Get all the parameters
        SirStructs.SystemParameters memory systemParams = VAULT.systemParams();
        SirStructs.VaultState memory vaultState = VAULT.vaultStates(vaultParams);
        if (vaultState.vaultId == 0) revert VaultCanBeCreated();

        // Get current reserves
        SirStructs.Reserves memory reserves = VAULT.getReserves(vaultParams);

        if (isAPE) {
            // Get supply of APE
            address ape = getAddressAPE(vaultState.vaultId);
            uint256 supplyAPE = IERC20(ape).totalSupply();

            // Get collateralOut
            uint256 collateralOut = uint144(FullMath.mulDiv(reserves.reserveApes, amountTokens, supplyAPE));

            // Compute collateral withdrawn
            uint256 feeNum;
            uint256 feeDen;
            if (vaultParams.leverageTier >= 0) {
                feeNum = 10000;
                feeDen = 10000 + (uint256(systemParams.baseFee) << uint8(vaultParams.leverageTier));
            } else {
                uint256 temp = 10000 << uint8(-vaultParams.leverageTier);
                feeNum = temp;
                feeDen = temp + uint256(systemParams.baseFee);
            }

            // Get collateral withdrawn
            amountCollateral = uint144((collateralOut * feeNum) / feeDen);
        } else {
            // Get supply of TEA
            uint256 supplyTEA = VAULT.totalSupply(vaultState.vaultId);

            // Get collateralOut
            uint256 collateralOut = uint144(FullMath.mulDiv(reserves.reserveLPers, amountTokens, supplyTEA));

            // Compute collateral withdrawn
            uint256 feeNum = 10000;
            uint256 feeDen = 10000 + uint256(systemParams.lpFee);
            amountCollateral = uint144((collateralOut * feeNum) / feeDen);
        }
    }

    /*////////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function _checkFeeTierExists(
        SirStructs.VaultParameters calldata vaultParams,
        uint24 feeTier
    ) private view returns (bool) {
        return
            UniswapPoolAddress
                .computeAddress(
                    Addresses.ADDR_UNISWAPV3_FACTORY,
                    UniswapPoolAddress.getPoolKey(vaultParams.collateralToken, vaultParams.debtToken, feeTier)
                )
                .code
                .length != 0;
    }

    function _amountFirstMint(address collateral, uint144 collateralIn) private view returns (uint256 amount) {
        uint256 collateralTotalSupply = IERC20(collateral).totalSupply();
        amount = collateralTotalSupply > SystemConstants.TEA_MAX_SUPPLY
            ? FullMath.mulDiv(SystemConstants.TEA_MAX_SUPPLY, collateralIn, collateralTotalSupply)
            : collateralIn;
    }
}
