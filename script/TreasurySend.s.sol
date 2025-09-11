// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IVault} from "core/interfaces/IVault.sol";

// Contracts
import {TreasuryV1} from "src/TreasuryV1.sol";

import "forge-std/Script.sol";

/// @dev cli for HyperEVM testnet with big blocks:
///     BB_GAS=$(cast rpc --rpc-url hypertest eth_bigBlockGasPrice | tr -d '"' | cast to-dec)
///     forge script script/TreasurySend.s.sol --rpc-url hypertest --chain 998 --broadcast --ledger --hd-paths "m/44'/60'/0'/0/0" --with-gas-price $BB_GAS --slow
/// @dev cli for HyperEVM mainnet with big blocks:
///     BB_GAS=$(cast rpc --rpc-url hyperevm eth_bigBlockGasPrice | tr -d '"' | cast to-dec)
///     forge script script/TreasurySend.s.sol --rpc-url hyperevm --chain 999 --broadcast --ledger --hd-paths "m/44'/60'/0'/0/0" --with-gas-price $BB_GAS --slow
contract TreasurySend is Script {
    IVault vault;
    address sir;
    TreasuryV1 treasury;

    // Constants for transfer
    address constant RECIPIENT = 0x5000Ff6Cc1864690d947B864B9FB0d603E8d1F1A;
    uint256 constant AMOUNT = 6.8e6 * 1e12;

    function setUp() public {
        if (block.chainid != 998 && block.chainid != 999) {
            revert("Network not supported. Use chain 998 (testnet) or 999 (mainnet)");
        }
        
        vault = IVault(vm.envAddress("VAULT"));
        sir = vault.SIR();
        treasury = TreasuryV1(vm.envAddress("TREASURY"));
    }

    function run() public {
        require(RECIPIENT != address(0), "Invalid recipient address");
        require(AMOUNT > 0, "Amount must be greater than 0");

        vm.startBroadcast();

        // Check treasury balance before transfer
        uint256 treasuryBalance = IERC20(sir).balanceOf(address(treasury));
        console.log("Treasury SIR balance: ", treasuryBalance);
        console.log("Transferring: ", AMOUNT);
        console.log("To recipient: ", RECIPIENT);

        require(treasuryBalance >= AMOUNT, "Insufficient treasury balance");

        // Execute transfer through treasury's relayCall
        bytes memory transferCall = abi.encodeWithSelector(IERC20.transfer.selector, RECIPIENT, AMOUNT);

        bytes memory result = treasury.relayCall(sir, transferCall);
        bool success = abi.decode(result, (bool));
        require(success, "Transfer failed");

        // Verify transfer
        uint256 newTreasuryBalance = IERC20(sir).balanceOf(address(treasury));
        uint256 recipientBalance = IERC20(sir).balanceOf(RECIPIENT);

        console.log("Transfer successful!");
        console.log("New treasury balance: ", newTreasuryBalance);
        console.log("Recipient balance: ", recipientBalance);

        vm.stopBroadcast();
    }
}
