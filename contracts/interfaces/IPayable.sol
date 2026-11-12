// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title IPayable
 * @notice Reactive Network standard interface for system contracts and callback proxies
 *         that accept native fee settlements and track per-contract protocol debt.
 */
interface IPayable {
    /// @notice Allows the contract to receive native currency (ETH / REACT) for fee settlement.
    receive() external payable;

    /// @notice Queries the unpaid protocol debt accrued by `_contract`.
    /// @param _contract The Reactive or Callback contract address to inspect.
    /// @return The accrued debt amount in wei.
    function debt(address _contract) external view returns (uint256);
}
