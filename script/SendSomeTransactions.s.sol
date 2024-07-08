// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
// import "forge-std/console.sol";

import {Assistant} from "src/Assistant.sol";
import {SirStructs} from "core/libraries/SirStructs.sol";
import {Addresses} from "core/libraries/Addresses.sol";
import {IVault} from "core/interfaces/IVault.sol";
import {SaltedAddress} from "core/libraries/SaltedAddress.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract SendSomeTransactions is Script {
    Assistant public assistant;

    function setUp() public {
        assistant = Assistant(vm.envAddress("ASSISTANT"));
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("TARP_TESTNET_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Address of the Vault contract
        IVault vault = assistant.VAULT();
        console.log("Vault address: ", address(vault));

        // Quote mint
        uint256 amountTokens = assistant.quoteMint(
            true,
            SirStructs.VaultParameters({
                debtToken: Addresses.ADDR_USDT,
                collateralToken: Addresses.ADDR_WETH,
                leverageTier: int8(-2)
            }),
            950000000000000000
        );
        console.log("Quote mint amount: ", amountTokens);

        // // Address of APE
        // (, , uint48 vaultId) = vault.vaultStates(Addresses.ADDR_USDT, Addresses.ADDR_WETH, int8(-2));
        // console.log("Vault ID: ", vaultId);
        // address ape = assistant.getAddressAPE(address(vault), vaultId);
        // console.log("APE address: ", ape);

        // // Total supplies
        // uint256 totalSupplyOfAPE = IERC20(ape).totalSupply();
        // console.log("Total supply of APE: ", totalSupplyOfAPE);
        // uint256 totalSupplyOfTEA = vault.totalSupply(vaultId);
        // console.log("Total supply of TEA: ", totalSupplyOfTEA);

        // // Attempt to mint APE
        // IERC20(Addresses.ADDR_WETH).approve(address(assistant), 950000000000000000);
        // uint256 amountTokens = assistant.mint(
        //     ape,
        //     vaultId,
        //     SirStructs.VaultParameters({
        //         debtToken: Addresses.ADDR_USDT,
        //         collateralToken: Addresses.ADDR_WETH,
        //         leverageTier: int8(-2)
        //     }),
        //     950000000000000000
        // );
        // console.log("Mint amount: ", amountTokens);

        vm.stopBroadcast();
    }
}
