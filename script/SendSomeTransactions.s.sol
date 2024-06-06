// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
// import "forge-std/console.sol";

import {Assistant} from "src/Assistant.sol";
import {VaultStructs} from "core/libraries/VaultStructs.sol";
import {Addresses} from "core/libraries/Addresses.sol";
import {Vault} from "core/Vault.sol";
import {SaltedAddress} from "core/libraries/SaltedAddress.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract SendSomeTransactions is Script {
    Assistant constant ASSISTANT = Assistant(0xf975A646FCa589Be9fc4E0C28ea426A75645fB1f);

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("TARP_TESTNET_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Address of the Vault contract
        Vault vault = ASSISTANT.vault();
        console.log("Vault address: ", address(vault));

        // // Quote mint
        // uint256 amountTokens = ASSISTANT.quoteMint(
        //     true,
        //     VaultStructs.VaultParameters({
        //         debtToken: Addresses.ADDR_USDT,
        //         collateralToken: Addresses.ADDR_WETH,
        //         leverageTier: int8(-2)
        //     }),
        //     950000000000000000
        // );
        // console.log("Quote mint amount: ", amountTokens);

        // Address of APE
        (, , uint48 vaultId) = vault.vaultStates(Addresses.ADDR_USDT, Addresses.ADDR_WETH, int8(-2));
        console.log("Vault ID: ", vaultId);
        address ape = SaltedAddress.getAddress(address(vault), vaultId);
        console.log("APE address: ", ape);

        // Total supplies
        uint256 totalSupplyOfAPE = IERC20(ape).totalSupply();
        console.log("Total supply of APE: ", totalSupplyOfAPE);
        uint256 totalSupplyOfTEA = vault.totalSupply(vaultId);
        console.log("Total supply of TEA: ", totalSupplyOfTEA);

        // // Attempt to mint APE
        // IERC20(Addresses.ADDR_WETH).approve(address(ASSISTANT), 950000000000000000);
        // uint256 amountTokens = ASSISTANT.mint(
        //     ape,
        //     vaultId,
        //     VaultStructs.VaultParameters({
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
