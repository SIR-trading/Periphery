// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {TreasuryV1} from "src/TreasuryV1.sol";

import "forge-std/Script.sol";

/// @dev cli for HyperEVM testnet with big blocks:
///     BB_GAS=$(cast rpc --rpc-url hypertest eth_bigBlockGasPrice | tr -d '"' | cast to-dec)
///     forge script script/DeployTreasuryV1.s.sol --rpc-url hypertest --chain 998 --broadcast --ledger --hd-paths HD_PATH --with-gas-price $BB_GAS --slow
/// @dev cli for HyperEVM mainnet with big blocks:
///     BB_GAS=$(cast rpc --rpc-url hyperevm eth_bigBlockGasPrice | tr -d '"' | cast to-dec)
///     forge script script/DeployTreasuryV1.s.sol --rpc-url hyperevm --chain 999 --broadcast --ledger --hd-paths HD_PATH --with-gas-price $BB_GAS --verify --slow -verifier etherscan --etherscan-api-key APY_KEY
contract DeployTreasuryV1 is Script {
    function setUp() public {
        if (block.chainid != 998 && block.chainid != 999) {
            revert("Network not supported. Use chain 998 (testnet) or 999 (mainnet)");
        }
    }

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
