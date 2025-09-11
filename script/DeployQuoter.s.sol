// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "forge-std/Script.sol";
import {QuoterHyperEVM} from "src/quoter/QuoterHyperEVM.sol";

/**
 * @notice Deployment script for QuoterHyperEVM on HyperEVM networks
 * @dev Uses the custom QuoterHyperEVM contract that has the correct POOL_INIT_CODE_HASH
 * for HyperEVM's Uniswap V3 deployment
 *
 * @dev cli for HyperEVM testnet with big blocks:
 *     BB_GAS=$(cast rpc --rpc-url hypertest eth_bigBlockGasPrice | tr -d '"' | cast to-dec)
 *     forge script script/DeployQuoter.s.sol --rpc-url hypertest --chain 998 --broadcast --ledger --hd-paths "m/44'/60'/0'/0/0" --with-gas-price $BB_GAS --slow
 * @dev cli for HyperEVM mainnet with big blocks:
 *     BB_GAS=$(cast rpc --rpc-url hyperevm eth_bigBlockGasPrice | tr -d '"' | cast to-dec)
 *     forge script script/DeployQuoter.s.sol --rpc-url hyperevm --chain 999 --broadcast --ledger --hd-paths "m/44'/60'/0'/0/0" --with-gas-price $BB_GAS --slow
 */
contract DeployQuoter is Script {
    // Uniswap V3 Factory addresses from AddressesHyperEVM libraries
    address constant UNISWAP_V3_FACTORY_MAINNET = 0xB1c0fa0B789320044A6F623cFe5eBda9562602E3; // Chain 999
    address constant UNISWAP_V3_FACTORY_TESTNET = 0x22B0768972bB7f1F5ea7a8740BB8f94b32483826; // Chain 998

    // Pool init code hash for HyperEVM Uniswap V3
    bytes32 constant HYPEREVM_POOL_INIT_CODE_HASH = 0xe3572921be1688dba92df30c6781b8770499ff274d20ae9b325f4242634774fb;

    uint256 chainId;

    function setUp() public {
        uint256 id;
        assembly {
            id := chainid()
        }
        chainId = id;

        if (chainId != 998 && chainId != 999) {
            revert("Network not supported. Use chain 998 (testnet) or 999 (mainnet)");
        }
    }

    function run() public {
        vm.startBroadcast();

        // Get the appropriate factory address based on chain ID
        address factory = chainId == 999 ? UNISWAP_V3_FACTORY_MAINNET : UNISWAP_V3_FACTORY_TESTNET;

        // Deploy QuoterHyperEVM
        QuoterHyperEVM quoter = new QuoterHyperEVM(factory);

        console.log("========================================");
        console.log("QuoterHyperEVM deployed at:", address(quoter));
        console.log("Using Uniswap V3 Factory at:", factory);
        console.log("Chain ID:", chainId);
        console.log("Pool init code hash:", vm.toString(HYPEREVM_POOL_INIT_CODE_HASH));
        console.log("========================================");

        vm.stopBroadcast();
    }
}
