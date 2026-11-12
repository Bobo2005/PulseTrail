// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./IPayable.sol";

// Wildcard constant used when subscribing to any topic or address on Reactive Network.
uint256 constant REACTIVE_IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;

/**
 * @title ISubscriptionService
 * @notice Interface for Reactive Network's event subscription service (`0x0000000000000000000000000000000000fffFfF`).
 */
interface ISubscriptionService is IPayable {
    /**
     * @notice Subscribes the calling Reactive contract to matching logs on an origin chain.
     * @param chain_id EIP-155 chain ID of the origin network (e.g., `8453` for Base Mainnet).
     * @param _contract Emitting contract address on the origin chain (`address(0)` for wildcard).
     * @param topic_0 Event signature hash (`REACTIVE_IGNORE` for wildcard).
     * @param topic_1 First indexed topic filter (`REACTIVE_IGNORE` for wildcard).
     * @param topic_2 Second indexed topic filter (`REACTIVE_IGNORE` for wildcard).
     * @param topic_3 Third indexed topic filter (`REACTIVE_IGNORE` for wildcard).
     */
    function subscribe(
        uint256 chain_id,
        address _contract,
        uint256 topic_0,
        uint256 topic_1,
        uint256 topic_2,
        uint256 topic_3
    ) external;

    /**
     * @notice Removes an existing log subscription on the Reactive Network.
     * @param chain_id EIP-155 chain ID of the origin network.
     * @param _contract Emitting contract address on the origin chain.
     * @param topic_0 Event signature hash.
     * @param topic_1 First indexed topic filter.
     * @param topic_2 Second indexed topic filter.
     * @param topic_3 Third indexed topic filter.
     */
    function unsubscribe(
        uint256 chain_id,
        address _contract,
        uint256 topic_0,
        uint256 topic_1,
        uint256 topic_2,
        uint256 topic_3
    ) external;
}
