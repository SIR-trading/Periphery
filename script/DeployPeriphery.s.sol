// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {Assistant} from "src/Assistant.sol";
import {Addresses} from "core/libraries/Addresses.sol";

contract DeployPeriphery is Script {
    address public constant VAULT = 0x2ca60d89144D4cdf85dA87af4FE12aBF9265F28C;
    bytes32 public constant HASH_CREATION_CODE_APE = 0x47506ce687e7393e061a27c5920877ca8b32056ab3feb8b417367524455546de;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("TARP_TESTNET_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy oracle
        address assistant = address(new Assistant(Addresses.ADDR_UNISWAPV3_SWAP_ROUTER, VAULT, HASH_CREATION_CODE_APE));
        console.log("Assistant deployed at: ", assistant);

        vm.stopBroadcast();
    }
}
