// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {SirProxy} from "src/SirProxy.sol";

/**
 * @dev cli for local testnet:  forge script script/DeploySirProxy.s.sol --rpc-url mainnet --chain 1 --broadcast --slow --verify --ledger --hd-paths PATHS --etherscan-api-key YOUR_KEY
 * @dev cli for Sepolia:        forge script script/DeploySirProxy.s.sol --rpc-url sepolia --chain sepolia --broadcast
 */
contract DeploySirProxy is Script {
    uint256 deployerPrivateKey;

    address public assistant;

    function setUp() public {
        if (block.chainid == 11155111) {
            deployerPrivateKey = vm.envUint("SEPOLIA_DEPLOYER_PRIVATE_KEY");
        } else if (block.chainid != 1) {
            revert("Network not supported");
        }

        assistant = vm.envAddress("ASSISTANT");
    }

    function run() public {
        if (block.chainid == 1) vm.startBroadcast();
        else vm.startBroadcast(deployerPrivateKey);

        // Deploy SirProxy
        address sirProxy = address(new SirProxy(assistant));
        console.log("SirProxy deployed at: ", sirProxy);

        vm.stopBroadcast();
    }
}
