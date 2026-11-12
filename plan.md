# PulseTrail — Project Plan

## Overview

**PulseTrail** is a fully on-chain trailing stop-loss system built on Reactive Omni. It monitors Uniswap pool events in real time, continuously tracks the highest price reached after entry (the high-water mark), and automatically executes a sell only when price pulls back a user-defined percentage from that peak.

Unlike fixed stop-losses, the trigger level only moves upward. This allows traders to ride trends while locking in profits on pullbacks — without needing to watch charts or run off-chain bots.

The system is designed for the **Reactive Omni Buildathon (Track 1: Every Second Counts)** and specifically highlights the value of ~1-second (and sub-second on Base Mainnet) block times for tight, responsive trailing logic.

**Key differentiators** (focus of this build):
- Volatility-adaptive trail
- Multi-stage partial exits
- Profit-activated trailing

---

## Core Concept (Plain English)

Imagine you buy a token at $100 and tell the system:  
“Only start trailing after I’m up 15%. Once trailing starts, sell in stages if it pulls back from its highs, and widen the trail when things get choppy.”

- Price rises 15% → trailing activates.
- Price continues higher → high-water mark and trail move up with it.
- Volatility spikes → the system automatically widens the trail so you don’t get stopped out by noise.
- Price pulls back past the first trail → sells a portion (e.g. 40%).
- Remaining position continues with a tighter trail.
- Price pulls back again → sells the rest.

Everything happens automatically on-chain.

---

## Technical Logic

### High-Level Flow

1. User deploys (or uses a shared) callback contract on **Base Mainnet** (or other supported mainnets like Ethereum / Arbitrum).
2. User approves tokens and registers parameters (activation profit %, trail distances per stage, partial exit percentages, volatility sensitivity, max slippage, optional tax estimate, optional hard floor).
3. Frontend/script performs a liquidity pre-check and shows warnings if needed.
4. Reactive contract on **Reactive Mainnet** (`1597`) subscribes to the pool’s `Sync` (Uniswap V2 / Aerodrome) or `Swap` (Uniswap V3) events.
5. On every matching event the reactive contract:
   - Decodes current price.
   - Updates high-water mark if a new high is reached.
   - Checks whether profit activation threshold has been crossed.
   - Calculates adaptive trail distance based on recent volatility.
   - Evaluates multi-stage partial exit conditions.
   - If a stage is triggered, emits a callback with the sell amount for that stage.
6. The callback contract executes the Uniswap swap for the specified portion (with slippage protection) and returns proceeds to the user.
7. Reactive contract advances the stage, updates remaining balance, and continues tracking.
8. User can cancel protection and withdraw remaining tokens at any time.

### Key On-Chain State (Reactive Contract)

- `highWaterMark`
- `entryPrice` / `activationPrice`
- `currentStage` (0 = not activated, 1–3 = active stages)
- `trailBps` per stage (or base + adaptive adjustment)
- Recent price buffer (for volatility calculation)
- Remaining position size / partial percentages
- User → callback contract mapping
- Stage-specific flags
- Optional hard floor price
- User max slippage tolerance

---

## Focus Features

### 1. Volatility-Adaptive Trail

The reactive contract maintains a small rolling buffer of recent prices (e.g. last 5–8 events).

On each new event it computes a simple volatility measure (e.g. average absolute percentage change or standard deviation of recent returns).

- High recent volatility → trail distance is widened (user-configurable multiplier or additive bps).
- Low recent volatility → trail distance is tightened toward the user’s base setting.

This reduces premature stops during noisy memecoin pumps while still protecting capital in calmer conditions. The calculation stays lightweight so `react()` remains efficient.

### 2. Multi-Stage Partial Exits

Instead of a single full exit, the position is managed in stages:

