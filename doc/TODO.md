# PulseTrail — Actionable Task Tracker (`TODO.md`)

> **Target Deployment:** Base Mainnet (`8453`) + Reactive Mainnet (`1597`)  
> **Goal:** 20/20 Score across Execution, Integration, Usefulness, and Craft

---

## Phase Group A: Workspace & Core Interfaces
- [x] **Task 0.1:** Define `IReactive.sol` interface (`LogRecord` struct, `Callback` event, `react` function).
- [x] **Task 0.2:** Complete comprehensive project documentation in `doc/` (`prd.md`, `architecture.md`, `design-system.md`, `project-plan.md`, `memory.md`, `handoff.md`, `TODO.md`, `20-phase-master-prompt.md`).
- [x] **Task 1.1:** Initialize Foundry (`foundry.toml`) & Node dependencies (`reactive-lib`, `@openzeppelin/contracts`, `ethers`).
- [x] **Task 1.2:** Create `.env.example` with Mainnet RPCs (`BASE_MAINNET_RPC`, `REACTIVE_MAINNET_RPC`), system addresses, and deployer key placeholders.
- [x] **Task 1.3:** Create abstract base contracts from `reactive-lib` (`AbstractReactive.sol`, `AbstractCallback.sol`, `AbstractPayer.sol`, `ISystemContract.sol`, `ISubscriptionService.sol`).
- [x] **Task 1.4:** Create `contracts/interfaces/IUniswapV2Pair.sol` and `contracts/interfaces/IUniswapV2Router02.sol`.
- [x] **Task 1.5:** Create `contracts/interfaces/IPulseTrailCallback.sol` and `contracts/interfaces/IPulseTrailReactive.sol` with rich telemetry events.

---

## Phase Group B: Destination Contract (`PulseTrailCallback.sol` on Base Mainnet `8453`)
- [x] **Task 2.1:** Implement `CallbackPosition` struct, state mappings, and constructor inheriting `AbstractCallback(0x0D3E76De6bC44309083cAAFdB49A088B8a250947)`.
- [x] **Task 2.2:** Implement `checkPoolLiquidity(address pair, address tokenIn, uint256 amountIn)` view returning pool reserve ratio (bps) and warning flags.
- [x] **Task 2.3:** Implement `simulateSellDryRun(address tokenIn, address tokenOut, uint256 amountIn)` helper for pre-flight tax/honeypot estimation.
- [x] **Task 2.4:** Implement `createPosition(...)` with fee-on-transfer safe deposit (`balanceAfter - balanceBefore`), input validation, and `PositionRegistered` event emission.
- [x] **Task 2.5:** Implement `executeStageExit(address rvm_id, uint256 positionId, uint8 stage, uint256 amountToSell, uint256 minAmountOut)` with:
  - `authorizedSenderOnly` and `rvmIdOnly(rvm_id)` guards.
  - Replay / double-trigger guard (`require(stage > pos.currentStage)`).
  - `try uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(...)` block with `SwapExecuted` and graceful `catch` emitting `SwapFailed`.
- [x] **Task 2.6:** Implement `cancelPosition(uint256 positionId)` allowing instant user emergency withdrawal and emitting `PositionCancelled`.
- [x] **Task 2.7:** Verify `pay()` and `coverDebt()` functions work seamlessly with Base Callback Proxy.

---

