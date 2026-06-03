// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {Disperse} from "src/Disperse.sol";

/**
 * Deploys the Disperse (multisend) contract on HyperEVM (chain 999).
 *
 * Ethereum reuses the canonical Disperse
 * (0xD152f549545093347A162Dce210e7293f1452150); the MegaETH deployment lives on
 * the `megaeth` branch.
 *
 * After deploying, verify the source on hyperevmscan.io. Disperse.sol has no
 * imports, so single-file verification works (or use forge):
 *   forge verify-contract <deployed> src/Disperse.sol:Disperse \
 *     --verifier-url <hyperevm-explorer-api> --etherscan-api-key <key> --watch
 *
 * @dev cli for HyperEVM mainnet (ledger):
 *      forge script script/DeployDisperse.s.sol --rpc-url hyperevm --broadcast --ledger --hd-paths $HD_PATH --skip-simulation
 */
contract DeployDisperse is Script {
    function setUp() public view {
        if (block.chainid != 999) {
            revert("This script deploys Disperse on HyperEVM (999). Use the megaeth branch for MegaETH.");
        }
    }

    function run() public {
        vm.startBroadcast();
        Disperse disperse = new Disperse();
        vm.stopBroadcast();

        console.log("Disperse deployed at", address(disperse));
    }
}