| Stage | Trigger | Action | Next Trail |
|-------|---------|--------|------------|
| 0     | Profit activation not reached | Hard stop only (optional) | — |
| 1     | Pullback from high-water mark ≥ Stage 1 trail | Sell 40% | Switch to Stage 2 trail |
| 2     | Pullback from (new) high-water mark ≥ Stage 2 trail | Sell 30% | Switch to Stage 3 trail |
| 3     | Pullback from high-water mark ≥ Stage 3 trail | Sell remaining 30% | Position closed |

Each stage can have its own trail distance. After a partial sell, the high-water mark can optionally be reset or continue from the previous peak. All stage logic lives in the reactive contract; the callback only executes the requested portion.

### 3. Profit-Activated Trailing

Trailing does **not** begin immediately after entry.

- User sets an activation threshold (e.g. +15% or +20% profit).
- Until that level is reached, only an optional hard stop-loss is active.
- Once price exceeds the activation level, the system begins tracking the high-water mark and applies the adaptive trailing logic.

This prevents early noise from stopping out a position before it has a chance to run, which is especially valuable for volatile assets.

---

## Competitive Gaps & Adaptations

### What We Can Adapt / Fix in PulseTrail

**High-value adaptations (fit our three focus features):**

- **From OmniStop** — Steal their evidence quality:
  - Full-loop latency measurement (origin event → reactive reaction → callback execution).
  - Public dashboard with live addresses and transaction hashes.
  - Explicit risks section.
  - Authenticated callback pattern.

- **From Hyperliquid / Jupiter** — Activation price concept:
  - We already have Profit-Activated Trailing. Make the activation threshold very clear and user-configurable.

- **From bots (Banana Gun / Thor)** — Partial exit culture:
  - Our Multi-stage Partial Exits already match what users expect from bots. Emphasize this heavily in the demo and docs.

- **From general trailing literature** — Volatility awareness:
  - Our Volatility-Adaptive Trail is the biggest differentiator. Most systems use fixed trails and get shaken out.

### Gaps We Should Actively Close

- **Real swap execution** — Must actually call the Uniswap router and move funds.
- **Slippage protection** — Add minimum amount out checks in the callback.
- **Position size / remaining balance tracking** — Critical for multi-stage partials.
- **Clear stage visibility** — Emit rich events so the demo can show stage transitions, adaptive trail changes, and activation status.
- **Memecoin-friendly defaults** — Wider base trails + volatility widening by default.

---

## Deep-Dive: Tackling Real-World Risks & Threats

### 1. Tackling Malicious & Honeypot Tokens

A honeypot is a token where you can buy, but when you try to sell:
- The token contract reverts on `transfer` or `transferFrom` (or checks `require(tx.origin == msg.sender)` to block smart contracts from selling).
- It charges a 99% or 100% hidden transfer tax.
- The developer blacklists the seller or pauses trading.

#### Solutions for PulseTrail:
- **A. Smart Contract Level: Graceful `try / catch` (Never Brick the System)**  
  If a token reverts during a sell, it must never break the callback contract or freeze other users' funds:
  ```solidity
  // In PulseTrailCallback.sol
  try uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
      amountToSell,
      minAmountOut,
      path,
      recipient,
      deadline
  ) {
      emit SwapExecuted(positionId, amountToSell);
  } catch Error(string memory reason) {
      // Gracefully catch standard reverts (e.g., Honeypot blacklist/revert)
      emit SwapFailed(positionId, reason);
      position.status = PositionStatus.Failed;
  } catch {
      // Catch low-level or non-standard reverts
      emit SwapFailed(positionId, "Unknown/Honeypot revert");
      position.status = PositionStatus.Failed;
  }
  ```
  *Why this matters:* The reactive watchdog advances the stage, and the callback records the failure rather than crashing or burning user gas in endless retry loops.

