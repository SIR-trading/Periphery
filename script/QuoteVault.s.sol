// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {IVault} from "core/interfaces/IVault.sol";
import {IOracle} from "core/interfaces/IOracle.sol";
import {Assistant} from "src/Assistant.sol";
import {SirStructs} from "core/libraries/SirStructs.sol";

contract QuoteVault is Script {
    uint256 deployerPrivateKey;

    IVault public vault;
    IOracle public oracle;
    Assistant public assistant;

    function setUp() public {
        if (block.chainid == 1) {
            deployerPrivateKey = vm.envUint("TARP_TESTNET_PRIVATE_KEY");
        } else if (block.chainid == 11155111) {
            deployerPrivateKey = vm.envUint("SEPOLIA_DEPLOYER_PRIVATE_KEY");
        } else {
            revert("Network not supported");
        }

        vault = IVault(vm.envAddress("VAULT"));
        oracle = IOracle(vm.envAddress("ORACLE"));
        assistant = Assistant(vm.envAddress("ASSISTANT"));
    }

    /** cli for local testnet:  forge script script/QuoteVault.s.sol --rpc-url tarp_testnet --broadcast --legacy
        cli for Sepolia:        forge script script/QuoteVault.s.sol --rpc-url sepolia --chain sepolia --broadcast
     */
    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        SirStructs.VaultParameters memory vaultParams = vault.paramsById(1);

        SirStructs.OracleState memory state = oracle.state(vaultParams.collateralToken, vaultParams.debtToken);
        console.log("Uniswap fee tier: ", state.uniswapFeeTier.fee);

        uint24 feeTier = oracle.uniswapFeeTierOf(vaultParams.collateralToken, vaultParams.debtToken);
        console.log("Uniswap fee tier: ", feeTier);

        // Quote vault id 1
        (uint256 amountTokens, uint256 amountCollateral) = assistant.quoteMintWithDebtToken(
            false,
            vaultParams,
            995896400000000000000
        );
        console.log("Minting expects: ", amountTokens);
        console.log("Uniswap swap returns: ", amountCollateral);

        vm.stopBroadcast();
    }
}
