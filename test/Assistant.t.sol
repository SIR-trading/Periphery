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

contract AssistantTest is Test {
    IWETH9 private constant WETH = IWETH9(Addresses.ADDR_WETH);

    Vault vault;
    Assistant assistant;

    uint96 constant ETH_SUPPLY = 120e6 * 10 ** 18;

    function setUp() public {
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
        wethDeposited = uint144(_bound(wethDeposited, 2, wethMinted)); // Minimum amount that must be deposited is 2

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

    ////////////////////////////////////////////////////////////////////////
    /////////////// P R I V A T E ////// F U N C T I O N S ////////////////
    //////////////////////////////////////////////////////////////////////

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

        (, , uint48 vaultId) = vault.vaultStates(Addresses.ADDR_USDT, Addresses.ADDR_WETH, leverageTier);
    }

    function _dealWETH(address to, uint256 amount) private {
        vm.deal(vm.addr(1), amount);
        vm.prank(vm.addr(1));
        WETH.deposit{value: amount}();
        vm.prank(vm.addr(1));
        WETH.transfer(address(to), amount);
    }
}