- **B. Registration "Dry-Run" Test (Pre-flight Check)**  
  When the user registers a position in `PulseTrailCallback`, run a micro-sell dry run:
  - Have the contract or frontend simulate selling 1 wei or 0.0001 token through the Uniswap router using `eth_call` (simulation).
  - If the simulation reverts or burns >10% of the test amount in fees, reject registration immediately with: *"Token appears to be a honeypot or unsellable by smart contracts."*

- **C. Support Fee-on-Transfer Tokens**  
  Many legit memecoins have a 1%–5% tax that funds marketing or liquidity:
  - Always use `swapExactTokensForTokensSupportingFeeOnTransferTokens` instead of standard `swapExactTokensForTokens`.
  - Measure token balances before and after receiving funds:
    ```solidity
    uint256 balanceBefore = token.balanceOf(address(this));
    token.safeTransferFrom(msg.sender, address(this), amount);
    uint256 actualReceived = token.balanceOf(address(this)) - balanceBefore;
    ```
    This tracks the real balance received so math in later stages doesn't try to sell tokens that were burned on transfer.

- **D. Frontend Security Screening (Off-Chain APIs)**  
  In the dApp frontend / registration UI, integrate free token audit APIs like GoPlus Security API or Honeypot.is:
  - Check: Is the contract open source? Is there a blacklist function? Is the sell tax >10%?
  - If red flags are detected, surface a big warning: *"Warning: This token has suspicious ownership/tax functions."*

---

### 2. Tackling Price Gaps / Flash Crashes

A price gap happens when a giant "whale" sells before your transaction lands, causing the price to jump instantly from e.g. $100 → $70, skipping your $90 target.

#### Solutions for PulseTrail:
- **Slippage Protection (`amountOutMinimum`):**
  - Never sell with `amountOutMinimum = 0`.
  - When the reactive contract triggers a sell at price $P$, calculate:
    $$\text{minOut} = \text{amountToSell} \times P \times (1 - \text{maxSlippageBps})$$
  - If a flash crash knocked the price below your safety threshold, the swap reverts safely rather than dumping your tokens for practically 0.
- **Multi-Stage Partial Exits (Our Stage 1 / 2 / 3):**
  - Because PulseTrail sells in portions (e.g. 40% → 30% → 30%), a price gap only affects the active stage rather than wiping out the entire bag.
- **Reactive Omni's ~1s / 200ms Blocks:**
  - Traditional bots on 12-second block chains suffer massive price gaps because 50 trades can happen in one block.
  - On Base Mainnet (~200ms blocks) and Reactive Mainnet (~1s blocks), PulseTrail catches the very first trade that breaches the line before a crash can compound.

---

### 3. Tackling Low Liquidity (High Price Impact)

When a pool only has a few thousand dollars in liquidity, your sell order might push the price down 20% by itself.

#### Solutions for PulseTrail:
- **Liquidity Depth Check at Registration:**
  - When registering, the contract queries the Uniswap pool reserves:
    ```solidity
    (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
    ```
  - If the user's position is more than e.g. 5%–10% of the total pool reserves, warn the user or automatically suggest smaller partial exit stages (e.g., 5 stages of 20% instead of 2 stages of 50%).
- **User-Configurable Max Price Impact:**
  - Allow the user to specify their max tolerated exit slippage (e.g., 3% for high-liquidity tokens, 10% for small-cap memecoins).

---

## Risk Mitigations & Trust Features (Summary)

- **Liquidity pre-check + warning**: Before registration, check pool liquidity and warn the user if it is too thin (“Exit may fail or have high slippage”).
- **Mandatory slippage protection**: Always use `amountOutMinimum`. User sets max slippage tolerance (e.g. 5–20%). Swap fails instead of executing at a bad price.
- **Transfer-tax handling**: Clear warning that some tokens have taxes. Optional user-provided estimated tax % so displayed proceeds are more realistic. Post-sell event shows actual amount received.
- **Optional hard floor**: In addition to trailing logic, user can set an absolute minimum price (e.g. “never sell below 50% of entry”). Protects against extreme gaps.
- **Emergency cancel / withdraw**: User can pause or fully cancel the trailing protection and withdraw remaining tokens at any time.
- **Clear warnings and reporting**: Prominent risk disclosures in UI and README. After every partial exit, emit events showing tokens sold vs. proceeds received.
- **Public verifiability**: Rich events + full-loop transaction hashes so anyone can verify behavior.
- **Recommended defaults for volatile pairs**: Wider trails, higher activation threshold, and conservative slippage for memecoins.
- **Position size awareness**: Optional warning or soft limit when the managed amount is large relative to pool liquidity.

