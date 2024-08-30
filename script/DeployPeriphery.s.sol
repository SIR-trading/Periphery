// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {Assistant} from "src/Assistant.sol";
import {Addresses} from "core/libraries/Addresses.sol";

contract DeployPeriphery is Script {
    uint256 deployerPrivateKey;

    address public vault;
    bytes32 public hashCreationCodeAPE;

    function setUp() public {
        if (block.chainid == 1) {
            deployerPrivateKey = vm.envUint("TARP_TESTNET_PRIVATE_KEY");
        } else if (block.chainid == 11155111) {
            deployerPrivateKey = vm.envUint("SEPOLIA_DEPLOYER_PRIVATE_KEY");
        } else {
            revert("Network not supported");
        }

        vault = vm.envAddress("VAULT");
        hashCreationCodeAPE = vm.envBytes32("HASH_CREATION_CODE_APE");
    }

    /** cli for local testnet:  forge script script/DeployPeriphery.s.sol --rpc-url tarp_testnet --broadcast --legacy
        cli for Sepolia:        forge script script/DeployPeriphery.s.sol --rpc-url sepolia --chain sepolia --broadcast
     */
    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        // Deploy oracle
        address assistant = address(new Assistant(Addresses.ADDR_UNISWAPV3_SWAP_ROUTER, vault, hashCreationCodeAPE));
        console.log("Assistant deployed at: ", assistant);

        vm.stopBroadcast();
    }
}
