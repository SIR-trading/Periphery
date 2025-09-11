// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {IVault} from "core/interfaces/IVault.sol";
import {Assistant} from "src/Assistant.sol";
import {SirStructs} from "core/libraries/SirStructs.sol";

contract QuoteReserves is Script {
    IVault public vault;
    Assistant public assistant;

    function setUp() public {
        if (block.chainid != 998 && block.chainid != 999) {
            revert("Network not supported. Use chain 998 (testnet) or 999 (mainnet)");
        }
        
        vault = IVault(vm.envAddress("VAULT"));
        assistant = Assistant(vm.envAddress("ASSISTANT"));
    }

    /** @dev cli for HyperEVM testnet with big blocks:
            BB_GAS=$(cast rpc --rpc-url hypertest eth_bigBlockGasPrice | tr -d '"' | cast to-dec)
            forge script script/QuoteReserves.s.sol --rpc-url hypertest --chain 998 --broadcast --ledger --hd-paths "m/44'/60'/0'/0/0" --with-gas-price $BB_GAS --slow
        @dev cli for HyperEVM mainnet with big blocks:
            BB_GAS=$(cast rpc --rpc-url hyperevm eth_bigBlockGasPrice | tr -d '"' | cast to-dec)
            forge script script/QuoteReserves.s.sol --rpc-url hyperevm --chain 999 --broadcast --ledger --hd-paths "m/44'/60'/0'/0/0" --with-gas-price $BB_GAS --slow
     */
    function run() public {
        vm.startBroadcast();

        uint48 Nvaults = vault.numberOfVaults();
        console.log("Number of vaults: ", Nvaults);

        // Quote all vaults
        uint48[] memory vaultIds = new uint48[](Nvaults);
        for (uint48 i = 0; i < Nvaults; i++) {
            vaultIds[i] = i + 1;
        }
        SirStructs.Reserves[] memory reserves = assistant.getReserves(vaultIds);

        // Print reserves
        for (uint48 i = 0; i < Nvaults; i++) {
            console.log(vaultIds[i], reserves[i].reserveApes, reserves[i].reserveLPers);
        }

        vm.stopBroadcast();
    }
}
