// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/**
 * @title Disperse
 * @notice Batch-distribute ETH or ERC20 tokens to many recipients in a single
 *         transaction. A Solidity 0.8 reimplementation of the canonical Disperse
 *         (banteg), used to pay out SIR leaderboard prizes.
 *
 * @dev `disperseToken` pulls `sum(values)` from the caller into this contract
 *      (the caller must `approve` this contract first) and then fans the tokens
 *      out. `disperseTokenSimple` transfers directly from the caller to each
 *      recipient. Token transfers go through a minimal safe-call helper that
 *      accepts both standard (bool-returning) and non-standard (void-returning)
 *      ERC20s. The contract is stateless: it never holds tokens or ETH between
 *      calls, so there is nothing to rescue or administer.
 */
contract Disperse {
    function disperseEther(
        address[] calldata recipients,
        uint256[] calldata values
    ) external payable {
        require(recipients.length == values.length, "length mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            (bool ok, ) = payable(recipients[i]).call{value: values[i]}("");
            require(ok, "ether transfer failed");
        }
        // Refund any dust left over (e.g. caller over-sent msg.value).
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool ok, ) = payable(msg.sender).call{value: balance}("");
            require(ok, "refund failed");
        }
    }

    function disperseToken(
        IERC20 token,
        address[] calldata recipients,
        uint256[] calldata values
    ) external {
        require(recipients.length == values.length, "length mismatch");
        uint256 total = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            total += values[i];
        }
        _safeTransferFrom(token, msg.sender, address(this), total);
        for (uint256 i = 0; i < recipients.length; i++) {
            _safeTransfer(token, recipients[i], values[i]);
        }
    }

    function disperseTokenSimple(
        IERC20 token,
        address[] calldata recipients,
        uint256[] calldata values
    ) external {
        require(recipients.length == values.length, "length mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            _safeTransferFrom(token, msg.sender, recipients[i], values[i]);
        }
    }

    function _safeTransfer(IERC20 token, address to, uint256 value) private {
        _safeCall(
            address(token),
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    function _safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) private {
        _safeCall(
            address(token),
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
    }

    /// @dev Reverts unless the call succeeds and returns either nothing or `true`.
    function _safeCall(address token, bytes memory data) private {
        (bool success, bytes memory returndata) = token.call(data);
        require(
            success && (returndata.length == 0 || abi.decode(returndata, (bool))),
            "token transfer failed"
        );
    }
}
