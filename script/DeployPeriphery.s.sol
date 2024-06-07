// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {Assistant} from "src/Assistant.sol";
import {Addresses} from "core/libraries/Addresses.sol";

contract DeployPeriphery is Script {
    address public vault;
    bytes32 public hashCreationCodeAPE;

    function setUp() public {
        vault = vm.envAddress("VAULT");
        hashCreationCodeAPE = vm.envBytes32("HASH_CREATION_CODE_APE");
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("TARP_TESTNET_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy oracle
        address assistant = address(new Assistant(Addresses.ADDR_UNISWAPV3_SWAP_ROUTER, vault, hashCreationCodeAPE));
        console.log("Assistant deployed at: ", assistant);

        vm.stopBroadcast();
    }
}
