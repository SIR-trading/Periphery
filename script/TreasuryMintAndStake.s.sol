// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {Vault} from "core/Vault.sol";
import {ISIR} from "core/interfaces/ISIR.sol";
import {SirStructs} from "core/libraries/SirStructs.sol";
import {Addresses} from "core/libraries/Addresses.sol";
import {TreasuryV1} from "src/TreasuryV1.sol";

import "forge-std/Script.sol";

/// @dev cli for mainnet:  forge script script/TreasuryMintAndStake.s.sol --rpc-url mainnet --chain 1 --broadcast --verify --ledger --hd-paths HD_PATH
/// @dev cli for Sepolia:  forge script script/TreasuryMintAndStake.s.sol --rpc-url sepolia --chain sepolia --broadcast
contract TreasuryMintAndStake is Script {
    uint256 privateKey;

    address vault;
    address sir;
    TreasuryV1 treasury;

    function setUp() public {
        if (block.chainid == 11155111) {
            privateKey = vm.envUint("SEPOLIA_DEPLOYER_PRIVATE_KEY");
        } else if (block.chainid != 1) {
            revert("Network not supported");
        }

        vault = vm.envAddress("VAULT");
        sir = vm.envAddress("SIR");
        treasury = TreasuryV1(vm.envAddress("TREASURY"));
    }

    function run() public {
        if (block.chainid == 1) vm.startBroadcast();
        else vm.startBroadcast(privateKey);

        // Mint SIR tokens
        uint80 rewards = bytesToUint80(treasury.relayCall(sir, abi.encodeWithSelector(ISIR.contributorMint.selector)));

        // Approve vault to spend SIR tokens
        treasury.relayCall(sir, abi.encodeWithSelector(ISIR.approve.selector, vault, type(uint256).max));

        // Mint TEA in vault SIR/WETH^1.5
        treasury.relayCall(
            vault,
            abi.encodeWithSelector(
                Vault.mint.selector,
                false,
                SirStructs.VaultParameters({debtToken: sir, collateralToken: Addresses.ADDR_WETH, leverageTier: -2}),
                rewards,
                0
            )
        );

        vm.stopBroadcast();
    }

    function bytesToUint80(bytes memory data) public pure returns (uint80 result) {
        require(data.length == 10, "Input must be 10 bytes");

        assembly {
            // Load the 10 bytes into the higher bits of a 32-byte word
            let bytesValue := mload(add(data, 0x20)) // Load first 32 bytes (includes 10 data bytes + 22 zeros)
            // Shift right to align the 10 bytes to the lower 80 bits
            result := shr(176, bytesValue) // 22 bytes = 176 bits (32 - 10 = 22)
        }

        // Ensure the result is within uint80 range (optional safety check)
        require(result <= (1 << 80) - 1, "Value exceeds uint80 range");
        return uint80(result);
    }
}
