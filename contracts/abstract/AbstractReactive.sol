// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "../interfaces/IReactive.sol";
import "../interfaces/ISystemContract.sol";
import "./AbstractPayer.sol";

/**
 * @title AbstractReactive
 * @notice Base contract for Reactive smart contracts deployed on Reactive Mainnet (`1597`).
 *         Distinguishes between the Reactive Network context (`!vm`, where subscriptions are managed)
 *         and the isolated ReactVM execution context (`vm`, where `react()` processes logs).
 */
abstract contract AbstractReactive is IReactive, AbstractPayer {
    /// @notice Wildcard topic/address filter constant for Reactive Network subscriptions.
    uint256 internal constant REACTIVE_IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;

    /// @notice Canonical Reactive Network System Subscription Service address (`0x0000000000000000000000000000000000fffFfF`).
    ISystemContract internal constant SERVICE_ADDR = ISystemContract(payable(0x0000000000000000000000000000000000fffFfF));

    /// @notice True when executing inside an isolated ReactVM instance; false on the public Reactive Network.
    bool internal vm;

    /// @notice Reference to the active subscription & billing service contract.
    ISystemContract internal service;

    error RnkOnly();
    error VmOnly();

    /**
     * @notice Restricts function execution to the Reactive Network context (`!vm`).
     */
    modifier rnkOnly() {
        if (vm) {
            revert RnkOnly();
        }
        _;
    }

    /**
     * @notice Restricts function execution to the isolated ReactVM context (`vm`).
     */
    modifier vmOnly() {
        if (!vm) {
            revert VmOnly();
        }
        _;
    }

    constructor() {
        vendor = service = SERVICE_ADDR;
        addAuthorizedSender(address(SERVICE_ADDR));
        detectVm();
    }

    /**
     * @notice Detects whether the contract is running inside a ReactVM instance by checking
     *         if code exists at `0x0000000000000000000000000000000000fffFfF`.
     *         On the Reactive Network, `SERVICE_ADDR` has system bytecode (`extcodesize > 0`).
     *         Inside a ReactVM instance, `SERVICE_ADDR` has no bytecode (`extcodesize == 0`).
     */
    function detectVm() internal {
        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(0x0000000000000000000000000000000000fffFfF)
        }
        vm = size == 0;
    }
}

