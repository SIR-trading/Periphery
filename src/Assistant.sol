// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vault} from "core/Vault.sol";
import {VaultStructs} from "core/libraries/VaultStructs.sol";
import {SystemConstants} from "core/libraries/SystemConstants.sol";
import {Fees} from "core/libraries/Fees.sol";
import {SaltedAddress} from "core/libraries/SaltedAddress.sol";
import {FullMath} from "core/libraries/FullMath.sol";
import {TransferHelper} from "core/libraries/TransferHelper.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {IERC20} from "v2-core/interfaces/IERC20.sol";

/** @dev More gas-efficient version of this contract would inherit SwapRouter rather than calling the external swapRouter
 */
contract Assistant {
    error VaultDoesNotExist();

    ISwapRouter public immutable swapRouter; // Uniswap V3 SwapRouter
    Vault public immutable vault;

    constructor(address swapRouter_, address vault_) {
        swapRouter = ISwapRouter(swapRouter_);
        vault = Vault(vault_);
    }

    /** @notice This contract must be approved to spend collateral tokens
     */
    function mint(
        bool isAPE,
        VaultStructs.VaultParameters calldata vaultParams,
        uint144 amountCollateral
    ) external returns (uint256 amountTokens) {
        // Transfer collateral from user to vault
        TransferHelper.safeTransferFrom(vaultParams.collateralToken, msg.sender, address(vault), amountCollateral);

        // Mint TEA or APE
        amountTokens = vault.mint(isAPE, vaultParams);
    }

    /** @notice This contract must be approved to spend debt tokens
     */
    function swapAndMint(
        bool isAPE,
        VaultStructs.VaultParameters calldata vaultParams,
        uint256 amountDebtToken,
        uint256 minCollateral,
        uint24 uniswapFeeTier
    ) external returns (uint256 amountTokens) {
        // Transfer debt token from user to vault
        TransferHelper.safeTransferFrom(vaultParams.debtToken, msg.sender, address(vault), amountDebtToken);

        // Approve swapRouter to spend debtToken from this contract
        TransferHelper.safeApprove(vaultParams.debtToken, address(swapRouter), amountDebtToken);

        // Swap collateral for debt token, and send them to the vault
        swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: vaultParams.debtToken,
                tokenOut: vaultParams.collateralToken,
                fee: uniswapFeeTier,
                recipient: address(vault),
                deadline: block.timestamp,
                amountIn: amountDebtToken,
                amountOutMinimum: minCollateral,
                sqrtPriceLimitX96: 0
            })
        );

        // Mint TEA or APE
        amountTokens = vault.mint(isAPE, vaultParams);
    }

    function burn(
        bool isAPE,
        VaultStructs.VaultParameters calldata vaultParams,
        uint256 amountTokens
    ) external returns (uint144 amountCollateral) {
        // Burn TEA or APE
        amountCollateral = vault.burn(isAPE, vaultParams, amountTokens);

        // Transfer collateral to user
        TransferHelper.safeTransfer(vaultParams.collateralToken, msg.sender, amountCollateral);
    }

    function burnAndSwap(
        bool isAPE,
        VaultStructs.VaultParameters calldata vaultParams,
        uint256 amountTokens,
        uint256 minDebtToken,
        uint24 uniswapFeeTier
    ) external returns (uint256 amountDebtToken) {
        // Burn TEA or APE
        uint144 amountCollateral = vault.burn(isAPE, vaultParams, amountTokens);

        // Approve swapRouter to spend collateralToken from this contract
        TransferHelper.safeApprove(vaultParams.collateralToken, address(swapRouter), amountCollateral);

        // Swap collateral for debt token, and send them to the user
        amountDebtToken = swapRouter.exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: vaultParams.collateralToken,
                tokenOut: vaultParams.debtToken,
                fee: uniswapFeeTier,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountOut: minDebtToken,
                amountInMaximum: amountCollateral,
                sqrtPriceLimitX96: 0
            })
        );
    }

    /** @notice It returns the ideal price of TEA if there were no fees for withdrawing.
        @notice To get the price as [units of Collateral][per unit of TEA], divide num by den.
     */
    function priceOfTEA(
        VaultStructs.VaultParameters calldata vaultParams
    ) external view returns (uint256 num, uint256 den) {
        // Get current reserves
        VaultStructs.Reserves memory reserves = vault.getReserves(vaultParams);
        num = reserves.reserveLPers;

        // Get supply of TEA
        (, , uint48 vaultId) = vault.vaultStates(
            vaultParams.debtToken,
            vaultParams.collateralToken,
            vaultParams.leverageTier
        );
        den = vault.totalSupply(vaultParams.vaultId);
    }

    /** @notice It returns the ideal price of APE if there were no fees for withdrawing.
        @notice To get the price as [units of Collateral][per unit of APE], divide num by den.
     */
    function priceOfAPE(
        VaultStructs.VaultParameters calldata vaultParams
    ) external view returns (uint256 num, uint256 den) {
        // Get current reserves
        VaultStructs.Reserves memory reserves = vault.getReserves(vaultParams);
        num = reserves.reserveApes;

        // Get supply of APE
        (, , uint48 vaultId) = vault.vaultStates(
            vaultParams.debtToken,
            vaultParams.collateralToken,
            vaultParams.leverageTier
        );
        den = IERC20(SaltedAddress.getAddress(address(vault), vaultId)).totalSupply();
    }

    /*////////////////////////////////////////////////////////////////
                            SIMULATION FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function quoteMint(
        bool isAPE,
        VaultStructs.VaultParameters calldata vaultParams,
        uint144 amountCollateral
    ) external view returns (uint256 amountTokens) {
        // Get all the parameters
        (, uint16 baseFee, uint8 lpFee, , ) = vault.systemParams();
        (, , uint48 vaultId) = vault.vaultStates(
            vaultParams.debtToken,
            vaultParams.collateralToken,
            vaultParams.leverageTier
        );
        if (vaultId == 0) revert VaultDoesNotExist();

        // Get current reserves
        VaultStructs.Reserves memory reserves = vault.getReserves(vaultParams);

        if (isAPE) {
            // Compute how much collateral actually gets deposited
            uint256 feeNum;
            uint256 feeDen;
            if (vaultParams.leverageTier >= 0) {
                feeNum = 10000; // baseFee is uint16, leverageTier is int8, so feeNum does not require more than 24 bits
                feeDen = 10000 + (uint256(baseFee) << uint8(vaultParams.leverageTier));
            } else {
                uint256 temp = 10000 << uint8(-vaultParams.leverageTier);
                feeNum = temp;
                feeDen = temp + uint256(baseFee);
            }

            // Get collateralIn
            uint256 collateralIn = (uint256(amountCollateral) * feeNum) / feeDen;

            // Get supply of APE
            address ape = SaltedAddress.getAddress(address(vault), vaultId);
            uint256 supplyAPE = IERC20(ape).totalSupply();

            // Calculate tokens
            amountTokens = supplyAPE == 0
                ? collateralIn + reserves.reserveApes
                : FullMath.mulDiv(supplyAPE, collateralIn, reserves.reserveApes);
        } else {
            // Get current tax
            uint8 tax = vault.vaultTax(vaultId);

            // Compute how much collateral actually gets deposited
            (uint144 collateralIn, , uint144 lpersFee, uint144 polFee) = Fees.hiddenFeeTEA(
                amountCollateral,
                lpFee,
                tax
            );
            reserves.reserveLPers += lpersFee;

            // Get supply of TEA
            uint256 supplyTEA = vault.totalSupply(vaultId);

            // POL
            uint256 amountPOL = supplyTEA == 0
                ? _amountFirstMint(vaultParams.collateralToken, polFee + reserves.reserveLPers)
                : FullMath.mulDiv(supplyTEA, polFee, reserves.reserveLPers);
            supplyTEA += amountPOL;

            // LPer fees
            reserves.reserveLPers += polFee;

            // Calculate tokens
            amountTokens = supplyTEA == 0
                ? _amountFirstMint(vaultParams.collateralToken, collateralIn + reserves.reserveLPers)
                : FullMath.mulDiv(supplyTEA, collateralIn, reserves.reserveLPers);
        }
    }

    function quoteBurn(
        bool isAPE,
        VaultStructs.VaultParameters calldata vaultParams,
        uint256 amountTokens
    ) external view returns (uint144 amountCollateral) {
        // Get all the parameters
        (, uint16 baseFee, uint8 lpFee, , ) = vault.systemParams();
        (, , uint48 vaultId) = vault.vaultStates(
            vaultParams.debtToken,
            vaultParams.collateralToken,
            vaultParams.leverageTier
        );
        if (vaultId == 0) revert VaultDoesNotExist();

        // Get current reserves
        VaultStructs.Reserves memory reserves = vault.getReserves(vaultParams);

        if (isAPE) {
            // Get supply of APE
            address ape = SaltedAddress.getAddress(address(vault), vaultId);
            uint256 supplyAPE = IERC20(ape).totalSupply();

            // Get collateralOut
            uint256 collateralOut = uint144(FullMath.mulDiv(reserves.reserveApes, amountTokens, supplyAPE));

            // Compute collateral withdrawn
            uint256 feeNum;
            uint256 feeDen;
            if (vaultParams.leverageTier >= 0) {
                feeNum = 10000;
                feeDen = 10000 + (uint256(baseFee) << uint8(vaultParams.leverageTier));
            } else {
                uint256 temp = 10000 << uint8(-vaultParams.leverageTier);
                feeNum = temp;
                feeDen = temp + uint256(baseFee);
            }

            // Get collateral withdrawn
            amountCollateral = uint144((collateralOut * feeNum) / feeDen);
        } else {
            // Get supply of TEA
            uint256 supplyTEA = vault.totalSupply(vaultId);

            // Get collateralOut
            uint256 collateralOut = uint144(FullMath.mulDiv(reserves.reserveLPers, amountTokens, supplyTEA));

            // Compute collateral withdrawn
            uint256 feeNum = 10000;
            uint256 feeDen = 10000 + uint256(lpFee);
            amountCollateral = uint144((collateralOut * feeNum) / feeDen);
        }
    }

    /*////////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function _amountFirstMint(address collateral, uint144 collateralIn) private view returns (uint256 amount) {
        uint256 collateralTotalSupply = IERC20(collateral).totalSupply();
        amount = collateralTotalSupply > SystemConstants.TEA_MAX_SUPPLY
            ? FullMath.mulDiv(SystemConstants.TEA_MAX_SUPPLY, collateralIn, collateralTotalSupply)
            : collateralIn;
    }
}
