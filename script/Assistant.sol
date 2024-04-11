// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vault} from "core/Vault.sol";
import {VaultStructs} from "core/libraries/VaultStructs.sol";
import {TransferHelper} from "core/libraries/TransferHelper.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";

/** @dev More gas-efficient version of this contract would inherit SwapRouter rather than calling the external swapRouter
 */
contract Assistant {
    error ReceivedAmountTooLow(uint256 amount, uint256 minAmount);

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
        uint256 amountCollateral,
        uint256 minTokens
    ) external returns (uint256 amountTokens) {
        // Transfer collateral from user to vault
        TransferHelper.safeTransferFrom(vaultParams.collateralToken, msg.sender, address(vault), amountCollateral);

        // Mint TEA or APE
        amountTokens = vault.mint(isAPE, vaultParams);

        // Unsatisfactory amount of tokens minted
        if (amountTokens < minTokens) emit ReceivedAmountTooLow(amountTokens, minTokens);
    }

    /** @notice This contract must be approved to spend debt tokens
     */
    function swapAndMint(
        bool isAPE,
        VaultStructs.VaultParameters calldata vaultParams,
        uint256 amountDebtToken,
        uint256 minTokens,
        uint24 uniswapFeeTier
    ) external returns (uint256 amountTokens) {
        // Transfer debt token from user to vault
        TransferHelper.safeTransferFrom(vaultParams.debtToken, msg.sender, address(vault), amountDebtToken);

        // Approve swapRouter to spend debtToken from this contract
        TransferHelper.safeApprove(vaultParams.debtToken, address(swapRouter), amountDebtToken);

        // Swap collateral for debt token, and send them to the vault
        uint256 amountCollateral = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: vaultParams.debtToken,
                tokenOut: vaultParams.collateralToken,
                fee: uniswapFeeTier,
                recipient: address(vault),
                deadline: block.timestamp,
                amountIn: amountDebtToken,
                amountOutMinimum: 0, // Min amount is enforced later
                sqrtPriceLimitX96: 0
            })
        );

        // Mint TEA or APE
        amountTokens = vault.mint(isAPE, vaultParams);

        // Unsatisfactory amount of tokens minted
        if (amountTokens < minTokens) emit ReceivedAmountTooLow(amountTokens, minTokens);
    }

    function burn(
        bool isAPE,
        VaultStructs.VaultParameters calldata vaultParams,
        uint256 amountTokens,
        uint256 minCollateral
    ) external returns (uint256 amountCollateral) {
        // Burn TEA or APE
        amountCollateral = vault.burn(isAPE, vaultParams, amountTokens);

        // Unsatisfactory amount of collateral received
        if (amountCollateral < minCollateral) emit ReceivedAmountTooLow(amountCollateral, minCollateral);

        // Transfer collateral to user
        TransferHelper.safeTransfer(vaultParams.collateralToken, msg.sender, amountCollateral);
    }

    function burnAndSwap(
        bool isAPE,
        VaultStructs.VaultParameters calldata vaultParams,
        uint256 amountTokens,
        uint256 minCollateral,
        uint256 minDebtToken,
        uint24 uniswapFeeTier
    ) external returns (uint256 amountDebtToken) {
        // Burn TEA or APE
        uint256 amountCollateral = vault.burn(isAPE, vaultParams, amountTokens);

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
}
