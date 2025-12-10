// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";

import {Assistant} from "src/Assistant.sol";

/** @dev cli for MegaETH testnet:  forge script script/QueryAssistant.s.sol --rpc-url megatest --chain 6343 --broadcast
*/
contract QueryAssistant is Script {
    uint256 privateKey;

    address public vault;

    function setUp() public {
        if (block.chainid == 6343) {
            privateKey = vm.envUint("MEGAETH_DEPLOYER_PRIVATE_KEY");
        } else if (block.chainid != 6342) {
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
