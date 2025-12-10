// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IVault} from "core/interfaces/IVault.sol";

// Contracts
import {TreasuryV1} from "src/TreasuryV1.sol";

import "forge-std/Script.sol";

/// @dev cli for MegaETH testnet:  forge script script/TreasurySend.s.sol --rpc-url megatest --chain 6343 --broadcast
contract TreasurySend is Script {
    uint256 privateKey;

    IVault vault;
    address sir;
    TreasuryV1 treasury;

    // Constants for transfer
    address constant RECIPIENT = address(0x5000Ff6Cc1864690d947B864B9FB0d603E8d1F1A);
    uint256 constant AMOUNT = 12947371 * 1e12;

    function setUp() public {
        if (block.chainid == 6343) {
            privateKey = vm.envUint("MEGAETH_DEPLOYER_PRIVATE_KEY");
        } else if (block.chainid != 6342) {
            revert("Network not supported");
        }

        vault = IVault(vm.envAddress("VAULT"));
        sir = vault.SIR();
        treasury = TreasuryV1(vm.envAddress("TREASURY"));
    }

    function run() public {
        require(RECIPIENT != address(0), "Invalid recipient address");
        require(AMOUNT > 0, "Amount must be greater than 0");

        if (block.chainid == 6342) vm.startBroadcast();
        else vm.startBroadcast(privateKey);

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
