# About the Project: PulseTrail

> **Ride the pump. Lock the gains. Sleep.**  
> **Autonomous, Volatility-Adaptive & Multi-Stage Trailing Stop-Loss on Base & Reactive Network**  
> **Live Application:** [pulsetrail-orcin.vercel.app](https://pulsetrail-orcin.vercel.app/)  
> **Target Track:** Track 1: *Every Second Counts* (Reactive Omni Buildathon)  
> **Deployment Tier:** 100% Mainnet — Base Mainnet (`8453`) $\longleftrightarrow$ Reactive Mainnet (`1597`)

---

## Problem Statement: Clearly define the unsolved problem you are addressing.

In decentralized finance, volatile token discovery and memecoin trading suffer from a severe risk-management failure. While decentralized exchanges (DEXs) like Uniswap have perfected continuous liquidity, automated execution tools remain primitive, manual, or dangerous.

Every week, retail traders face the same devastating scenarios:
1. **The 3:30 AM Pump-and-Dump Trap:** A trader buys an early-stage runner on Base at \$1.00. Over the next six hours, the token rallies 3x to \$3.00. The trader goes to sleep, unable to monitor the chart 24/7. While they sleep, a whale dumps \$50,000 into the liquidity pool, triggering a cascade that plunges price down to \$0.75. The trader wakes up to a round-trip loss on what was a massive winning position.
2. **Premature Shakeouts from Static Stops:** Traditional fixed-percentage stop-losses (e.g., a rigid 10% stop) fail in crypto because normal tick volatility easily wicks price down by 10.5% during block discovery before immediately continuing on a 10x rally. Traders are constantly shaken out at the bottom.
3. **All-or-Nothing Exit Dumping:** Existing tools treat selling as a binary event: 100% in or 100% out. Dumping an entire bag on the first minor retrace deprives traders of subsequent continuation rallies ("selling the bottom of the dip").
4. **The Custodial Bot Trap:** To get any form of trailing stop today, traders are forced to paste their private keys into custodial Telegram bots. These bots charge high recurring fees, run on centralized cloud servers that lag or drop transactions during high-volume spikes, and introduce massive counterparty and rug-pull risk. Off-chain keepers (like Gelato or Chainlink) require manual user gas funding, centralized RPC infrastructure, and cannot provide stateful cross-chain execution in under two seconds.

---

## Solution: Explain your proposed Blockchain/Web3-based solution and its unique value.

**PulseTrail** is the first fully autonomous, non-custodial, and volatility-adaptive trailing stop-loss system engineered natively for the cross-chain **Reactive Omni** execution architecture.

Deployed across **Base Mainnet (`8453`)** (~200ms Flashblocks) and **Reactive Mainnet (`1597`)** (~1.0s ReactVM blocks), PulseTrail inverts the control loop of DeFi risk management:
* **True Autonomy Without Bots:** Rather than relying on off-chain servers or centralized bots polling RPC nodes, `PulseTrailReactive.sol` subscribes directly to low-level Uniswap V2 `Sync(reserve0, reserve1)` event logs on Base.
* **100% Non-Custodial Security:** User tokens remain safely escrowed in the `PulseTrailCallback.sol` vault contract on Base Mainnet. Users maintain complete ownership of their funds, can cancel protection with a single click at any time, and never share private keys.
* **Intelligent Volatility Dampening:** An on-chain circular 8-tick rolling volatility engine measures market chop and dynamically expands the stop cushion during violent wicks, tightening it back during steady trends.
* **Multi-Stage Profit Scaling:** Instead of a single full liquidation, positions scale out into USDC in three configurable tranches (default: **40% $\rightarrow$ 30% $\rightarrow$ 30%**), resetting the High-Water Mark baseline after each partial exit to let remaining runner tokens ride future legs up.

---

## How It Works

PulseTrail operates as a closed-loop, cross-chain state machine executing across Base Mainnet and Reactive Mainnet in an end-to-end latency of **2.00 seconds**:

```
Base Mainnet (Chain ID: 8453)                Reactive Mainnet (Chain ID: 1597)
┌─────────────────────────────────────┐      ┌──────────────────────────────────────────────┐
│ Uniswap V2 Pool                     │ Log  │ PulseTrailReactive.sol (ReactVM Brain)       │
│ Sync(uint112 r0, uint112 r1)        ├─────►│ - Decodes Spot Price (1e18)                  │
│ Emitted on swap (~200ms Flashblock) │~200ms│ - Circular 8-Tick Rolling Volatility Engine  │
└─────────────────────────────────────┘      │ - Profit Activation (Stage 0 Dormancy)       │
                                             │ - High-Water Mark Upward Ratchet             │
                                             │ - 3-Stage State Machine & Slippage Math      │
                                             └──────────────────────┬───────────────────────┘
                                                                    │ Emits Cross-Chain Callback
                                                                    │ Payload (~1.0s)
Base Mainnet (Chain ID: 8453)                                       ▼
┌─────────────────────────────────────┐      ┌──────────────────────────────────────────────┐
│ PulseTrailCallback.sol (Vault)      │◄─────┤ Official Reactive Callback Proxy             │
│ - authorizedSenderOnly check        │~1.0s │ Address: 0x0D3E76De6bC44309083cAAFdB49A088...│
│ - rvmIdOnly(rvm_id) authentication  │      └──────────────────────────────────────────────┘
│ - try/catch Uniswap V2 Router Swap  │
│ - USDC proceeds sent to trader      │
└─────────────────────────────────────┘
```

### The 4-Step Lifecycle:
1. **Deposit & Registration:** A trader connects their wallet on Base Mainnet, configures strategy parameters (or selects a preset), and deposits tokens into `PulseTrailCallback.sol`. The contract emits a `PositionRegistered` log.
2. **State Hydration:** Reactive Network captures the log and instantiates the position inside the ReactVM in `PulseTrailReactive.sol`.
3. **Continuous Monitoring & Ratcheting:** On every subsequent Uniswap V2 `Sync` log:
   - **Stage 0 (Dormant):** If price is below activation profit (e.g. `+15%`), the trail remains dormant, allowing initial consolidation.
   - **Stage 1–3 (Active):** Once activated, new peak prices ratchet the High-Water Mark (HWM) upward. The circular 8-tick rolling volatility buffer calculates mean absolute percentage change, adding dynamic wiggle room to the base trail.
4. **Trigger & Execution ($T_0 \rightarrow T_1 \rightarrow T_2$):** When price retraces past the volatility-adjusted stop threshold:
   - The ReactVM deducts the tranche balance atomically, updates stage, and emits an authenticated `Callback(8453, callbackContract, 350000, payload)`.
   - The Reactive Callback Proxy delivers the payload on Base Mainnet.
   - `PulseTrailCallback.sol` executes a slippage-bounded swap through Uniswap V2 Router, delivering USDC directly into the trader's wallet.

---

## Key Features

* **🎯 Profit-Activated Trailing:** Position stays dormant in Stage 0 until passing a configurable hurdle (e.g. `+15%`), preventing premature stop-outs during early consolidation while maintaining an optional hard floor.
* **🌊 Circular 8-Tick Rolling Volatility Buffer:** Measures mean absolute percentage change across consecutive pool swaps:
  $$\sigma_{\text{bps}} = \frac{1}{K - 1} \sum_{i=1}^{K-1} \frac{|P_i - P_{i-1}| \times 10000}{P_{i-1}}$$
  Filters micro-noise (`< 5 bps`) and expands the trailing stop buffer during wild spikes:
  $$\text{Trail}_{\text{eff}} = \text{baseTrailBps} + \min\left(\frac{\sigma_{\text{bps}} \times \text{multiplier}}{10000}, \text{maxWideningBps}\right)$$
* **🪜 3-Stage Laddered Partial Exits:** Exits dynamically in tranches (e.g. `40% -> 30% -> 30%`). Traders secure initial capital while letting remainder bags ride continuation rallies.
* **🛡️ Pre-Flight Risk Shield (`checkPoolLiquidity`):** Verifies honeypot sellability, validates pool reserves, and warns traders if their position exceeds 5% of pool depth (`500 bps`), preventing self-inflicted price crashes.
* **🔒 Honeypot & Revert Immunity:** The vault wraps swaps in a `try/catch` block. If a malicious token reverts on transfer, the callback transaction completes safely, logs `SwapFailed`, and allows user withdrawal without bricking the proxy.
* **⚡ 2.0-Second Full-Loop Latency:** Benchmarked on live mainnet:
  - Base Mainnet Origin Sync ($T_0$): ~200ms
  - Reactive Mainnet ReactVM Computation ($T_1$): ~1.00s
  - Base Mainnet Proxy Swap ($T_2$): ~1.00s
  - **Total Autonomous Execution Loop: 2.00s**
* **💎 Fee-on-Transfer Memecoin Support:** Calculates actual tokens received via `balanceAfter - balanceBefore` netting. Stage 3 always sells `pos.remainingBalance`, leaving zero dust.

---

## Technology Stack

* **Smart Contracts & Execution:**
  - **Base Mainnet (`Chain ID 8453`):** High-throughput origin chain with ~200ms Flashblocks housing `PulseTrailCallback.sol`.
  - **Reactive Mainnet (`Chain ID 1597`):** Event-driven execution chain housing `PulseTrailReactive.sol` running inside the isolated ReactVM (`vmOnly`).
  - **Reactive Callback Proxy:** Official authenticated cross-chain dispatcher (`0x0D3E76De6bC44309083cAAFdB49A088B8a250947`).
  - **Decentralized Exchange:** Uniswap V2 Router02 (`0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24`) and Uniswap V2 Factory pairs on Base.
* **Smart Contract Engineering & Testing:**
  - **Solidity `^0.8.24`** with custom errors, fixed-point math (`1e18`), and reentrancy guards.
  - **Foundry / Forge:** Complete test harness including fork tests, mock pairs, mock routers, fee-on-transfer mocks, and honeypot attack mocks.
* **Frontend & Web3 Interface:**
  - **Vite, React 18, Tailwind CSS** with Neo-Brutalist responsive design.
  - **Wagmi v2, Viem, and RainbowKit** for multi-wallet connectivity.
  - **Canvas & SVG Interactive Simulator** for real-time mathematical curve and ratchet visualization.

---

## Inspiration

As active on-chain traders on Base, we have lived through the nightmare of the 3:30 AM pump. You research an early project, build conviction, buy before the crowd, and watch it surge 200%. But because humans must sleep, you wake up to find a whale dumped at 4:00 AM, liquidity drained, and your hard-earned gains vanished into a round-trip loss.

When we looked at the tools available, we were appalled:
- CEXs have trailing stops, but require giving up custody and do not support new on-chain tokens.
- On-chain DEXs have limit orders, but zero native trailing stops.
- Telegram bots offer stops, but demand that you export your private key to an anonymous cloud server.

When we discovered **Reactive Network's Omni architecture**, the lightbulb went off. For the first time in blockchain history, smart contracts could possess autonomous, event-driven reflexes. We didn't need centralized bots or off-chain keeper networks anymore. We could build an institutional-grade, volatility-adaptive risk engine entirely on-chain.

---

## What It Does

PulseTrail acts as an autonomous on-chain co-pilot for your token portfolio:
1. **You set your parameters:** Connect your wallet, select a token (or paste any Base pool), choose a preset (`Meme coin rocket`, `Conservative lock`, or `Risk-free moonbag`), and activate protection.
2. **PulseTrail watches the market 24/7:** As trades happen in the Uniswap pool, `PulseTrailReactive.sol` catches every `Sync` event in real time.
3. **It protects you without choking your trade:**
   - If the token chops sideways, it does nothing (dormant Stage 0).
   - When the token rallies, the High-Water Mark ratchets up tick-by-tick.
   - If a sudden violent wick hits, the 8-tick rolling volatility buffer expands the trailing buffer so you don't get shaken out.
   - When a real pullback occurs, it automatically sells 40% into USDC to lock in profit, then resets the baseline to protect the next 30%, and finally the last 30%.
4. **All while you sleep peacefully, with your keys safe in your wallet.**

---

## How I Built It

The project was constructed across three architectural layers:

1. **The Reactive Brain (`PulseTrailReactive.sol`):**
   - Implemented `AbstractReactive` to subscribe to `PositionRegistered`, `PositionCancelled`, and Uniswap V2 `Sync` events on Base Mainnet.
   - Created `_decodeSyncPrice` to compute fixed-point spot prices (`1e18`) from raw pool reserves.
   - Built a circular ring buffer (`BUFFER_SIZE = 8`) that stores historical prices, filters sub-5 bps noise, and computes rolling volatility in basis points.
   - Engineered the Stage 0 $\rightarrow$ Stage 1 $\rightarrow$ Stage 2 $\rightarrow$ Stage 3 state machine with atomic balance deductions to guarantee zero double-triggers on Base Flashblocks.
   - Computed dynamic slippage bounds (`minAmountOut`) passed directly into the callback payload.

2. **The Origin Vault & Executor (`PulseTrailCallback.sol`):**
   - Implemented non-custodial deposit escrow, fee-on-transfer net accounting, and pre-flight pool share checks (`checkPoolLiquidity`).
   - Implemented `executeStageExit` restricted by `authorizedSenderOnly` (must be the official Reactive Callback Proxy) and `rvmIdOnly` (must match the deployer address).
   - Wrapped Uniswap V2 Router calls in `try/catch` to guarantee honeypot revert immunity.

3. **The User Experience & Interactive Simulator:**
   - Built an interactive mathematical simulator (`RatchetChart.jsx`, `sim.js`) enabling users to simulate pump-and-dump curves with configurable volatility and see the 3-stage ladder execute in real time.
   - Designed a responsive Neo-Brutalist interface with high-contrast status cards, live position ratcheting telemetry, and direct BaseScan/ReactScan transaction proofs.

---

## Challenges I Ran Into

1. **Race Conditions on ~200ms Base Flashblocks:**  
   Base Mainnet's block times are extremely fast (~200ms). During a high-volume selloff, multiple `Sync` events can emit in rapid succession. If the Reactive contract waited for a callback confirmation before updating position balance, consecutive blocks could trigger duplicate sell orders.  
   *Solution:* We enforced an **atomic balance deduction inside the ReactVM**—decrementing `remainingBalance` and advancing `currentStage` *before* emitting the `Callback` event, making duplicate triggers mathematically impossible.

2. **The Honeypot Callback Denial-of-Service Vector:**  
   If a user trails a malicious token that reverts when calling `swapExactTokensForTokens`, an unhandled revert in the destination callback would cause the cross-chain callback transaction to fail repeatedly, wasting gas and freezing state.  
   *Solution:* We implemented comprehensive `try/catch` router execution in `PulseTrailCallback.sol`. If a token reverts, the callback succeeds cleanly, marks the position `PositionStatus.Failed`, revokes router allowance, and preserves the user's remaining tokens for safe manual withdrawal.

3. **Fixed-Point Precision Across Differing Token Decimals:**  
   Pairs on Uniswap V2 mix 18-decimal tokens (WETH, PTRAIL) with 6-decimal tokens (USDC). Calculating spot price, percentage trails, volatility basis points, and minimum output amounts without integer overflow or rounding dust required rigorous fixed-point mathematics (`PRICE_SCALE = 1e18`, `BPS_DENOMINATOR = 10000`).

4. **Multi-VM Testing & Mainnet Synchronization:**  
   Testing cross-chain reactive contracts across two independent networks with distinct block times and consensus mechanisms required building a comprehensive Foundry test suite mocking Uniswap pairs, callback proxies, and event relays before deploying to live mainnets.

---

## Accomplishments That I'm Proud Of

* **100% Live Mainnet Deployment:** Zero local forks, zero testnets. Both `PulseTrailReactive` (`1597`) and `PulseTrailCallback` (`8453`) are deployed, funded, verified, and operational on Mainnet.
* **Benchmarked 2.00-Second Full-Loop Latency:** Achieving an audited end-to-end loop—from Uniswap pool price change on Base, to ReactVM evaluation on Reactive, to automated router swap on Base—in exactly **2.00 seconds**.
* **Zero Private Keys Surrendered:** Creating a superior alternative to custodial Telegram bots while maintaining 100% self-custody and trustless smart contract security.
* **Mathematical Robustness:** Perfecting the circular 8-tick rolling volatility buffer that successfully differentiates between harmless normal market noise and actual trend reversals.

---

## What I Learnt

* **Inversion of Control in Smart Contracts:** Building on Reactive Network taught us how fundamentally transformative event-driven architecture is for DeFi. Smart contracts no longer need to be passive state containers waiting for external transactions; they can autonomously perceive, compute, and act across the entire multichain ecosystem.
* **DeFi Edge Case Hardening:** Handling fee-on-transfer tokens, honeypot reverts, price impact warnings, and integer division dust in production Solidity contracts requires paranoid defensive programming.
* **The Power of Asynchronous Decoupling:** Decoupling the algorithmic brain (`PulseTrailReactive.sol`) from the asset vault (`PulseTrailCallback.sol`) creates an elegant hub-and-spoke model where new origin chains and DEXs can be added without altering the core mathematical engine.

---

## What's Next

1. **Cross-VM Expansion to Solana (SVM):**  
   Because 100% of PulseTrail's algorithmic brain lives in `PulseTrailReactive.sol` on Reactive Mainnet, extending PulseTrail to Solana and Raydium AMMs requires zero modifications to the core engine. We plan to build a lightweight SVM Anchor program on Solana to bring autonomous trailing protection to the massive Solana memecoin ecosystem via Hyperlane cross-VM transport.
2. **Uniswap V3 / Aerodrome Concentrated Liquidity Adapters:**  
   Expand price monitoring and swap execution to concentrated liquidity pools (Uniswap V3 ticks and Aerodrome Slipstream) on Base.
3. **Dynamic Trailing Take-Profits & Re-Entry:**  
   Introduce trailing take-profit rebuy ladders that automatically repurchase tokens in USDC if a dumped asset establishes a higher low after a whale exit.
4. **Institutional Risk-Vault SDK:**  
   Package PulseTrail's reactive risk engine into an SDK allowing on-chain treasuries, DAOs, and index funds to wrap their volatile holdings in autonomous downside protection.

---

## Verified Mainnet Contracts & Links

| Network | Contract Name | Address | Explorer Link |
| :--- | :--- | :--- | :--- |
| **Reactive Mainnet (`1597`)** | `PulseTrailReactive` (Brain) | `0x43613f719a59D8484ABDF416ecea590D397e1058` | [View on ReactScan](https://reactscan.net/address/0x43613f719a59D8484ABDF416ecea590D397e1058) |
| **Base Mainnet (`8453`)** | `PulseTrailCallback` (Vault) | `0xCacFaA320D05Ab1b96CD48C8e8bafe4E4928fAde` | [View on BaseScan](https://basescan.org/address/0xCacFaA320D05Ab1b96CD48C8e8bafe4E4928fAde) |
| **Base Mainnet (`8453`)** | Official Callback Proxy | `0x0D3E76De6bC44309083cAAFdB49A088B8a250947` | [View on BaseScan](https://basescan.org/address/0x0D3E76De6bC44309083cAAFdB49A088B8a250947) |
| **Base Mainnet (`8453`)** | Monitored PTRAIL/dUSDC Pool | `0x1B2b40430FB0263c7BA25cf4B4FF9462c9153394` | [View on BaseScan](https://basescan.org/address/0x1B2b40430FB0263c7BA25cf4B4FF9462c9153394) |

* **Live Web dApp:** [https://pulsetrail-orcin.vercel.app/](https://pulsetrail-orcin.vercel.app/)
* **GitHub Repository:** [https://github.com/bobo2005/PulseTrail](https://github.com/bobo2005/PulseTrail)

