# PulseTrail — Product Requirements Document (PRD)

| Metadata | Details |
| :--- | :--- |
| **Product Name** | PulseTrail |
| **Track** | Reactive Omni Buildathon — Track 1: *Every Second Counts* |
| **Target Networks** | **Base Mainnet** (`8453`) & **Reactive Mainnet** (`1597`) |
| **Secondary Networks** | Ethereum Mainnet (`1`), Arbitrum One (`42161`), BNB Smart Chain (`56`) |
| **Status** | Specification Complete / Ready for Implementation |

---

## 1. Executive Summary

**PulseTrail** is a 100% autonomous, non-custodial, on-chain trailing stop-loss and laddered profit-taking protocol powered by **Reactive Mainnet** (`1597`) and **Base Mainnet** (`8453`). 

By subscribing to real-time DEX pool events (`Sync` and `Swap`) on Base Mainnet (~200ms block times) and processing stateful algorithmic logic on Reactive Mainnet (~1s block times), PulseTrail continuously tracks the post-entry **High-Water Mark (HWM)** of an asset's price. Unlike static stop-loss orders that execute at a fixed floor or centralized Telegram bots that require custodial private keys, PulseTrail dynamically ratchets the exit trigger upward as price climbs, adapts its trailing distance to real-time on-chain volatility, and scales out of positions in multi-stage partial exits.

---

## 2. Problem Statement

DeFi and memecoin traders on high-speed L2s like Base face four acute pain points:

1. **Static Stop-Losses Leave Upside on the Table or Trigger Prematurely:** A fixed stop-loss either gets wicked out early or fails to lock in gains after a token rallies 2x–5x and subsequently retraces 80%.
2. **Custodial Bot Risk & Centralization:** Existing trailing-stop tools (e.g., Telegram trading bots like Banana Gun, Maestro, Thor) require users to hand over private keys to centralized servers, pay 1%–2% per-trade fees, and trust off-chain keepers that go offline during congestion.
3. **Volatility Shakeouts ("Wick Hunting"):** Fixed-percentage trailing stops (e.g., flat 5% trail) get prematurely triggered during temporary high-volatility consolidation phases before the main trend resumes.
4. **All-or-Nothing Execution & Honeypot Failures:** Traditional on-chain limit/stop orders dump 100% of a position at once—causing massive price impact in thin pools—and often brick or enter infinite retry loops when encountering fee-on-transfer taxes or malicious token mechanics.

---

## 3. Target User Personas

| Persona | Profile | Key Pain Point | PulseTrail Value Proposition |
| :--- | :--- | :--- | :--- |
| **Active Base DEX Trader ("DeFi Degen")** | Trades volatile tokens & memecoins on Base Uniswap/Aerodrome pools; sleeps 6–8 hours a night. | Wakes up to find a +200% unrealized gain turned into a -50% loss overnight. | Profit-activated, multi-stage trailing stop locks in 40%–70% of gains on the way down while letting a moonbag ride. |
| **Self-Custody Purist** | Refuses to import private keys into Telegram bots or CEX accounts. | Lacks advanced algorithmic order types (trailing stops, volatility-adjusted exits) on DEXs. | 100% on-chain execution via audited smart contract patterns (`AbstractReactive` & `AbstractCallback`). |
| **Liquidity-Conscious Whale** | Holds 1%–5% of a mid-cap token's pool depth. | Selling 100% in one transaction causes severe slippage. | Multi-stage partial exits (e.g., 40% / 30% / 30%) distribute sell pressure across distinct pullback thresholds. |

---

## 4. Core Product Features & Functional Requirements

### FR-1: Profit-Activated Trailing
- **Description:** Trailing logic remains dormant until the token price reaches a user-defined profit activation threshold (`activationPrice`).
- **Behavior:**
  - In **Stage 0 (Dormant)**, price fluctuations above the hard floor do not move the trailing stop or trigger partial sells.
  - Once `currentPrice >= activationPrice`, the position transitions to **Stage 1 (Active)**, sets `highWaterMark = currentPrice`, and begins active trailing.
- **Benefit:** Prevents noisy post-entry chop from stopping out a position before the trend establishes.

