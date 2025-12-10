// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {IVault} from "core/interfaces/IVault.sol";
import {Assistant} from "src/Assistant.sol";
import {SirStructs} from "core/libraries/SirStructs.sol";

/** @dev cli for MegaETH testnet:  forge script script/QuoteReserves.s.sol --rpc-url megatest --chain 6343 --broadcast
*/
contract QuoteReserves is Script {
    uint256 privateKey;

    IVault public vault;
    Assistant public assistant;

    function setUp() public {
        if (block.chainid == 6343) {
            privateKey = vm.envUint("MEGAETH_DEPLOYER_PRIVATE_KEY");
        } else if (block.chainid != 6342) {
            revert("Network not supported");
        }

        vault = IVault(vm.envAddress("VAULT"));
        assistant = Assistant(vm.envAddress("ASSISTANT"));
    }

    function run() public {
        vm.startBroadcast(privateKey);

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
