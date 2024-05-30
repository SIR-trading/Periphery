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
import {VaultStructs} from "core/libraries/VaultStructs.sol";
import {IWETH9} from "core/interfaces/IWETH9.sol";
import {Assistant} from "src/Assistant.sol";
import {SaltedAddress} from "core/libraries/SaltedAddress.sol";
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

    uint256 constant SLOT_TEA_SUPPLY = 4;
    uint256 constant SLOT_APE_SUPPLY = 2;
    uint256 constant SLOT_VAULT_STATE = 7;
    uint256 constant SLOT_TOKEN_STATE = 8;

    IWETH9 private constant WETH = IWETH9(Addresses.ADDR_WETH);
    IERC20 private constant USDT = IERC20(Addresses.ADDR_USDT);

    Vault vault;
    Assistant assistant;

    uint96 constant ETH_SUPPLY = 120e6 * 10 ** 18;
    uint256 constant USDT_SUPPLY = 100e9 * 10 ** 6;

    function setUp() public {
        // vm.writeFile("./mint.log", "");

        vm.createSelectFork("mainnet", 18128102);

        // Deploy oracle
        address oracle = address(new Oracle(Addresses.ADDR_UNISWAPV3_FACTORY));

        // Deploy SystemControl
        address systemControl = address(new SystemControl());

        // Deploy SIR token contract
        address payable sir = payable(address(new SIR(Addresses.ADDR_WETH)));

        // Deploy Vault
        vault = new Vault(systemControl, sir, oracle);

        // Initialize SIR
        SIR(sir).initialize(address(vault));

        // Initialize SystemControl
        SystemControl(systemControl).initialize(address(vault), sir);

        // Deploy Assistant
        assistant = new Assistant(address(0), address(vault));

        // Approve Assistant to spend WETH
        WETH.approve(address(assistant), type(uint256).max);
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
        leverageTier = _initializeVault(leverageTier);

        // Bound WETH amounts
        wethMinted = uint144(_bound(wethMinted, 2, ETH_SUPPLY));
        wethDeposited = uint144(_bound(wethDeposited, 2, wethMinted)); // Minimum amount that must be deposited is

        // Deal WETH
        vm.assume(user != address(0));
        _dealWETH(user, wethDeposited);

        // Get vault ID if TEA
        (, , uint48 vaultId) = vault.vaultStates(Addresses.ADDR_USDT, Addresses.ADDR_WETH, leverageTier);

        // Approve assistant to spend WETH
        vm.prank(user);
        WETH.approve(address(assistant), wethDeposited);

        // Mint TEA or APE and test it against quoteMint
        bool expectRevert;
        uint256 amountTokens;
        try
            // Quote mint
            assistant.quoteMint(
                isAPE,
                VaultStructs.VaultParameters({
                    debtToken: Addresses.ADDR_USDT,
                    collateralToken: Addresses.ADDR_WETH,
                    leverageTier: leverageTier
                }),
                wethDeposited
            )
        returns (uint256 temp) {
            expectRevert = false;
            amountTokens = temp;
        } catch {
            expectRevert = true;
            vm.expectRevert();
        }

        // Mint
        vm.prank(user);
        uint256 amountTokens_ = assistant.mint(
            isAPE ? SaltedAddress.getAddress(address(vault), vaultId) : address(0),
            vaultId,
            VaultStructs.VaultParameters({
                debtToken: Addresses.ADDR_USDT,
                collateralToken: Addresses.ADDR_WETH,
                leverageTier: leverageTier
            }),
            wethDeposited
        );
        if (!expectRevert) {
            assertEq(amountTokens_, amountTokens, "mint and quoteMint should return the same amount of tokens");
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
        leverageTier = _initializeVault(leverageTier);

        // Get vault ID
        (, , uint48 vaultId) = vault.vaultStates(Addresses.ADDR_USDT, Addresses.ADDR_WETH, leverageTier);

        // Initialize vault state
        address ape = SaltedAddress.getAddress(address(vault), vaultId);
        _initializeState(leverageTier, state, ape);

        // Bound WETH amounts
        wethMinted = uint144(_bound(wethMinted, 0, ETH_SUPPLY));
        wethDeposited = uint144(_bound(wethDeposited, 0, wethMinted)); // Minimum amount that must be deposited is

        // Deal WETH
        vm.assume(user != address(0));
        _dealWETH(user, wethDeposited);

        // Approve assistant to spend WETH
        vm.prank(user);
        WETH.approve(address(assistant), wethDeposited);

        // Mint TEA or APE and test it against quoteMint
        bool mayWork;
        uint256 amountTokens;
        try
            // Quote mint
            assistant.quoteMint(
                isAPE,
                VaultStructs.VaultParameters({
                    debtToken: Addresses.ADDR_USDT,
                    collateralToken: Addresses.ADDR_WETH,
                    leverageTier: leverageTier
                }),
                wethDeposited
            )
        returns (uint256 temp) {
            amountTokens = temp;
            mayWork = true;
        } catch {
            // vm.writeLine("./mint.log", "quoteMint revert, mint revert");
            // quoteMint reverts => mint reverts
            vm.expectRevert();
            vm.prank(user);
            assistant.mint(
                isAPE ? ape : address(0),
                vaultId,
                VaultStructs.VaultParameters({
                    debtToken: Addresses.ADDR_USDT,
                    collateralToken: Addresses.ADDR_WETH,
                    leverageTier: leverageTier
                }),
                wethDeposited
            );
        }

        // Mint
        if (mayWork) {
            vm.prank(user);
            try
                assistant.mint(
                    isAPE ? SaltedAddress.getAddress(address(vault), vaultId) : address(0),
                    vaultId,
                    VaultStructs.VaultParameters({
                        debtToken: Addresses.ADDR_USDT,
                        collateralToken: Addresses.ADDR_WETH,
                        leverageTier: leverageTier
                    }),
                    wethDeposited
                )
            returns (uint256 amountTokens_) {
                // vm.writeLine("./mint.log", "quoteMint successful, mint successful");
                assertEq(amountTokens_, amountTokens, "mint and quoteMint should return the same amount of tokens");
            } catch {
                // vm.writeLine("./mint.log", "quoteMint successful, mint revert");
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
        leverageTier = _initializeVault(leverageTier);

        // Get vault ID
        (, , uint48 vaultId) = vault.vaultStates(Addresses.ADDR_USDT, Addresses.ADDR_WETH, leverageTier);

        // Initialize vault state
        address ape = SaltedAddress.getAddress(address(vault), vaultId);
        _initializeState(leverageTier, state, ape);

        vm.assume(user != address(0));

        // Burn TEA or APE and test it against quoteMint
        bool mayWork;
        uint144 amountCollateral;
        try
            // Quote mint
            assistant.quoteBurn(
                isAPE,
                VaultStructs.VaultParameters({
                    debtToken: Addresses.ADDR_USDT,
                    collateralToken: Addresses.ADDR_WETH,
                    leverageTier: leverageTier
                }),
                tokensBurnt
            )
        returns (uint144 temp) {
            amountCollateral = temp;
            mayWork = true;
        } catch {
            // vm.writeLine("./mint.log", "quoteMint revert, mint revert");
            // quoteMint reverts => mint reverts
            vm.expectRevert();
            vm.prank(user);
            vault.burn(
                isAPE,
                VaultStructs.VaultParameters({
                    debtToken: Addresses.ADDR_USDT,
                    collateralToken: Addresses.ADDR_WETH,
                    leverageTier: leverageTier
                }),
                tokensBurnt
            );
        }

        // Mint
        if (mayWork) {
            vm.prank(user);
            try
                vault.burn(
                    isAPE,
                    VaultStructs.VaultParameters({
                        debtToken: Addresses.ADDR_USDT,
                        collateralToken: Addresses.ADDR_WETH,
                        leverageTier: leverageTier
                    }),
                    tokensBurnt
                )
            returns (uint144 amountCollateral_) {
                // vm.writeLine("./mint.log", "quoteMint successful, mint successful");
                assertEq(
                    amountCollateral_,
                    amountCollateral,
                    "burn and quoteBurn should return the same amount of collateral"
                );
            } catch {
                // vm.writeLine("./mint.log", "quoteMint successful, mint revert");
            }
        }
    }

    // function testFuzz_swapAndMintFirstTime(
    //     bool isAPE,
    //     int8 leverageTier,
    //     uint144 usdtMinted,
    //     uint144 usdtDeposited,
    //     address user
    // ) public {
    //     // Initialize vault
    //     leverageTier = _initializeVault(leverageTier);

    //     // Bound WETH amounts
    //     usdtMinted = uint144(_bound(usdtMinted, 2, USDT_SUPPLY));
    //     usdtDeposited = uint144(_bound(usdtDeposited, 2, usdtMinted)); // Minimum amount that must be deposited is 2

    //     // Deal USDT
    //     vm.assume(user != address(0));
    //     _dealUSDT(user, wethDeposited);

    //     // Get vault ID if TEA
    //     (, , uint48 vaultId) = vault.vaultStates(Addresses.ADDR_USDT, Addresses.ADDR_WETH, leverageTier);

    //     // Approve assistant to spend USDT
    //     vm.prank(user);
    //     USDT.approve(address(assistant), usdtDeposited);

    //     // Mint TEA or APE and test it against quoteMint
    //     bool expectRevert;
    //     uint256 amountTokens;
    //     try
    //         // Quote mint
    //         assistant.quoteMint(
    //             isAPE,
    //             VaultStructs.VaultParameters({
    //                 debtToken: Addresses.ADDR_USDT,
    //                 collateralToken: Addresses.ADDR_WETH,
    //                 leverageTier: leverageTier
    //             }),
    //             wethDeposited
    //         )
    //     returns (uint256 temp) {
    //         expectRevert = false;
    //         amountTokens = temp;
    //     } catch {
    //         expectRevert = true;
    //         vm.expectRevert();
    //     }

    //     // Mint
    //     vm.prank(user);
    //     uint256 amountTokens_ = assistant.mint(
    //         isAPE ? SaltedAddress.getAddress(address(vault), vaultId) : address(0),
    //         vaultId,
    //         VaultStructs.VaultParameters({
    //             debtToken: Addresses.ADDR_USDT,
    //             collateralToken: Addresses.ADDR_WETH,
    //             leverageTier: leverageTier
    //         }),
    //         wethDeposited
    //     );
    //     if (!expectRevert) {
    //         assertEq(amountTokens_, amountTokens, "mint and quoteMint should return the same amount of tokens");
    //     }
    // }

    ////////////////////////////////////////////////////////////////////////
    /////////////// P R I V A T E ////// F U N C T I O N S ////////////////
    //////////////////////////////////////////////////////////////////////

    function _initializeState(int8 leverageTier, State memory state, address ape) private {
        state.total = uint144(_bound(state.total, 2, type(uint144).max));
        state.reserve = uint144(_bound(state.reserve, 2, state.total));
        state.collectedFees = uint112(_bound(state.collectedFees, 0, state.total - state.reserve));

        state.teaTotalSupply = uint128(_bound(state.teaTotalSupply, 0, SystemConstants.TEA_MAX_SUPPLY));
        state.teaBalanceVault = uint128(_bound(state.teaBalanceVault, 0, state.teaTotalSupply));

        // Deposit WETH to vault
        _dealWETH(address(vault), state.total);

        console.log("state.reserve", state.reserve);
        console.log("state.tickPriceSatX42", vm.toString(state.tickPriceSatX42));
        console.log("state.total", state.total);
        console.log("state.collectedFees", state.collectedFees);
        console.log("state.teaTotalSupply", state.teaTotalSupply);
        console.log("state.teaBalanceVault", state.teaBalanceVault);
        console.log("state.apeTotalSupply", state.apeTotalSupply);

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

        (uint144 reserve, int64 tickPriceSatX42, uint48 vaultId) = vault.vaultStates(
            Addresses.ADDR_USDT,
            Addresses.ADDR_WETH,
            leverageTier
        );
        assertEq(reserve, state.reserve, "Wrong reserve used by vm.store");
        assertEq(tickPriceSatX42, state.tickPriceSatX42, "Wrong tickPriceSatX42 used by vm.store");
        assertEq(vaultId, vaultId_, "Wrong vaultId used by vm.store");

        //////////////////////////////////////////////////////////////////////////

        slotInd = keccak256(abi.encode(Addresses.ADDR_WETH, bytes32(uint256(SLOT_TOKEN_STATE))));
        vm.store(address(vault), slotInd, bytes32(abi.encodePacked(state.total, state.collectedFees)));

        (uint112 collectedFees, uint144 total) = vault.tokenStates(Addresses.ADDR_WETH);
        assertEq(collectedFees, state.collectedFees, "Wrong collectedFees used by vm.store");
        assertEq(total, state.total, "Wrong total used by vm.store");

        //////////////////////////////////////////////////////////////////////////

        vm.store(ape, bytes32(SLOT_APE_SUPPLY), bytes32(state.apeTotalSupply));
        assertEq(IERC20(ape).totalSupply(), state.apeTotalSupply, "Wrong apeTotalSupply used by vm.store");
    }

    function _initializeVault(int8 leverageTier) private returns (int8 boundedLeverageTier) {
        boundedLeverageTier = int8(
            _bound(leverageTier, SystemConstants.MIN_LEVERAGE_TIER, SystemConstants.MAX_LEVERAGE_TIER)
        );

        // Initialize vault
        vault.initialize(
            VaultStructs.VaultParameters({
                debtToken: Addresses.ADDR_USDT,
                collateralToken: Addresses.ADDR_WETH,
                leverageTier: boundedLeverageTier
            })
        );
    }

    function _dealWETH(address to, uint256 amount) private {
        vm.deal(vm.addr(1), amount);
        vm.prank(vm.addr(1));
        WETH.deposit{value: amount}();
        vm.prank(vm.addr(1));
        WETH.transfer(address(to), amount);
    }

    function _dealUSDT(address to, uint256 amount) private {
        if (amount == 0) return;
        deal(Addresses.ADDR_USDT, vm.addr(1), amount);
        vm.prank(vm.addr(1));
        USDT.approve(address(this), amount);
        USDT.transferFrom(vm.addr(1), to, amount); // I used transferFrom instead of transfer because of the weird BNB non-standard quirks
    }
}
