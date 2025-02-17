// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import {ISIR} from "core/interfaces/ISIR.sol";

// Libraries
import {UUPSUpgradeable} from "oz-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "oz-upgradeable/access/Ownable2StepUpgradeable.sol";

/** @notice Simplest implementation of the Treasury contract.
    @notice Only the owner can mint and/or stake SIR tokens.
    @notice To be upgraded later with a fully functioning DAO.
 */
contract TreasuryV1 is Ownable2StepUpgradeable, UUPSUpgradeable {
    uint256[50] __gap;

    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init(msg.sender);
    }

    /** @notice This function allows us to call other contracts in behalf of the Treasury.
        @notice For instance we can mint the treasury's SIR allocation, stake SIR, etc.
     */
    function relayCall(address to, bytes memory data) external onlyOwner returns (bytes memory) {
        (bool success, bytes memory retData) = to.call(data);

        // If the call was successful, return the return data
        if (success) return retData;

        // If the call failed, revert with the return data
        if (retData.length > 0) {
            assembly {
                let retData_size := mload(retData)
                revert(add(32, retData), retData_size)
            }
        }

        // If the return data is empty, revert with generic error
        revert("relayCall failed");
    }

    // --------------------- I n t e r n a l --- F u n c t i o n s ---------------------

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
