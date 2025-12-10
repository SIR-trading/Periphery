// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

// Contracts
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {IVault} from "core/interfaces/IVault.sol";
import {ISIR} from "core/interfaces/ISIR.sol";
import {SirStructs} from "core/libraries/SirStructs.sol";
import {TreasuryV1} from "src/TreasuryV1.sol";

import "forge-std/Script.sol";

/// @dev cli for MegaETH testnet:  forge script script/TreasuryMint.s.sol --rpc-url megatest --chain 6343 --broadcast
contract TreasuryMint is Script {
    uint256 privateKey;

    address sir;
    TreasuryV1 treasury;

    function setUp() public {
        if (block.chainid == 6343) {
            privateKey = vm.envUint("MEGAETH_DEPLOYER_PRIVATE_KEY");
        } else if (block.chainid != 6342) {
            revert("Network not supported");
        }

        IVault vault = IVault(vm.envAddress("VAULT"));
        sir = vault.SIR();
        treasury = TreasuryV1(vm.envAddress("TREASURY"));
    }

    function run() public {
        if (block.chainid == 6342) vm.startBroadcast();
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
        console.log("Minted SIR rewards:", rewards / 1e12);

        // Log final balance
        uint256 treasuryBalanceAfter = IERC20(sir).balanceOf(address(treasury));
        console.log("Treasury SIR balance after mint:", treasuryBalanceAfter / 1e12);
        console.log("SIR tokens minted:", (treasuryBalanceAfter - treasuryBalanceBefore) / 1e12);

        vm.stopBroadcast();
    }
}
