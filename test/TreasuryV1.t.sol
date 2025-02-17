// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

// Libraries
import {Addresses} from "core/libraries/Addresses.sol";

// Contracts
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {TreasuryV1} from "src/TreasuryV1.sol";
import {Oracle} from "core/Oracle.sol";
import {SystemControl} from "core/SystemControl.sol";
import {SIR} from "core/SIR.sol";
import {APE} from "core/APE.sol";
import {Vault} from "core/Vault.sol";

import "forge-std/Test.sol";

contract TreasuryV1Test is Test {
    address public proxy;
    address payable sir;

    function setUp() public {
        vm.createSelectFork("mainnet", 18128102);

        // Treasury address
        string memory json = vm.readFile("lib/core/contributors/spice-contributors.json");
        proxy = stdJson.readAddress(json, "$[0].address");

        // ------------------- Treasury -------------------

        // Deploy treasury implementation
        TreasuryV1 treasuryImplementation = new TreasuryV1();

        // Deploy treasury proxy and initialize owner
        deployCodeTo(
            "ERC1967Proxy.sol",
            abi.encode(address(treasuryImplementation), abi.encodeWithSelector(TreasuryV1.initialize.selector)),
            proxy
        );

        // --------------------- Core ---------------------

        // Deploy oracle
        address oracle = address(new Oracle(Addresses.ADDR_UNISWAPV3_FACTORY));

        // Deploy SystemControl
        address systemControl = address(new SystemControl());

        // Deploy SIR
        sir = payable(address(new SIR(Addresses.ADDR_WETH, systemControl)));

        // Deploy APE implementation
        address apeImplementation = address(new APE());

        // Deploy Vault
        address vault = address(new Vault(systemControl, sir, oracle, apeImplementation, Addresses.ADDR_WETH));

        // Initialize SIR
        SIR(sir).initialize(vault);

        // Initialize SystemControl
        SystemControl(systemControl).initialize(vault, sir);
    }

    function test_Ownership() public view {
        TreasuryV1 treasury = TreasuryV1(proxy);
        assertEq(treasury.owner(), address(this), "Owner should be test_ contract");
    }

    error InvalidInitialization();

    function test_CannotReinitialize() public {
        TreasuryV1 treasury = TreasuryV1(proxy);
        vm.expectRevert(InvalidInitialization.selector);
        treasury.initialize();
    }

    function test_RelayCallSuccess() public {
        TreasuryV1 treasury = TreasuryV1(proxy);
        MockContract mock = new MockContract();

        bytes memory data = abi.encodeWithSelector(mock.doSomething.selector);
        bytes memory result = treasury.relayCall(address(mock), data);

        uint256 decoded = abi.decode(result, (uint256));
        assertEq(decoded, 42, "Should return correct value");
    }

    function test_RelayCallRevertWithMessage() public {
        TreasuryV1 treasury = TreasuryV1(proxy);
        MockContract mock = new MockContract();

        bytes memory data = abi.encodeWithSelector(mock.doRevert.selector);
        vm.expectRevert("MockContract: error");
        treasury.relayCall(address(mock), data);
    }

    function test_RelayCallRevertWithoutMessage() public {
        TreasuryV1 treasury = TreasuryV1(proxy);
        MockContract mock = new MockContract();

        bytes memory data = abi.encodeWithSelector(mock.doRevertWithoutMessage.selector);
        vm.expectRevert("relayCall failed");
        treasury.relayCall(address(mock), data);
    }

    error OwnableUnauthorizedAccount(address account);

    function test_NonOwnerCannotRelayCall() public {
        TreasuryV1 treasury = TreasuryV1(proxy);
        address attacker = address(0xbad);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, attacker));
        treasury.relayCall(address(0), "");
    }

    function test_MintSIR() public {
        TreasuryV1 treasury = TreasuryV1(proxy);
        skip(1000 days);

        assertEq(IERC20(sir).balanceOf(proxy), 0);
        treasury.relayCall(sir, abi.encodeWithSelector(SIR.contributorMint.selector));
        assertTrue(IERC20(sir).balanceOf(proxy) > 0);
    }

    // Add these test functions to your TreasuryV1Test contract
    function test_SuccessfulUpgrade() public {
        // Deploy new implementation
        TreasuryV2 v2Implementation = new TreasuryV2();

        // Perform upgrade
        TreasuryV1(proxy).upgradeToAndCall(address(v2Implementation), "");

        // Verify implementation changed
        address newImpl = getImplementation(proxy);
        assertEq(newImpl, address(v2Implementation), "Implementation not upgraded");

        // Test new functionality
        TreasuryV2 upgraded = TreasuryV2(proxy);
        assertEq(upgraded.newFeature(), "V2 functionality", "New feature not working");

        // Verify existing state preserved
        assertEq(upgraded.owner(), address(this), "Ownership not preserved");
    }

    function test_NonOwnerCannotUpgrade() public {
        address attacker = address(0xbad);
        TreasuryV2 v2Implementation = new TreasuryV2();

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, attacker));
        TreasuryV1(proxy).upgradeToAndCall(address(v2Implementation), "");
    }

    // Helper function to read implementation address from storage
    function getImplementation(address proxyAddr) internal view returns (address) {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        return address(uint160(uint256(vm.load(proxyAddr, slot))));
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

contract TreasuryV2 is TreasuryV1 {
    function newFeature() public pure returns (string memory) {
        return "V2 functionality";
    }
}
