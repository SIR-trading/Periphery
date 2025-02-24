// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Assistant} from "src/Assistant.sol";
import {Addresses} from "core/libraries/Addresses.sol";
import {AddressesSepolia} from "core/libraries/AddressesSepolia.sol";

/**
 * @dev cli for local testnet:  forge script script/DeployAssistant.s.sol --rpc-url mainnet --chain 1 --broadcast --verify --ledger --hd-paths PATHS --etherscan-api-key YOUR_KEY
 * @dev cli for Sepolia:        forge script script/DeployAssistant.s.sol --rpc-url sepolia --chain sepolia --broadcast
 */
contract DeployAssistant is Script {
    uint256 deployerPrivateKey;

    address public vault;
    address public oracle;

    function setUp() public {
        if (block.chainid == 11155111) {
            deployerPrivateKey = vm.envUint("SEPOLIA_DEPLOYER_PRIVATE_KEY");
        } else if (block.chainid != 1) {
            revert("Network not supported");
        }

        vault = vm.envAddress("VAULT");
        oracle = vm.envAddress("ORACLE");
    }

    function run() public {
        if (block.chainid == 1) vm.startBroadcast();
        else vm.startBroadcast(deployerPrivateKey);

        // Deploy assistant
        address assistant = address(
            new Assistant(
                vault,
                oracle,
                block.chainid == 1 ? Addresses.ADDR_UNISWAPV3_FACTORY : AddressesSepolia.ADDR_UNISWAPV3_FACTORY
            )
        );
        console.log("Assistant deployed at: ", assistant);

        vm.stopBroadcast();
    }
}
