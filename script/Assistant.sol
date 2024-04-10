// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vault} from "core/Vault.sol";
import {VaultStructs} from "core/libraries/VaultStructs.sol";
import {TransferHelper} from "core/libraries/TransferHelper.sol";

contract Assistant {
    Vault public vault;

    constructor(address vault_) {
        vault = Vault(vault_);
    }

    function mint(bool isAPE, uint256 amount, address debtToken, address collateralToken, int8 leverageTier) external {
        // ADD MIN AMOUNT? THIS COULD BE A PROTECTION AGAINST RUGGY TOKENS AND, ALTHOUGH LESS DANGEROUS, PRICE CHANGES

        // Transfer collateral from user to vault
        TransferHelper.safeTransferFrom(collateralToken, msg.sender, address(vault), amount);

        // Mint TEA or APE
        vault.mint(isAPE, VaultStructs.VaultParameters(debtToken, collateralToken, leverageTier));
    }
}
