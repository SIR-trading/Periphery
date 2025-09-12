// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";

import {Assistant} from "src/Assistant.sol";
import {AddressesHyperEVM} from "core/libraries/AddressesHyperEVM.sol";

/** @dev cli for HyperEVM testnet:
        forge script script/QueryAssistant.s.sol --rpc-url hypertest --chain 998 --broadcast
    @dev cli for HyperEVM mainnet:
        forge script script/QueryAssistant.s.sol --rpc-url hyperevm --chain 999 --broadcast
*/
contract QueryAssistant is Script {
    address public vault;

    function setUp() public {
        if (block.chainid != 998 && block.chainid != 999) {
            revert("Network not supported. Use chain 998 (testnet) or 999 (mainnet)");
        }

        vault = vm.envAddress("VAULT");
    }

    function run() public {
        vm.startBroadcast();

        // Query public parameters
        Assistant assistant = Assistant(vm.envAddress("ASSISTANT"));

        // Size of the contract
        console.log("Size of the contract: ", address(assistant).code.length);

        // Address of the Vault
        console.log("Vault: ", address(assistant.VAULT()));

        vm.stopBroadcast();
    }
}
