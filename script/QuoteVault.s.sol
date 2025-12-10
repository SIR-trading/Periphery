// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {IVault} from "core/interfaces/IVault.sol";
import {IOracle} from "core/interfaces/IOracle.sol";
import {Assistant} from "src/Assistant.sol";
import {SirStructs} from "core/libraries/SirStructs.sol";

/** @dev cli for MegaETH testnet:  forge script script/QuoteVault.s.sol --rpc-url megatest --chain 6343 --broadcast
*/
contract QuoteVault is Script {
    uint256 deployerPrivateKey;

    IVault public vault;
    address public oracle;
    Assistant public assistant;

    function setUp() public {
        if (block.chainid == 6343) {
            deployerPrivateKey = vm.envUint("MEGAETH_DEPLOYER_PRIVATE_KEY");
        } else if (block.chainid != 6342) {
            revert("Network not supported");
        }

        vault = IVault(vm.envAddress("VAULT"));
        oracle = vault.ORACLE();
        assistant = Assistant(vm.envAddress("ASSISTANT"));
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        SirStructs.VaultParameters memory vaultParams = vault.paramsById(1);

        SirStructs.OracleState memory state = IOracle(oracle).state(vaultParams.collateralToken, vaultParams.debtToken);
        console.log("Uniswap fee tier: ", state.uniswapFeeTier.fee);

        uint24 feeTier = IOracle(oracle).uniswapFeeTierOf(vaultParams.collateralToken, vaultParams.debtToken);
        console.log("Uniswap fee tier: ", feeTier);

        // Quote vault id 1
        (uint256 amountTokens, uint256 amountCollateral, uint256 amountCollateralIdeal) = assistant
            .quoteMintWithDebtToken(false, vaultParams, 995896400000000000000);

        console.log("Minting expects: ", amountTokens);
        console.log("Uniswap swap returns: ", amountCollateral);
        console.log("Uniswap swap would return without slippage: ", amountCollateralIdeal);

        vm.stopBroadcast();
    }
}
