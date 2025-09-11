// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import {IWETH9} from "core/interfaces/IWETH9.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

// Libraries
import {AddressesHyperEVM} from "core/libraries/AddressesHyperEVM.sol";
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

    IWETH9 private constant WHYPE = IWETH9(AddressesHyperEVM.ADDR_WHYPE);
    IERC20 private constant USDT = IERC20(AddressesHyperEVM.ADDR_USDT0);

    Vault vault;
    Assistant assistant;

    uint96 constant HYPE_SUPPLY = 120e6 * 10 ** 18;
    uint256 constant USDT_SUPPLY = 100e9 * 10 ** 6;

    SirStructs.VaultParameters vaultParams =
        SirStructs.VaultParameters({
            debtToken: AddressesHyperEVM.ADDR_USDT0,
            collateralToken: AddressesHyperEVM.ADDR_WHYPE,
            leverageTier: 0
        });

    function setUp() public {
        vm.createSelectFork("hyperevm", 13552974);

        // Deploy oracle
        address oracle = address(new Oracle(AddressesHyperEVM.ADDR_UNISWAPV3_FACTORY));

        // Deploy SystemControl
        address systemControl = address(new SystemControl());

        // Deploy Contributors
        address contributors = address(new Contributors());

        // Deploy SIR token contract
        address payable sir = payable(address(new SIR(contributors, AddressesHyperEVM.ADDR_WHYPE, systemControl)));

        // Deploy APE implementation
        address ape = address(new APE());

        // Deploy Vault
        vault = new Vault(systemControl, sir, oracle, ape, AddressesHyperEVM.ADDR_WHYPE);

        // Initialize SIR
        SIR(sir).initialize(address(vault));

        // Initialize SystemControl
        SystemControl(systemControl).initialize(address(vault), sir);

        console.log(address(vault), oracle, AddressesHyperEVM.ADDR_UNISWAPV3_FACTORY);

        // Deploy Assistant
        assistant = new Assistant(address(vault), oracle, AddressesHyperEVM.ADDR_UNISWAPV3_FACTORY);

        console.log("there");

        // Approve Assistant to spend WHYPE
        WHYPE.approve(address(vault), type(uint256).max);
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
        vaultParams.collateralToken = AddressesHyperEVM.ADDR_kHYPE;
        vaultParams.debtToken = AddressesHyperEVM.ADDR_PENDLE;

        uint256 vaultStatus = uint256(assistant.getVaultStatus(vaultParams));
        assertEq(vaultStatus, uint256(VaultStatus.NoUniswapPool));
    }

    function test_getVaultWithWrongAddress() public {
        vaultParams.collateralToken = AddressesHyperEVM.ADDR_WHYPE;
        vaultParams.debtToken = AddressesHyperEVM.ADDR_UNISWAPV3_FACTORY;

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

        // Bound WHYPE amounts
        wethMinted = uint144(_bound(wethMinted, 0, HYPE_SUPPLY));
        wethDeposited = uint144(_bound(wethDeposited, 0, wethMinted)); // Minimum amount that must be deposited is

        // Deal WHYPE
        vm.assume(user != address(0));
        _dealWHYPE(user, wethMinted);

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

        // Approve vault to spend WHYPE
        vm.prank(user);
        WHYPE.approve(address(vault), wethDeposited);

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
    function testFuzz_mintWithHYPEFirstTime(
        bool isAPE,
        int8 leverageTier,
        uint144 ethMinted,
        uint144 ethDeposited,
        uint144 ethFakeDeposited,
        address user
    ) public {
        // Initialize vault
        _initializeVault(leverageTier);

        // Bound HYPE amounts
        ethMinted = uint144(_bound(ethMinted, 0, HYPE_SUPPLY));
        ethDeposited = uint144(_bound(ethDeposited, 0, ethMinted)); // Minimum amount that must be deposited is

        // Deal HYPE
        vm.assume(user != address(0));
        vm.deal(user, ethMinted);

        // For exactness quoteMint needs to retrieve the exact same totalSupply
        vm.mockCall(
            AddressesHyperEVM.ADDR_WHYPE,
            abi.encodeWithSelector(WHYPE.totalSupply.selector),
            abi.encode(WHYPE.totalSupply() + ethDeposited)
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
        uint144 usdtMinted,
        uint144 usdtDeposited,
        address user,
        uint144 amountCollateralMin
    ) public {
        // Initialize vault
        _initializeVault(leverageTier);

        // Bound USDT amounts
        usdtMinted = uint144(_bound(usdtMinted, 0, USDT_SUPPLY / 10000)); // Swapping too large amounts will cost a lot of gas in Uniswap v3 because of all the ticks crossed
        usdtDeposited = uint144(_bound(usdtDeposited, 0, usdtMinted)); // Minimum amount that must be deposited is

        // Approve assistant to spend USDT
        vm.prank(user);
        USDT.forceApprove(address(vault), usdtDeposited);

        // Mint TEA or APE and test it against quoteMint
        bool mintMustRevert;
        uint256 amountTokens;
        uint256 amountCollateral;
        // vm.writeLine("./test.log", string.concat("quoteMint with ", vm.toString(usdtDeposited)));
        try
            // Quote mint
            assistant.quoteMintWithDebtToken(isAPE, vaultParams, usdtDeposited)
        returns (uint256 amountTokens_, uint256 amountCollateral_) {
            amountTokens = amountTokens_;
            amountCollateral = amountCollateral_;
            amountCollateralMin = uint144(_bound(amountCollateralMin, 1, amountCollateral));
            mintMustRevert = false;
            // vm.writeLine("./test.log", string.concat("quoteMint returned ", vm.toString(amountTokens)));
        } catch {
            mintMustRevert = true;
            // vm.writeLine("./test.log", "quoteMint reverted");
        }
        // vm.writeLine("./test.log", "--------------------------------");

        // Deal USDT
        vm.assume(user != address(0));
        deal(address(USDT), user, usdtDeposited);

        vm.prank(user);
        if (mintMustRevert) {
            // Mint must revert
            vm.expectRevert();
            vault.mint(isAPE, vaultParams, usdtDeposited, amountCollateralMin, 0);
        } else {
            try
                // Mint could revert
                vault.mint(isAPE, vaultParams, usdtDeposited, amountCollateralMin, 0)
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

        // Bound WHYPE amounts
        wethMinted = uint144(_bound(wethMinted, 0, HYPE_SUPPLY));
        wethDeposited = uint144(_bound(wethDeposited, 0, wethMinted)); // Minimum amount that must be deposited is

        // Deal WHYPE
        vm.assume(user != address(0));
        _dealWHYPE(user, wethMinted);

        // Approve assistant to spend WHYPE
        vm.prank(user);
        WHYPE.approve(address(vault), wethDeposited);

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

    function testFuzz_mintWithHYPE(
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

        // Bound HYPE amounts
        ethMinted = uint144(_bound(ethMinted, 0, HYPE_SUPPLY));
        ethDeposited = uint144(_bound(ethDeposited, 0, ethMinted)); // Minimum amount that must be deposited is

        // Deal HYPE
        vm.assume(user != address(0));
        deal(user, ethMinted);

        // Mint TEA or APE and test it against quoteMint
        bool mintMustRevert;
        uint256 amountTokens;

        // Simulate WHYPE supply increase due to wrapping the received HYPE
        deal(address(this), ethDeposited);
        WHYPE.deposit{value: ethDeposited}();

        try
            // Quote mint
            assistant.quoteMint(isAPE, vaultParams, ethDeposited)
        returns (uint256 amountTokens_) {
            amountTokens = amountTokens_;
            mintMustRevert = false;
        } catch {
            mintMustRevert = true;
        }

        // Remove extra WHYPE
        WHYPE.withdraw(ethDeposited);
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
        uint144 usdtMinted,
        uint144 usdtDeposited,
        address user,
        uint144 amountCollateralMin,
        State memory state
    ) public {
        // Initialize vault
        _initializeVault(leverageTier);

        // Initialize vault state
        _initializeState(vaultParams.leverageTier, state);

        // Bound USDT amounts
        usdtMinted = uint144(_bound(usdtMinted, 0, USDT_SUPPLY / 10000)); // Swapping too large amounts will cost a lot of gas in Uniswap v3 because of all the ticks crossed
        usdtDeposited = uint144(_bound(usdtDeposited, 0, usdtMinted)); // Minimum amount that must be deposited is

        // Approve assistant to spend USDT
        vm.prank(user);
        USDT.forceApprove(address(vault), usdtDeposited);

        // Mint TEA or APE and test it against quoteMint
        bool mintMustRevert;
        uint256 amountTokens;
        uint256 amountCollateral;
        // vm.writeLine("./test.log", string.concat("quoteMint with ", vm.toString(usdtDeposited)));
        try
            // Quote mint
            assistant.quoteMintWithDebtToken(isAPE, vaultParams, usdtDeposited)
        returns (uint256 amountTokens_, uint256 amountCollateral_) {
            amountTokens = amountTokens_;
            amountCollateral = amountCollateral_;
            amountCollateralMin = uint144(_bound(amountCollateralMin, 1, amountCollateral));
            mintMustRevert = false;
            // vm.writeLine("./test.log", string.concat("quoteMint returned ", vm.toString(amountTokens)));
        } catch {
            mintMustRevert = true;
            // vm.writeLine("./test.log", "quoteMint reverted");
        }
        // vm.writeLine("./test.log", "--------------------------------");

        // Deal USDT
        vm.assume(user != address(0));
        deal(address(USDT), user, usdtDeposited);

        vm.prank(user);
        if (mintMustRevert) {
            // Mint must revert
            vm.expectRevert();
            vault.mint(isAPE, vaultParams, usdtDeposited, amountCollateralMin, 0);
        } else {
            try
                // Mint could revert
                vault.mint(isAPE, vaultParams, usdtDeposited, amountCollateralMin, 0)
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
        try
            // Quote mint
            assistant.quoteBurn(isAPE, vaultParams, tokensBurnt)
        returns (uint144 amountCollateral_) {
            amountCollateral = amountCollateral_;
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

        // Price of 1 ether at April 15, 2024 was 3,080 USDT approximately
        assertApproxEqAbs(amountDebtToken, 3_080e6, 1e6); // 1 USDT as margin of error
    }

    ////////////////////////////////////////////////////////////////////////
    /////////////// P R I V A T E ////// F U N C T I O N S ////////////////
    //////////////////////////////////////////////////////////////////////

    function _initializeState(int8 leverageTier, State memory state) private {
        state.totalReserve = _bound(state.totalReserve, 2, HYPE_SUPPLY);
        state.collectedFees = _bound(state.collectedFees, 0, HYPE_SUPPLY);

        state.teaTotalSupply = uint128(_bound(state.teaTotalSupply, 0, SystemConstants.TEA_MAX_SUPPLY));
        state.teaBalanceVault = uint128(_bound(state.teaBalanceVault, 0, state.teaTotalSupply));

        // Deposit WHYPE to vault
        _dealWHYPE(address(vault), state.totalReserve + state.collectedFees);

        bytes32 slotInd = keccak256(
            abi.encode(
                leverageTier,
                keccak256(
                    abi.encode(
                        AddressesHyperEVM.ADDR_WHYPE,
                        keccak256(abi.encode(AddressesHyperEVM.ADDR_USDT0, bytes32(uint256(SLOT_VAULT_STATE))))
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
            SirStructs.VaultParameters(AddressesHyperEVM.ADDR_USDT0, AddressesHyperEVM.ADDR_WHYPE, leverageTier)
        );
        assertEq(vaultState.reserve, state.totalReserve, "Wrong reserve used by vm.store");
        assertEq(vaultState.tickPriceSatX42, state.tickPriceSatX42, "Wrong tickPriceSatX42 used by vm.store");
        assertEq(vaultState.vaultId, vaultId_, "Wrong vaultId used by vm.store");

        //////////////////////////////////////////////////////////////////////////

        slotInd = keccak256(abi.encode(AddressesHyperEVM.ADDR_WHYPE, bytes32(uint256(SLOT_RESERVES_TOTAL))));
        vm.store(address(vault), slotInd, bytes32(state.totalReserve));

        uint256 totalReserve_ = vault.totalReserves(AddressesHyperEVM.ADDR_WHYPE);
        assertEq(
            WHYPE.balanceOf(address(vault)) - state.totalReserve,
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

    function _dealWHYPE(address to, uint256 amount) private {
        vm.deal(vm.addr(1), amount);
        vm.prank(vm.addr(1));
        WHYPE.deposit{value: amount}();
        vm.prank(vm.addr(1));
        WHYPE.transfer(address(to), amount);
    }
}
