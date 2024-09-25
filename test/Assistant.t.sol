// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {Addresses} from "core/libraries/Addresses.sol";
import {Oracle} from "core/Oracle.sol";
import {SystemControl} from "core/SystemControl.sol";
import {SIR} from "core/SIR.sol";
import {APE} from "core/APE.sol";
import {Vault} from "core/Vault.sol";
import {SystemConstants} from "core/libraries/SystemConstants.sol";
import {SirStructs} from "core/libraries/SirStructs.sol";
import {IWETH9} from "core/interfaces/IWETH9.sol";
import {Assistant} from "src/Assistant.sol";
import {AddressClone} from "core/libraries/AddressClone.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract AssistantTest is Test {
    struct State {
        uint144 reserve;
        int64 tickPriceSatX42;
        uint144 total;
        uint112 collectedFees;
        uint128 teaTotalSupply;
        uint128 teaBalanceVault;
        uint256 apeTotalSupply;
    }

    bytes32 private constant _HASH_CREATION_CODE_APE = keccak256(type(APE).creationCode);

    uint256 constant SLOT_TEA_SUPPLY = 4;
    uint256 constant SLOT_APE_SUPPLY = 5;
    uint256 constant SLOT_VAULT_STATE = 7;
    uint256 constant SLOT_TOKEN_STATE = 8;

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

        vm.createSelectFork("mainnet", 18128102);

        // Deploy oracle
        address oracle = address(new Oracle());

        // Deploy SystemControl
        address systemControl = address(new SystemControl());

        // Deploy SIR token contract
        address payable sir = payable(address(new SIR()));

        // Deploy APE implementation
        address ape = address(new APE());

        // Deploy Vault
        vault = new Vault(systemControl, sir, oracle, ape);

        // Initialize SIR
        SIR(sir).initialize(address(vault));

        // Initialize SystemControl
        SystemControl(systemControl).initialize(address(vault));

        // Deploy Assistant
        assistant = new Assistant(address(vault));

        // Approve Assistant to spend WETH
        WETH.approve(address(vault), type(uint256).max);
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
            vault.mint(isAPE, vaultParams, wethDeposited);
        } else {
            try
                // Mint could revert
                vault.mint(isAPE, vaultParams, wethDeposited)
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
            vault.mint{value: ethDeposited}(isAPE, vaultParams, ethFakeDeposited);
        } else {
            try
                // Mint could revert
                vault.mint{value: ethDeposited}(isAPE, vaultParams, ethFakeDeposited)
            returns (uint256 amountTokens_) {
                // Mint does not revert like quoteMint
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

        // Deal WETH
        vm.assume(user != address(0));
        _dealWETH(user, wethMinted);

        vm.prank(user);
        if (mintMustRevert) {
            // Mint must revert
            vm.expectRevert();
            vault.mint(isAPE, vaultParams, wethDeposited);
        } else {
            try
                // Mint could revert
                vault.mint(isAPE, vaultParams, wethDeposited)
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

        // Bound WETH amounts
        ethMinted = uint144(_bound(ethMinted, 0, ETH_SUPPLY));
        ethDeposited = uint144(_bound(ethDeposited, 0, ethMinted)); // Minimum amount that must be deposited is

        // Mint TEA or APE and test it against quoteMint
        bool mintMustRevert;
        uint256 amountTokens;
        try
            // Quote mint
            assistant.quoteMint(isAPE, vaultParams, ethDeposited)
        returns (uint256 amountTokens_) {
            amountTokens = amountTokens_;
            mintMustRevert = false;
        } catch {
            mintMustRevert = true;
        }

        // Deal WETH
        vm.assume(user != address(0));
        deal(user, ethMinted);

        vm.prank(user);
        if (mintMustRevert) {
            // Mint must revert
            vm.expectRevert();
            vault.mint{value: ethDeposited}(isAPE, vaultParams, ethFakeDeposited);
        } else {
            try
                // Mint could revert
                vault.mint{value: ethDeposited}(isAPE, vaultParams, ethFakeDeposited)
            returns (uint256 amountTokens_) {
                // Mint does not revert like quoteMint
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

    ////////////////////////////////////////////////////////////////////////
    /////////////// P R I V A T E ////// F U N C T I O N S ////////////////
    //////////////////////////////////////////////////////////////////////

    function _initializeState(int8 leverageTier, State memory state) private {
        state.total = uint144(_bound(state.total, 2, type(uint144).max));
        state.reserve = uint144(_bound(state.reserve, 2, state.total));
        state.collectedFees = uint112(_bound(state.collectedFees, 0, state.total - state.reserve));

        state.teaTotalSupply = uint128(_bound(state.teaTotalSupply, 0, SystemConstants.TEA_MAX_SUPPLY));
        state.teaBalanceVault = uint128(_bound(state.teaBalanceVault, 0, state.teaTotalSupply));

        // Deposit WETH to vault
        _dealWETH(address(vault), state.total);

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

        vm.store(address(vault), slotInd, bytes32(abi.encodePacked(vaultId_, state.tickPriceSatX42, state.reserve)));

        SirStructs.VaultState memory vaultState = vault.vaultStates(
            SirStructs.VaultParameters(Addresses.ADDR_USDT, Addresses.ADDR_WETH, leverageTier)
        );
        assertEq(vaultState.reserve, state.reserve, "Wrong reserve used by vm.store");
        assertEq(vaultState.tickPriceSatX42, state.tickPriceSatX42, "Wrong tickPriceSatX42 used by vm.store");
        assertEq(vaultState.vaultId, vaultId_, "Wrong vaultId used by vm.store");

        //////////////////////////////////////////////////////////////////////////

        slotInd = keccak256(abi.encode(Addresses.ADDR_WETH, bytes32(uint256(SLOT_TOKEN_STATE))));
        vm.store(address(vault), slotInd, bytes32(abi.encodePacked(state.total, state.collectedFees)));

        SirStructs.CollateralState memory collateralState = vault.collateralStates(Addresses.ADDR_WETH);
        assertEq(collateralState.totalFeesToStakers, state.collectedFees, "Wrong collectedFees used by vm.store");
        assertEq(collateralState.total, state.total, "Wrong total used by vm.store");

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
