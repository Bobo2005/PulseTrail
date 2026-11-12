# PulseTrail — Master Project Execution Plan

## 1. Strategic Objective

Deliver a production-ready, Mainnet-verified autonomous trailing stop-loss protocol on **Base Mainnet (`8453`)** and **Reactive Mainnet (`1597`)** that scores **20 / 20** (5/5 across Execution, Integration, Usefulness, and Craft) in the **Reactive Omni Buildathon (Track 1: *Every Second Counts*)**.

---

## 2. Work Breakdown Structure (WBS) & Milestones

### Milestone 1: Environment, Dependencies & Core Interfaces (Phases 1–3)
- Initialize Foundry + Hardhat / Node.js hybrid workspace.
- Install `reactive-lib` (`IReactive`, `AbstractReactive`, `AbstractCallback`, `AbstractPayer`) and `@openzeppelin/contracts`.
- Define canonical interfaces:
  - `IPulseTrailCallback.sol`
  - `IPulseTrailReactive.sol`
  - `IUniswapV2Pair.sol` & `IUniswapV2Router02.sol`
- Configure `foundry.toml` and `.env.example` with **Reactive Mainnet (`1597`)** and **Base Mainnet (`8453`)** RPC endpoints and system addresses.

### Milestone 2: Destination Contract Engineering — `PulseTrailCallback.sol` (Phases 4–6)
- Implement position registration (`createPosition`) with post-tax balance accounting (`balanceAfter - balanceBefore`).
- Implement pre-flight safety helpers (`checkPoolLiquidity`, `estimateSellOutput`).
- Implement authenticated callback entrypoint (`executeStageExit(address rvm_id, uint256 positionId, uint8 stage, uint256 amountToSell, uint256 minAmountOut)`) guarded by `authorizedSenderOnly` and `rvmIdOnly`.
- Wrap Uniswap V2 Router `swapExactTokensForTokensSupportingFeeOnTransferTokens` inside a resilient `try / catch` block so honeypots or flash crashes emit `SwapFailed` rather than bricking the callback proxy.
- Implement `cancelPosition` emergency withdrawal and `AbstractPayer` debt settlement (`pay`, `coverDebt`).

### Milestone 3: Reactive Brain Engineering — `PulseTrailReactive.sol` (Phases 7–10)
- Implement subscription management in constructor and dynamic `subscribeToPool(address pair)` on Reactive Mainnet (`0x0000000000000000000000000000000000fffFfF`).
- Implement `react(LogRecord calldata log)` router handling three origin event types from Base Mainnet (`8453`):
  1. `PositionRegistered`: Hydrates position parameters into ReactVM state.
  2. `PositionCancelled`: Marks position inactive in ReactVM state.
  3. Uniswap V2 `Sync(uint112,uint112)`: Decodes spot price, updates circular 8-slot price buffer, computes volatility in bps, updates High-Water Mark, evaluates profit activation, and checks stage pullback triggers.
- Implement atomic stage advancement before emitting `Callback(8453, callbackContract, 350000, payload)` to eliminate double-triggers on rapid ~200ms Base blocks.

### Milestone 4: Comprehensive Foundry Test Suite (Phases 11–13)
- Build mock tokens (`MockERC20`, `MockFeeOnTransferERC20`, `MockHoneypotERC20`) and mock Uniswap V2 Pair/Router.
- Write unit and fuzz tests covering:
  - Price decoding accuracy across decimals and token0/token1 orderings.
  - Dormant Stage 0 behavior and Hard Floor circuit breaker.
  - Profit activation gate transition (`Stage 0 -> Stage 1`).
  - Rolling 8-tick volatility calculation and adaptive trail widening/tightening.
  - Multi-stage partial exits (`40% -> 30% -> 30%`) and remaining balance accounting.
  - Fee-on-transfer token sells and graceful `try / catch` recovery on honeypot reverts.
  - Double-trigger replay prevention and unauthorized caller rejection.

### Milestone 5: Mainnet Deployment & Live Cross-Chain Loop Execution (Phases 14–16)
- Deploy `PulseTrailCallback` to **Base Mainnet (`8453`)** wired to the official Base Callback Proxy (`0x0D3E76De6bC44309083cAAFdB49A088B8a250947`) and fund it with ETH for callback settlement.
- Deploy `PulseTrailReactive` to **Reactive Mainnet (`1597`)** wired to the Base Mainnet callback address and fund it with `REACT`.
- Execute a live end-to-end Mainnet workflow on a Base Uniswap V2 pool:
  1. Register a real trailing stop position on Base Mainnet.
  2. Execute swaps on the Base Uniswap V2 pool to trigger profit activation, HWM ratcheting, volatility adaptation, and multi-stage pullback callbacks.
  3. Capture all transaction hashes across `basescan.org` and `reactscan.net`.
- Run automated latency measurement script (`scripts/verify-latency.js`) to calculate exact block-to-block and timestamp-to-timestamp delta across chains.

### Milestone 6: Web3 Telemetry Dashboard, CLI & Submission Polish (Phases 17–20)
- Build the interactive Web3 Frontend Dashboard (`frontend/`) adhering to `doc/design-system.md` (Live Ratchet Chart, 4-Stage Stepper, Pre-Flight Risk Shield, and Judge Verification Explorer Table).
- Build an interactive CLI control & reproduction utility (`scripts/pulsetrail-cli.js`).
- Populate `README.md` with deployed Mainnet addresses, clickable full-loop transaction proof tables, architecture diagrams, and the "Risks & Mitigations" analysis.
- Record the `< 3 minute` walkthrough demo video script and finalize submission checks.

---

## 3. Risk Management Matrix

| Risk Category | Probability | Severity | Mitigation Strategy |
| :--- | :---: | :---: | :--- |
| **Callback Ignored Due to Gas Limit** | Low | Critical | Hardcode `CALLBACK_GAS_LIMIT = 350_000` (well above Reactive's 100,000 minimum). |
| **Unpaid Callback Proxy Debt** | Medium | High | Fund both contracts upon deployment and call `coverDebt()` automatically in deployment scripts. |
| **High Gas in `react()`** | Low | Medium | Bound volatility ring buffer to `uint256[8]` and skip storage updates when price change `< 5 bps`. |
| **Token Transfer Tax / Honeypot Revert** | Medium | High | Use `swapExactTokensForTokensSupportingFeeOnTransferTokens` inside `try / catch` and measure actual delta balances. |
| **Base 200ms Block Double-Trigger** | Medium | High | Advance `currentStage` atomically in `PulseTrailReactive` prior to `emit Callback(...)` and validate `stage > currentStage` in `PulseTrailCallback`. |

