// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {Disperse} from "src/Disperse.sol";

/**
 * Deploys the Disperse (multisend) contract on MegaETH (chain 4326).
 *
 * Ethereum reuses the canonical Disperse
 * (0xD152f549545093347A162Dce210e7293f1452150); the HyperEVM deployment lives on
 * the `hyperEVM` branch.
 *
 * After deploying, verify the source on mega.etherscan.io. Disperse.sol has no
 * imports, so single-file verification works (or use forge):
 *   forge verify-contract <deployed> src/Disperse.sol:Disperse \
 *     --verifier-url <megaeth-explorer-api> --etherscan-api-key <key> --watch
 *
 * @dev cli for MegaETH mainnet (ledger):
 *      forge script script/DeployDisperse.s.sol --rpc-url megaeth --broadcast --ledger --hd-paths $HD_PATH \
 *      --gas-price 1200000 --priority-gas-price 100000 --skip-simulation
 */
contract DeployDisperse is Script {
    function setUp() public view {
        if (block.chainid != 4326) {
            revert("This script deploys Disperse on MegaETH (4326). Use the hyperEVM branch for HyperEVM.");
        }
    }

    function run() public {
        vm.startBroadcast();
        Disperse disperse = new Disperse();
        vm.stopBroadcast();

        console.log("Disperse deployed at", address(disperse));
    }
}
