// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AbstractCallback } from "./abstract/AbstractCallback.sol";
import { IPulseTrailCallback } from "./interfaces/IPulseTrailCallback.sol";
import { IUniswapV2Pair } from "./interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router02.sol";
import { IERC20 } from "./interfaces/IERC20.sol";

/**
 * @title PulseTrailCallback
 * @notice Destination vault, pre-flight risk verifier, and authenticated Uniswap V2 swap executor
 *         deployed on Base Mainnet (`8453`).
 * @dev Inherits `AbstractCallback` to authenticate cross-chain callbacks delivered by the official
 *      Base Mainnet Callback Proxy (`0x0D3E76De6bC44309083cAAFdB49A088B8a250947`) and verify the
 *      originating ReactVM ID (`rvmIdOnly`).
 */
contract PulseTrailCallback is AbstractCallback, IPulseTrailCallback {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant PRICE_SCALE = 1e18;
    uint256 public constant MAX_HEALTHY_POOL_SHARE_BPS = 500; // 5.00% of pool reserves
    uint16 public constant MIN_BASE_TRAIL_BPS = 50;           // 0.50% minimum base trail
    uint16 public constant MAX_BASE_TRAIL_BPS = 5_000;        // 50.00% maximum base trail
    uint16 public constant MAX_SLIPPAGE_LIMIT_BPS = 5_000;    // 50.00% maximum slippage cap
    uint256 public constant SWAP_DEADLINE_WINDOW = 300;       // 5-minute timestamp window

    // -------------------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------------------

    /// @notice Contract administrator (deployer).
    address public owner;

    /// @notice Canonical Uniswap V2 Router02 on Base Mainnet (`0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24`).
    IUniswapV2Router02 public immutable uniswapRouter;

    /// @notice Auto-incrementing counter for registered positions (1-indexed).
    uint256 public nextPositionId;

    /// @notice Mapping from `positionId` to its `CallbackPosition` state on Base Mainnet.
    mapping(uint256 => CallbackPosition) internal _positions;

    /// @notice Mapping from trader address to an array of their registered `positionId`s.
    mapping(address => uint256[]) internal _userPositions;

    /// @notice Lightweight reentrancy lock (`1 = unlocked`, `2 = locked`).
    uint256 private _unlocked = 1;

    // -------------------------------------------------------------------------
    // Custom Errors
    // -------------------------------------------------------------------------

    error OnlyOwner();
    error ReentrancyGuardReentrantCall();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidExitPortions();
    error InvalidBaseTrailBps();
    error InvalidSlippageBps();
    error InvalidWideningBps();
    error InvalidHardFloorPrice();
    error InvalidTokenPair();
    error EmptyPoolReserves();
    error ZeroTokensReceived();
    error TokenTransferFailed();
    error TokenApproveFailed();
    error PositionNotFound();
    error NotPositionOwner();
    error PositionNotActive();
    error InvalidOrDuplicateStage(uint8 currentStage, uint8 requestedStage);
    error PositionNotCancellable();

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert OnlyOwner();
        }
        _;
    }

    modifier nonReentrant() {
        if (_unlocked != 1) {
            revert ReentrancyGuardReentrantCall();
        }
        _unlocked = 2;
        _;
        _unlocked = 1;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @param _callbackProxy Official Reactive Callback Proxy on Base Mainnet (`0x0D3E76De6bC44309083cAAFdB49A088B8a250947`).
     * @param _uniswapRouter Canonical Uniswap V2 Router02 on Base Mainnet (`0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24`).
     */
    constructor(
        address _callbackProxy,
        address _uniswapRouter
    ) payable AbstractCallback(_callbackProxy) {
        if (_callbackProxy == address(0) || _uniswapRouter == address(0)) {
            revert InvalidAddress();
        }
        owner = msg.sender;
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
    }

    // -------------------------------------------------------------------------
    // Pre-Flight Risk Shield Views (Liquidity Depth & Dry-Run Simulation)
    // -------------------------------------------------------------------------

    /**
     * @notice Queries the Uniswap V2 pair's reserves, determines token ordering, computes the current
     *         spot price scaled by `1e18`, and evaluates whether `amountIn` is within healthy liquidity depth (`<= 5%`).
     * @param pair Uniswap V2 pair address on Base Mainnet.
     * @param tokenIn Address of the token being trailed/sold.
     * @param amountIn Proposed token position size.
     * @return isHealthy True if `positionShareBps <= 500` (5% of pool reserves).
     * @return positionShareBps Position size relative to `reserveIn` in basis points.
     * @return spotPrice1e18 Current spot price (`reserveOut * 1e18 / reserveIn`).
     * @return reserveIn Current pool reserve of `tokenIn`.
     * @return reserveOut Current pool reserve of the quote token (`tokenOut`).
     */
    function checkPoolLiquidity(
        address pair,
        address tokenIn,
        uint256 amountIn
    )
        public
        view
        override
        returns (
            bool isHealthy,
            uint256 positionShareBps,
            uint256 spotPrice1e18,
            uint256 reserveIn,
            uint256 reserveOut
        )
    {
        if (pair == address(0) || tokenIn == address(0)) {
            revert InvalidAddress();
        }

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        if (tokenIn != token0 && tokenIn != token1) {
            revert InvalidTokenPair();
        }

        (uint112 r0, uint112 r1, ) = IUniswapV2Pair(pair).getReserves();
        bool isToken0 = (tokenIn == token0);

        reserveIn = isToken0 ? uint256(r0) : uint256(r1);
        reserveOut = isToken0 ? uint256(r1) : uint256(r0);

        if (reserveIn == 0 || reserveOut == 0) {
            revert EmptyPoolReserves();
        }

        spotPrice1e18 = (reserveOut * PRICE_SCALE) / reserveIn;
        positionShareBps = (amountIn * BPS_DENOMINATOR) / reserveIn;
        isHealthy = positionShareBps <= MAX_HEALTHY_POOL_SHARE_BPS;
    }

    /**
     * @notice Estimates output tokens and slippage floor using `uniswapRouter.getAmountsOut` wrapped in `try/catch`.
     * @param tokenIn Address of the input token to sell.
     * @param tokenOut Address of the quote token to receive.
     * @param amountIn Input token amount to simulate.
     * @param maxSlippageBps User's maximum tolerated slippage in basis points (e.g., `300` = 3%).
     * @return canSell True if the router simulation succeeded with non-zero output.
     * @return expectedAmountOut Router's quoted output amount before slippage tolerance.
     * @return minAmountOut Slippage-protected minimum output amount (`expectedAmountOut * (10000 - maxSlippageBps) / 10000`).
     */
    function estimateSellOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint16 maxSlippageBps
    )
        public
        view
        override
        returns (
            bool canSell,
            uint256 expectedAmountOut,
            uint256 minAmountOut
        )
    {
        if (tokenIn == address(0) || tokenOut == address(0) || amountIn == 0 || maxSlippageBps > MAX_SLIPPAGE_LIMIT_BPS) {
            return (false, 0, 0);
        }

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        try uniswapRouter.getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
            if (amounts.length >= 2 && amounts[1] > 0) {
                expectedAmountOut = amounts[1];
                minAmountOut = (expectedAmountOut * (BPS_DENOMINATOR - uint256(maxSlippageBps))) / BPS_DENOMINATOR;
                canSell = true;
            }
        } catch {
            return (false, 0, 0);
        }
    }

    /**
     * @notice Convenience alias for pre-flight dry-run simulation with a default 300 bps (3%) slippage window.
     */
    function simulateSellDryRun(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    )
        external
        view
        returns (
            bool canSell,
            uint256 expectedAmountOut,
            uint256 minAmountOut
        )
    {
        return estimateSellOutput(tokenIn, tokenOut, amountIn, 300);
    }

    // -------------------------------------------------------------------------
    // Position Registration (Vault Escrow & Event Emission)
    // -------------------------------------------------------------------------

    /**
     * @notice Escrows user tokens (measuring exact post-tax balance received), validates trailing parameters,
     *         checks pool liquidity depth, and emits `PositionRegistered` to initialize Reactive Mainnet tracking.
     * @param params Configuration struct for the multi-stage adaptive trailing stop position.
     * @return positionId Newly assigned 1-indexed position identifier.
     */
    function createPosition(
        CreatePositionParams calldata params
    ) external override nonReentrant returns (uint256 positionId) {
        if (params.tokenIn == address(0) || params.tokenOut == address(0) || params.pair == address(0)) {
            revert InvalidAddress();
        }
        if (params.amountIn == 0) {
            revert InvalidAmount();
        }

        // 1. Validate 3-stage exit portions sum to 100% (10,000 bps)
        uint256 totalPortionBps = uint256(params.exitPortionBps[0]) +
            uint256(params.exitPortionBps[1]) +
            uint256(params.exitPortionBps[2]);
        if (
            totalPortionBps != BPS_DENOMINATOR ||
            params.exitPortionBps[0] == 0 ||
            params.exitPortionBps[1] == 0 ||
            params.exitPortionBps[2] == 0
        ) {
            revert InvalidExitPortions();
        }

        // 2. Validate base trail distances per stage (50 bps to 5,000 bps -> 0.5% to 50%)
        for (uint256 i = 0; i < 3; ++i) {
            if (params.baseTrailBps[i] < MIN_BASE_TRAIL_BPS || params.baseTrailBps[i] > MAX_BASE_TRAIL_BPS) {
                revert InvalidBaseTrailBps();
            }
        }

        // 3. Validate slippage and volatility widening bounds
        if (params.maxSlippageBps == 0 || params.maxSlippageBps > MAX_SLIPPAGE_LIMIT_BPS) {
            revert InvalidSlippageBps();
        }
        if (params.maxWideningBps > MAX_BASE_TRAIL_BPS) {
            revert InvalidWideningBps();
        }

        // 4. Verify token pair membership
        address token0 = IUniswapV2Pair(params.pair).token0();
        address token1 = IUniswapV2Pair(params.pair).token1();
        bool isToken0;
        if (params.tokenIn == token0 && params.tokenOut == token1) {
            isToken0 = true;
        } else if (params.tokenIn == token1 && params.tokenOut == token0) {
            isToken0 = false;
        } else {
            revert InvalidTokenPair();
        }

        // 5. Measure exact post-tax tokens received to support fee-on-transfer memecoins
        uint256 balanceBefore = IERC20(params.tokenIn).balanceOf(address(this));
        _safeTransferFrom(params.tokenIn, msg.sender, address(this), params.amountIn);
        uint256 balanceAfter = IERC20(params.tokenIn).balanceOf(address(this));
        uint256 actualReceived = balanceAfter - balanceBefore;
        if (actualReceived == 0) {
            revert ZeroTokensReceived();
        }

        // 6. Evaluate pool liquidity depth and spot entry price using actualReceived
        (
            bool isHealthy,
            uint256 positionShareBps,
            uint256 entryPrice,
            ,

        ) = checkPoolLiquidity(params.pair, params.tokenIn, actualReceived);

        if (params.hardFloorPrice > 0 && params.hardFloorPrice >= entryPrice) {
            revert InvalidHardFloorPrice();
        }

        if (!isHealthy) {
            emit LiquidityWarning(
                params.pair,
                positionShareBps,
                "Position exceeds 5% of pool reserves; high price impact possible"
            );
        }

        uint256 activationPrice = (entryPrice * (BPS_DENOMINATOR + uint256(params.activationProfitBps))) /
            BPS_DENOMINATOR;

        // 7. Persist position record
        positionId = ++nextPositionId;
        CallbackPosition storage pos = _positions[positionId];
        pos.owner = msg.sender;
        pos.tokenIn = params.tokenIn;
        pos.tokenOut = params.tokenOut;
        pos.pair = params.pair;
        pos.isToken0 = isToken0;
        pos.initialBalance = actualReceived;
        pos.remainingBalance = actualReceived;
        pos.totalProceeds = 0;
        pos.entryPrice = entryPrice;
        pos.activationPrice = activationPrice;
        pos.hardFloorPrice = params.hardFloorPrice;
        pos.baseTrailBps = params.baseTrailBps;
        pos.exitPortionBps = params.exitPortionBps;
        pos.volatilityMultiplierBps = params.volatilityMultiplierBps;
        pos.maxWideningBps = params.maxWideningBps;
        pos.maxSlippageBps = params.maxSlippageBps;
        pos.currentStage = 0;
        pos.status = PositionStatus.Active;
        pos.createdAt = block.timestamp;

        _userPositions[msg.sender].push(positionId);

        // 8. Emit registration log for Reactive Mainnet (1597) subscription
        emit PositionRegistered(
            positionId,
            msg.sender,
            params.pair,
            params.tokenIn,
            params.tokenOut,
            isToken0,
            actualReceived,
            entryPrice,
            activationPrice,
            params.hardFloorPrice,
            params.baseTrailBps,
            params.exitPortionBps,
            params.volatilityMultiplierBps,
            params.maxWideningBps,
            params.maxSlippageBps
        );
    }

    // -------------------------------------------------------------------------
    // Authenticated Cross-Chain Callback Execution & Emergency Controls
    // -------------------------------------------------------------------------

    /**
     * @notice Authenticated callback entrypoint triggered by the Base Callback Proxy (`0x0D3E76De6bC44309083cAAFdB49A088B8a250947`).
     *         Executes a slippage-protected Uniswap V2 swap inside a `try/catch` block so malicious/honeypot tokens
     *         can never revert the callback transaction or freeze the protocol.
     * @param rvm_id First payload argument automatically overwritten by Reactive Network with the ReactVM deployer ID.
     * @param positionId Target position ID to partially or fully exit.
     * @param stage Triggered stage (`1`, `2`, `3` for laddered partial exits, or `4` for Stage 0 Hard Floor emergency exit).
     * @param amountToSell Token amount calculated by `PulseTrailReactive`.
     * @param minAmountOut Minimum acceptable output tokens calculated by `PulseTrailReactive`.
     */
    function executeStageExit(
        address rvm_id,
        uint256 positionId,
        uint8 stage,
        uint256 amountToSell,
        uint256 minAmountOut
    ) external override authorizedSenderOnly rvmIdOnly(rvm_id) nonReentrant {
        CallbackPosition storage pos = _positions[positionId];
        if (pos.owner == address(0)) {
            revert PositionNotFound();
        }
        if (pos.status != PositionStatus.Active) {
            revert PositionNotActive();
        }
        if (stage <= pos.currentStage || stage > 4) {
            revert InvalidOrDuplicateStage(pos.currentStage, stage);
        }

        uint256 actualSellAmount = amountToSell > pos.remainingBalance
            ? pos.remainingBalance
            : amountToSell;

        if (stage == 3 || stage == 4 || actualSellAmount == 0) {
            actualSellAmount = pos.remainingBalance;
        }

        if (!_tryApprove(pos.tokenIn, address(uniswapRouter), actualSellAmount)) {
            pos.currentStage = stage;
            pos.status = PositionStatus.Failed;
            emit SwapFailed(positionId, stage, actualSellAmount, "Token approve failed");
            return;
        }

        address[] memory path = new address[](2);
        path[0] = pos.tokenIn;
        path[1] = pos.tokenOut;

        uint256 quoteBalanceBefore = IERC20(pos.tokenOut).balanceOf(pos.owner);

        try
            uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                actualSellAmount,
                minAmountOut,
                path,
                pos.owner,
                block.timestamp + SWAP_DEADLINE_WINDOW
            )
        {
            uint256 quoteBalanceAfter = IERC20(pos.tokenOut).balanceOf(pos.owner);
            uint256 proceeds = quoteBalanceAfter > quoteBalanceBefore
                ? quoteBalanceAfter - quoteBalanceBefore
                : 0;

            pos.remainingBalance -= actualSellAmount;
            pos.totalProceeds += proceeds;
            pos.currentStage = stage;

            if (pos.remainingBalance == 0 || stage == 3 || stage == 4) {
                pos.status = PositionStatus.Completed;
            }

            emit StageExitExecuted(
                positionId,
                stage,
                actualSellAmount,
                proceeds,
                pos.remainingBalance
            );
        } catch Error(string memory reason) {
            _tryApprove(pos.tokenIn, address(uniswapRouter), 0);
            pos.currentStage = stage;
            pos.status = PositionStatus.Failed;
            emit SwapFailed(positionId, stage, actualSellAmount, reason);
        } catch {
            _tryApprove(pos.tokenIn, address(uniswapRouter), 0);
            pos.currentStage = stage;
            pos.status = PositionStatus.Failed;
            emit SwapFailed(positionId, stage, actualSellAmount, "Unknown/Honeypot revert");
        }
    }

    /**
     * @notice Allows the trader to cancel protection at any time (in `Active` or `Failed` state)
     *         and immediately withdraw all remaining unswapped tokens.
     * @param positionId Position identifier to cancel.
     */
    function cancelPosition(uint256 positionId) external override nonReentrant {
        CallbackPosition storage pos = _positions[positionId];
        if (pos.owner == address(0)) {
            revert PositionNotFound();
        }
        if (msg.sender != pos.owner) {
            revert NotPositionOwner();
        }
        if (pos.status != PositionStatus.Active && pos.status != PositionStatus.Failed) {
            revert PositionNotCancellable();
        }

        uint256 amountReturned = pos.remainingBalance;
        pos.remainingBalance = 0;
        pos.status = PositionStatus.Cancelled;

        if (amountReturned > 0) {
            _safeTransfer(pos.tokenIn, pos.owner, amountReturned);
        }

        emit PositionCancelled(positionId, pos.owner, amountReturned);
    }

    // -------------------------------------------------------------------------
    // View Helpers & Administration
    // -------------------------------------------------------------------------

    /// @inheritdoc IPulseTrailCallback
    function getPosition(
        uint256 positionId
    ) external view override returns (CallbackPosition memory) {
        return _positions[positionId];
    }

    /// @inheritdoc IPulseTrailCallback
    function getUserPositions(
        address user
    ) external view override returns (uint256[] memory) {
        return _userPositions[user];
    }

    /// @notice Returns the currently authorized ReactVM deployer ID (`rvm_id`).
    function getRvmId() external view returns (address) {
        return rvm_id;
    }

    /// @notice Updates the expected `rvm_id` if the Reactive contract is redeployed by a new address.
    function setRvmId(address _newRvmId) external onlyOwner {
        rvm_id = _newRvmId;
    }

    /// @notice Allows the owner to authorize an additional callback proxy if needed.
    function setAuthorizedSender(address _sender, bool _authorized) external onlyOwner {
        if (_authorized) {
            addAuthorizedSender(_sender);
        } else {
            removeAuthorizedSender(_sender);
        }
    }

    // -------------------------------------------------------------------------
    // Internal Safe ERC-20 Helpers
    // -------------------------------------------------------------------------

    function _safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert TokenTransferFailed();
        }
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value)
        );
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert TokenTransferFailed();
        }
    }

    function _tryApprove(address token, address spender, uint256 value) internal returns (bool) {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, value)
        );
        return success && (data.length == 0 || abi.decode(data, (bool)));
    }
}

