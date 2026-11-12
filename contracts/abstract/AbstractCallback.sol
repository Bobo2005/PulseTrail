// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./AbstractPayer.sol";

/**
 * @title AbstractCallback
 * @notice Base contract for destination-chain callback receivers (e.g., on Base Mainnet `8453`).
 *         Authenticates both the Reactive Callback Proxy (`authorizedSenderOnly`) and the
 *         originating ReactVM deployer ID (`rvmIdOnly`).
 */
abstract contract AbstractCallback is AbstractPayer {
    /// @notice Expected ReactVM ID (the deployer address of the associated Reactive contract).
    address internal rvm_id;

    error InvalidRvmId(address expected, address actual);

    /**
     * @param _callback_sender Official Reactive Callback Proxy on the destination chain
     *                         (e.g., `0x0D3E76De6bC44309083cAAFdB49A088B8a250947` on Base Mainnet).
     */
    constructor(address _callback_sender) {
        rvm_id = msg.sender;
        vendor = IPayable(payable(_callback_sender));
        addAuthorizedSender(_callback_sender);
    }

    /**
     * @notice Verifies that the first argument of the callback payload (overwritten by Reactive Network)
     *         matches the authorized `rvm_id`.
     * @param _rvm_id The ReactVM ID injected by the Callback Proxy into the first 32 bytes of the payload.
     */
    modifier rvmIdOnly(address _rvm_id) {
        if (rvm_id != address(0) && rvm_id != _rvm_id) {
            revert InvalidRvmId(rvm_id, _rvm_id);
        }
        _;
    }
}

