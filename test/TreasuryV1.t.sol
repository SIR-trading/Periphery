// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

// Libraries
import {Addresses} from "core/libraries/Addresses.sol";
// import {SystemConstants} from "core/libraries/SystemConstants.sol";
// import {SirStructs} from "core/libraries/SirStructs.sol";

// Contracts
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {TreasuryV1} from "src/TreasuryV1.sol";
import {Oracle} from "core/Oracle.sol";
import {SystemControl} from "core/SystemControl.sol";
import {SIR} from "core/SIR.sol";
import {APE} from "core/APE.sol";
import {Vault} from "core/Vault.sol";
import {Assistant} from "src/Assistant.sol";

import "forge-std/Test.sol";

contract TreasuryV1Test is Test {
    ERC1967Proxy public proxy;

    function setUp() public {
        vm.createSelectFork("mainnet", 18128102);

        // ------------------- Treasury -------------------

        // Deploy treasury implementation
        TreasuryV1 treasuryImplementation = new TreasuryV1();

        // Deploy treasury proxy and initialize owner
        proxy = new ERC1967Proxy(
            address(treasuryImplementation),
            abi.encodeWithSelector(TreasuryV1.initialize.selector)
        );

        // --------------------- Core ---------------------

        // Deploy oracle
        address oracle = address(new Oracle(Addresses.ADDR_UNISWAPV3_FACTORY));

        // Deploy SystemControl
        address systemControl = address(new SystemControl());

        // Deploy SIR
        address payable sir = payable(address(new SIR(Addresses.ADDR_WETH, systemControl)));

        // Deploy APE implementation
        address apeImplementation = address(new APE());

        // Deploy Vault
        address vault = address(new Vault(systemControl, sir, oracle, apeImplementation, Addresses.ADDR_WETH));

        // Initialize SIR
        SIR(sir).initialize(vault);

        // Initialize SystemControl
        SystemControl(systemControl).initialize(vault, sir);
    }

    function testOwnership() public {
        TreasuryV1 treasury = TreasuryV1(address(proxy));
        assertEq(treasury.owner(), address(this), "Owner should be test contract");
    }

    error InvalidInitialization();

    function testCannotReinitialize() public {
        TreasuryV1 treasury = TreasuryV1(address(proxy));
        vm.expectRevert(InvalidInitialization.selector);
        treasury.initialize();
    }

    function testRelayCallSuccess() public {
        TreasuryV1 treasury = TreasuryV1(address(proxy));
        MockContract mock = new MockContract();

        bytes memory data = abi.encodeWithSelector(mock.doSomething.selector);
        bytes memory result = treasury.relayCall(address(mock), data);

        uint256 decoded = abi.decode(result, (uint256));
        assertEq(decoded, 42, "Should return correct value");
    }

    function testRelayCallRevertWithMessage() public {
        TreasuryV1 treasury = TreasuryV1(address(proxy));
        MockContract mock = new MockContract();

        bytes memory data = abi.encodeWithSelector(mock.doRevert.selector);
        vm.expectRevert("MockContract: error");
        treasury.relayCall(address(mock), data);
    }

    function testRelayCallRevertWithoutMessage() public {
        TreasuryV1 treasury = TreasuryV1(address(proxy));
        MockContract mock = new MockContract();

        bytes memory data = abi.encodeWithSelector(mock.doRevertWithoutMessage.selector);
        vm.expectRevert("relayCall failed");
        treasury.relayCall(address(mock), data);
    }

    error OwnableUnauthorizedAccount(address account);

    function testNonOwnerCannotRelayCall() public {
        TreasuryV1 treasury = TreasuryV1(address(proxy));
        address attacker = address(0xbad);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, attacker));
        treasury.relayCall(address(0), "");
    }
}

contract MockContract {
    function doSomething() external pure returns (uint256) {
        return 42;
    }

    function doRevert() external pure {
        revert("MockContract: error");
    }

    function doRevertWithoutMessage() external pure {
        revert();
    }
}
