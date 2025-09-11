// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

// Contracts
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {IVault} from "core/interfaces/IVault.sol";
import {ISIR} from "core/interfaces/ISIR.sol";
import {SirStructs} from "core/libraries/SirStructs.sol";
import {AddressesHyperEVM} from "core/libraries/AddressesHyperEVM.sol";
import {TreasuryV1} from "src/TreasuryV1.sol";

import "forge-std/Script.sol";

/// @dev cli for HyperEVM testnet with big blocks:
///     BB_GAS=$(cast rpc --rpc-url hypertest eth_bigBlockGasPrice | tr -d '"' | cast to-dec)
///     forge script script/TreasuryMint.s.sol --rpc-url hypertest --chain 998 --broadcast --ledger --hd-paths "m/44'/60'/0'/0/0" --with-gas-price $BB_GAS --slow
/// @dev cli for HyperEVM mainnet with big blocks:
///     BB_GAS=$(cast rpc --rpc-url hyperevm eth_bigBlockGasPrice | tr -d '"' | cast to-dec)
///     forge script script/TreasuryMint.s.sol --rpc-url hyperevm --chain 999 --broadcast --ledger --hd-paths "m/44'/60'/0'/0/0" --with-gas-price $BB_GAS --slow
contract TreasuryMint is Script {
    IVault vault;
    address sir;
    TreasuryV1 treasury;

    function setUp() public {
        if (block.chainid != 998 && block.chainid != 999) {
            revert("Network not supported. Use chain 998 (testnet) or 999 (mainnet)");
        }
        
        vault = IVault(vm.envAddress("VAULT"));
        sir = vault.SIR();
        treasury = TreasuryV1(vm.envAddress("TREASURY"));
    }

    function run() public {
        vm.startBroadcast();

        // Log initial balances
        uint256 treasuryBalanceBefore = IERC20(sir).balanceOf(address(treasury));
        console.log("Treasury SIR balance before mint:", treasuryBalanceBefore);
        console.log("Treasury address:", address(treasury));
        console.log("SIR token address:", sir);

        // Mint SIR tokens through treasury's relayCall
        console.log("Calling contributorMint through treasury...");
        bytes memory result = treasury.relayCall(sir, abi.encodeWithSelector(ISIR.contributorMint.selector));
        
        // Decode the returned uint256 value
        uint256 rewards = abi.decode(result, (uint256));
        console.log("Minted SIR rewards:", rewards);

        // Log final balance
        uint256 treasuryBalanceAfter = IERC20(sir).balanceOf(address(treasury));
        console.log("Treasury SIR balance after mint:", treasuryBalanceAfter);
        console.log("SIR tokens minted:", treasuryBalanceAfter - treasuryBalanceBefore);

        vm.stopBroadcast();
    }
}
