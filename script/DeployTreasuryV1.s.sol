// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {TreasuryV1} from "src/TreasuryV1.sol";

import "forge-std/Script.sol";

/// @dev cli for mainnet:  forge script script/DeployTreasuryV1.s.sol --rpc-url mainnet --chain 1 --broadcast --verify --ledger --hd-paths PATHS --etherscan-api-key YOUR_KEY
/// @dev cli for Sepolia:  forge script script/DeployTreasuryV1.s.sol --rpc-url sepolia --chain sepolia --broadcast --verify --etherscan-api-key YOUR_KEY
contract DeployTreasuryV1 is Script {
    uint256 privateKey;

    function setUp() public {
        if (block.chainid == 11155111) {
            privateKey = vm.envUint("SEPOLIA_DEPLOYER_PRIVATE_KEY");
        } else if (block.chainid != 1) {
            revert("Network not supported");
        }
    }

    function run() public {
        if (block.chainid == 1) vm.startBroadcast();
        else vm.startBroadcast(privateKey);

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
