// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Assistant} from "src/Assistant.sol";
import {IVault} from "core/interfaces/IVault.sol";
import {AddressesMegaETH} from "core/libraries/AddressesMegaETH.sol";
import {AddressesMegaETHTest} from "core/libraries/AddressesMegaETHTest.sol";

/**
 * @dev cli for MegaETH testnet:  forge script script/DeployAssistant.s.sol --rpc-url megatest --chain 6343 --broadcast
 */
contract DeployAssistant is Script {
    uint256 deployerPrivateKey;

    IVault public vault;
    address public oracle;

    function setUp() public {
        if (block.chainid == 6343) {
            deployerPrivateKey = vm.envUint("MEGAETH_DEPLOYER_PRIVATE_KEY");
        } else if (block.chainid != 6342) {
            revert("Network not supported");
        }

        vault = IVault(vm.envAddress("VAULT"));
        oracle = vault.ORACLE();
    }

    function run() public {
        if (block.chainid == 6342) vm.startBroadcast();
        else vm.startBroadcast(deployerPrivateKey);

        // Deploy assistant
        address assistant = address(
            new Assistant(
                address(vault),
                oracle,
                block.chainid == 6342 ? AddressesMegaETH.ADDR_UNISWAPV3_FACTORY : AddressesMegaETHTest.ADDR_UNISWAPV3_FACTORY
            )
        );
        console.log("Assistant deployed at: ", assistant);

        vm.stopBroadcast();
    }
}