---

## Risks & Mitigations (Technical Checklist)

- **High gas in `react()`**: Keep volatility buffer small (5–8 prices) and only write storage on meaningful changes.
- **Price decoding errors**: Dedicated unit tests for V2 `Sync` and V3/V4 `Swap` price conversion.
- **Double-trigger on rapid events**: Stage is advanced atomically in the reactive contract before the callback is emitted.
- **Price gaps**: System sells with strict `amountOutMinimum` calculation; multi-stage scaling limits gap exposure.
- **Remaining balance tracking**: Updated after every partial sell to prevent overselling.
- **Callback security**: Only the reactive contract can trigger sells. Replay / double-trigger protection on stages.
- **Honeypot / malicious tokens**: Handled via `try/catch` execution, pre-flight dry runs, balance checks, and frontend screening.

---

## Base Mainnet Specific Notes

- Blocks are produced every ~200 ms.
- Use **timestamps** for any time-based logic, cooldowns, or deadlines. Do not rely on block numbers.
- Confirm that the chosen pool actually emits frequent events.

---

## Why Omni Speed Matters

On older ~7-second Reactive blocks, a tight adaptive trail frequently missed peaks or was triggered by noise between updates. With ~1-second blocks (and Base Mainnet’s ~200 ms), the reactive contract sees nearly every meaningful price update, can recalculate volatility and high-water mark in near real time, and can advance stages quickly. This is the practical advantage Track 1 is designed to showcase.

---

## Applicability to Memecoins

PulseTrail works with any ERC-20 that has a Uniswap/Aerodrome pool on Base Mainnet, Ethereum Mainnet, or Arbitrum One, including memecoins.

The three focus features + risk mitigations are particularly useful here:
- Profit-activated trailing avoids getting shaken out right after entry.
- Volatility-adaptive trails handle extreme noise.
- Multi-stage partial exits lock in capital early.
- Liquidity warnings, slippage protection, tax estimates, and hard floors reduce nasty surprises.

### Memecoin-Specific Considerations

- Default to wider base trails (10–25%).
- Liquidity pre-check is mandatory in the UI.
- Transfer-tax warning is always shown.
- Honeypot risk remains — user responsibility, clearly disclosed.

### Future Multi-VM Roadmap: Solana, Raydium & Cross-VM Expansion

- **Current EVM Memecoin Coverage:** Today, PulseTrail natively supports EVM memecoin ecosystems across **Base Mainnet** (`8453` — Uniswap V2/V3, Aerodrome, Clanker, Virtuals, plus Solana memecoins bridged to Base via the Base–Solana bridge / Wormhole) and **BNB Smart Chain** (`56` — PancakeSwap V2/V3 & Four.meme), leveraging Base's ~200ms Flashblocks (twice as fast as Solana's ~400ms slot cadence).
- **Zero-Refactor SVM / Raydium Extensibility:** Reactive Network's broader roadmap includes cross-VM expansion (via Hyperlane transport and SVM/MoveVM adapters). Because 100% of PulseTrail's algorithmic intelligence—continuous High-Water Mark tracking, the rolling 8-tick volatility buffer, profit-activation gating, and the 3-stage state machine—is decoupled and lives inside `PulseTrailReactive.sol` on Reactive Mainnet (`1597`), extending PulseTrail to native **Solana & Raydium** pools requires only a lightweight SVM callback/vault program on Solana—with **zero changes** to the core Reactive brain.

