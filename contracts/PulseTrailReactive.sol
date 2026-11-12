// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AbstractReactive } from "./abstract/AbstractReactive.sol";
import { IReactive, LogRecord } from "./interfaces/IReactive.sol";
import { IPulseTrailReactive } from "./interfaces/IPulseTrailReactive.sol";

/**
 * @title PulseTrailReactive
 * @notice Stateful cross-chain trailing stop brain deployed on Reactive Mainnet (`1597`).
 * @dev Subscribes to `PositionRegistered`, `PositionCancelled`, and Uniswap V2 `Sync` events on
 *      Base Mainnet (`8453`). Inside the isolated ReactVM (`vmOnly`), continuously computes
 *      rolling 8-tick volatility, profit-activation transitions, High-Water Mark ratcheting,
 *      and 3-stage partial exit callbacks.
 */
contract PulseTrailReactive is AbstractReactive, IPulseTrailReactive {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice Default origin & destination chain ID (Base Mainnet = `8453`).
    uint256 public constant ORIGIN_CHAIN_ID = 8453;

    /// @notice Callback gas limit (must be >= 100,000 on Reactive Network; 350,000 covers Uniswap V2 Router swaps).
    uint64 public constant CALLBACK_GAS_LIMIT = 350_000;

    /// @notice Uniswap V2 `Sync(uint112 reserve0, uint112 reserve1)` topic0 hash.
    uint256 public constant UNISWAP_V2_SYNC_TOPIC_0 =
        0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1;

    /// @notice `PositionRegistered` event signature topic0 hash emitted by `PulseTrailCallback`.
    uint256 public constant POSITION_REGISTERED_TOPIC_0 =
        uint256(
            keccak256(
                "PositionRegistered(uint256,address,address,address,address,bool,uint256,uint256,uint256,uint256,uint16[3],uint16[3],uint16,uint16,uint16)"
            )
        );

    /// @notice `PositionCancelled` event signature topic0 hash emitted by `PulseTrailCallback`.
    uint256 public constant POSITION_CANCELLED_TOPIC_0 =
        uint256(keccak256("PositionCancelled(uint256,address,uint256)"));

    /// @notice Rolling price buffer capacity for volatility calculation.
    uint8 public constant BUFFER_SIZE = 8;

    /// @notice Basis points denominator (100% = 10,000 bps).
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Fixed-point price precision scale (`1e18`).
    uint256 public constant PRICE_SCALE = 1e18;

    /// @notice Minimum tick change (`5 bps` = 0.05%) required to append to the volatility ring buffer.
    uint256 public constant MIN_VOLATILITY_TICK_DIFF_BPS = 5;

    /// @notice Maximum allowed effective trail distance (`9000 bps` = 90%).
    uint256 public constant MAX_EFFECTIVE_TRAIL_BPS = 9_000;

    // -------------------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------------------

    /// @notice Contract administrator (deployer).
    address public owner;

    /// @notice Configured origin & destination chain ID (defaults to `8453` Base Mainnet).
    uint256 public immutable originChainId;

    /// @notice Address of `PulseTrailCallback` on the origin/destination chain.
    address public immutable callbackContract;

    /// @notice Mapping from `positionId` to its `ReactivePosition` state inside the ReactVM.
    mapping(uint256 => ReactivePosition) internal _positions;

    /// @notice Mapping from Uniswap V2 pair address to all tracked `positionId`s monitoring that pair.
    mapping(address => uint256[]) internal _pairPositions;

    /// @notice Tracks whether a Uniswap V2 pair is subscribed on the Reactive Network (`!vm`).
    mapping(address => bool) public subscribedPairs;

    // -------------------------------------------------------------------------
    // Custom Errors
    // -------------------------------------------------------------------------

    error OnlyOwner();
    error InvalidAddress();
    error InvalidReserves();

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert OnlyOwner();
        }
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor & Subscriptions (RNK Network Context)
    // -------------------------------------------------------------------------

    /**
     * @param _originChainId Origin/destination chain ID (`8453` for Base Mainnet; `0` defaults to `8453`).
     * @param _callbackContract Deployed `PulseTrailCallback` address on the origin/destination chain.
     * @param _initialPair Optional initial Uniswap V2 pair address to subscribe to (`address(0)` to skip).
     */
    constructor(
        uint256 _originChainId,
        address _callbackContract,
        address _initialPair
    ) payable AbstractReactive() {
        if (_callbackContract == address(0)) {
            revert InvalidAddress();
        }

        owner = msg.sender;
        originChainId = _originChainId == 0 ? ORIGIN_CHAIN_ID : _originChainId;
        callbackContract = _callbackContract;

        if (!vm) {
            // Subscribe to PositionRegistered events from PulseTrailCallback
            service.subscribe(
                originChainId,
                callbackContract,
                POSITION_REGISTERED_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );

            // Subscribe to PositionCancelled events from PulseTrailCallback
            service.subscribe(
                originChainId,
                callbackContract,
                POSITION_CANCELLED_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );

            // Optionally subscribe to an initial Uniswap V2 pair's Sync events
            if (_initialPair != address(0)) {
                service.subscribe(
                    originChainId,
                    _initialPair,
                    UNISWAP_V2_SYNC_TOPIC_0,
                    REACTIVE_IGNORE,
                    REACTIVE_IGNORE,
                    REACTIVE_IGNORE
                );
                subscribedPairs[_initialPair] = true;
                emit PairSubscribed(originChainId, _initialPair);
            }
        }
    }

    /**
     * @notice Dynamically subscribes to `Sync(uint112,uint112)` events for a Uniswap V2 pair on `originChainId`.
     * @dev Callable only on the Reactive Network (`!vm`), never inside the ReactVM (`vm`).
     * @param pair Uniswap V2 pair address on Base Mainnet.
     */
    function subscribeToPair(address pair) external rnkOnly {
        if (pair == address(0)) {
            revert InvalidAddress();
        }
        if (!subscribedPairs[pair]) {
            service.subscribe(
                originChainId,
                pair,
                UNISWAP_V2_SYNC_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
            subscribedPairs[pair] = true;
            emit PairSubscribed(originChainId, pair);
        }
    }

    /**
     * @notice Unsubscribes from `Sync(uint112,uint112)` events for a Uniswap V2 pair on `originChainId`.
     * @param pair Uniswap V2 pair address on Base Mainnet.
     */
    function unsubscribeFromPair(address pair) external rnkOnly onlyOwner {
        if (subscribedPairs[pair]) {
            service.unsubscribe(
                originChainId,
                pair,
                UNISWAP_V2_SYNC_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
            subscribedPairs[pair] = false;
        }
    }

    // -------------------------------------------------------------------------
    // ReactVM Event Router (`vmOnly`)
    // -------------------------------------------------------------------------

    /**
     * @notice Core Reactive Network entrypoint executed inside the isolated ReactVM whenever a
     *         subscribed log arrives from Base Mainnet (`8453`).
     * @param log Relayed cross-chain `LogRecord`.
     */
    function react(LogRecord calldata log) external override vmOnly {
        if (log.chain_id != originChainId) {
            return;
        }

        if (log._contract == callbackContract) {
            if (log.topic_0 == POSITION_REGISTERED_TOPIC_0) {
                _onPositionRegistered(log);
                return;
            }
            if (log.topic_0 == POSITION_CANCELLED_TOPIC_0) {
                _onPositionCancelled(log);
                return;
            }
        }

        if (log.topic_0 == UNISWAP_V2_SYNC_TOPIC_0) {
            _onPoolSync(log);
        }
    }

    // -------------------------------------------------------------------------
    // Internal Event Handlers (ReactVM State Hydration & Sync Processing)
    // -------------------------------------------------------------------------

    /**
     * @notice Hydrates a new `ReactivePosition` inside the ReactVM from a Base Mainnet `PositionRegistered` log.
     */
    function _onPositionRegistered(LogRecord calldata log) internal {
        uint256 positionId = log.topic_1;
        address posOwner = address(uint160(log.topic_2));
        address pair = address(uint160(log.topic_3));

        (
            ,
            ,
            bool isToken0,
            uint256 initialBalance,
            uint256 entryPrice,
            uint256 activationPrice,
            uint256 hardFloorPrice,
            uint16[3] memory baseTrailBps,
            uint16[3] memory exitPortionBps,
            uint16 volatilityMultiplierBps,
            uint16 maxWideningBps,
            uint16 maxSlippageBps
        ) = abi.decode(
                log.data,
                (
                    address,
                    address,
                    bool,
                    uint256,
                    uint256,
                    uint256,
                    uint256,
                    uint16[3],
                    uint16[3],
                    uint16,
                    uint16,
                    uint16
                )
            );

        ReactivePosition storage pos = _positions[positionId];
        pos.positionId = positionId;
        pos.owner = posOwner;
        pos.pair = pair;
        pos.isToken0 = isToken0;
        pos.entryPrice = entryPrice;
        pos.activationPrice = activationPrice;
        pos.hardFloorPrice = hardFloorPrice;
        pos.highWaterMark = 0;
        pos.initialBalance = initialBalance;
        pos.remainingBalance = initialBalance;
        pos.baseTrailBps = baseTrailBps;
        pos.exitPortionBps = exitPortionBps;
        pos.volatilityMultiplierBps = volatilityMultiplierBps;
        pos.maxWideningBps = maxWideningBps;
        pos.maxSlippageBps = maxSlippageBps;
        pos.currentStage = 0;
        pos.active = true;
        pos.bufferIndex = 0;
        pos.bufferCount = 0;
        pos.currentVolatilityBps = 0;

        _pairPositions[pair].push(positionId);

        emit PositionTracked(positionId, pair, entryPrice, activationPrice);
    }

    /**
     * @notice Deactivates a tracked position inside the ReactVM when `PositionCancelled` arrives from Base Mainnet.
     */
    function _onPositionCancelled(LogRecord calldata log) internal {
        uint256 positionId = log.topic_1;
        ReactivePosition storage pos = _positions[positionId];
        if (pos.active) {
            pos.active = false;
            pos.remainingBalance = 0;
            pos.currentStage = 4;
            emit PositionUntracked(positionId, "Cancelled by user on origin chain");
        }
    }

    /**
     * @notice Processes a Uniswap V2 `Sync(uint112,uint112)` log for all active positions on `log._contract`.
     */
    function _onPoolSync(LogRecord calldata log) internal {
        uint256[] storage posIds = _pairPositions[log._contract];
        uint256 len = posIds.length;
        if (len == 0) {
            return;
        }

        for (uint256 i = 0; i < len; ++i) {
            uint256 posId = posIds[i];
            ReactivePosition storage pos = _positions[posId];
            if (!pos.active || pos.remainingBalance == 0) {
                continue;
            }
            uint256 currentPrice = _decodeSyncPrice(log.data, pos.isToken0);
            _evaluatePosition(posId, currentPrice);
        }
    }

    // -------------------------------------------------------------------------
    // Mathematical Core: Price Decoding, Rolling Volatility & Adaptive Trail
    // -------------------------------------------------------------------------

    /**
     * @notice Decodes `(uint112 reserve0, uint112 reserve1)` from a Uniswap V2 `Sync` payload and returns
     *         the spot price of `tokenIn` denominated in `tokenOut` scaled by `1e18`.
     * @param data Raw `log.data` bytes from `Sync(uint112,uint112)`.
     * @param isToken0 True if the position is selling `token0` for `token1`; false if selling `token1` for `token0`.
     * @return price1e18 Spot price scaled by `1e18`.
     */
    function _decodeSyncPrice(
        bytes calldata data,
        bool isToken0
    ) internal pure returns (uint256 price1e18) {
        (uint112 reserve0, uint112 reserve1) = abi.decode(data, (uint112, uint112));
        if (reserve0 == 0 || reserve1 == 0) {
            revert InvalidReserves();
        }
        price1e18 = isToken0
            ? (uint256(reserve1) * PRICE_SCALE) / uint256(reserve0)
            : (uint256(reserve0) * PRICE_SCALE) / uint256(reserve1);
    }

    /**
     * @notice Appends `newPrice` to the 8-slot circular buffer (filtering `< 5 bps` micro-noise)
     *         and computes the mean absolute percentage change across consecutive ticks in basis points.
     * @param pos Storage pointer to the `ReactivePosition`.
     * @param newPrice Newly decoded spot price (`1e18`).
     * @return volatilityBps Updated rolling volatility in basis points.
     */
    function _updateVolatility(
        ReactivePosition storage pos,
        uint256 newPrice
    ) internal returns (uint256 volatilityBps) {
        uint8 count = pos.bufferCount;

        // Ignore micro-noise (< 5 bps = 0.05%) compared to the most recently recorded tick
        if (count > 0) {
            uint8 lastIdx = (pos.bufferIndex + BUFFER_SIZE - 1) % BUFFER_SIZE;
            uint256 lastPrice = pos.priceBuffer[lastIdx];
            if (lastPrice > 0) {
                uint256 diff = newPrice > lastPrice ? newPrice - lastPrice : lastPrice - newPrice;
                uint256 changeBps = (diff * BPS_DENOMINATOR) / lastPrice;
                if (changeBps < MIN_VOLATILITY_TICK_DIFF_BPS) {
                    return pos.currentVolatilityBps;
                }
            }
        }

        // Write newPrice into circular buffer
        uint8 writeIdx = pos.bufferIndex;
        pos.priceBuffer[writeIdx] = newPrice;
        pos.bufferIndex = (writeIdx + 1) % BUFFER_SIZE;
        if (count < BUFFER_SIZE) {
            count += 1;
            pos.bufferCount = count;
        }

        if (count < 2) {
            pos.currentVolatilityBps = 0;
            return 0;
        }

        // Oldest element is at index 0 when buffer is not yet full, or at `pos.bufferIndex` when full (count == 8)
        uint8 oldestIdx = count < BUFFER_SIZE ? 0 : pos.bufferIndex;
        uint256 sumDeltaBps = 0;
        uint256 prevPrice = pos.priceBuffer[oldestIdx];

        for (uint8 i = 1; i < count; ++i) {
            uint8 currIdx = (oldestIdx + i) % BUFFER_SIZE;
            uint256 currPrice = pos.priceBuffer[currIdx];
            uint256 absDiff = currPrice > prevPrice ? currPrice - prevPrice : prevPrice - currPrice;
            if (prevPrice > 0) {
                sumDeltaBps += (absDiff * BPS_DENOMINATOR) / prevPrice;
            }
            prevPrice = currPrice;
        }

        volatilityBps = sumDeltaBps / uint256(count - 1);
        pos.currentVolatilityBps = volatilityBps;
    }

    /**
     * @notice Computes the effective trail distance in basis points for `stage` (`1..3`),
     *         combining the stage's base trail with the capped volatility widening addon.
     * @param pos Storage pointer to the `ReactivePosition`.
     * @param stage Active stage (`1`, `2`, or `3`).
     * @return Effective trail distance in basis points (capped at `9000 bps` = 90%).
     */
    function _getEffectiveTrailBps(
        ReactivePosition storage pos,
        uint8 stage
    ) internal view returns (uint16) {
        uint256 addonBps = (pos.currentVolatilityBps * uint256(pos.volatilityMultiplierBps)) /
            BPS_DENOMINATOR;
        if (addonBps > uint256(pos.maxWideningBps)) {
            addonBps = uint256(pos.maxWideningBps);
        }

        uint256 totalTrail = uint256(pos.baseTrailBps[stage - 1]) + addonBps;
        if (totalTrail > MAX_EFFECTIVE_TRAIL_BPS) {
            totalTrail = MAX_EFFECTIVE_TRAIL_BPS;
        }
        return uint16(totalTrail);
    }

    // -------------------------------------------------------------------------
    // State Machine Evaluation: Activation, HWM Ratchet & Stage Exit Dispatch
    // -------------------------------------------------------------------------

    /**
     * @notice Evaluates a position against `currentPrice`, handling Hard Floor circuit breakers,
     *         Stage 0 -> Stage 1 profit activation, High-Water Mark upward ratcheting, and
     *         pullback-triggered multi-stage partial exit callbacks.
     * @param positionId Tracked position identifier.
     * @param currentPrice Current spot price scaled by `1e18`.
     */
    function _evaluatePosition(uint256 positionId, uint256 currentPrice) internal {
        ReactivePosition storage pos = _positions[positionId];
        if (!pos.active || pos.remainingBalance == 0) {
            return;
        }

        // 1. Update rolling 8-tick volatility buffer
        uint256 volBps = _updateVolatility(pos, currentPrice);

        // 2. Hard Floor Circuit Breaker (valid in any active stage, including Stage 0)
        if (pos.hardFloorPrice > 0 && currentPrice <= pos.hardFloorPrice) {
            uint256 sellAmt = pos.remainingBalance;
            uint256 hwmSnapshot = pos.highWaterMark;
            uint256 minOut = (((sellAmt * currentPrice) / PRICE_SCALE) *
                (BPS_DENOMINATOR - uint256(pos.maxSlippageBps))) / BPS_DENOMINATOR;

            // Atomic state update before Callback emission
            pos.remainingBalance = 0;
            pos.currentStage = 4;
            pos.active = false;

            emit StageTriggered(positionId, 4, currentPrice, hwmSnapshot, sellAmt, minOut);
            _emitExitCallback(positionId, 4, sellAmt, minOut);
            return;
        }

        // 3. Stage 0 (Dormant — Waiting for Profit Activation Threshold)
        if (pos.currentStage == 0) {
            if (currentPrice >= pos.activationPrice) {
                pos.currentStage = 1;
                pos.highWaterMark = currentPrice;
                emit ProfitActivated(
                    positionId,
                    pos.activationPrice,
                    currentPrice,
                    block.timestamp
                );
            }
            return;
        }

        // 4. Stages 1, 2, and 3 (Active Volatility-Adaptive Trailing)
        uint8 activeStage = pos.currentStage;
        uint16 effTrailBps = _getEffectiveTrailBps(pos, activeStage);
        emit VolatilityUpdated(positionId, volBps, effTrailBps);

        // 4a. Ratchet High-Water Mark upward on new price peak
        if (currentPrice > pos.highWaterMark) {
            uint256 oldHwm = pos.highWaterMark;
            pos.highWaterMark = currentPrice;
            uint256 newStop = (currentPrice * (BPS_DENOMINATOR - uint256(effTrailBps))) /
                BPS_DENOMINATOR;

            emit HighWaterMarkUpdated(
                positionId,
                activeStage,
                oldHwm,
                currentPrice,
                effTrailBps,
                newStop
            );
            return;
        }

        // 4b. Evaluate Pullback Trigger against dynamic stop price
        uint256 stopPrice = (pos.highWaterMark * (BPS_DENOMINATOR - uint256(effTrailBps))) /
            BPS_DENOMINATOR;

        if (currentPrice <= stopPrice) {
            uint8 triggeredStage = activeStage;
            uint256 triggerHwm = pos.highWaterMark;
            uint256 amountToSell;

            if (triggeredStage < 3) {
                uint256 portion = (pos.initialBalance *
                    uint256(pos.exitPortionBps[triggeredStage - 1])) / BPS_DENOMINATOR;
                amountToSell = portion > pos.remainingBalance ? pos.remainingBalance : portion;
            } else {
                amountToSell = pos.remainingBalance;
            }

            uint256 minAmountOut = (((amountToSell * currentPrice) / PRICE_SCALE) *
                (BPS_DENOMINATOR - uint256(pos.maxSlippageBps))) / BPS_DENOMINATOR;

            // Atomic state update BEFORE emitting Callback to prevent double-triggers on ~200ms Base blocks
            pos.remainingBalance -= amountToSell;
            if (triggeredStage == 3 || pos.remainingBalance == 0) {
                pos.currentStage = 4;
                pos.active = false;
            } else {
                pos.currentStage = triggeredStage + 1;
                pos.highWaterMark = currentPrice;
            }

            emit StageTriggered(
                positionId,
                triggeredStage,
                currentPrice,
                triggerHwm,
                amountToSell,
                minAmountOut
            );

            _emitExitCallback(positionId, triggeredStage, amountToSell, minAmountOut);
        }
    }

    /**
     * @notice Alias for `_evaluatePosition` matching the architecture specification.
     */
    function _evaluatePositionOnPriceTick(uint256 positionId, uint256 currentPrice) internal {
        _evaluatePosition(positionId, currentPrice);
    }

    /**
     * @notice Encodes the `executeStageExit` payload (with `address(0)` as the first parameter
     *         to be overwritten by Reactive Network with `rvm_id`) and emits `Callback`.
     */
    function _emitExitCallback(
        uint256 positionId,
        uint8 stageToTrigger,
        uint256 amountToSell,
        uint256 minAmountOut
    ) internal {
        bytes memory payload = abi.encodeWithSignature(
            "executeStageExit(address,uint256,uint8,uint256,uint256)",
            address(0),
            positionId,
            stageToTrigger,
            amountToSell,
            minAmountOut
        );

        emit Callback(originChainId, callbackContract, CALLBACK_GAS_LIMIT, payload);
    }

    // -------------------------------------------------------------------------
    // View Helpers for Telemetry CLI, Frontend & Unit Tests
    // -------------------------------------------------------------------------

    /**
     * @notice Returns the full `ReactivePosition` state for `positionId`.
     */
    function getReactivePosition(
        uint256 positionId
    ) external view returns (ReactivePosition memory) {
        return _positions[positionId];
    }

    /**
     * @notice Computes the current effective trail bps and dynamic stop trigger price for `positionId`.
     */
    function getEffectiveTrailAndStopPrice(
        uint256 positionId
    ) external view returns (uint16 effectiveTrailBps, uint256 stopPrice) {
        ReactivePosition storage pos = _positions[positionId];
        if (!pos.active || pos.currentStage == 0 || pos.currentStage > 3) {
            return (0, pos.hardFloorPrice);
        }
        effectiveTrailBps = _getEffectiveTrailBps(pos, pos.currentStage);
        stopPrice = (pos.highWaterMark * (BPS_DENOMINATOR - uint256(effectiveTrailBps))) /
            BPS_DENOMINATOR;
    }

    /**
     * @notice Returns all tracked `positionId`s associated with a Uniswap V2 `pair`.
     */
    function getPairPositions(address pair) external view returns (uint256[] memory) {
        return _pairPositions[pair];
    }

    /**
     * @notice External pure helper exposing `_decodeSyncPrice` for unit/fuzz testing and off-chain verification.
     */
    function decodeSyncPrice(
        bytes calldata data,
        bool isToken0
    ) external pure returns (uint256 price1e18) {
        return _decodeSyncPrice(data, isToken0);
    }

    /**
     * @notice External pure helper exposing the adaptive trail formula for unit/fuzz testing and UI previews.
     */
    function calculateEffectiveTrailBps(
        uint16 baseTrail,
        uint256 volatilityBps,
        uint16 volatilityMultiplierBps,
        uint16 maxWideningBps
    ) external pure returns (uint16) {
        uint256 addonBps = (volatilityBps * uint256(volatilityMultiplierBps)) / BPS_DENOMINATOR;
        if (addonBps > uint256(maxWideningBps)) {
            addonBps = uint256(maxWideningBps);
        }
        uint256 totalTrail = uint256(baseTrail) + addonBps;
        if (totalTrail > MAX_EFFECTIVE_TRAIL_BPS) {
            totalTrail = MAX_EFFECTIVE_TRAIL_BPS;
        }
        return uint16(totalTrail);
    }
}

