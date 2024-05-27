// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {Assistant} from "src/Assistant.sol";
import {Addresses} from "core/libraries/Addresses.sol";

contract DeployPeriphery is Script {
    address public constant VAULT = 0x41219a0a9C0b86ED81933c788a6B63Dfef8f17eE;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("TARP_TESTNET_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy oracle
        address assistant = address(new Assistant(Addresses.ADDR_UNISWAPV3_SWAP_ROUTER, VAULT));
        console.log("Assistant deployed at: ", assistant);

        vm.stopBroadcast();
    }
}
