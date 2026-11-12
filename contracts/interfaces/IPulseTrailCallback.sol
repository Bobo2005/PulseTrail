// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @title IPulseTrailCallback
 * @notice Domain interface for `PulseTrailCallback.sol` deployed on Base Mainnet (`8453`).
 *         Manages user token escrow, pre-flight liquidity/honeypot risk checks, and authenticated
 *         multi-stage Uniswap V2 swaps triggered by Reactive Mainnet (`1597`).
 */
interface IPulseTrailCallback {
    /**
     * @notice Lifecycle status of a trailing stop position on the destination chain.
     */
    enum PositionStatus {
        Active,     // 0: Currently monitored and eligible for stage exits
        Completed,  // 1: All stages exited or 100% emergency hard floor executed
        Cancelled,  // 2: User manually cancelled and withdrew remaining tokens
        Failed      // 3: Router swap reverted (e.g., honeypot/excessive slippage caught gracefully)
    }

    /**
     * @notice Complete state record stored on Base Mainnet for each registered position.
     */
    struct CallbackPosition {
        address owner;                  // Trader wallet receiving swap proceeds
        address tokenIn;                // Token being trailed/sold
        address tokenOut;               // Quote token (e.g., WETH or USDC)
        address pair;                   // Uniswap V2 Pair being monitored
        bool isToken0;                  // True if tokenIn is token0 in the pair
        uint256 initialBalance;         // Actual post-tax tokens received at registration
        uint256 remainingBalance;       // Current unswapped tokens remaining in escrow
        uint256 totalProceeds;          // Cumulative quote tokens sent to owner across exited stages
        uint256 entryPrice;             // Spot price at registration (scaled by 1e18)
        uint256 activationPrice;        // Profit threshold price to activate Stage 1 trailing (scaled by 1e18)
        uint256 hardFloorPrice;         // Optional absolute minimum emergency exit price (0 = disabled)
        uint16[3] baseTrailBps;         // Base trail distances per stage in bps (e.g., [800, 600, 500])
        uint16[3] exitPortionBps;       // Portion of initialBalance to sell per stage in bps (e.g., [4000, 3000, 3000])
        uint16 volatilityMultiplierBps; // Sensitivity multiplier for volatility widening (e.g., 15000 = 1.5x)
        uint16 maxWideningBps;          // Maximum additive widening cap in bps (e.g., 1000 = +10%)
        uint16 maxSlippageBps;          // Max slippage tolerance in bps (e.g., 300 = 3%)
        uint8 currentStage;             // Last executed stage (0 = None, 1..3 = Stage exits, 4 = Hard floor exit)
        PositionStatus status;          // Current lifecycle state
        uint256 createdAt;              // Block timestamp of registration
    }

    /**
     * @notice Input parameters for `createPosition`.
     */
    struct CreatePositionParams {
        address tokenIn;
        address tokenOut;
        address pair;
        uint256 amountIn;
        uint16 activationProfitBps;     // Profit % above entryPrice required to activate Stage 1 (e.g., 1500 = +15%)
        uint256 hardFloorPrice;         // Optional hard stop price scaled by 1e18 (0 to disable)
        uint16[3] baseTrailBps;         // Base trail bps for [Stage 1, Stage 2, Stage 3]
        uint16[3] exitPortionBps;       // Exit portions in bps summing to 10000 (e.g., [4000, 3000, 3000])
        uint16 volatilityMultiplierBps; // Multiplier applied to rolling volatility bps (e.g., 15000 = 1.5x)
        uint16 maxWideningBps;          // Cap on adaptive widening in bps (e.g., 1000 = +10%)
        uint16 maxSlippageBps;          // Max slippage tolerance in bps (e.g., 300 = 3%)
    }

    /**
     * @notice Emitted when a user registers a new position on Base Mainnet.
     *         Subscribed to by `PulseTrailReactive` on Reactive Mainnet (`1597`) to hydrate tracking state.
     */
    event PositionRegistered(
        uint256 indexed positionId,
        address indexed owner,
        address indexed pair,
        address tokenIn,
        address tokenOut,
        bool isToken0,
        uint256 initialBalance,
        uint256 entryPrice,
        uint256 activationPrice,
        uint256 hardFloorPrice,
        uint16[3] baseTrailBps,
        uint16[3] exitPortionBps,
        uint16 volatilityMultiplierBps,
        uint16 maxWideningBps,
        uint16 maxSlippageBps
    );

    /**
     * @notice Emitted when a stage exit swap succeeds on the Uniswap V2 Router.
     */
    event StageExitExecuted(
        uint256 indexed positionId,
        uint8 indexed stage,
        uint256 amountSold,
        uint256 proceedsReceived,
        uint256 remainingBalance
    );

    /**
     * @notice Emitted when a router swap reverts inside the `try/catch` block (e.g. honeypot or extreme price gap),
     *         allowing the callback transaction to succeed without bricking the position or proxy.
     */
    event SwapFailed(
        uint256 indexed positionId,
        uint8 indexed stage,
        uint256 amountAttempted,
        string reason
    );

    /**
     * @notice Emitted when a user cancels an active/failed position and withdraws their remaining tokens.
     *         Subscribed to by `PulseTrailReactive` to deactivate tracking.
     */
    event PositionCancelled(
        uint256 indexed positionId,
        address indexed owner,
        uint256 amountReturned
    );

    /**
     * @notice Emitted during registration if the user's position size exceeds 5% (`500 bps`) of pool reserves.
     */
    event LiquidityWarning(
        address indexed pair,
        uint256 positionShareBps,
        string message
    );

    /// @notice Pre-flight check of pool reserve depth and spot price.
    function checkPoolLiquidity(
        address pair,
        address tokenIn,
        uint256 amountIn
    )
        external
        view
        returns (
            bool isHealthy,
            uint256 positionShareBps,
            uint256 spotPrice1e18,
            uint256 reserveIn,
            uint256 reserveOut
        );

    /// @notice Pre-flight dry-run estimation of router swap output and minimum slippage threshold.
    function estimateSellOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint16 maxSlippageBps
    )
        external
        view
        returns (
            bool canSell,
            uint256 expectedAmountOut,
            uint256 minAmountOut
        );

    /// @notice Escrows `tokenIn` and registers a multi-stage adaptive trailing stop position.
    function createPosition(
        CreatePositionParams calldata params
    ) external returns (uint256 positionId);

    /// @notice Authenticated callback entrypoint invoked by the Base Callback Proxy (`0x0D3E76De6bC44309083cAAFdB49A088B8a250947`).
    function executeStageExit(
        address rvm_id,
        uint256 positionId,
        uint8 stage,
        uint256 amountToSell,
        uint256 minAmountOut
    ) external;

    /// @notice Allows the position owner to cancel protection and withdraw remaining tokens at any time.
    function cancelPosition(uint256 positionId) external;

    /// @notice Returns the full `CallbackPosition` struct for `positionId`.
    function getPosition(
        uint256 positionId
    ) external view returns (CallbackPosition memory);

    /// @notice Returns all position IDs created by `user`.
    function getUserPositions(
        address user
    ) external view returns (uint256[] memory);
}