---

## Competitive Landscape

### What Already Exists

- Fixed stop-loss / take-profit on Reactive Network (official demos + OmniStop).
- Trailing stops on CEXs and some DEXs (Jupiter, Hyperliquid, trading bots).
- Hybrid off-chain high-water mark systems.

### What Remains Differentiated

A fully on-chain reactive system combining continuous high-water mark tracking, volatility-adaptive trails, multi-stage partial exits, and profit-activated trailing — with practical risk mitigations — running on Reactive Omni with measurable low latency.

---

## Architecture

```
Base Mainnet (8453)                 Reactive Mainnet (1597)               Base Mainnet (8453)
┌──────────────────────────┐  Sync / Swap events  ┌──────────────────────────────────┐     Callback      ┌──────────────────────────┐
│ Uniswap V2/V3 Pool       │ ───────────────────► │ PulseTrailReactive               │ ────────────────► │ PulseTrailCallback       │
│ (or Aerodrome Pair)      │                      │ - Profit activation              │                   │ - Real Uniswap swap      │
│                          │                      │ - Volatility + adaptive trail    │                   │ - Slippage protection    │
│                          │                      │ - Multi-stage logic              │                   │ - Proceeds to user       │
│                          │                      │ - Remaining balance              │                   │ - Emergency withdraw     │
│                          │                      │ - Hard floor check               │                   │ - Debt & fee settlement  │
└──────────────────────────┘                      └──────────────────────────────────┘                   └──────────────────────────┘
```

---

## Reactive Network Technical Reference & Project Specifications (Mainnet)

