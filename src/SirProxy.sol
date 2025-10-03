// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ISIR} from "core/interfaces/ISIR.sol";
import {IVault} from "core/interfaces/IVault.sol";
import {IERC20} from "core/interfaces/IWETH9.sol";
import {IAssistant} from "./interfaces/IAssistant.sol";
import {SirStructs} from "core/libraries/SirStructs.sol";
import {AddressClone} from "core/libraries/AddressClone.sol";

// Minimal interface to get VAULT from Assistant
interface IAssistantVault {
    function VAULT() external view returns (address);
}

/**
 * @title SirProxy
 * @dev This contract is designed for read-only operations
 */
contract SirProxy {
    ISIR public immutable SIR_TOKEN;
    IVault public immutable VAULT;
    IAssistant public immutable ASSISTANT;

    constructor(address _assistant) {
        ASSISTANT = IAssistant(_assistant);
        // Get VAULT address from Assistant (it has a public VAULT getter)
        VAULT = IVault(IAssistantVault(_assistant).VAULT());
        // Get SIR token address from Vault
        SIR_TOKEN = ISIR(payable(VAULT.SIR()));
    }

    /**
     * @notice Returns the name of the token
     * @return The name from the SIR token contract
     */
    function name() external view returns (string memory) {
        return "Proxy SIR for offchain operations";
    }

    /**
     * @notice Returns the symbol of the token
     * @return The symbol from the SIR token contract
     */
    function symbol() external view returns (string memory) {
        return SIR_TOKEN.symbol();
    }

    /**
     * @notice Returns the number of decimals the token uses
     * @return The decimals from the SIR token contract
     */
    function decimals() external view returns (uint8) {
        return SIR_TOKEN.decimals();
    }

    /**
     * @notice Returns the total supply of SIR tokens
     * @return The total supply from the SIR token contract
     */
    function totalSupply() external view returns (uint256) {
        return SIR_TOKEN.totalSupply();
    }

    /**
     * @notice Returns the aggregated SIR balance for an account from all sources
     * @dev Aggregates: current balance, staked (locked + unlocked), unclaimed rewards, pending contributor rewards, and equity from TEA/APE tokens
     * @param account The address to check the balance for
     * @return totalBalance The total aggregated SIR balance
     */
    function balanceOf(address account) external view returns (uint256 totalBalance) {
        // 1. Get current SIR token balance
        totalBalance = SIR_TOKEN.balanceOf(account);

        // 2. Get staked SIR (both unlocked and locked)
        (uint80 unlockedStake, uint80 lockedStake) = SIR_TOKEN.stakeOf(account);
        totalBalance += unlockedStake + lockedStake;

        // 3. Get unclaimed SIR rewards from LP positions across all vaults
        uint48 numberOfVaults = VAULT.numberOfVaults();
        for (uint48 vaultId = 1; vaultId <= numberOfVaults; vaultId++) {
            // Get unclaimed rewards for this vault
            uint80 unclaimedRewards = VAULT.unclaimedRewards(vaultId, account);
            totalBalance += unclaimedRewards;
        }

        // 4. Get pending contributor rewards
        uint80 contributorRewards = SIR_TOKEN.contributorUnclaimedSIR(account);
        totalBalance += contributorRewards;

        // 5. Get SIR equity from TEA and APE tokens
        totalBalance += _getSirEquityFromTeaAndApe(account, numberOfVaults);
    }

    /**
     * @notice Calculate SIR equity from TEA and APE token holdings
     * @dev Uses Assistant's quoteBurn to determine SIR value, wrapped in try-catch
     * @param account The account to check
     * @param numberOfVaults Total number of vaults to iterate through
     * @return sirEquity The total SIR equity from TEA and APE tokens
     */
    function _getSirEquityFromTeaAndApe(
        address account,
        uint48 numberOfVaults
    ) private view returns (uint256 sirEquity) {
        for (uint48 vaultId = 1; vaultId <= numberOfVaults; vaultId++) {
            // Get vault parameters
            SirStructs.VaultParameters memory vaultParams = VAULT.paramsById(vaultId);

            // Skip if collateral is not SIR
            if (vaultParams.collateralToken != address(SIR_TOKEN)) continue;

            // Get TEA balance and calculate SIR equity
            uint256 teaBalance = VAULT.balanceOf(account, vaultId);
            if (teaBalance > 0) {
                try ASSISTANT.quoteBurn(false, vaultParams, teaBalance) returns (uint144 collateralAmount) {
                    // Direct 1:1 since collateral is SIR
                    sirEquity += collateralAmount;
                } catch {
                    // If quoteBurn reverts, assume 0 SIR value
                }
            }

            // Get APE balance and calculate SIR equity
            address apeToken = AddressClone.getAddress(address(VAULT), vaultId);
            uint256 apeBalance = IERC20(apeToken).balanceOf(account);
            if (apeBalance > 0) {
                try ASSISTANT.quoteBurn(true, vaultParams, apeBalance) returns (uint144 collateralAmount) {
                    // Direct 1:1 since collateral is SIR
                    sirEquity += collateralAmount;
                } catch {
                    // If quoteBurn reverts, assume 0 SIR value
                }
            }
        }

        return sirEquity;
    }
}