## Phase Group C: Reactive Brain (`PulseTrailReactive.sol` on Reactive Mainnet `1597`)
- [x] **Task 3.1:** Implement `ReactivePosition` struct, circular `uint256[8] priceBuffer`, and state mappings.
- [x] **Task 3.2:** Implement constructor subscribing to `PositionRegistered` and `PositionCancelled` events from `PulseTrailCallback` on Base Mainnet (`8453`), plus `Sync` events on target Uniswap V2 pairs.
- [x] **Task 3.3:** Implement dynamic `subscribeToPair(address pair)` (callable on RNK network `!vm`) for adding new Uniswap pools.
- [x] **Task 3.4:** Implement `_handlePositionRegistered(LogRecord calldata log)` and `_handlePositionCancelled(LogRecord calldata log)` inside ReactVM.
- [x] **Task 3.5:** Implement `_decodeSyncPrice(bytes calldata data, bool isToken0)` converting `uint112 reserve0, uint112 reserve1` to a `1e18` fixed-point spot price.
- [x] **Task 3.6:** Implement `_updateVolatilityBuffer(ReactivePosition storage pos, uint256 currentPrice)` calculating rolling mean absolute percentage change in bps.
- [x] **Task 3.7:** Implement `_evaluatePositionOnPriceTick( uint256 posId, uint256 currentPrice )`:
  - Stage 0 Hard Floor check.
  - Stage 0 $\rightarrow$ Stage 1 Profit Activation gate (`currentPrice >= activationPrice`).
  - High-Water Mark ratchet (`if (currentPrice > pos.highWaterMark) pos.highWaterMark = currentPrice`).
  - Adaptive trail calculation (`baseTrailBps[stage-1] + min(volBps * mult / 10000, maxWideningBps)`).
  - Pullback check (`currentPrice <= stopPrice`) $\rightarrow$ atomic stage increment & balance deduction $\rightarrow$ `emit Callback(8453, callbackContract, 350000, payload)`.

---

## Phase Group D: Foundry Testing & Verification Suite
- [x] **Task 4.1:** Write `test/mocks/MockERC20.sol`, `MockFeeOnTransferERC20.sol`, `MockHoneypotERC20.sol`, `MockUniswapV2Pair.sol`, and `MockUniswapV2Router.sol`.
- [x] **Task 4.2:** Write `test/PulseTrailCallback.t.sol` testing registration, liquidity warnings, stage exits, slippage protection, fee-on-transfer handling, honeypot `try/catch` isolation, and emergency cancel.
- [x] **Task 4.3:** Write `test/PulseTrailReactive.t.sol` testing `Sync` decoding, profit activation, HWM ratcheting, rolling volatility widening/tightening, 3-stage partial exits (`40% -> 30% -> 30%`), and double-trigger prevention.
- [x] **Task 4.4:** Write `test/PulseTrailEndToEnd.t.sol` simulating the full Base $\rightarrow$ Reactive $\rightarrow$ Base cross-chain loop with gas profiling (`forge test --gas-report`).

---

## Phase Group E: Mainnet Deployment & Live On-Chain Loop Proof
- [x] **Task 5.1:** Create `script/DeployBaseMainnet.s.sol` to deploy and fund `PulseTrailCallback` on Base Mainnet (`8453`).
- [x] **Task 5.2:** Create `script/DeployReactiveMainnet.s.sol` to deploy and fund `PulseTrailReactive` on Reactive Mainnet (`1597`).
- [x] **Task 5.3:** Create `scripts/run-mainnet-loop.js` to register a live position on Base Mainnet, trigger pool `Sync` events, monitor the Reactive Mainnet `react()` transaction, and verify the resulting Base Mainnet callback swap.
- [x] **Task 5.4:** Create `scripts/verify-latency.js` to fetch block timestamps across Base Mainnet and Reactive Mainnet and generate the Markdown latency proof table.

---

## Phase Group F: Frontend Terminal, CLI & Hackathon Submission
- [x] **Task 6.1:** Build the Web3 Telemetry Dashboard (`frontend/`) following `doc/design-system.md` (Ratchet Chart, 4-Stage Ladder Stepper, Pre-Flight Risk Shield, Live Cross-Chain Proof Table).
- [x] **Task 6.2:** Build `scripts/pulsetrail-cli.js` for command-line position creation, live monitoring, and emergency cancellation.
- [x] **Task 6.3:** Write comprehensive `README.md` with Mainnet contract addresses, full-loop transaction hashes, latency benchmarks, architecture diagrams, and the "Risks & Mitigations" section.
- [x] **Task 6.4:** Prepare the `< 3 minute` video walkthrough script & final submission package.

