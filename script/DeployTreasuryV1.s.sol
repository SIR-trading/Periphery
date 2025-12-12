// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {TreasuryV1} from "src/TreasuryV1.sol";

import "forge-std/Script.sol";

/// @dev cli for MegaETH testnet:  forge script script/DeployTreasuryV1.s.sol --rpc-url megatest --broadcast --private-key $PRIVATE_KEY --skip-simulation --gas-price 1000000 --gas-limit 9000000
contract DeployTreasuryV1 is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy treasury implementation
        TreasuryV1 treasuryImplementation = new TreasuryV1();
        console.log("Treasury deployed at ", address(treasuryImplementation));

        // Deploy treasury proxy and point to implementation
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(treasuryImplementation),
            abi.encodeWithSelector(TreasuryV1.initialize.selector)
        );
        console.log("Proxy deployed at ", address(proxy));

        vm.stopBroadcast();
    }
}
