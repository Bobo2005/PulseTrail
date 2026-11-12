// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MockERC20 } from "./MockERC20.sol";

/**
 * @title MockHoneypotERC20
 * @notice Malicious ERC-20 token that allows normal deposits when `honeypotMode == false`,
 *         but reverts on `transfer` / `transferFrom` once `honeypotMode == true` to test
 *         `PulseTrailCallback`'s `try/catch` isolation.
 */
contract MockHoneypotERC20 is MockERC20 {
    bool public honeypotMode;
    bool public revertWithoutReason;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) MockERC20(_name, _symbol, _decimals) {}

    /// @notice Enables or disables the malicious transfer revert behavior.
    function setHoneypotMode(bool _enabled) external {
        honeypotMode = _enabled;
    }

    /// @notice Configures whether the honeypot reverts with a low-level empty revert vs. `Error(string)`.
    function setRevertWithoutReason(bool _emptyRevert) external {
        revertWithoutReason = _emptyRevert;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        if (honeypotMode) {
            if (revertWithoutReason) {
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    revert(0, 0)
                }
            }
            revert("Honeypot: Token transfer blocked");
        }
        super._transfer(from, to, amount);
    }
}

