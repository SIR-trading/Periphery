// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Assistant} from "src/Assistant.sol";
import {IVault} from "core/interfaces/IVault.sol";
import {AddressesMegaETHTest} from "core/libraries/AddressesMegaETHTest.sol";

/** @dev Run with:
        forge script script/DeployAssistant.s.sol --rpc-url megatest --broadcast --private-key $PRIVATE_KEY \
        --skip-simulation --gas-price 10000000 --priority-gas-price 1000000 --gas-limit 1000000000 --slow
    @dev If forge script fails, use forge create:
        forge create src/Assistant.sol:Assistant --rpc-url megatest --private-key $PRIVATE_KEY \
        --gas-price 10000000 --priority-gas-price 1000000 --gas-limit 1000000000 --broadcast \
        --constructor-args $VAULT $ORACLE
 */
contract DeployAssistant is Script {
    IVault public vault = IVault(0xDe23e9DCeBf6edadae4822B921363E640bb9B718);
    address public oracle;

    function setUp() public {
        if (block.chainid != 6343) {
            revert("Only MegaETH testnet (chain 6343) is currently supported");
        }

        oracle = vault.ORACLE();
    }

    function run() public {
        vm.startBroadcast();

        // Deploy assistant (factory and init hash are fetched from oracle)
        address assistant = address(new Assistant(address(vault), oracle));
        console.log("Assistant deployed at: ", assistant);

        vm.stopBroadcast();
    }
}
