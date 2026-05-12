// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Script.sol";

import {UniswapV3Staker} from "v3-staker/UniswapV3Staker.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {PoolAddress} from "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";

/** WARNING: Different V3 deployments use different POOL_INIT_CODE_HASHes.
    Set poolInitCodeHash to match your target factory. If it differs from the hash compiled into
    PoolAddress.sol (lib/v3-staker/node_modules/.../libraries/PoolAddress.sol),
    you must patch PoolAddress.sol before deploying.

    cli for MegaETH testnet:
        forge script script/DeployUniswapV3Staker.s.sol --rpc-url megatest --broadcast --private-key $PRIVATE_KEY --skip-simulation \
        --gas-price 10000000 --priority-gas-price 1000000 --gas-limit 5000000000 --slow
    cli for MegaETH mainnet:
        forge script script/DeployUniswapV3Staker.s.sol --rpc-url megaeth --broadcast --ledger --hd-paths $HD_PATH \
        --gas-price 1200000 --priority-gas-price 100000 --gas-limit 5000000000 --skip-simulation
*/
contract DeployUniswapV3Staker is Script {
    // ---- Configure these before deploying ----
    IUniswapV3Factory public factory = IUniswapV3Factory(0x68b34591f662508076927803c567Cc8006988a09);
    INonfungiblePositionManager public nonfungiblePositionManager =
        INonfungiblePositionManager(0x2b781C57e6358f64864Ff8EC464a03Fdaf9974bA);
    bytes32 public poolInitCodeHash = 0x851d77a45b8b9a205fb9f44cb829cceba85282714d2603d601840640628a3da7;

    uint256 public maxIncentiveStartLeadTime = 2592000; // 30 days
    uint256 public maxIncentiveDuration = 63072000; // 2 years (730 days)

    function _getChainId() internal pure returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }

    function setUp() public {
        uint256 chainId = _getChainId();
        require(chainId == 6343 || chainId == 4326, "Only MegaETH is currently supported");
        require(address(factory) != address(0), "Set factory address");
        require(address(nonfungiblePositionManager) != address(0), "Set nonfungiblePositionManager address");
        require(poolInitCodeHash != bytes32(0), "Set poolInitCodeHash");
        require(
            poolInitCodeHash == PoolAddress.POOL_INIT_CODE_HASH,
            "poolInitCodeHash != PoolAddress.POOL_INIT_CODE_HASH - patch PoolAddress.sol"
        );
    }

    function run() public {
        vm.startBroadcast();

        address staker = address(
            new UniswapV3Staker(factory, nonfungiblePositionManager, maxIncentiveStartLeadTime, maxIncentiveDuration)
        );
        console.log("UniswapV3Staker deployed at: ", staker);

        vm.stopBroadcast();
    }
}
