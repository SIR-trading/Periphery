// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";

import {Assistant} from "src/Assistant.sol";
import {Addresses} from "core/libraries/Addresses.sol";

/** @dev cli for local testnet:  forge script script/QueryAssistant.s.sol --rpc-url tarp_testnet --broadcast --legacy
    @dev cli for Sepolia:        forge script script/QueryAssistant.s.sol --rpc-url sepolia --chain sepolia --broadcast
*/
contract QueryAssistant is Script {
    uint256 privateKey;

    address public vault;

    function setUp() public {
        if (block.chainid == 1) {
            privateKey = vm.envUint("TARP_TESTNET_PRIVATE_KEY");
        } else if (block.chainid == 11155111) {
            privateKey = vm.envUint("SEPOLIA_PUBLIC_ADDRESS");
        } else {
            revert("Network not supported");
        }

        vault = vm.envAddress("VAULT");
    }

    function run() public {
        vm.startBroadcast(privateKey);

        // Query public parameters
        Assistant assistant = Assistant(vm.envAddress("ASSISTANT"));

        // Size of the contract
        console.log("Size of the contract: ", address(assistant).code.length);

        // Address of the Vault
        console.log("Vault: ", address(assistant.VAULT()));

        vm.stopBroadcast();
    }
}