From the official [Reactive Network Developer Documentation](https://dev.reactive.network/), the following core components, addresses, and architectural requirements apply directly to PulseTrail on **Mainnet**:

### 1. Chain IDs, RPCs & System Addresses

| Network | Role | Chain ID | RPC URL / Explorer | System Contract / Callback Proxy Address |
| :--- | :---: | :---: | :--- | :--- |
| **Reactive Mainnet** | Reactive VM | `1597` | `https://mainnet-rpc.rnk.dev/`<br>Explorer: [reactscan.net](https://reactscan.net/) | Service: `0x0000000000000000000000000000000000fffFfF`<br>System: `0x8888888888888888888888888888888888888888` |
| **Base Mainnet** | Primary Origin & Destination | `8453` | `https://mainnet.base.org`<br>Explorer: [basescan.org](https://basescan.org/) | Callback Proxy: `0x0D3E76De6bC44309083cAAFdB49A088B8a250947` |
| **Ethereum Mainnet** | Origin & Destination | `1` | `https://eth.llamarpc.com`<br>Explorer: [etherscan.io](https://etherscan.io/) | Callback Proxy: `0x1D5267C1bb7D8bA68964dDF3990601BDB7902D76` |
| **Arbitrum One** | Origin & Destination | `42161` | `https://arb1.arbitrum.io/rpc`<br>Explorer: [arbiscan.io](https://arbiscan.io/) | Callback Proxy: `0x4730c58FDA9d78f60c987039aEaB7d261aAd942E` |
| **BNB Smart Chain** | Origin & Destination | `56` | `https://binance.llamarpc.com`<br>Explorer: [bscscan.com](https://bscscan.com/) | Callback Proxy: `0xdb81A196A0dF9Ef974C9430495a09B6d535fAc48` |
| **Avalanche C-Chain** | Origin & Destination | `43114` | `https://api.avax.network/ext/bc/C/rpc`<br>Explorer: [snowtrace.io](https://snowtrace.io/) | Callback Proxy: `0x934Ea75496562D4e83E80865c33dbA600644fCDa` |

*(Note: Origins and destinations must match network tier — Mainnet Reactive contracts only listen to and trigger callbacks on Mainnet EVM chains. Base Mainnet is our primary target for Track 1 due to ~200ms block intervals).*

---

### 2. Reactive Contract Architecture (`PulseTrailReactive.sol`)

- **Inheritance & Interfaces**:
  - Implements `IReactive`
  - Inherits `AbstractReactive` from `reactive-lib`
- **System Service Subscription**:
  - Interacts with system contract `ISubscriptionService(0x0000000000000000000000000000000000fffFfF)` (or system dispatcher `0x8888888888888888888888888888888888888888`)
  - Subscribes in constructor (or dynamically) to Uniswap Pool events on Base Mainnet (`8453`):
    - **Uniswap V2 `Sync(uint112,uint112)`**: Topic `0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1`
    - **Uniswap V3 `Swap(...)`**: Topic `0xc42079f93a632750e11013731845751c9d1ab2dc0a20c0e9ec5dd76e6b853cb`
- **Event Handling (`react`)**:
  - Implements the exact entrypoint:
    ```solidity
    function react(LogRecord calldata log) external vmOnly { ... }
    ```
  - The `LogRecord` struct provides `chain_id`, `_contract`, `topic_0`...`topic_3`, `data`, `block_number`, and `op_code`.
- **Callback Emission**:
  - When trail conditions are met, emits:
    ```solidity
    emit Callback(destinationChainId, callbackContract, gasLimit, payload);
    ```
  - Payload is encoded via:
    ```solidity
    abi.encodeWithSignature("executeStageExit(uint256,uint256,uint256,uint256)", positionId, stage, amountToSell, minAmountOut)
    ```

---

### 3. Destination Callback Architecture (`PulseTrailCallback.sol`)

- **Inheritance & Security (`AbstractCallback`)**:
  - Inherits `AbstractCallback` (which extends `AbstractPayer`):
    ```solidity
    constructor(address _callbackProxy) AbstractCallback(_callbackProxy) { ... }
    ```
  - On Base Mainnet, `_callbackProxy` is `0x0D3E76De6bC44309083cAAFdB49A088B8a250947`.
  - Enforces `rvmIdOnly(authorizedReactiveAddress)` so that only callbacks emitted by the verified ReactVM instance can trigger sell executions.
  - Registers the callback proxy as an authorized payment sender for automated debt settlement.
- **Execution Safeguards**:
  - Performs Uniswap router swap (`swapExactTokensForTokensSupportingFeeOnTransferTokens`).
  - Strict slippage check with `amountOutMin`.
  - Wraps swaps in `try/catch` to gracefully catch honeypots and non-standard reverts without reverting the callback handler.

---

### 4. Reactive Economy, Gas Limits & Debt Management

- **Minimum Callback Gas Limit (Strict)**:
  - Reactive Network strictly enforces a **minimum callback gas limit of 100,000 gas**. Callbacks requesting less than 100,000 gas are automatically ignored. PulseTrail uses `250,000–350,000 gas` to account for Uniswap router swaps.
- **Funding & Debt Settlement (`AbstractPayer`)**:
  - Both Reactive contracts on Reactive Mainnet and Callback contracts on Base Mainnet must maintain positive native balances (in `REACT`).
  - If a contract accumulates unpaid debt to the callback proxy, it enters an **inactive / blocklisted state** and will cease executing callbacks.
  - Contracts inherit `AbstractPayer` for automated settlement via `pay()`, and support manual top-up or debt clearing via `coverDebt()`.

---

### 5. Tooling & Dependencies Needed

- **Core Libraries**:
  - `Reactive-Network/reactive-lib` (contains `IReactive.sol`, `AbstractReactive.sol`, `AbstractCallback.sol`, `AbstractPayer.sol`, `IPayable.sol`)
  - `@openzeppelin/contracts` (ERC20 utilities, `SafeERC20`, `ReentrancyGuard`, `Ownable`)
  - Uniswap V2 / V3 interfaces (`IUniswapV2Router02`, `IUniswapV2Pair`, `ISwapRouter`)
- **Testing & Deployment**:
  - Standard EVM tooling (Hardhat / Foundry) configured with Reactive Mainnet RPC (`https://mainnet-rpc.rnk.dev/`) and Base Mainnet RPC (`https://mainnet.base.org`).

---

## How PulseTrail Maps to the Reactive Judging Criteria (5/5 Strategy)

Every entry is scored from 1 to 5 on four equally weighted criteria. PulseTrail is engineered specifically to achieve top marks (5/5) across all four:

### 1. Execution (The Pass/Fail Gate)
> *"Does it run? We want to see the reactive transactions and the callbacks they trigger on-chain. Entries without them aren't scored further."*

Judges explicitly filter out projects that only exist on local forks or lack live on-chain callbacks.

* **Target Artifacts:**
  * **Origin & Destination Chain (Base Mainnet - `8453`):** Deployed `PulseTrailCallback` and live Uniswap pool.
  * **Reactive Chain (Reactive Mainnet - `1597`):** Deployed `PulseTrailReactive` subscribed to pool `Sync`/`Swap` events.
* **Verifiable On-Chain Loop:**
  * Origin Swap/Sync event `tx_hash` on Base Mainnet.
  * Reactive reaction `tx_hash` on Reactive Mainnet (`reactscan.net`) showing `react()` execution and `Callback` event emission.
  * Destination callback `tx_hash` on Base Mainnet executed by the official Callback Proxy (`0x0D3E76De6bC44309083cAAFdB49A088B8a250947`).
* **Latency Logging:** Include a Markdown table and verification script that reads block timestamps across chains to prove end-to-end execution latency.

### 2. Integration
> *"Does the reactive contract do real work, or is it bolted on? Each track's brief says what this means there."*

A project is penalized as "bolted-on" if the reactive contract is a glorified relayer (e.g., merely forwarding an event if `price < target`). For Track 1 (*"Every Second Counts"*), the Reactive VM must perform non-trivial, continuous stateful logic:

* **Real Stateful Work on Reactive Mainnet:**
  * **Rolling Volatility Calculation:** Maintains an in-memory buffer of recent price ticks to calculate instantaneous volatility and dynamically expand/contract trail bps.
  * **High-Water Mark (HWM) Engine:** Dynamically ratchets the trigger price upward on new peaks without any off-chain keeper.
  * **State Machine:** Manages multi-stage partial exits (e.g., Stage 0: Dormant → Stage 1: 40% exit → Stage 2: 30% exit → Stage 3: Closeout).
  * **Profit-Activation Gate:** Evaluates whether the threshold has been cleared before enabling the high-water tracker.
  * **Payload Assembly:** Computes the dynamic `amountToSell` and slippage-protected `minAmountOut` on the Reactive VM before dispatching the callback.

### 3. Usefulness
> *"Does it solve a problem real users have?"*

DeFi traders and memecoin buyers face severe real-world pain points:

* **The Problem:**
  * Fixed stop-losses exit too early or miss massive continuation.
  * Centralized trading bots require custodial private keys, charge recurring fees, and fail when backend servers crash.
  * Fast-moving memecoins produce fakeout wicks that prematurely trigger fixed trails.
* **PulseTrail's Solution:**
  * **100% Autonomous & Non-Custodial:** Runs purely on-chain via Reactive smart contracts.
  * **Volatility-Adaptive:** Relaxes the trail during violent swings so users aren’t shaken out by noise.
  * **Laddered Partial Exits:** Secures capital in tiers rather than dumping the full position.
  * **Protection against Honeypots/Slippage:** `try/catch` fee-on-transfer router swaps prevent transaction bricking or zero-liquidity drain.

### 4. Craft
> *"Readable code, a working demo, and documentation someone else could follow."*

* **Readable Code:**
  * Clean NatSpec comments on all public/external functions.
  * Adherence to standard patterns: `AbstractReactive`, `AbstractCallback`, `rvmIdOnly`, and OpenZeppelin's `SafeERC20`.
  * Comprehensive test suite (Foundry/Hardhat) covering edge cases (honeypots, price gap skips, double-triggers).
* **Working Demo:**
  * A clear video walkthrough under 3 minutes showing order creation, simulated price movement, live callback execution, and fund settlement.
  * A simple interactive dashboard / CLI runner to inspect live positions.
* **Followable Documentation:**
  * Step-by-step reproduction guide in the `README.md`.
  * Complete contract address tables (Reactive Mainnet, Base Mainnet).
  * Architectural ASCII / Mermaid diagrams.
  * Transparent "Risks & Mitigations" section (highlighting honeypot handling, slippage limits, and gas reserve debt).

---

## Buildathon Positioning (Track 1)

- Emphasize end-to-end latency measurement.
- Show practical value of 1s / 200ms blocks for adaptive trailing and multi-stage decisions on Mainnet.
- Demonstrate real stateful work in the reactive contract.
- Include clear transaction hashes, rich events, liquidity/tax warnings, and a short demo video.
- Public evidence of full loops + explicit risks section.

---

## Implementation Notes

- Prefer timestamps over block numbers on Base Mainnet.
- Keep `react()` gas-efficient with a small fixed-size price buffer.
- Emit detailed events for activation, high-water mark, volatility changes, stage transitions, partial sells, and actual proceeds.
- Support percentage-based and fixed-distance trails.
- Provide a simple frontend/script for registration, liquidity check, status display, and emergency cancel.
- Real Uniswap router swaps with user-set `amountOutMin`.
- Track remaining balance accurately.
- Authenticate callbacks and prevent double-triggers.
- Optional hard floor and user tax estimate.

---

## Demo & Submission Requirements

- Demo video under 3 minutes showing full flow including warnings, activation, adaptive trail, multi-stage exits, and emergency cancel option.
- Public open-source repository.
- Deployed contract addresses on Reactive Mainnet (`1597`) and Base Mainnet (`8453`).
- Multiple full-loop transaction hashes with timestamps.
- Explicit “Risks & Mitigations” section in README.
- Clear documentation.

---

## Priority Order (Build Sequence)

1. Minimal working version with real Uniswap swaps + single-stage trail + slippage protection.
2. Add remaining balance tracking + multi-stage partial exits.
3. Add profit-activated trailing + optional hard floor.
4. Add volatility-adaptive trail.
5. Add liquidity pre-check warnings, tax estimate support, and emergency withdraw.
6. Measure and document full-loop latency.
7. Polish rich events, dashboard/script, README, and demo video.

---

## Next Steps

1. Finalize interfaces with support for stages, adaptive parameters, remaining balance, slippage, hard floor, and emergency cancel.
2. Implement core contracts (`PulseTrailCallback.sol`, `PulseTrailReactive.sol`).
3. Write comprehensive Foundry tests (activation, stages, volatility, slippage, balance tracking, price decoding, double-trigger protection).
4. Deploy to Reactive Mainnet (`1597`) + Base Mainnet (`8453`).
5. Measure latency and collect full-loop evidence.
6. Build simple UI/script with warnings and status.
7. Create demo video and submit to Track 1.

---

## Summary

PulseTrail is an autonomous on-chain trailing stop with volatility adaptation, multi-stage partial exits, and profit-activated trailing, built for Reactive Omni’s speed. Combined with practical risk mitigations (liquidity warnings, slippage protection, tax awareness, hard floor, and emergency withdraw), it becomes both more useful for volatile assets and more trustworthy for users. Deployed to Reactive Mainnet and Base Mainnet, these elements differentiate it from basic stop-loss demos and align strongly with Track 1 judging criteria to achieve a 5/5 across all categories.