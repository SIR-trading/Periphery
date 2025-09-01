// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

// Contracts
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {IVault} from "core/interfaces/IVault.sol";
import {ISIR} from "core/interfaces/ISIR.sol";
import {SirStructs} from "core/libraries/SirStructs.sol";
import {Addresses} from "core/libraries/Addresses.sol";
import {TreasuryV1} from "src/TreasuryV1.sol";

import "forge-std/Script.sol";

/// @dev cli for mainnet:  forge script script/TreasuryMint.s.sol --rpc-url mainnet --chain 1 --broadcast --verify --ledger --hd-paths HD_PATH
/// @dev cli for Sepolia:  forge script script/TreasuryMint.s.sol --rpc-url sepolia --chain sepolia --broadcast
contract TreasuryMint is Script {
    uint256 privateKey;

    IVault vault;
    address sir;
    TreasuryV1 treasury;

    function setUp() public {
        if (block.chainid == 11155111) {
            privateKey = vm.envUint("SEPOLIA_DEPLOYER_PRIVATE_KEY");
        } else if (block.chainid != 1) {
            revert("Network not supported");
        }

        vault = IVault(vm.envAddress("VAULT"));
        sir = vault.SIR();
        treasury = TreasuryV1(vm.envAddress("TREASURY"));
    }

    function run() public {
        if (block.chainid == 1) vm.startBroadcast();
        else vm.startBroadcast(privateKey);

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
