// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {SirProxy} from "src/SirProxy.sol";

/**
 * @dev cli for MegaETH testnet:  forge script script/DeploySirProxy.s.sol --rpc-url megatest --chain 6343 --broadcast
 */
contract DeploySirProxy is Script {
    uint256 deployerPrivateKey;

    address public assistant;

    function setUp() public {
        if (block.chainid == 6343) {
            deployerPrivateKey = vm.envUint("MEGAETH_DEPLOYER_PRIVATE_KEY");
        } else if (block.chainid != 6342) {
            revert("Network not supported");
        }

        assistant = vm.envAddress("ASSISTANT");
    }

    function run() public {
        if (block.chainid == 6342) vm.startBroadcast();
        else vm.startBroadcast(deployerPrivateKey);

        // Deploy SirProxy
        address sirProxy = address(new SirProxy(assistant));
        console.log("SirProxy deployed at: ", sirProxy);

        vm.stopBroadcast();
    }
}
