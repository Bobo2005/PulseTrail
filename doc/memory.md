# PulseTrail — Project Memory & Canonical Context (`memory.md`)

> **Purpose:** Single source of truth for architectural decisions, Mainnet constants, Reactive Network invariants, and domain rules. Keep updated across sessions.

---

## 1. Core Identity & Track Alignment
- **Project Name:** PulseTrail
- **Hackathon & Track:** Reactive Omni Buildathon — **Track 1: *Every Second Counts***
- **Deployment Tier:** **MAINNET ONLY** (Transitioned permanently from Lasna/Sepolia testnets to **Reactive Mainnet `1597`** and **Base Mainnet `8453`**).
- **Three Signature Differentiators:**
  1. **Profit-Activated Trailing:** Dormant in Stage 0 until `currentPrice >= activationPrice` (prevents early shakeouts).
  2. **Volatility-Adaptive Trail Distance:** Rolling 8-tick circular price buffer on Reactive Mainnet widens trail distance during high volatility and tightens during calm trends.
  3. **Multi-Stage Laddered Partial Exits:** Scales out across 3 configurable stages (default `40% -> 30% -> 30%`) instead of a single all-or-nothing dump.

---

## 2. Canonical Mainnet Network Constants (DO NOT ALTER)

### Reactive Mainnet (The Brain)
- **Chain ID:** `1597`
- **RPC Endpoint:** `https://mainnet-rpc.rnk.dev/`
- **Currency:** `REACT`
- **Block Explorer:** `https://reactscan.net/`
- **System Subscription Service (`SERVICE_ADDR`):** `0x0000000000000000000000000000000000fffFfF`
- **System Dispatcher Contract:** `0x8888888888888888888888888888888888888888`
- **Block Time:** `~1.0 second`

### Base Mainnet (Primary Origin & Destination Chain)
- **Chain ID:** `8453`
- **RPC Endpoint:** `https://mainnet.base.org`
- **Currency:** `ETH`
- **Block Explorer:** `https://basescan.org/`
- **Official Reactive Callback Proxy:** `0x0D3E76De6bC44309083cAAFdB49A088B8a250947`
- **Uniswap V2 Router02 (Base Mainnet):** `0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24`
- **Uniswap V2 Factory (Base Mainnet):** `0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6`
- **WETH (Base Mainnet):** `0x4200000000000000000000000000000000000006`
- **USDC (Base Mainnet):** `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`
- **Block Time:** `~200ms` (Flashblocks / sub-second L2 blocks)

### Additional Supported Destination Mainnets
- **Ethereum Mainnet (`1`):** Callback Proxy `0x1D5267C1bb7D8bA68964dDF3990601BDB7902D76`
- **Arbitrum One (`42161`):** Callback Proxy `0x4730c58FDA9d78f60c987039aEaB7d261aAd942E`
- **BNB Smart Chain (`56`):** Callback Proxy `0xdb81A196A0dF9Ef974C9430495a09B6d535fAc48`
- **Avalanche C-Chain (`43114`):** Callback Proxy `0x934Ea75496562D4e83E80865c33dbA600644fCDa`

---

## 3. Critical Reactive Network Invariants

1. **First Argument of Callback Payload (`address rvm_id`):**
   - Reactive Network **automatically overwrites the first 32 bytes (`address`) of every callback payload** with the `rvm_id` (the deployer address of the Reactive contract).
   - Therefore, `executeStageExit` in `PulseTrailCallback.sol` **MUST** have `address rvm_id` as its first parameter:
     ```solidity
     function executeStageExit(
         address rvm_id,
         uint256 positionId,
         uint8 stage,
         uint256 amountToSell,
         uint256 minAmountOut
     ) external authorizedSenderOnly rvmIdOnly(rvm_id)
     ```
   - And when `PulseTrailReactive.sol` encodes the payload, it passes `address(0)` as the placeholder first argument:
     ```solidity
     bytes memory payload = abi.encodeWithSignature(
         "executeStageExit(address,uint256,uint8,uint256,uint256)",
         address(0), // Overwritten by Reactive Network with rvm_id
         positionId,
         stageToTrigger,
         amountToSell,
         minAmountOut
     );
     ```

2. **Minimum Callback Gas Limit (`>= 100,000`):**
   - Reactive Network silently drops any `Callback` event with `gas_limit < 100,000`.
   - PulseTrail enforces `uint64 public constant CALLBACK_GAS_LIMIT = 350_000;` to safely cover Uniswap V2 Router swaps and ERC-20 transfers.

3. **Dual Execution Context (`vm` vs `!vm`) in `PulseTrailReactive`:**
   - Subscriptions (`service.subscribe(...)`) can **only** be called on the Reactive Network (`!vm`), never inside the ReactVM (`vm`).
   - `react(LogRecord calldata log)` can **only** be called inside the ReactVM (`vmOnly`).
   - State variables initialized in the constructor are copied into the ReactVM snapshot at deployment, while dynamic state changes from Base Mainnet must arrive via subscribed event logs (`PositionRegistered`, `PositionCancelled`, `Sync`).

4. **Atomic Stage Advancement (Anti-Double-Trigger):**
   - Because Base Mainnet produces blocks every ~200ms, multiple `Sync` events may arrive before the destination callback executes.
   - `PulseTrailReactive` **must** advance `pos.currentStage` and reduce `pos.remainingBalance` inside `react()` **immediately before** emitting `Callback`.
   - `PulseTrailCallback` **must** also check `require(stage > pos.currentStage, "Stage already processed")`.

5. **Never Brick the Callback Proxy on Malicious Tokens:**
   - All router swaps in `PulseTrailCallback.sol` use `try uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(...) { ... } catch { ... }` so a honeypot revert logs `SwapFailed` cleanly without reverting the callback transaction.

6. **Timestamps Over Block Numbers:**
   - Never use `block.number` for cooldowns or swap deadlines on Base Mainnet; always use `block.timestamp`.

---

## 4. Multi-VM & Memecoin Ecosystem Positioning
- **Live Native EVM Memecoin Support:** Works natively today on **Base Mainnet (`8453`)** (Uniswap V2/V3, Aerodrome, plus bridged Solana memecoins on Base) and **BNB Smart Chain (`56`)** (PancakeSwap V2/V3).
- **Future Multi-VM Roadmap (Solana / Raydium):** Reactive Network has discussed cross-VM expansion via **Hyperlane** and **SVM adapters**. Because 100% of PulseTrail's trailing math, rolling 8-tick volatility buffer, profit-activation gating, and 3-stage state machine live inside `PulseTrailReactive.sol` on Reactive Mainnet (`1597`), adding **Solana & Raydium** in the future only requires a lightweight SVM callback/vault adapter—**zero changes to the core Reactive brain**.

---

## 5. Buildathon Completion Status & Submission Artifacts
- **Current Status:** 100% Complete across all 20 development phases and task groups A through F.
- **Master Documentation:** `README.md`
- **Latency Benchmark Report:** `doc/latency-benchmark.md`
- **Video Walkthrough Script:** `doc/demo-video-script.md`
- **Project Handoff:** `doc/handoff.md`
- **Task Tracker:** `doc/TODO.md` (100% checked)
- **Frontend Dashboard:** `frontend/index.html`, `frontend/styles.css`, `frontend/app.js`
- **CLI & Automation:** `scripts/pulsetrail-cli.js`, `scripts/run-mainnet-loop.js`, `scripts/verify-latency.js`
- **Target Submission Score:** 20/20 across Execution, Integration, Usefulness, and Craft.


