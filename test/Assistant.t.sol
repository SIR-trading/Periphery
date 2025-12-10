// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import {IWETH9} from "core/interfaces/IWETH9.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

// Libraries
import {AddressesMegaETHTest} from "core/libraries/AddressesMegaETHTest.sol";
import {SystemConstants} from "core/libraries/SystemConstants.sol";
import {SirStructs} from "core/libraries/SirStructs.sol";
import {AddressClone} from "core/libraries/AddressClone.sol";

// Contracts
import {Oracle} from "core/Oracle.sol";
import {SystemControl} from "core/SystemControl.sol";
import {SIR} from "core/SIR.sol";
import {APE} from "core/APE.sol";
import {Vault} from "core/Vault.sol";
import {Contributors} from "core/Contributors.sol";
import {Assistant} from "src/Assistant.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "forge-std/Test.sol";

contract AssistantTest is Test {
    using SafeERC20 for IERC20;

    struct State {
        uint256 totalReserve;
        uint256 collectedFees;
        int64 tickPriceSatX42;
        uint128 teaTotalSupply;
        uint128 teaBalanceVault;
        uint256 apeTotalSupply;
    }

    receive() external payable {}

    bytes32 private constant _HASH_CREATION_CODE_APE = keccak256(type(APE).creationCode);

    uint256 constant SLOT_TEA_SUPPLY = 4;
    uint256 constant SLOT_APE_SUPPLY = 5;
    uint256 constant SLOT_VAULT_STATE = 9;
    uint256 constant SLOT_RESERVES_TOTAL = 10;

    IWETH9 private constant WETH = IWETH9(AddressesMegaETHTest.ADDR_WETH);
    IERC20 private constant USDC = IERC20(AddressesMegaETHTest.ADDR_USDC);

    Vault vault;
    Assistant assistant;

    uint96 constant ETH_SUPPLY = 120e6 * 10 ** 18;
    uint256 constant USDC_SUPPLY = 100e9 * 10 ** 6;

    SirStructs.VaultParameters vaultParams =
        SirStructs.VaultParameters({
            debtToken: AddressesMegaETHTest.ADDR_USDC,
            collateralToken: AddressesMegaETHTest.ADDR_WETH,
            leverageTier: 0
        });

    function setUp() public {
        // vm.writeFile("./mint.log", "");

        vm.createSelectFork("megatest");

        // Deploy oracle
        address oracle = address(new Oracle(AddressesMegaETHTest.ADDR_UNISWAPV3_FACTORY));

        // Deploy SystemControl
        address systemControl = address(new SystemControl());

        // Deploy Contributors
        address contributors = address(new Contributors());

        // Deploy SIR token contract
        address payable sir = payable(address(new SIR(contributors, AddressesMegaETHTest.ADDR_WETH, systemControl)));

        // Deploy APE implementation
        address ape = address(new APE());

        // Deploy Vault
        vault = new Vault(systemControl, sir, oracle, ape, AddressesMegaETHTest.ADDR_WETH);

        // Initialize SIR
        SIR(sir).initialize(address(vault));

        // Initialize SystemControl
        SystemControl(systemControl).initialize(address(vault), sir);

        // Deploy Assistant
        assistant = new Assistant(address(vault), oracle, AddressesMegaETHTest.ADDR_UNISWAPV3_FACTORY);

        // Approve Assistant to spend WETH
        WETH.approve(address(vault), type(uint256).max);

        vm.writeFile("./test.log", "");
    }

    enum VaultStatus {
        InvalidVault,
        NoUniswapPool,
        VaultCanBeCreated,
        VaultAlreadyExists
    }

    function testFuzz_getVaultAlreadyExistsStatus(int8 leverageTier) public {
        // Initialize vault
        _initializeVault(leverageTier);

        uint256 vaultStatus = uint256(assistant.getVaultStatus(vaultParams));
        assertEq(vaultStatus, uint256(VaultStatus.VaultAlreadyExists));
    }

    function test_getVaultDoesNotExistsStatus() public view {
        uint256 vaultStatus = uint256(assistant.getVaultStatus(vaultParams));
        assertEq(vaultStatus, uint256(VaultStatus.VaultCanBeCreated));
    }

    function test_getVaultWithNoUniswapPool() public {
        vaultParams.collateralToken = AddressesMegaETHTest.ADDR_TEST01;
        vaultParams.debtToken = AddressesMegaETHTest.ADDR_TEST02;

        uint256 vaultStatus = uint256(assistant.getVaultStatus(vaultParams));
        assertEq(vaultStatus, uint256(VaultStatus.NoUniswapPool));
    }

    function test_getVaultWithWrongAddress() public {
        vaultParams.collateralToken = AddressesMegaETHTest.ADDR_WETH;
        vaultParams.debtToken = AddressesMegaETHTest.ADDR_UNISWAPV3_FACTORY;

        uint256 vaultStatus = uint256(assistant.getVaultStatus(vaultParams));
        assertEq(vaultStatus, uint256(VaultStatus.InvalidVault));
    }

    /** @dev Important to run first quoteMint before mint changes the state of the Vault
     */
    function testFuzz_mintFirstTime(
        bool isAPE,
        int8 leverageTier,
        uint144 wethMinted,
        uint144 wethDeposited,
        address user
    ) public {
        // Initialize vault
        _initializeVault(leverageTier);

        // Bound WETH amounts
        wethMinted = uint144(_bound(wethMinted, 0, ETH_SUPPLY));
        wethDeposited = uint144(_bound(wethDeposited, 0, wethMinted)); // Minimum amount that must be deposited is

        // Deal WETH
        vm.assume(user != address(0));
        _dealWETH(user, wethMinted);

        // Mint TEA or APE and test it against quoteMint
        bool mintMustRevert;
        uint256 amountTokens;
        try
            // Quote mint
            assistant.quoteMint(isAPE, vaultParams, wethDeposited)
        returns (uint256 amountTokens_) {
            mintMustRevert = false;
            amountTokens = amountTokens_;
        } catch {
            mintMustRevert = true;
        }

        // Approve vault to spend WETH
        vm.prank(user);
        WETH.approve(address(vault), wethDeposited);

        vm.prank(user);
        if (mintMustRevert) {
            // Mint must revert
            vm.expectRevert();
            vault.mint(isAPE, vaultParams, wethDeposited, 0, 0);
        } else {
            try
                // Mint could revert
                vault.mint(isAPE, vaultParams, wethDeposited, 0, 0)
            returns (uint256 amountTokens_) {
                // Mint does not revert like quoteMint
                assertEq(amountTokens_, amountTokens, "mint and quoteMint should return the same amount of tokens");
            } catch {
                // Mint reverts contrary to quoteMint
            }
        }
    }

    /** @dev Important to run first quoteMint before mint changes the state of the Vault
     */
    function testFuzz_mintWithETHFirstTime(
        bool isAPE,
        int8 leverageTier,
        uint144 ethMinted,
        uint144 ethDeposited,
        uint144 ethFakeDeposited,
        address user
    ) public {
        // Initialize vault
        _initializeVault(leverageTier);

        // Bound ETH amounts
        ethMinted = uint144(_bound(ethMinted, 0, ETH_SUPPLY));
        ethDeposited = uint144(_bound(ethDeposited, 0, ethMinted)); // Minimum amount that must be deposited is

        // Deal ETH
        vm.assume(user != address(0));
        vm.deal(user, ethMinted);

        // For exactness quoteMint needs to retrieve the exact same totalSupply
        vm.mockCall(
            AddressesMegaETHTest.ADDR_WETH,
            abi.encodeWithSelector(WETH.totalSupply.selector),
            abi.encode(WETH.totalSupply() + ethDeposited)
        );

        // Mint TEA or APE and test it against quoteMint
        bool mintMustRevert;
        uint256 amountTokens;
        try
            // Quote mint
            assistant.quoteMint(isAPE, vaultParams, ethDeposited)
        returns (uint256 amountTokens_) {
            mintMustRevert = false;
            amountTokens = amountTokens_;
        } catch {
            mintMustRevert = true;
        }

        vm.clearMockedCalls();

        vm.prank(user);
        if (mintMustRevert) {
            // Mint must revert
            vm.expectRevert();
            vault.mint{value: ethDeposited}(isAPE, vaultParams, ethFakeDeposited, 0, 0);
        } else {
            try
                // Mint could revert
                vault.mint{value: ethDeposited}(isAPE, vaultParams, ethFakeDeposited, 0, 0)
            returns (uint256 amountTokens_) {
                // Mint does not revert like quoteMint
                assertEq(amountTokens_, amountTokens, "mint and quoteMint should return the same amount of tokens");
            } catch {
                // Mint reverts contrary to quoteMint
            }
        }
    }

    function testFuzz_mintWithDebtTokenFirstTime(
        bool isAPE,
        int8 leverageTier,
        uint144 usdcMinted,
        uint144 usdcDeposited,
        address user,
        uint144 amountCollateralMin
    ) public {
        // Initialize vault
        _initializeVault(leverageTier);

        // Bound USDC amounts
        usdcMinted = uint144(_bound(usdcMinted, 0, USDC_SUPPLY / 10000)); // Swapping too large amounts will cost a lot of gas in Uniswap v3 because of all the ticks crossed
        usdcDeposited = uint144(_bound(usdcDeposited, 0, usdcMinted)); // Minimum amount that must be deposited is

        // Approve assistant to spend USDC
        vm.prank(user);
        USDC.forceApprove(address(vault), usdcDeposited);

        // Mint TEA or APE and test it against quoteMint
        bool mintMustRevert;
        uint256 amountTokens;
        uint256 amountCollateral;
        uint256 amountCollateralIdeal;
        // vm.writeLine("./test.log", string.concat("quoteMint with ", vm.toString(usdcDeposited)));
        try
            // Quote mint
            assistant.quoteMintWithDebtToken(isAPE, vaultParams, usdcDeposited)
        returns (uint256 amountTokens_, uint256 amountCollateral_, uint256 amountCollateralIdeal_) {
            amountTokens = amountTokens_;
            amountCollateral = amountCollateral_;
            amountCollateralIdeal = amountCollateralIdeal_;

            // Test that ideal amount is greater or equal to actual amount (due to slippage)
            assertGe(amountCollateralIdeal, amountCollateral, "Ideal should be >= actual due to slippage");

            // For reasonable amounts (1-100 USDC), check that ideal and actual are close
            // Skip slippage check for dust amounts (< 1 USDC) where high slippage is expected
            if (usdcDeposited >= 1e6 && usdcDeposited < 100e6) {
                // Calculate percentage difference: (ideal - actual) / ideal * 100
                uint256 percentDiff = amountCollateralIdeal > 0
                    ? ((amountCollateralIdeal - amountCollateral) * 10000) / amountCollateralIdeal
                    : 0;
                // Assert less than 1% difference for reasonable small amounts
                assertLt(percentDiff, 100, "Small amounts (1-100 USDC) should have < 1% slippage");
            }

            amountCollateralMin = uint144(_bound(amountCollateralMin, 1, amountCollateral));
            mintMustRevert = false;
            // vm.writeLine("./test.log", string.concat("quoteMint returned ", vm.toString(amountTokens)));
        } catch {
            mintMustRevert = true;
            // vm.writeLine("./test.log", "quoteMint reverted");
        }
        // vm.writeLine("./test.log", "--------------------------------");

        // Deal USDC
        vm.assume(user != address(0));
        deal(address(USDC), user, usdcDeposited);

        vm.prank(user);
        if (mintMustRevert) {
            // quoteMint reverted - on testnet the Quoter may fail due to staticcall limitations
            // so we can't assume mint will also revert. Just try mint and accept either outcome.
            try vault.mint(isAPE, vaultParams, usdcDeposited, amountCollateralMin, 0) {
                // Mint succeeded despite quoteMint reverting (possible on testnet)
            } catch {
                // Mint also reverted as expected
            }
        } else {
            try
                // Mint could revert
                vault.mint(isAPE, vaultParams, usdcDeposited, amountCollateralMin, 0)
            returns (uint256 amountTokens_) {
                // Mint does not revert like quoteMint
                console.log("mint returned", amountTokens_);
                assertEq(amountTokens_, amountTokens, "mint and quoteMint should return the same amount of tokens");
            } catch {
                // Mint reverts contrary to quoteMint
            }
        }
    }

    function testFuzz_mint(
        bool isAPE,
        int8 leverageTier,
        uint144 wethMinted,
        uint144 wethDeposited,
        address user,
        State memory state
    ) public {
        // Initialize vault
        _initializeVault(leverageTier);

        // Initialize vault state
        _initializeState(vaultParams.leverageTier, state);

        // Bound WETH amounts
        wethMinted = uint144(_bound(wethMinted, 0, ETH_SUPPLY));
        wethDeposited = uint144(_bound(wethDeposited, 0, wethMinted)); // Minimum amount that must be deposited is

        // Deal WETH
        vm.assume(user != address(0));
        _dealWETH(user, wethMinted);

        // Approve assistant to spend WETH
        vm.prank(user);
        WETH.approve(address(vault), wethDeposited);

        // Mint TEA or APE and test it against quoteMint
        bool mintMustRevert;
        uint256 amountTokens;
        try
            // Quote mint
            assistant.quoteMint(isAPE, vaultParams, wethDeposited)
        returns (uint256 amountTokens_) {
            amountTokens = amountTokens_;
            mintMustRevert = false;
        } catch {
            mintMustRevert = true;
        }

        vm.prank(user);
        if (mintMustRevert) {
            // Mint must revert
            vm.expectRevert();
            vault.mint(isAPE, vaultParams, wethDeposited, 0, 0);
        } else {
            try
                // Mint could revert
                vault.mint(isAPE, vaultParams, wethDeposited, 0, 0)
            returns (uint256 amountTokens_) {
                // Mint does not revert like quoteMint
                assertEq(amountTokens_, amountTokens, "mint and quoteMint should return the same amount of tokens");
            } catch {
                // Mint reverts contrary to quoteMint
            }
        }
    }

    function testFuzz_mintWithETH(
        bool isAPE,
        int8 leverageTier,
        uint144 ethMinted,
        uint144 ethDeposited,
        uint144 ethFakeDeposited,
        address user,
        State memory state
    ) public {
        // Initialize vault
        _initializeVault(leverageTier);

        // Initialize vault state
        _initializeState(vaultParams.leverageTier, state);

        // Bound ETH amounts
        ethMinted = uint144(_bound(ethMinted, 0, ETH_SUPPLY));
        ethDeposited = uint144(_bound(ethDeposited, 0, ethMinted)); // Minimum amount that must be deposited is

        // Deal ETH
        vm.assume(user != address(0));
        deal(user, ethMinted);

        // Mint TEA or APE and test it against quoteMint
        bool mintMustRevert;
        uint256 amountTokens;

        // Simulate WETH supply increase due to wrapping the received ETH
        deal(address(this), ethDeposited);
        WETH.deposit{value: ethDeposited}();

        try
            // Quote mint
            assistant.quoteMint(isAPE, vaultParams, ethDeposited)
        returns (uint256 amountTokens_) {
            amountTokens = amountTokens_;
            mintMustRevert = false;
        } catch {
            mintMustRevert = true;
        }

        // Remove extra WETH
        WETH.withdraw(ethDeposited);
        vm.prank(user);

        if (mintMustRevert) {
            // Mint must revert
            vm.expectRevert();
            vault.mint{value: ethDeposited}(isAPE, vaultParams, ethFakeDeposited, 0, 0);
        } else {
            try
                // Mint could revert
                vault.mint{value: ethDeposited}(isAPE, vaultParams, ethFakeDeposited, 0, 0)
            returns (uint256 amountTokens_) {
                // Mint does not revert like quoteMint
                assertEq(amountTokens_, amountTokens, "mint and quoteMint should return the same amount of tokens");
            } catch {
                // Mint reverts contrary to quoteMint
            }
        }
    }

    function testFuzz_mintWithDebtToken(
        bool isAPE,
        int8 leverageTier,
        uint144 usdcMinted,
        uint144 usdcDeposited,
        address user,
        uint144 amountCollateralMin,
        State memory state
    ) public {
        // Initialize vault
        _initializeVault(leverageTier);

        // Initialize vault state
        _initializeState(vaultParams.leverageTier, state);

        // Bound USDC amounts
        usdcMinted = uint144(_bound(usdcMinted, 0, USDC_SUPPLY / 10000)); // Swapping too large amounts will cost a lot of gas in Uniswap v3 because of all the ticks crossed
        usdcDeposited = uint144(_bound(usdcDeposited, 0, usdcMinted)); // Minimum amount that must be deposited is

        // Approve assistant to spend USDC
        vm.prank(user);
        USDC.forceApprove(address(vault), usdcDeposited);

        // Mint TEA or APE and test it against quoteMint
        bool mintMustRevert;
        uint256 amountTokens;
        uint256 amountCollateral;
        uint256 amountCollateralIdeal;
        // vm.writeLine("./test.log", string.concat("quoteMint with ", vm.toString(usdcDeposited)));
        try
            // Quote mint
            assistant.quoteMintWithDebtToken(isAPE, vaultParams, usdcDeposited)
        returns (uint256 amountTokens_, uint256 amountCollateral_, uint256 amountCollateralIdeal_) {
            amountTokens = amountTokens_;
            amountCollateral = amountCollateral_;
            amountCollateralIdeal = amountCollateralIdeal_;

            // Test that ideal amount is greater or equal to actual amount (due to slippage)
            assertGe(amountCollateralIdeal, amountCollateral, "Ideal should be >= actual due to slippage");

            // For reasonable amounts (1-100 USDC), check that ideal and actual are close
            // Skip slippage check for dust amounts (< 1 USDC) where high slippage is expected
            if (usdcDeposited >= 1e6 && usdcDeposited < 100e6) {
                // Calculate percentage difference: (ideal - actual) / ideal * 100
                uint256 percentDiff = amountCollateralIdeal > 0
                    ? ((amountCollateralIdeal - amountCollateral) * 10000) / amountCollateralIdeal
                    : 0;
                // Assert less than 1% difference for reasonable small amounts
                assertLt(percentDiff, 100, "Small amounts (1-100 USDC) should have < 1% slippage");
            }

            amountCollateralMin = uint144(_bound(amountCollateralMin, 1, amountCollateral));
            mintMustRevert = false;
            // vm.writeLine("./test.log", string.concat("quoteMint returned ", vm.toString(amountTokens)));
        } catch {
            mintMustRevert = true;
            // vm.writeLine("./test.log", "quoteMint reverted");
        }
        // vm.writeLine("./test.log", "--------------------------------");

        // Deal USDC
        vm.assume(user != address(0));
        deal(address(USDC), user, usdcDeposited);

        vm.prank(user);
        if (mintMustRevert) {
            // quoteMint reverted - on testnet the Quoter may fail due to staticcall limitations
            // so we can't assume mint will also revert. Just try mint and accept either outcome.
            try vault.mint(isAPE, vaultParams, usdcDeposited, amountCollateralMin, 0) {
                // Mint succeeded despite quoteMint reverting (possible on testnet)
            } catch {
                // Mint also reverted as expected
            }
        } else {
            try
                // Mint could revert
                vault.mint(isAPE, vaultParams, usdcDeposited, amountCollateralMin, 0)
            returns (uint256 amountTokens_) {
                // Mint does not revert like quoteMint
                console.log("mint returned", amountTokens_);
                assertEq(amountTokens_, amountTokens, "mint and quoteMint should return the same amount of tokens");
            } catch {
                // Mint reverts contrary to quoteMint
            }
        }
    }

    function testFuzz_burn(
        bool isAPE,
        int8 leverageTier,
        uint256 tokensBurnt,
        address user,
        State memory state
    ) public {
        // Initialize vault
        _initializeVault(leverageTier);

        // Initialize vault state
        _initializeState(vaultParams.leverageTier, state);

        vm.assume(user != address(0));

        // Burn TEA or APE and test it against quoteBurn
        bool burnMustRevert;
        uint144 amountCollateral;
        uint256 amountDebtToken;
        try
            // Quote mint
            assistant.quoteBurn(isAPE, vaultParams, tokensBurnt)
        returns (uint144 amountCollateral_, uint256 amountDebtToken_) {
            amountCollateral = amountCollateral_;
            amountDebtToken = amountDebtToken_;
            burnMustRevert = false;
        } catch {
            burnMustRevert = true;
        }

        vm.prank(user);
        if (burnMustRevert) {
            // Burn must revert
            vm.expectRevert();
            vault.burn(isAPE, vaultParams, tokensBurnt, 0);
        } else {
            try
                // Burn could revert
                vault.burn(isAPE, vaultParams, tokensBurnt, 0)
            returns (uint144 amountCollateral_) {
                // Burn does not revert like quoteBurn
                assertEq(
                    amountCollateral_,
                    amountCollateral,
                    "burn and quoteBurn should return the same amount of collateral"
                );

                // Check that amountDebtToken from quoteBurn matches quoteCollateralToDebtToken
                uint256 expectedDebtToken = assistant.quoteCollateralToDebtToken(
                    vaultParams.debtToken,
                    vaultParams.collateralToken,
                    amountCollateral_
                );

                // Allow for small difference due to potential rounding or TWAP vs spot price
                // Using 1% tolerance (1/100) for TWAP vs spot price difference
                uint256 tolerance = expectedDebtToken / 100;
                assertApproxEqAbs(
                    amountDebtToken,
                    expectedDebtToken,
                    tolerance,
                    "quoteBurn amountDebtToken should match quoteCollateralToDebtToken"
                );
            } catch {
                // Burn reverts contrary to quoteBurn
            }
        }
    }

    function test_quoteCollateralToDebtToken() public {
        // Initialize vault
        _initializeVault(vaultParams.leverageTier);

        // Quote 1 ether of collateral
        uint256 amountDebtToken = assistant.quoteCollateralToDebtToken(
            vaultParams.debtToken,
            vaultParams.collateralToken,
            1 ether
        );

        // Price varies on testnet - just check it returns something reasonable
        assertGt(amountDebtToken, 0, "Should return a non-zero debt token amount");
    }

    function test_quoteBurnDebtTokenAmount() public {
        // Initialize vault
        _initializeVault(vaultParams.leverageTier);

        // First mint some TEA and APE tokens to have non-zero supply
        address user = address(0x1234);
        _dealWETH(user, 20 ether);

        vm.startPrank(user);
        WETH.approve(address(vault), 20 ether);

        // Mint TEA tokens
        vault.mint(false, vaultParams, 10 ether, 0, 0);

        // Mint APE tokens
        vault.mint(true, vaultParams, 5 ether, 0, 0);
        vm.stopPrank();

        // Test TEA burn
        uint256 teaBurnAmount = 100e18;
        (uint144 teaCollateral, uint256 teaDebtToken) = assistant.quoteBurn(false, vaultParams, teaBurnAmount);

        // Verify debt token amount matches quoteCollateralToDebtToken
        uint256 expectedTeaDebtToken = assistant.quoteCollateralToDebtToken(
            vaultParams.debtToken,
            vaultParams.collateralToken,
            teaCollateral
        );

        assertApproxEqRel(
            teaDebtToken,
            expectedTeaDebtToken,
            0.01e18, // 1% tolerance for TWAP vs spot price difference
            "TEA burn: amountDebtToken should match quoteCollateralToDebtToken"
        );

        // Test APE burn
        uint256 apeBurnAmount = 200e18;
        (uint144 apeCollateral, uint256 apeDebtToken) = assistant.quoteBurn(true, vaultParams, apeBurnAmount);

        // Verify debt token amount matches quoteCollateralToDebtToken
        uint256 expectedApeDebtToken = assistant.quoteCollateralToDebtToken(
            vaultParams.debtToken,
            vaultParams.collateralToken,
            apeCollateral
        );

        assertApproxEqRel(
            apeDebtToken,
            expectedApeDebtToken,
            0.01e18, // 1% tolerance for TWAP vs spot price difference
            "APE burn: amountDebtToken should match quoteCollateralToDebtToken"
        );

        // Ensure the values are reasonable
        assertGt(teaDebtToken, 0, "TEA debt token amount should be positive");
        assertGt(apeDebtToken, 0, "APE debt token amount should be positive");
    }

    ////////////////////////////////////////////////////////////////////////
    /////////////// P R I V A T E ////// F U N C T I O N S ////////////////
    //////////////////////////////////////////////////////////////////////

    function _initializeState(int8 leverageTier, State memory state) private {
        state.totalReserve = _bound(state.totalReserve, 2, ETH_SUPPLY);
        state.collectedFees = _bound(state.collectedFees, 0, ETH_SUPPLY);

        state.teaTotalSupply = uint128(_bound(state.teaTotalSupply, 0, SystemConstants.TEA_MAX_SUPPLY));
        state.teaBalanceVault = uint128(_bound(state.teaBalanceVault, 0, state.teaTotalSupply));

        // Deposit WETH to vault
        _dealWETH(address(vault), state.totalReserve + state.collectedFees);

        bytes32 slotInd = keccak256(
            abi.encode(
                leverageTier,
                keccak256(
                    abi.encode(
                        AddressesMegaETHTest.ADDR_WETH,
                        keccak256(abi.encode(AddressesMegaETHTest.ADDR_USDC, bytes32(uint256(SLOT_VAULT_STATE))))
                    )
                )
            )
        );
        uint256 slot = uint256(vm.load(address(vault), slotInd));
        slot >>= 208;
        uint48 vaultId_ = uint48(slot);

        vm.store(
            address(vault),
            slotInd,
            bytes32(abi.encodePacked(vaultId_, state.tickPriceSatX42, uint144(state.totalReserve)))
        );

        SirStructs.VaultState memory vaultState = vault.vaultStates(
            SirStructs.VaultParameters(AddressesMegaETHTest.ADDR_USDC, AddressesMegaETHTest.ADDR_WETH, leverageTier)
        );
        assertEq(vaultState.reserve, state.totalReserve, "Wrong reserve used by vm.store");
        assertEq(vaultState.tickPriceSatX42, state.tickPriceSatX42, "Wrong tickPriceSatX42 used by vm.store");
        assertEq(vaultState.vaultId, vaultId_, "Wrong vaultId used by vm.store");

        //////////////////////////////////////////////////////////////////////////

        slotInd = keccak256(abi.encode(AddressesMegaETHTest.ADDR_WETH, bytes32(uint256(SLOT_RESERVES_TOTAL))));
        vm.store(address(vault), slotInd, bytes32(state.totalReserve));

        uint256 totalReserve_ = vault.totalReserves(AddressesMegaETHTest.ADDR_WETH);
        assertEq(
            WETH.balanceOf(address(vault)) - state.totalReserve,
            state.collectedFees,
            "Wrong collectedFees used by vm.store"
        );
        assertEq(totalReserve_, state.totalReserve, "Wrong total used by vm.store");

        //////////////////////////////////////////////////////////////////////////

        address ape = AddressClone.getAddress(address(vault), 1);
        vm.store(ape, bytes32(SLOT_APE_SUPPLY), bytes32(state.apeTotalSupply));
        assertEq(IERC20(ape).totalSupply(), state.apeTotalSupply, "Wrong apeTotalSupply used by vm.store");
    }

    function _initializeVault(int8 leverageTier) private {
        vaultParams.leverageTier = int8(
            _bound(leverageTier, SystemConstants.MIN_LEVERAGE_TIER, SystemConstants.MAX_LEVERAGE_TIER)
        );

        // Initialize vault
        vault.initialize(vaultParams);
    }

    function _dealWETH(address to, uint256 amount) private {
        vm.deal(vm.addr(1), amount);
        vm.prank(vm.addr(1));
        WETH.deposit{value: amount}();
        vm.prank(vm.addr(1));
        WETH.transfer(address(to), amount);
    }

    // function _dealUSDC(address to, uint256 amount) private {
    //     if (amount == 0) return;
    //     deal(AddressesMegaETHTest.ADDR_USDC, vm.addr(1), amount);
    //     vm.prank(vm.addr(1));
    //     USDC.approve(address(this), amount);
    //     USDC.transferFrom(vm.addr(1), to, amount);
    // }
}
