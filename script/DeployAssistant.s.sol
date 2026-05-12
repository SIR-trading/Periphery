// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Assistant} from "src/Assistant.sol";
import {IVault} from "core/interfaces/IVault.sol";
import {AddressesMegaETHTest} from "core/libraries/AddressesMegaETHTest.sol";

/** @dev cli for MegaETH testnet:
        forge script script/DeployAssistant.s.sol --rpc-url megatest --broadcast --private-key $PRIVATE_KEY --skip-simulation \
        --gas-price 10000000 --priority-gas-price 1000000 --gas-limit 5000000000 --slow
    @dev cli for MegaETH mainnet:
        forge script script/DeployAssistant.s.sol --rpc-url megaeth --broadcast --ledger --hd-paths $HD_PATH  \
        --gas-price 1200000 --priority-gas-price 100000 --gas-limit 5000000000 --skip-simulation
*/
contract DeployAssistant is Script {
    IVault public vault = IVault(0x8d694D1b369BdE5B274Ad643fEdD74f836E88543);
    address public oracle;

    function setUp() public {
        if (block.chainid != 6343 && block.chainid != 4326) {
            revert("Only MegaETH is currently supported");
        }

        oracle = vault.ORACLE();
    }

    function run() public {
        vm.startBroadcast();

        // Deploy assistant (factory and init hash are fetched from oracle)
        address assistant = address(new Assistant(address(vault), oracle));
        console.log("Assistant deployed at: ", assistant);

        vm.stopBroadcast();
    }
}
