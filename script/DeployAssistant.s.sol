// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Assistant} from "src/Assistant.sol";
import {IVault} from "core/interfaces/IVault.sol";
import {AddressesHyperEVM} from "core/libraries/AddressesHyperEVM.sol";
import {AddressesHyperEVMTest} from "core/libraries/AddressesHyperEVMTest.sol";

/**
 * @dev cli for HyperEVM testnet with big blocks:
 *     BB_GAS=$(cast rpc --rpc-url hypertest eth_bigBlockGasPrice | tr -d '"' | cast to-dec)
 *     forge script script/DeployAssistant.s.sol --rpc-url hypertest --chain 998 --broadcast --ledger --hd-paths HD_PATH --with-gas-price $BB_GAS --slow
 * @dev cli for HyperEVM mainnet with big blocks:
 *     BB_GAS=$(cast rpc --rpc-url hyperevm eth_bigBlockGasPrice | tr -d '"' | cast to-dec)
 *     forge script script/DeployAssistant.s.sol --rpc-url hyperevm --chain 999 --broadcast --ledger --hd-paths HD_PATH --with-gas-price $BB_GAS --verify --slow -verifier etherscan --etherscan-api-key APY_KEY
 */
contract DeployAssistant is Script {
    IVault public vault;
    address public oracle;

    function setUp() public {
        if (block.chainid != 998 && block.chainid != 999) {
            revert("Network not supported. Use chain 998 (testnet) or 999 (mainnet)");
        }

        vault = IVault(vm.envAddress("VAULT"));
        oracle = vault.ORACLE();
    }

    function run() public {
        vm.startBroadcast();

        // Deploy assistant
        address uniswapFactory = block.chainid == 999
            ? AddressesHyperEVM.ADDR_UNISWAPV3_FACTORY
            : AddressesHyperEVMTest.ADDR_UNISWAPV3_FACTORY;

        address assistant = address(new Assistant(address(vault), oracle, uniswapFactory));
        console.log("Assistant deployed at: ", assistant);

        vm.stopBroadcast();
    }
}
