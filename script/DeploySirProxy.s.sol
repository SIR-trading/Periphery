// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {SirProxy} from "src/SirProxy.sol";

/** @dev cli for MegaETH testnet:
        forge script script/DeploySirProxy.s.sol --rpc-url megatest --broadcast --private-key $PRIVATE_KEY --skip-simulation \
        --gas-price 10000000 --priority-gas-price 1000000 --gas-limit 5000000000
    @dev cli for MegaETH mainnet:
        forge script script/DeploySirProxy.s.sol --rpc-url megaeth --broadcast --ledger --hd-paths $HD_PATH \
        --gas-price 1200000 --priority-gas-price 100000 --gas-limit 5000000000 --skip-simulation
*/
contract DeploySirProxy is Script {
    address public assistant;

    function setUp() public {
        if (block.chainid != 6343 && block.chainid != 4326) {
            revert("Only MegaETH is currently supported");
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
