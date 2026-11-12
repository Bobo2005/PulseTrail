// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "../interfaces/IPayable.sol";

/**
 * @title AbstractPayer
 * @notice Base contract for Reactive contracts and Destination Callback contracts that settle
 *         execution/callback fees with the Reactive System Contract or Callback Proxy.
 */
abstract contract AbstractPayer is IPayable {
    /// @notice The system vendor or callback proxy to which protocol debt is owed.
    IPayable internal vendor;

    /// @notice Whitelist of addresses authorized to trigger callbacks or request fee payments.
    mapping(address => bool) internal senders;

    error NotAuthorizedSender(address caller);
    error TransferFailed();

    /**
     * @notice Restricts execution to registered system contracts / callback proxies.
     */
    modifier authorizedSenderOnly() {
        if (!senders[msg.sender]) {
            revert NotAuthorizedSender(msg.sender);
        }
        _;
    }

    constructor() {}

    /// @inheritdoc IPayable
    receive() external payable virtual override {}

    /**
     * @notice Called by an authorized Callback Proxy or System Contract to collect `amount` of native currency.
     * @param amount Exact wei requested by the vendor.
     */
    function pay(uint256 amount) external authorizedSenderOnly {
        _pay(payable(msg.sender), amount);
    }

    /**
     * @inheritdoc IPayable
     */
    function debt(address _contract) external view virtual override returns (uint256) {
        if (address(vendor) == address(0) || address(vendor).code.length == 0) return 0;
        return vendor.debt(_contract);
    }

    /**
     * @notice Automatically queries and settles any outstanding protocol debt with `vendor`.
     */
    function coverDebt() external {
        if (address(vendor) == address(0) || address(vendor).code.length == 0) return;
        uint256 amount = vendor.debt(address(this));
        if (amount > 0) {
            _pay(payable(address(vendor)), amount);
        }
    }

    /**
     * @notice Internal helper for safe native token transfer.
     * @param recipient Destination payable address.
     * @param amount Amount in wei to transfer.
     */
    function _pay(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Insufficient funds");
        if (amount > 0) {
            (bool success, ) = recipient.call{value: amount}(new bytes(0));
            if (!success) {
                revert TransferFailed();
            }
        }
    }

    /**
     * @notice Grants callback/payment authorization to `_sender`.
     * @param _sender Address to authorize (e.g., Callback Proxy or System Contract).
     */
    function addAuthorizedSender(address _sender) internal {
        senders[_sender] = true;
    }

    /**
     * @notice Revokes callback/payment authorization from `_sender`.
     * @param _sender Address to deauthorize.
     */
    function removeAuthorizedSender(address _sender) internal {
        senders[_sender] = false;
    }
}

