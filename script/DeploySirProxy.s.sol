// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {SirProxy} from "src/SirProxy.sol";

/**
 * @dev cli for HyperEVM testnet with big blocks:
 *     forge script script/DeploySirProxy.s.sol --rpc-url hypertest --chain 998 --broadcast --ledger --hd-paths $HD_PATH
 * @dev cli for HyperEVM mainnet with big blocks:
 *     forge script script/DeploySirProxy.s.sol --rpc-url hyperevm --chain 999 --broadcast --ledger --hd-paths $HD_PATH \
       --with-gas-price 0.8gwei --priority-gas-price 0.1gwei --verify --etherscan-api-key $API_KEY
 */
contract DeploySirProxy is Script {
    address public assistant;

    function setUp() public {
        if (block.chainid != 998 && block.chainid != 999) {
            revert("Network not supported. Use chain 998 (testnet) or 999 (mainnet)");
        }

        assistant = vm.envAddress("ASSISTANT");
    }

    function run() public {
        vm.startBroadcast();

        // Deploy SirProxy
        address sirProxy = address(new SirProxy(assistant));
        console.log("SirProxy deployed at: ", sirProxy);

        vm.stopBroadcast();
    }
}