### FR-2: Continuous High-Water Mark (HWM) Ratchet
- **Description:** Once activated, `PulseTrailReactive` monitors every `Sync` / `Swap` log emitted by the target Uniswap pool on Base Mainnet.
- **Behavior:**
  - Whenever `currentPrice > highWaterMark`, `highWaterMark` is updated to `currentPrice`.
  - The trigger price strictly ratchets upward (`highWaterMark * (10000 - effectiveTrailBps) / 10000`) and never decreases within a stage.

### FR-3: Volatility-Adaptive Trail Distance
- **Description:** The reactive contract maintains a lightweight rolling circular buffer of the last $N$ (e.g., $N = 8$) price ticks.
- **Behavior:**
  - Computes instantaneous volatility as the mean absolute percentage change (in basis points) across the buffer.
  - Dynamically computes `effectiveTrailBps = baseTrailBps + min(volatilityBps * sensitivityMultiplier, maxWideningBps)`.
  - Widens the trail during turbulent price swings to avoid premature wick-outs; tightens back toward `baseTrailBps` during calm trend continuation.

### FR-4: Multi-Stage Laddered Partial Exits
- **Description:** Positions exit across three configurable stages rather than a single 100% liquidation:
  - **Stage 0 (Pre-Activation):** Optional Hard Floor stop-loss only (sells 100% if catastrophic dump occurs before activation).
  - **Stage 1 (Initial Lock-In):** Pullback from HWM $\ge$ Stage 1 Adaptive Trail $\rightarrow$ Sells `stage1ExitBps` (default 40% of initial position) $\rightarrow$ Advances to Stage 2.
  - **Stage 2 (Trend Harvest):** Pullback from HWM $\ge$ Stage 2 Adaptive Trail $\rightarrow$ Sells `stage2ExitBps` (default 30% of initial position) $\rightarrow$ Advances to Stage 3.
  - **Stage 3 (Final Closeout):** Pullback from HWM $\ge$ Stage 3 Adaptive Trail $\rightarrow$ Sells remaining 100% of held balance $\rightarrow$ Marks position `Completed`.

### FR-5: Real DEX Swap Execution with Slippage & Tax Resilience
- **Description:** `PulseTrailCallback` on Base Mainnet executes real swaps through the Uniswap V2 / Aerodrome Router.
- **Behavior:**
  - Uses `swapExactTokensForTokensSupportingFeeOnTransferTokens` to support tokens with 1%–10% transfer taxes.
  - Enforces strict `minAmountOut` computed from trigger price and user's `maxSlippageBps`.
  - Measures exact pre- and post-transfer balances so transfer taxes never cause arithmetic underflows in later stages.

### FR-6: Honeypot Immunity (`try / catch` Execution & Pre-Flight Dry Run)
- **Description:** Malicious or paused tokens must never brick the callback proxy or trap the state machine.
- **Behavior:**
  - Swap call in `PulseTrailCallback` is wrapped in a `try / catch` block. If the router reverts, `SwapFailed(positionId, stage, reason)` is emitted instead of reverting the outer transaction.
  - Frontend/CLI performs an `eth_call` simulated micro-sell dry-run and pool reserve depth check prior to registration.

### FR-7: Optional Hard Floor & Emergency User Withdraw
- **Description:** Users retain full sovereignty over their tokens at all times.
- **Behavior:**
  - Users can configure an optional `hardFloorPrice` (e.g., -25% below entry) that acts as a circuit breaker even before profit activation.
  - Users can call `cancelPosition(positionId)` on `PulseTrailCallback` at any moment to immediately halt trailing and withdraw 100% of remaining tokens back to their wallet.

---

## 5. Non-Functional Requirements (NFRs)

