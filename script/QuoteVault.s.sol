// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {IVault} from "core/interfaces/IVault.sol";
import {IOracle} from "core/interfaces/IOracle.sol";
import {Assistant} from "src/Assistant.sol";
import {SirStructs} from "core/libraries/SirStructs.sol";

contract QuoteVault is Script {
    IVault public vault;
    address public oracle;
    Assistant public assistant;

    function setUp() public {
        if (block.chainid != 998 && block.chainid != 999) {
            revert("Network not supported. Use chain 998 (testnet) or 999 (mainnet)");
        }
        
        vault = IVault(vm.envAddress("VAULT"));
        oracle = vault.ORACLE();
        assistant = Assistant(vm.envAddress("ASSISTANT"));
    }

    /** @dev cli for HyperEVM testnet with big blocks:
            BB_GAS=$(cast rpc --rpc-url hypertest eth_bigBlockGasPrice | tr -d '"' | cast to-dec)
            forge script script/QuoteVault.s.sol --rpc-url hypertest --chain 998 --broadcast --ledger --hd-paths "m/44'/60'/0'/0/0" --with-gas-price $BB_GAS --slow
        @dev cli for HyperEVM mainnet with big blocks:
            BB_GAS=$(cast rpc --rpc-url hyperevm eth_bigBlockGasPrice | tr -d '"' | cast to-dec)
            forge script script/QuoteVault.s.sol --rpc-url hyperevm --chain 999 --broadcast --ledger --hd-paths "m/44'/60'/0'/0/0" --with-gas-price $BB_GAS --slow
     */
    function run() public {
        vm.startBroadcast();

        SirStructs.VaultParameters memory vaultParams = vault.paramsById(1);

        SirStructs.OracleState memory state = IOracle(oracle).state(vaultParams.collateralToken, vaultParams.debtToken);
        console.log("Uniswap fee tier: ", state.uniswapFeeTier.fee);

        uint24 feeTier = IOracle(oracle).uniswapFeeTierOf(vaultParams.collateralToken, vaultParams.debtToken);
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
