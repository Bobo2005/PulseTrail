// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IPayable } from "./IPayable.sol";
import { ISubscriptionService } from "./ISubscriptionService.sol";

/**
 * @title ISystemContract
 * @notice Unified Reactive Network system contract interface combining fee settlement (`IPayable`)
 *         and cross-chain log subscriptions (`ISubscriptionService`).
 */
interface ISystemContract is IPayable, ISubscriptionService {}
