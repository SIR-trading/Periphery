// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "forge-std/Script.sol";
import {Quoter} from "view-quoter-v3/contracts/Quoter.sol";

/** @notice Deployment script for Quoter on MegaETH testnet
    @dev Run with:
        forge script script/DeployQuoter.s.sol --rpc-url megatest --broadcast --private-key $PRIVATE_KEY \
        --skip-simulation --gas-price 10000000 --priority-gas-price 1000000 --gas-limit 1000000000 --slow
    @dev If forge script fails, use forge create:
        forge create lib/view-quoter-v3/contracts/Quoter.sol:Quoter --rpc-url megatest --private-key $PRIVATE_KEY \
        --gas-price 10000000 --priority-gas-price 1000000 --gas-limit 1000000000 --broadcast \
        --constructor-args $UNISWAP_V3_FACTORY
 */
contract DeployQuoter is Script {
    // Uniswap V3 Factory address
    address constant UNISWAP_V3_FACTORY = 0x94996d371622304F2eB85df1eb7f328F7B317C3E;

    function _chainId() internal pure returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }

    function setUp() public view {
        require(_chainId() == 6343, "Only MegaETH testnet (chain 6343) is currently supported");
    }

    function run() public {
        vm.startBroadcast();

        // Deploy Quoter
        Quoter quoter = new Quoter(UNISWAP_V3_FACTORY);

        console.log("========================================");
        console.log("Quoter deployed at:", address(quoter));
        console.log("Using Uniswap V3 Factory at:", UNISWAP_V3_FACTORY);
        console.log("Chain ID:", _chainId());
        console.log("========================================");

        vm.stopBroadcast();
    }
}
