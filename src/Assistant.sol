// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import {IQuoter} from "./IQuoter.sol";
import {IVault} from "core/interfaces/IVault.sol";
import {IOracle} from "core/interfaces/IOracle.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";

// Contracts and libraries
import {SirStructs} from "core/libraries/SirStructs.sol";
import {SystemConstants} from "core/libraries/SystemConstants.sol";
import {FullMath} from "core/libraries/FullMath.sol";
import {IWETH9, IERC20} from "core/interfaces/IWETH9.sol";
import {UniswapPoolAddress} from "core/libraries/UniswapPoolAddress.sol";
import {AddressClone} from "core/libraries/AddressClone.sol";

import "forge-std/console.sol";

/** @notice Helper functions for SIR protocol
 */
contract Assistant {
    IVault public immutable VAULT;
    IOracle private immutable SIR_ORACLE;
    address private immutable UNISWAPV3_FACTORY;
    IQuoter private immutable UNISWAPV3_QUOTER;

    error VaultDoesNotExist();
    error AmountTooLow();
    error TooMuchCollateral();
    error TEAMaxSupplyExceeded();

    enum VaultStatus {
        InvalidVault,
        NoUniswapPool,
        VaultCanBeCreated,
        VaultAlreadyExists
    }

    constructor(address vault, address oracle, address uniswapV3Factory) {
        VAULT = IVault(vault);
        SIR_ORACLE = IOracle(oracle);
        UNISWAPV3_FACTORY = uniswapV3Factory;

        if (block.chainid == 1) UNISWAPV3_QUOTER = IQuoter(0x5e55C9e631FAE526cd4B0526C4818D6e0a9eF0e3);
        else if (block.chainid == 11155111) UNISWAPV3_QUOTER = IQuoter(0xe3c07ebF66b9D070b589bCCa30903891F71A92Be);
        else revert("Network not supported");
    }

    function getReserves(uint48[] calldata vaultIds) external view returns (SirStructs.Reserves[] memory reserves) {
        reserves = new SirStructs.Reserves[](vaultIds.length);
        SirStructs.VaultParameters memory vaultParams;
        for (uint256 i = 0; i < vaultIds.length; i++) {
            vaultParams = VAULT.paramsById(vaultIds[i]);
            reserves[i] = VAULT.getReserves(vaultParams);
        }
    }

    /** @notice It returns the ideal price of TEA.
        @notice To get the price as [units of Collateral][per unit of TEA], divide num by den.
     */
    function priceOfTEA(
        SirStructs.VaultParameters calldata vaultParams
    ) external view returns (uint256 num, uint256 den) {
        // Get current reserves
        SirStructs.Reserves memory reserves = VAULT.getReserves(vaultParams);
        num = reserves.reserveLPers;

        // Get supply of TEA
        SirStructs.VaultState memory vaultState = VAULT.vaultStates(vaultParams);
        den = VAULT.totalSupply(vaultState.vaultId);
    }

    /** @notice It returns the ideal price of APE if there were no fees for withdrawing.
        @notice To get the price as [units of Collateral][per unit of APE], divide num by den.
     */
    function priceOfAPE(
        SirStructs.VaultParameters calldata vaultParams
    ) external view returns (uint256 num, uint256 den) {
        // Get current reserves
        SirStructs.Reserves memory reserves = VAULT.getReserves(vaultParams);
        num = reserves.reserveApes;

        // Get supply of APE
        SirStructs.VaultState memory vaultState = VAULT.vaultStates(vaultParams);
        den = IERC20(getAddressAPE(vaultState.vaultId)).totalSupply();
    }

    function getVaultStatus(SirStructs.VaultParameters calldata vaultParams) external view returns (VaultStatus) {
        // Check if the token addresses are a smart contract
        if (vaultParams.collateralToken.code.length == 0) return VaultStatus.InvalidVault;
        if (vaultParams.debtToken.code.length == 0) return VaultStatus.InvalidVault;

        // Check if the token returns total supply
        (bool success, ) = vaultParams.collateralToken.staticcall(abi.encodeWithSelector(IERC20.totalSupply.selector));
        if (!success) return VaultStatus.InvalidVault;
        (success, ) = vaultParams.debtToken.staticcall(abi.encodeWithSelector(IERC20.totalSupply.selector));
        if (!success) return VaultStatus.InvalidVault;

        // Check if the leverage tier is valid
        if (
            vaultParams.leverageTier < SystemConstants.MIN_LEVERAGE_TIER ||
            vaultParams.leverageTier > SystemConstants.MAX_LEVERAGE_TIER
        ) return VaultStatus.InvalidVault;

        // Check if a Uniswap pool exists
        if (
            !_checkFeeTierExists(vaultParams, 100) &&
            !_checkFeeTierExists(vaultParams, 500) &&
            !_checkFeeTierExists(vaultParams, 3000) &&
            !_checkFeeTierExists(vaultParams, 10000)
        ) return VaultStatus.NoUniswapPool;

        // Check if vault already exists
        SirStructs.VaultState memory vaultState = VAULT.vaultStates(vaultParams);
        if (vaultState.vaultId == 0) return VaultStatus.VaultCanBeCreated;
        return VaultStatus.VaultAlreadyExists;
    }

    function getAddressAPE(uint48 vaultId) public view returns (address) {
        return AddressClone.getAddress(address(VAULT), vaultId);
    }

    /*////////////////////////////////////////////////////////////////
                            SIMULATION FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /** @notice It returns the amount of TEA/APE tokens that would be obtained by depositing collateral token
        @dev Static function so we do not need to save on SLOADs
        @dev If quoteMint reverts, mint will revert as well; vice versa is not necessarily true.
        @return amountTokens that would be obtained by depositing amountCollateral
     */
    function quoteMint(
        bool isAPE,
        SirStructs.VaultParameters calldata vaultParams,
        uint144 amountCollateral
    ) public view returns (uint256 amountTokens) {
        // Get vault state
        SirStructs.VaultState memory vaultState = VAULT.vaultStates(vaultParams);
        if (vaultState.vaultId == 0) revert VaultDoesNotExist();
        if (amountCollateral == 0) revert AmountTooLow();

        // Get current reserves
        SirStructs.Reserves memory reserves = VAULT.getReserves(vaultParams);

        SirStructs.SystemParameters memory systemParams = VAULT.systemParams();
        if (isAPE) {
            // Compute how much collateral actually gets deposited
            uint256 feeNum;
            uint256 feeDen;
            if (vaultParams.leverageTier >= 0) {
                feeNum = 10000; // baseFee is uint16, leverageTier is int8, so feeNum does not require more than 24 bits
                feeDen = 10000 + (uint256(systemParams.baseFee.fee) << uint8(vaultParams.leverageTier));
            } else {
                uint256 temp = 10000 << uint8(-vaultParams.leverageTier);
                feeNum = temp;
                feeDen = temp + uint256(systemParams.baseFee.fee);
            }

            // Get collateralIn
            uint256 collateralIn = (uint256(amountCollateral) * feeNum) / feeDen;

            // Get supply of APE
            address ape = getAddressAPE(vaultState.vaultId);
            uint256 supplyAPE = IERC20(ape).totalSupply();

            // Calculate tokens
            amountTokens = supplyAPE == 0
                ? collateralIn + reserves.reserveApes
                : FullMath.mulDiv(supplyAPE, collateralIn, reserves.reserveApes);
        } else {
            // Compute how much collateral actually gets deposited
            uint256 feeNum = 10000;
            uint256 feeDen = 10000 + uint256(systemParams.lpFee.fee);

            // Get supply of TEA
            uint256 supplyTEA = VAULT.totalSupply(vaultState.vaultId);

            // Calculate tokens
            amountTokens = supplyTEA == 0
                ? _amountFirstMint(vaultParams.collateralToken, amountCollateral + reserves.reserveLPers)
                : FullMath.mulDiv(supplyTEA, amountCollateral, reserves.reserveLPers);

            // Check that total supply does not overflow
            if (amountTokens > SystemConstants.TEA_MAX_SUPPLY - supplyTEA) revert TEAMaxSupplyExceeded();

            // Get collateralIn
            uint256 collateralIn = uint144((uint256(amountCollateral) * feeNum) / feeDen);

            // Minter's share of TEA
            amountTokens = FullMath.mulDiv(
                amountTokens,
                collateralIn,
                supplyTEA == 0
                    ? amountCollateral + reserves.reserveLPers // In the first mint, reserveLPers contains orphaned fees from apes
                    : amountCollateral
            );
        }

        if (amountTokens == 0) revert AmountTooLow();
    }

    /** @notice It returns the amount of TEA/APE tokens that would be obtained by depositing debt token
        @dev Static function
        @dev If quoteMint reverts, mint will revert as well; vice versa is not necessarily true.
        @return amountTokens that would be obtained
     */
    function quoteMintWithDebtToken(
        bool isAPE,
        SirStructs.VaultParameters calldata vaultParams,
        uint256 amountDebtToken
    ) external view returns (uint256 amountTokens, uint256 amountCollateral) {
        if (amountDebtToken == 0) revert AmountTooLow();

        // Get fee tier
        uint24 feeTier = SIR_ORACLE.uniswapFeeTierOf(vaultParams.debtToken, vaultParams.collateralToken);

        // Quote Uniswap v3
        (amountCollateral, , , ) = UNISWAPV3_QUOTER.quoteExactInputSingle(
            IQuoter.QuoteExactInputSingleParams({
                tokenIn: vaultParams.debtToken,
                tokenOut: vaultParams.collateralToken,
                amountIn: amountDebtToken,
                fee: feeTier,
                sqrtPriceLimitX96: 0
            })
        );

        // Check that amountCollateral does not overflow
        if (amountCollateral > type(uint144).max) revert TooMuchCollateral();

        // Given that we know how much collateral we will get from Uniswap, we can now use the quoteMint function
        amountTokens = quoteMint(isAPE, vaultParams, uint144(amountCollateral));
    }

    function quoteCollateralToDebtToken(
        address debtToken,
        address collateralToken,
        uint256 amountCollateral
    ) external view returns (uint256 amountDebtToken) {
        // Get Uniswap pool
        address uniswapPool = SIR_ORACLE.uniswapFeeTierAddressOf(debtToken, collateralToken);

        // Get current price
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(uniswapPool).slot0();

        // Calculate price fraction with better precision if it doesn't overflow when multiplied by itself
        bool inverse = collateralToken == IUniswapV3Pool(uniswapPool).token1();
        if (sqrtPriceX96 <= type(uint128).max) {
            uint256 priceX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
            return
                !inverse
                    ? FullMath.mulDiv(priceX192, amountCollateral, 1 << 192)
                    : FullMath.mulDiv(1 << 192, amountCollateral, priceX192);
        } else {
            uint256 priceX128 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 64);
            return
                !inverse
                    ? FullMath.mulDiv(priceX128, amountCollateral, 1 << 128)
                    : FullMath.mulDiv(1 << 128, amountCollateral, priceX128);
        }
    }

    /** @dev Static function so we do not need to save on SLOADs
        @dev If quoteBurn reverts, burn in Vault.sol will revert as well; vice versa is not necessarily true.
        @return amountCollateral that would be obtained by burning amountTokens
     */
    function quoteBurn(
        bool isAPE,
        SirStructs.VaultParameters calldata vaultParams,
        uint256 amountTokens
    ) external view returns (uint144 amountCollateral) {
        // Get vault state
        SirStructs.VaultState memory vaultState = VAULT.vaultStates(vaultParams);
        if (vaultState.vaultId == 0) revert VaultDoesNotExist();
        if (amountTokens == 0) revert AmountTooLow();

        // Get current reserves
        SirStructs.Reserves memory reserves = VAULT.getReserves(vaultParams);

        if (isAPE) {
            // Get supply of APE
            address ape = getAddressAPE(vaultState.vaultId);
            uint256 supplyAPE = IERC20(ape).totalSupply();

            // Get collateralOut
            uint256 collateralOut = uint144(FullMath.mulDiv(reserves.reserveApes, amountTokens, supplyAPE));

            // Compute collateral withdrawn
            SirStructs.SystemParameters memory systemParams = VAULT.systemParams();
            uint256 feeNum;
            uint256 feeDen;
            if (vaultParams.leverageTier >= 0) {
                feeNum = 10000;
                feeDen = 10000 + (uint256(systemParams.baseFee.fee) << uint8(vaultParams.leverageTier));
            } else {
                uint256 temp = 10000 << uint8(-vaultParams.leverageTier);
                feeNum = temp;
                feeDen = temp + uint256(systemParams.baseFee.fee);
            }

            // Get collateral withdrawn
            amountCollateral = uint144((collateralOut * feeNum) / feeDen);
        } else {
            // Get supply of TEA
            uint256 supplyTEA = VAULT.totalSupply(vaultState.vaultId);

            // Get amount of collateral that would be withdrawn
            amountCollateral = uint144(FullMath.mulDiv(reserves.reserveLPers, amountTokens, supplyTEA));
        }
    }

    /*////////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function _checkFeeTierExists(
        SirStructs.VaultParameters calldata vaultParams,
        uint24 feeTier
    ) private view returns (bool) {
        return
            UniswapPoolAddress
                .computeAddress(
                    UNISWAPV3_FACTORY,
                    UniswapPoolAddress.getPoolKey(vaultParams.collateralToken, vaultParams.debtToken, feeTier)
                )
                .code
                .length != 0;
    }

    function _amountFirstMint(address collateral, uint144 collateralDeposited) private view returns (uint256 amount) {
        uint256 collateralTotalSupply = IERC20(collateral).totalSupply();
        amount = collateralTotalSupply > SystemConstants.TEA_MAX_SUPPLY / 1e6
            ? FullMath.mulDiv(SystemConstants.TEA_MAX_SUPPLY, collateralDeposited, collateralTotalSupply)
            : collateralDeposited * 1e6;
    }
}
