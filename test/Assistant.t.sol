// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import {IWETH9} from "core/interfaces/IWETH9.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

// Libraries
import {Addresses} from "core/libraries/Addresses.sol";
import {SystemConstants} from "core/libraries/SystemConstants.sol";
import {SirStructs} from "core/libraries/SirStructs.sol";
import {AddressClone} from "core/libraries/AddressClone.sol";

// Contracts
import {Oracle} from "core/Oracle.sol";
import {SystemControl} from "core/SystemControl.sol";
import {SIR} from "core/SIR.sol";
import {APE} from "core/APE.sol";
import {Vault} from "core/Vault.sol";
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

    IWETH9 private constant WETH = IWETH9(Addresses.ADDR_WETH);
    IERC20 private constant USDT = IERC20(Addresses.ADDR_USDT);

    Vault vault;
    Assistant assistant;

    uint96 constant ETH_SUPPLY = 120e6 * 10 ** 18;
    uint256 constant USDT_SUPPLY = 100e9 * 10 ** 6;

    SirStructs.VaultParameters vaultParams =
        SirStructs.VaultParameters({
            debtToken: Addresses.ADDR_USDT,
            collateralToken: Addresses.ADDR_WETH,
            leverageTier: 0
        });

    function setUp() public {
        // vm.writeFile("./mint.log", "");

        vm.createSelectFork("mainnet", 19662664);

        // Deploy oracle
        address oracle = address(new Oracle(Addresses.ADDR_UNISWAPV3_FACTORY));

        // Deploy SystemControl
        address systemControl = address(new SystemControl());

        // Deploy SIR token contract
        address payable sir = payable(address(new SIR(Addresses.ADDR_WETH, systemControl)));

        // Deploy APE implementation
        address ape = address(new APE());

        // Deploy Vault
        vault = new Vault(systemControl, sir, oracle, ape, Addresses.ADDR_WETH);

        // Initialize SIR
        SIR(sir).initialize(address(vault));

        // Initialize SystemControl
        SystemControl(systemControl).initialize(address(vault), sir);

        // Deploy Assistant
        assistant = new Assistant(address(vault), oracle, Addresses.ADDR_UNISWAPV3_FACTORY);

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
        vaultParams.collateralToken = Addresses.ADDR_BNB;
        vaultParams.debtToken = Addresses.ADDR_FRAX;

        uint256 vaultStatus = uint256(assistant.getVaultStatus(vaultParams));
        assertEq(vaultStatus, uint256(VaultStatus.NoUniswapPool));
    }

    function test_getVaultWithWrongAddress() public {
        vaultParams.collateralToken = Addresses.ADDR_WETH;
        vaultParams.debtToken = Addresses.ADDR_UNISWAPV3_FACTORY;

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
            vault.mint(isAPE, vaultParams, wethDeposited, 0);
        } else {
            try
                // Mint could revert
                vault.mint(isAPE, vaultParams, wethDeposited, 0)
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
            Addresses.ADDR_WETH,
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
            vm.expectRevert();
        }

        vm.clearMockedCalls();

        vm.prank(user);
        if (mintMustRevert) {
            // Mint must revert
            vm.expectRevert();
            vault.mint{value: ethDeposited}(isAPE, vaultParams, ethFakeDeposited, 0);
        } else {
            try
                // Mint could revert
                vault.mint{value: ethDeposited}(isAPE, vaultParams, ethFakeDeposited, 0)
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
            vault.mint(isAPE, vaultParams, usdtDeposited, amountCollateralMin);
        } else {
            try
                // Mint could revert
                vault.mint(isAPE, vaultParams, usdtDeposited, amountCollateralMin)
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
            vault.mint(isAPE, vaultParams, wethDeposited, 0);
        } else {
            try
                // Mint could revert
                vault.mint(isAPE, vaultParams, wethDeposited, 0)
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
            vault.mint{value: ethDeposited}(isAPE, vaultParams, ethFakeDeposited, 0);
        } else {
            try
                // Mint could revert
                vault.mint{value: ethDeposited}(isAPE, vaultParams, ethFakeDeposited, 0)
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
            vault.mint(isAPE, vaultParams, usdtDeposited, amountCollateralMin);
        } else {
            try
                // Mint could revert
                vault.mint(isAPE, vaultParams, usdtDeposited, amountCollateralMin)
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
            vault.burn(isAPE, vaultParams, tokensBurnt);
        } else {
            try
                // Burn could revert
                vault.burn(isAPE, vaultParams, tokensBurnt)
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
                        Addresses.ADDR_WETH,
                        keccak256(abi.encode(Addresses.ADDR_USDT, bytes32(uint256(SLOT_VAULT_STATE))))
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
            SirStructs.VaultParameters(Addresses.ADDR_USDT, Addresses.ADDR_WETH, leverageTier)
        );
        assertEq(vaultState.reserve, state.totalReserve, "Wrong reserve used by vm.store");
        assertEq(vaultState.tickPriceSatX42, state.tickPriceSatX42, "Wrong tickPriceSatX42 used by vm.store");
        assertEq(vaultState.vaultId, vaultId_, "Wrong vaultId used by vm.store");

        //////////////////////////////////////////////////////////////////////////

        slotInd = keccak256(abi.encode(Addresses.ADDR_WETH, bytes32(uint256(SLOT_RESERVES_TOTAL))));
        vm.store(address(vault), slotInd, bytes32(state.totalReserve));

        uint256 totalReserve_ = vault.totalReserves(Addresses.ADDR_WETH);
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

    // function _dealUSDT(address to, uint256 amount) private {
    //     if (amount == 0) return;
    //     deal(Addresses.ADDR_USDT, vm.addr(1), amount);
    //     vm.prank(vm.addr(1));
    //     USDT.approve(address(this), amount);
    //     USDT.transferFrom(vm.addr(1), to, amount); // I used transferFrom instead of transfer because of the weird BNB non-standard quirks
    // }
}
