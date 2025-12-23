// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/** @notice Deployment script for 2 mock ERC20 tokens
    @dev Run with:
        forge script script/DeployMockTokens.s.sol --rpc-url megatest --broadcast --private-key $PRIVATE_KEY \
        --skip-simulation --gas-price 10000000 --priority-gas-price 1000000 --gas-limit 1000000000 --slow
    @dev If forge script fails, use forge create:
        forge create src/mocks/MockERC20.sol:MockERC20 --rpc-url megatest --private-key $PRIVATE_KEY \
        --gas-price 10000000 --priority-gas-price 1000000 --gas-limit 1000000000 --broadcast \
        --constructor-args "Mock Token A" "MOCKA" 18
 */
contract DeployMockTokens is Script {
    function run() public {
        vm.startBroadcast();

        MockERC20 tokenA = new MockERC20("Mock Token A", "MOCKA", 18);
        MockERC20 tokenB = new MockERC20("Mock Token B", "MOCKB", 18);

        console.log("========================================");
        console.log("Mock Token A deployed at:", address(tokenA));
        console.log("Mock Token B deployed at:", address(tokenB));
        console.log("========================================");

        vm.stopBroadcast();
    }
}
