// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MockERC20 } from "./MockERC20.sol";

/**
 * @title MockFeeOnTransferERC20
 * @notice ERC-20 token with a configurable `transferTaxBps` (e.g., `500` = 5% tax burned on every transfer)
 *         to verify exact post-tax balance accounting in `PulseTrailCallback`.
 */
contract MockFeeOnTransferERC20 is MockERC20 {
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Transfer tax in basis points (e.g., `500` = 5.00%).
    uint16 public transferTaxBps;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint16 _transferTaxBps
    ) MockERC20(_name, _symbol, _decimals) {
        require(_transferTaxBps <= 5_000, "Tax too high");
        transferTaxBps = _transferTaxBps;
    }

    function setTransferTaxBps(uint16 _newTaxBps) external {
        require(_newTaxBps <= 5_000, "Tax too high");
        transferTaxBps = _newTaxBps;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != address(0) && to != address(0), "ERC20: zero address");
        require(balanceOf[from] >= amount, "ERC20: transfer amount exceeds balance");

        uint256 tax = (amount * uint256(transferTaxBps)) / BPS_DENOMINATOR;
        uint256 netAmount = amount - tax;

        balanceOf[from] -= amount;
        balanceOf[to] += netAmount;

        if (tax > 0) {
            totalSupply -= tax;
            emit Transfer(from, address(0), tax);
        }
        emit Transfer(from, to, netAmount);
    }
}

