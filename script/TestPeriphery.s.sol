// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
// import "forge-std/console.sol";

import {Assistant} from "src/Assistant.sol";
import {VaultStructs} from "core/libraries/VaultStructs.sol";
import {Addresses} from "core/libraries/Addresses.sol";

contract TestPeriphery is Script {
    Assistant constant ASSISTANT = Assistant(0xACB5b53F9F193b99bcd8EF8544ddF4c398DE24a3);

    VaultStructs.VaultParameters public vaultParameters =
        VaultStructs.VaultParameters({
            debtToken: Addresses.ADDR_USDT,
            collateralToken: Addresses.ADDR_WETH,
            leverageTier: int8(-1)
        });

    uint256 public amountCollateral = 1 ether;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("TARP_TESTNET_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("Minting with", amountCollateral, "collateral");
        uint256 amountTEA = ASSISTANT.quoteMint(false, vaultParameters, 1 ether);
        console.log("Expected amount of TEA received: ", amountTEA);

        vm.stopBroadcast();
    }
}