1. **Gas Efficiency in `react()`:** The `react(LogRecord calldata log)` execution on Reactive Mainnet must consume `< 120,000 gas` on non-triggering ticks by bounding the price buffer to a fixed `uint256[8]` array and avoiding unnecessary storage writes when price changes are negligible (`< 5 bps`).
2. **Callback Gas Minimum Compliance:** All emitted `Callback` events must specify `gas_limit >= 300,000` (strictly exceeding Reactive Network's 100,000 gas minimum floor).
3. **Strict Authentication (`vmOnly` & `rvmIdOnly`):**
   - `PulseTrailReactive.react()` is restricted via `vmOnly`.
   - `PulseTrailCallback.executeStageExit()` is restricted via `authorizedSenderOnly` and `rvmIdOnly(rvm_id)`.
4. **Timestamp-Driven Logic:** Because Base Mainnet produces blocks every ~200ms, all deadlines and cooldowns use `block.timestamp` rather than `block.number`.

---

## 6. Alignment with Reactive Judging Rubric (Target: 20/20)

| Criterion (Weight: 25%) | Target Score | How PulseTrail Delivers |
| :--- | :---: | :--- |
| **1. Execution** | **5 / 5** | Live contracts deployed on **Base Mainnet (`8453`)** and **Reactive Mainnet (`1597`)**. Complete, verifiable on-chain transaction loop (Origin Swap $\rightarrow$ Reactive `react()` $\rightarrow$ Callback Proxy Swap) with timestamp latency benchmarks. |
| **2. Integration** | **5 / 5** | The Reactive contract is the core algorithmic brain—computing rolling volatility, ratcheting high-water marks, managing 4-stage state transitions, and calculating slippage-protected payloads on every pool event. |
| **3. Usefulness** | **5 / 5** | Solves overnight drawdown and volatility shakeout problems for DEX traders without requiring custodial Telegram bot keys. Includes fee-on-transfer and honeypot protections. |
| **4. Craft** | **5 / 5** | Production-grade Solidity with NatSpec, comprehensive Foundry unit/fuzz/integration tests, a sleek institutional-grade Web3 dashboard + CLI runner, and reproducible documentation. |

---

## 7. User Journey (End-to-End Flow)

1. **Connect & Inspect:** User connects wallet on Base Mainnet and enters a token/pair address.
2. **Pre-Flight Check:** UI queries pool reserves (`getReserves()`), calculates liquidity impact, and simulates a sell to verify the token is not a honeypot.
3. **Configure Strategy:**
   - Entry Price: Auto-detected from pool reserves.
   - Profit Activation: `+15%` (`1500 bps`).
   - Base Trails: Stage 1 = `8%`, Stage 2 = `6%`, Stage 3 = `5%`.
   - Partial Exits: Stage 1 = `40%`, Stage 2 = `30%`, Stage 3 = `30%`.
   - Volatility Sensitivity: `1.5x` adaptive widening.
   - Max Slippage: `3%` (`300 bps`).
4. **Approve & Register:** User approves token spend and calls `createPosition()` on `PulseTrailCallback`, which escrows tokens and emits `PositionCreated`.
5. **Autonomous Monitoring:** `PulseTrailReactive` on Reactive Mainnet picks up `PositionRegistered` and every subsequent `Sync` event from the Base Mainnet pool.
6. **Multi-Stage Execution:** As the token pumps +40%, pulls back 9%, pumps again, and retraces, `PulseTrailReactive` dispatches authenticated callbacks to `PulseTrailCallback`, executing partial swaps on Uniswap and transferring USDC/WETH directly to the user's wallet.

---

## 8. Memecoin Ecosystem Coverage & Future Multi-VM Roadmap (Solana / Raydium)

### 8.1 Current Native EVM Memecoin Support
- **Base Mainnet (`8453`):** Natively supports Uniswap V2/V3 and Aerodrome pools (including Clanker, Virtuals, BRETT, DEGEN, and **bridged Solana memecoins** trading on Base via the Base–Solana bridge / Wormhole). Base's ~200ms Flashblocks provide twice the temporal resolution of Solana's ~400ms slots.
- **BNB Smart Chain (`56`) & Ethereum (`1`):** Works out of the box with PancakeSwap V2 (`Sync` events share the identical topic hash `0x1c411e...`) for Four.meme and BSC memecoins.

### 8.2 Future Multi-VM Expansion (Solana & Raydium via Hyperlane / SVM Adapters)
- Reactive Network's cross-chain roadmap includes expanding beyond EVM ecosystems via **Hyperlane transport** and **SVM (Solana Virtual Machine) / MoveVM adapters**.
- **Hub-and-Spoke Decoupling Advantage:** Because 100% of PulseTrail's algorithmic intelligence—continuous High-Water Mark ratcheting, the rolling 8-tick volatility buffer, profit-activation gating, and the 3-stage partial exit state machine—is encapsulated inside `PulseTrailReactive.sol` on Reactive Mainnet (`1597`), adding native **Solana & Raydium** support in the future requires only deploying a lightweight SVM callback/vault adapter on Solana—with **zero changes** to the core Reactive brain.


