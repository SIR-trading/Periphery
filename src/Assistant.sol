// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vault} from "core/Vault.sol";
import {VaultStructs} from "core/libraries/VaultStructs.sol";
import {SystemConstants} from "core/libraries/SystemConstants.sol";
import {Fees} from "core/libraries/Fees.sol";
import {FullMath} from "core/libraries/FullMath.sol";
import {TransferHelper} from "core/libraries/TransferHelper.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {ERC1155, ERC1155TokenReceiver} from "solmate/tokens/ERC1155.sol";
import {IWETH9, IERC20} from "core/interfaces/IWETH9.sol";
import {Addresses} from "core/libraries/Addresses.sol";

import "forge-std/console.sol";

/** @notice This contract must be approved to spend tokens. I recommend requesting 2^256-1 token
    @notice approval so that the user only needs to do it once per address.
    @dev More gas-efficient version of this contract would inherit SwapRouter rather than calling the external SWAP_ROUTER
    @dev No burn function because the burn function in Vault can be called directly
 */
contract Assistant is ERC1155TokenReceiver {
    // ASSISTANT WOULD BENEFIT OF A SPECIAL FUNCTION FOR VANILLA ETH SO THAT THE USER DOES NOT NEED TO (UN)WRAP ETH INTO WETH
    // COULD CONSIDER JUST PASSING vaultId TO VAULT MINT/BURN FUNCTIONS

    error VaultDoesNotExist();
    error CollateralIsNotWETH();
    error NoETHSent();

    IWETH9 private constant WETH = IWETH9(Addresses.ADDR_WETH);

    bytes32 public immutable HASH_CREATION_CODE_APE;

    ISwapRouter public immutable SWAP_ROUTER; // Uniswap V3 SwapRouter
    Vault public immutable VAULT;

    constructor(address swapRouter_, address vault_, bytes32 hashCreationCodeAPE) {
        SWAP_ROUTER = ISwapRouter(swapRouter_);
        VAULT = Vault(vault_);
        HASH_CREATION_CODE_APE = hashCreationCodeAPE;
    }

    /** @notice This contract must be approved to spend collateral tokens.
     */
    function mint(
        address ape, // Address of the APE token, or address(0) if TEA
        uint256 vaultId, // 0 if APE
        VaultStructs.VaultParameters calldata vaultParams,
        uint144 amountCollateral
    ) public returns (uint256 amountTokens) {
        // Transfer collateral from user to VAULT
        TransferHelper.safeTransferFrom(vaultParams.collateralToken, msg.sender, address(VAULT), amountCollateral);

        // Mint TEA or APE
        bool isAPE = ape != address(0);
        amountTokens = VAULT.mint(isAPE, vaultParams);

        // Because this contract called mint. The tokens are now here and need to be transfered to the user
        if (isAPE) {
            IERC20(ape).transfer(msg.sender, amountTokens); // No need for TransferHelper because APE is our own token
        } else {
            ERC1155(address(VAULT)).safeTransferFrom(address(this), msg.sender, vaultId, amountTokens, "");
        }
    }

    function mintWithETH(
        address ape, // Address of the APE token, or address(0) if TEA
        uint256 vaultId, // 0 if APE
        VaultStructs.VaultParameters calldata vaultParams
    ) external payable returns (uint256 amountTokens) {
        if (vaultParams.collateralToken != Addresses.ADDR_WETH) revert CollateralIsNotWETH();

        // We use balance in case there is some forgotten ETH in the contract
        uint256 balanceOfETH = address(this).balance;
        if (balanceOfETH == 0) revert NoETHSent();

        // Wrap ETH into WETH
        WETH.deposit{value: balanceOfETH}();

        // Transfer WETH to the vault
        WETH.transfer(address(VAULT), balanceOfETH);

        // Mint TEA or APE
        bool isAPE = ape != address(0);
        amountTokens = VAULT.mint(isAPE, vaultParams);

        // Because this contract called mint. The tokens are now here and need to be transfered to the user
        if (isAPE) {
            IERC20(ape).transfer(msg.sender, amountTokens); // No need for TransferHelper because APE is our own token
        } else {
            ERC1155(address(VAULT)).safeTransferFrom(address(this), msg.sender, vaultId, amountTokens, "");
        }
    }

    /** @notice This contract must be approved to spend debt tokens
        @notice This function requires knowing the market price of the debt token in terms of collateral to choose a sensible minDebtToken
     */
    function swapAndMint(
        address ape, // Address of the APE token, or address(0) if TEA
        uint256 vaultId, // 0 if APE
        VaultStructs.VaultParameters calldata vaultParams,
        uint256 amountDebtToken,
        uint256 minCollateral,
        uint24 uniswapFeeTier
    ) external returns (uint256 amountTokens) {
        // Retrieve debt tokens from user
        TransferHelper.safeTransferFrom(vaultParams.debtToken, msg.sender, address(this), amountDebtToken);

        // Approve SWAP_ROUTER to spend debtToken from this contract
        TransferHelper.safeApprove(vaultParams.debtToken, address(SWAP_ROUTER), amountDebtToken);

        // Swap debt token for collateral AND send them to the VAULT directly
        SWAP_ROUTER.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: vaultParams.debtToken,
                tokenOut: vaultParams.collateralToken,
                fee: uniswapFeeTier,
                recipient: address(VAULT),
                deadline: block.timestamp,
                amountIn: amountDebtToken,
                amountOutMinimum: minCollateral,
                sqrtPriceLimitX96: 0
            })
        );

        // Mint TEA or APE
        bool isAPE = ape != address(0);
        amountTokens = VAULT.mint(isAPE, vaultParams);

        // Because this contract called mint. The tokens are now here and need to be transfered to the user
        if (isAPE) {
            IERC20(ape).transfer(msg.sender, amountTokens); // No need for TransferHelper because APE is our own token
        } else {
            ERC1155(address(VAULT)).safeTransferFrom(address(this), msg.sender, vaultId, amountTokens, "");
        }
    }

    function burnAndSwap(
        address ape, // Address of the APE token, or address(0) if TEA
        uint256 vaultId, // 0 if APE
        VaultStructs.VaultParameters calldata vaultParams,
        uint256 amountTokens,
        uint256 minDebtToken,
        uint24 uniswapFeeTier
    ) external returns (uint256 amountDebtToken) {
        // Are we burning APE or TEA?
        bool isAPE = ape != address(0);

        // Transfer tokens from user
        if (isAPE) {
            IERC20(ape).transferFrom(msg.sender, address(this), amountTokens); // No need for TransferHelper because APE is our own token
        } else {
            ERC1155(address(VAULT)).safeTransferFrom(msg.sender, address(this), vaultId, amountTokens, "");
        }

        // Burn TEA or APE
        uint144 amountCollateral = VAULT.burn(isAPE, vaultParams, amountTokens);

        // Approve SWAP_ROUTER to spend collateralToken from this contract
        TransferHelper.safeApprove(vaultParams.collateralToken, address(SWAP_ROUTER), amountCollateral);

        // Swap collateral for debt token AND send them to the user
        amountDebtToken = SWAP_ROUTER.exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: vaultParams.collateralToken,
                tokenOut: vaultParams.debtToken,
                fee: uniswapFeeTier,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountOut: minDebtToken,
                amountInMaximum: amountCollateral,
                sqrtPriceLimitX96: 0
            })
        );
    }

    /** @notice It returns the ideal price of TEA if there were no fees for withdrawing.
        @notice To get the price as [units of Collateral][per unit of TEA], divide num by den.
     */
    function priceOfTEA(
        VaultStructs.VaultParameters calldata vaultParams
    ) external view returns (uint256 num, uint256 den) {
        // Get current reserves
        VaultStructs.Reserves memory reserves = VAULT.getReserves(vaultParams);
        num = reserves.reserveLPers;

        // Get supply of TEA
        (, , uint48 vaultId) = VAULT.vaultStates(
            vaultParams.debtToken,
            vaultParams.collateralToken,
            vaultParams.leverageTier
        );
        den = VAULT.totalSupply(vaultId);
    }

    /** @notice It returns the ideal price of APE if there were no fees for withdrawing.
        @notice To get the price as [units of Collateral][per unit of APE], divide num by den.
     */
    function priceOfAPE(
        VaultStructs.VaultParameters calldata vaultParams
    ) external view returns (uint256 num, uint256 den) {
        // Get current reserves
        VaultStructs.Reserves memory reserves = VAULT.getReserves(vaultParams);
        num = reserves.reserveApes;

        // Get supply of APE
        (, , uint48 vaultId) = VAULT.vaultStates(
            vaultParams.debtToken,
            vaultParams.collateralToken,
            vaultParams.leverageTier
        );
        den = IERC20(getAddressAPE(address(VAULT), vaultId)).totalSupply();
    }

    /*////////////////////////////////////////////////////////////////
                            SIMULATION FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    /** @dev Static function so we do not need to save on SLOADs
        @dev If quoteMint reverts, mint will revert as well; vice versa is not true.
        @return amountTokens that would be minted for a given amount of collateral
     */
    function quoteMint(
        bool isAPE,
        VaultStructs.VaultParameters calldata vaultParams,
        uint144 amountCollateral
    ) external view returns (uint256 amountTokens) {
        // Get all the parameters
        (, uint16 baseFee, uint16 lpFee, , ) = VAULT.systemParams();
        (, , uint48 vaultId) = VAULT.vaultStates(
            vaultParams.debtToken,
            vaultParams.collateralToken,
            vaultParams.leverageTier
        );
        if (vaultId == 0) revert VaultDoesNotExist();

        // Get current reserves
        VaultStructs.Reserves memory reserves = VAULT.getReserves(vaultParams);

        if (isAPE) {
            // Compute how much collateral actually gets deposited
            uint256 feeNum;
            uint256 feeDen;
            if (vaultParams.leverageTier >= 0) {
                feeNum = 10000; // baseFee is uint16, leverageTier is int8, so feeNum does not require more than 24 bits
                feeDen = 10000 + (uint256(baseFee) << uint8(vaultParams.leverageTier));
            } else {
                uint256 temp = 10000 << uint8(-vaultParams.leverageTier);
                feeNum = temp;
                feeDen = temp + uint256(baseFee);
            }

            // Get collateralIn
            uint256 collateralIn = (uint256(amountCollateral) * feeNum) / feeDen;

            // Get supply of APE
            address ape = getAddressAPE(address(VAULT), vaultId);
            uint256 supplyAPE = IERC20(ape).totalSupply();

            // Calculate tokens
            amountTokens = supplyAPE == 0
                ? collateralIn + reserves.reserveApes
                : FullMath.mulDiv(supplyAPE, collateralIn, reserves.reserveApes);
        } else {
            // Get current tax
            uint8 tax = VAULT.vaultTax(vaultId);

            // Compute how much collateral actually gets deposited
            (uint144 collateralIn, , uint144 lpersFee, uint144 polFee) = Fees.hiddenFeeTEA(
                amountCollateral,
                lpFee,
                tax
            );
            reserves.reserveLPers += lpersFee;

            // Get supply of TEA
            uint256 supplyTEA = VAULT.totalSupply(vaultId);

            // POL
            uint256 amountPOL = supplyTEA == 0
                ? _amountFirstMint(vaultParams.collateralToken, polFee + reserves.reserveLPers)
                : FullMath.mulDiv(supplyTEA, polFee, reserves.reserveLPers);
            supplyTEA += amountPOL;

            // LPer fees
            reserves.reserveLPers += polFee;

            // Calculate tokens
            amountTokens = supplyTEA == 0
                ? _amountFirstMint(vaultParams.collateralToken, collateralIn + reserves.reserveLPers)
                : FullMath.mulDiv(supplyTEA, collateralIn, reserves.reserveLPers);
        }
    }

    /** @dev Static function so we do not need to save on SLOADs
        @dev If quoteBurn reverts, burn in Vault.sol will revert as well; vice versa is not true.
        @return amountCollateral that would be obtained by burning a given amount of collateral
     */
    function quoteBurn(
        bool isAPE,
        VaultStructs.VaultParameters calldata vaultParams,
        uint256 amountTokens
    ) external view returns (uint144 amountCollateral) {
        // Get all the parameters
        (, uint16 baseFee, uint16 lpFee, , ) = VAULT.systemParams();
        (, , uint48 vaultId) = VAULT.vaultStates(
            vaultParams.debtToken,
            vaultParams.collateralToken,
            vaultParams.leverageTier
        );
        if (vaultId == 0) revert VaultDoesNotExist();

        // Get current reserves
        VaultStructs.Reserves memory reserves = VAULT.getReserves(vaultParams);

        if (isAPE) {
            // Get supply of APE
            address ape = getAddressAPE(address(VAULT), vaultId);
            uint256 supplyAPE = IERC20(ape).totalSupply();

            // Get collateralOut
            uint256 collateralOut = uint144(FullMath.mulDiv(reserves.reserveApes, amountTokens, supplyAPE));

            // Compute collateral withdrawn
            uint256 feeNum;
            uint256 feeDen;
            if (vaultParams.leverageTier >= 0) {
                feeNum = 10000;
                feeDen = 10000 + (uint256(baseFee) << uint8(vaultParams.leverageTier));
            } else {
                uint256 temp = 10000 << uint8(-vaultParams.leverageTier);
                feeNum = temp;
                feeDen = temp + uint256(baseFee);
            }

            // Get collateral withdrawn
            amountCollateral = uint144((collateralOut * feeNum) / feeDen);
        } else {
            // Get supply of TEA
            uint256 supplyTEA = VAULT.totalSupply(vaultId);

            // Get collateralOut
            uint256 collateralOut = uint144(FullMath.mulDiv(reserves.reserveLPers, amountTokens, supplyTEA));

            // Compute collateral withdrawn
            uint256 feeNum = 10000;
            uint256 feeDen = 10000 + uint256(lpFee);
            amountCollateral = uint144((collateralOut * feeNum) / feeDen);
        }
    }

    function getAddressAPE(address deployer, uint256 vaultId) public view returns (address) {
        return
            address(
                uint160(
                    uint(keccak256(abi.encodePacked(bytes1(0xff), deployer, bytes32(vaultId), HASH_CREATION_CODE_APE)))
                )
            );
    }

    /*////////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function _amountFirstMint(address collateral, uint144 collateralIn) private view returns (uint256 amount) {
        uint256 collateralTotalSupply = IERC20(collateral).totalSupply();
        amount = collateralTotalSupply > SystemConstants.TEA_MAX_SUPPLY
            ? FullMath.mulDiv(SystemConstants.TEA_MAX_SUPPLY, collateralIn, collateralTotalSupply)
            : collateralIn;
    }
}
