// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title IPulseTrailReactive
 * @notice Domain interface for `PulseTrailReactive.sol` deployed on Reactive Mainnet (`1597`).
 *         Performs stateful High-Water Mark tracking, rolling 8-tick volatility calculation,
 *         profit-activation gating, and 3-stage partial exit evaluation inside the ReactVM.
 */
interface IPulseTrailReactive {
    /**
     * @notice Stateful position tracking record maintained inside the ReactVM on Reactive Mainnet (`1597`).
     */
    struct ReactivePosition {
        uint256 positionId;
        address owner;
        address pair;
        bool isToken0;                  // True if tokenIn is token0 in the monitored Uniswap V2 pair
        uint256 entryPrice;             // Initial price scaled by 1e18 (tokenOut per tokenIn)
        uint256 activationPrice;        // Target price required to transition from Stage 0 -> Stage 1
        uint256 hardFloorPrice;         // Optional absolute minimum price trigger (0 = disabled)
        uint256 highWaterMark;          // Highest spot price observed since activation
        uint256 initialBalance;         // Initial post-tax token balance registered on Base Mainnet
        uint256 remainingBalance;       // Remaining token balance tracked across partial exits
        uint16[3] baseTrailBps;         // Base trail distances per stage in bps (e.g., [800, 600, 500])
        uint16[3] exitPortionBps;       // Exit portions per stage in bps (e.g., [4000, 3000, 3000])
        uint16 volatilityMultiplierBps; // Sensitivity multiplier (e.g., 15000 = 1.5x volatility)
        uint16 maxWideningBps;          // Maximum additive widening cap in bps (e.g., 1000 = +10%)
        uint16 maxSlippageBps;          // Slippage tolerance in bps used to compute minAmountOut
        uint8 currentStage;             // 0 = Dormant, 1 = Stage 1, 2 = Stage 2, 3 = Stage 3, 4 = Closed
        bool active;                    // False once all stages complete or position is cancelled
        uint256[8] priceBuffer;         // Circular 8-tick buffer of recent spot prices (1e18)
        uint8 bufferIndex;              // Next write index in `priceBuffer` (0..7)
        uint8 bufferCount;              // Number of populated ticks in `priceBuffer` (0..8)
        uint256 currentVolatilityBps;   // Latest rolling mean absolute percentage change in bps
    }

    /**
     * @notice Emitted inside the ReactVM when a `PositionRegistered` log from Base Mainnet is ingested.
     */
    event PositionTracked(
        uint256 indexed positionId,
        address indexed pair,
        uint256 entryPrice,
        uint256 activationPrice
    );

    /**
     * @notice Emitted when spot price crosses `activationPrice`, transitioning the position from Stage 0 (Dormant) to Stage 1.
     */
    event ProfitActivated(
        uint256 indexed positionId,
        uint256 activationPrice,
        uint256 currentPrice,
        uint256 timestamp
    );

    /**
     * @notice Emitted whenever a new peak ratchets the High-Water Mark upward during an active stage.
     */
    event HighWaterMarkUpdated(
        uint256 indexed positionId,
        uint8 stage,
        uint256 oldHwm,
        uint256 newHwm,
        uint256 effectiveTrailBps,
        uint256 currentStopPrice
    );

    /**
     * @notice Emitted when the rolling 8-tick volatility buffer updates the position's effective trail distance.
     */
    event VolatilityUpdated(
        uint256 indexed positionId,
        uint256 volatilityBps,
        uint16 effectiveTrailBps
    );

    /**
     * @notice Emitted immediately before `Callback` when a stage pullback or hard floor condition is breached.
     */
    event StageTriggered(
        uint256 indexed positionId,
        uint8 indexed stageTriggered,
        uint256 triggerPrice,
        uint256 highWaterMark,
        uint256 amountToSell,
        uint256 minAmountOut
    );

    /**
     * @notice Emitted when a position is deactivated due to user cancellation or final stage completion.
     */
    event PositionUntracked(
        uint256 indexed positionId,
        string reason
    );

    /**
     * @notice Emitted on Reactive Mainnet (`!vm`) when a new Uniswap V2 pair is subscribed to `Sync` logs.
     */
    event PairSubscribed(
        uint256 indexed chainId,
        address indexed pair
    );
}
