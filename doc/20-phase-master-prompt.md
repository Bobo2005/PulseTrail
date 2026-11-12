# PulseTrail — 20-Phase Comprehensive Master Engineering Prompt Book

> **Purpose:** This 20-phase master prompt sequence is engineered to take **PulseTrail** from specification (`plan.md`) to a fully tested, Mainnet-deployed (**Base Mainnet `8453`** + **Reactive Mainnet `1597`**), latency-benchmarked, and judge-ready submission scoring **5/5 across Execution, Integration, Usefulness, and Craft**.
>
> **How to Use:** You can feed these phases one by one (or in logical batches) to your AI coding agent, or ask the agent to execute Phase $N$ through Phase $M$ autonomously while updating `doc/TODO.md` and `doc/memory.md` after each phase.

---

## Phase 1: Workspace Initialization, Foundry Config & Mainnet Environment Setup
**Prompt:**
> Read `plan.md`, `doc/architecture.md`, and `doc/memory.md`. Initialize the hybrid Foundry + Node.js development workspace for **PulseTrail**:
> 1. Create `foundry.toml` configured with `solc = "0.8.24"`, `optimizer = true`, `optimizer_runs = 200`, `via_ir = true`, `src = "contracts"`, `test = "test"`, `script = "script"`, and RPC endpoints for `base_mainnet` (`https://mainnet.base.org`) and `reactive_mainnet` (`https://mainnet-rpc.rnk.dev/`).
> 2. Update `package.json` with scripts for `build`, `test`, `deploy:base`, `deploy:reactive`, `loop:mainnet`, `verify:latency`, and `cli`, and install `ethers` (v6) and `dotenv`.
> 3. Create `.env.example` containing all Mainnet constants:
>    - `BASE_MAINNET_RPC_URL=https://mainnet.base.org`
>    - `BASE_MAINNET_CHAIN_ID=8453`
>    - `BASE_CALLBACK_PROXY=0x0D3E76De6bC44309083cAAFdB49A088B8a250947`
>    - `BASE_UNISWAP_V2_ROUTER=0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24`
>    - `REACTIVE_MAINNET_RPC_URL=https://mainnet-rpc.rnk.dev/`
>    - `REACTIVE_MAINNET_CHAIN_ID=1597`
>    - `REACTIVE_SERVICE_ADDR=0x0000000000000000000000000000000000fffFfF`
>    - `REACTIVE_SYSTEM_CONTRACT=0x8888888888888888888888888888888888888888`
>    - `DEPLOYER_PRIVATE_KEY=`
> 4. Mark Task 1.1 and Task 1.2 complete in `doc/TODO.md`.

---

## Phase 2: Reactive Network Base Library & System Interfaces
**Prompt:**
> Read `contracts/interfaces/IReactive.sol` and `doc/architecture.md`. Create the complete, self-contained Reactive Network base contracts and interfaces under `contracts/interfaces/` and `contracts/abstract/` so the project compiles cleanly without broken submodule paths:
> 1. `contracts/interfaces/IPayable.sol`: Defines `receive() external payable` and `function debt(address _contract) external view returns (uint256)`.
> 2. `contracts/interfaces/ISubscriptionService.sol`: Inherits `IPayable` and defines `subscribe(uint256 chain_id, address _contract, uint256 topic_0, uint256 topic_1, uint256 topic_2, uint256 topic_3) external` and `unsubscribe(...) external`, plus `REACTIVE_IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad`.
> 3. `contracts/interfaces/ISystemContract.sol`: Inherits `IPayable` and `ISubscriptionService`.
> 4. `contracts/abstract/AbstractPayer.sol`: Implements `IPayable`, stores `IPayable internal vendor`, tracks `mapping(address => bool) senders`, provides `authorizedSenderOnly` modifier, `pay(uint256 amount)`, `coverDebt()`, and `addAuthorizedSender(address)` / `removeAuthorizedSender(address)`.
> 5. `contracts/abstract/AbstractCallback.sol`: Inherits `AbstractPayer`, stores `address internal rvm_id`, initializes `rvm_id = msg.sender` and `vendor = IPayable(_callback_sender)`, adds `_callback_sender` as authorized sender, and provides `rvmIdOnly(address _rvm_id)` modifier.
> 6. `contracts/abstract/AbstractReactive.sol`: Inherits `IReactive` and `AbstractPayer`, defines `uint256 internal constant REACTIVE_IGNORE`, `ISystemContract internal constant SERVICE_ADDR = ISystemContract(payable(0x0000000000000000000000000000000000fffFfF))`, `bool internal vm`, `detectVm()` examining `extcodesize(0x0000000000000000000000000000000000fffFfF) == 0`, and modifiers `rnkOnly` (`require(!vm)`) and `vmOnly` (`require(vm)`).
> 7. Verify all files compile cleanly and update `doc/TODO.md`.

---

## Phase 3: Uniswap V2 & PulseTrail Domain Interfaces
**Prompt:**
> Create the domain interfaces in `contracts/interfaces/`:
> 1. `contracts/interfaces/IUniswapV2Pair.sol`: Defines `token0()`, `token1()`, `getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)`, and `Sync(uint112 reserve0, uint112 reserve1)` event.
> 2. `contracts/interfaces/IUniswapV2Router02.sol`: Defines `factory()`, `WETH()`, `getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts)`, and `swapExactTokensForTokensSupportingFeeOnTransferTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external`.
> 3. `contracts/interfaces/IPulseTrailCallback.sol`: Defines `PositionStatus` enum (`Active`, `Completed`, `Cancelled`, `Failed`), `CallbackPosition` struct, `CreatePositionParams` struct, and rich events:
>    - `PositionRegistered(uint256 indexed positionId, address indexed owner, address indexed pair, address tokenIn, address tokenOut, bool isToken0, uint256 initialBalance, uint256 entryPrice, uint256 activationPrice, uint256 hardFloorPrice, uint16[3] baseTrailBps, uint16[3] exitPortionBps, uint16 volatilityMultiplierBps, uint16 maxWideningBps, uint16 maxSlippageBps)`
>    - `StageExitExecuted(uint256 indexed positionId, uint8 indexed stage, uint256 amountSold, uint256 proceedsReceived, uint256 remainingBalance)`
>    - `SwapFailed(uint256 indexed positionId, uint8 indexed stage, uint256 amountAttempted, string reason)`
>    - `PositionCancelled(uint256 indexed positionId, address indexed owner, uint256 amountReturned)`
>    - `LiquidityWarning(address indexed pair, uint256 positionShareBps, string message)`
> 4. `contracts/interfaces/IPulseTrailReactive.sol`: Defines `ReactivePosition` struct and rich telemetry events:
>    - `PositionTracked(uint256 indexed positionId, address indexed pair, uint256 entryPrice, uint256 activationPrice)`
>    - `ProfitActivated(uint256 indexed positionId, uint256 activationPrice, uint256 currentPrice, uint256 timestamp)`
>    - `HighWaterMarkUpdated(uint256 indexed positionId, uint8 stage, uint256 oldHwm, uint256 newHwm, uint256 effectiveTrailBps, uint256 currentStopPrice)`
>    - `VolatilityUpdated(uint256 indexed positionId, uint256 volatilityBps, uint16 effectiveTrailBps)`
>    - `StageTriggered(uint256 indexed positionId, uint8 indexed stageTriggered, uint256 triggerPrice, uint256 highWaterMark, uint256 amountToSell, uint256 minAmountOut)`
> 5. Verify compilation and update `doc/TODO.md`.

---

## Phase 4: `PulseTrailCallback.sol` — Vault, Pre-Flight Risk Shield & Position Registration
**Prompt:**
> Implement the first half of `contracts/PulseTrailCallback.sol` on Base Mainnet (`8453`):
> 1. Inherit `AbstractCallback` and `IPulseTrailCallback`, plus a lightweight `nonReentrant` guard and `onlyOwner` administration.
> 2. Implement `checkPoolLiquidity(address pair, address tokenIn, uint256 amountIn)` which queries `IUniswapV2Pair(pair).getReserves()`, identifies whether `tokenIn` is `token0` or `token1`, computes the current spot price scaled to `1e18`, and calculates `positionShareBps = (amountIn * 10000) / reserveIn`. Return `(bool isHealthy, uint256 positionShareBps, uint256 spotPrice1e18, uint256 reserveIn, uint256 reserveOut)` where `isHealthy = positionShareBps <= 500` (5% of pool).
> 3. Implement `estimateSellOutput(address tokenIn, address tokenOut, uint256 amountIn, uint16 maxSlippageBps)` using `try router.getAmountsOut(amountIn, path)` to assist the frontend/CLI with pre-flight dry runs.
> 4. Implement `createPosition(CreatePositionParams calldata params)`:
>    - Validate `exitPortionBps[0] + exitPortionBps[1] + exitPortionBps[2] == 10000`.
>    - Validate `baseTrailBps[i] >= 50 && baseTrailBps[i] <= 5000` (0.5% to 50%).
>    - Transfer `tokenIn` from `msg.sender` and measure `actualReceived = balanceAfter - balanceBefore` to support fee-on-transfer tokens accurately.
>    - Compute `entryPrice` from the pair's current reserves and `activationPrice = (entryPrice * (10000 + params.activationProfitBps)) / 10000`.
>    - If `positionShareBps > 500`, emit `LiquidityWarning`.
>    - Store `CallbackPosition` and emit `PositionRegistered(...)`.

---

## Phase 5: `PulseTrailCallback.sol` — Authenticated Swap Execution, Honeypot `try/catch` & Emergency Cancel
**Prompt:**
> Complete `contracts/PulseTrailCallback.sol` by implementing the cross-chain callback execution and user emergency controls:
> 1. Implement `executeStageExit(address rvm_id, uint256 positionId, uint8 stage, uint256 amountToSell, uint256 minAmountOut) external authorizedSenderOnly rvmIdOnly(rvm_id) nonReentrant`:
>    - Verify `pos.status == PositionStatus.Active`.
>    - Enforce replay protection: `require(stage > pos.currentStage && stage <= 4, "Invalid or duplicate stage")` (where `stage == 4` represents a Stage 0 Hard Floor emergency exit).
>    - Cap `actualSellAmount = amountToSell > pos.remainingBalance ? pos.remainingBalance : amountToSell`. If `stage == 3 || stage == 4`, set `actualSellAmount = pos.remainingBalance`.
>    - Approve `uniswapRouter` for `actualSellAmount`.
>    - Measure `quoteBalanceBefore = IERC20(pos.tokenOut).balanceOf(pos.owner)`.
>    - Execute inside `try uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(actualSellAmount, minAmountOut, path, pos.owner, block.timestamp + 300)`:
>      - On success: compute `proceeds = quoteBalanceAfter - quoteBalanceBefore`, deduct `actualSellAmount` from `pos.remainingBalance`, update `pos.currentStage = stage`, and if `pos.remainingBalance == 0 || stage == 3 || stage == 4`, set `pos.status = PositionStatus.Completed`. Emit `StageExitExecuted`.
>      - On `catch Error(string memory reason)` / `catch`: do **not** revert the callback transaction! Instead, update `pos.currentStage = stage`, set `pos.status = PositionStatus.Failed`, and emit `SwapFailed(positionId, stage, actualSellAmount, reason)`.
> 2. Implement `cancelPosition(uint256 positionId) external nonReentrant`:
>    - Verify `msg.sender == pos.owner` and `pos.status == PositionStatus.Active` or `PositionStatus.Failed`.
>    - Set `pos.status = PositionStatus.Cancelled`, zero out `pos.remainingBalance`, transfer remaining `tokenIn` back to `pos.owner`, and emit `PositionCancelled(positionId, pos.owner, amountReturned)`.
> 3. Add view helpers `getPosition(uint256 positionId)` and `getUserPositions(address user)`.

---

## Phase 6: `PulseTrailReactive.sol` — Subscriptions, State Storage & Event Routing
**Prompt:**
> Implement the structure, subscriptions, and event router of `contracts/PulseTrailReactive.sol` for **Reactive Mainnet (`1597`)**:
> 1. Inherit `AbstractReactive` and `IPulseTrailReactive`.
> 2. Define constants:
>    - `uint256 public constant ORIGIN_CHAIN_ID = 8453;` (Base Mainnet, or configurable via constructor for multi-chain support)
>    - `uint64 public constant CALLBACK_GAS_LIMIT = 350_000;`
>    - `uint256 public constant UNISWAP_V2_SYNC_TOPIC_0 = 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1;`
>    - `uint256 public constant POSITION_REGISTERED_TOPIC_0 = uint256(keccak256("PositionRegistered(uint256,address,address,address,address,bool,uint256,uint256,uint256,uint256,uint16[3],uint16[3],uint16,uint16,uint16)"));`
>    - `uint256 public constant POSITION_CANCELLED_TOPIC_0 = uint256(keccak256("PositionCancelled(uint256,address,uint256)"));`
> 3. In the constructor (`payable`), store `owner`, `originChainId`, and `callbackContract`. If `!vm`:
>    - Subscribe to `POSITION_REGISTERED_TOPIC_0` from `callbackContract` on `originChainId`.
>    - Subscribe to `POSITION_CANCELLED_TOPIC_0` from `callbackContract` on `originChainId`.
>    - Optionally subscribe to an initial Uniswap V2 `pair` if non-zero (`UNISWAP_V2_SYNC_TOPIC_0`).
> 4. Implement `subscribeToPair(address pair) external rnkOnly` so new Uniswap V2 pairs on Base Mainnet can be subscribed dynamically.
> 5. Implement `react(LogRecord calldata log) external vmOnly` routing:
>    - `log.topic_0 == POSITION_REGISTERED_TOPIC_0` $\rightarrow$ `_onPositionRegistered(log)`
>    - `log.topic_0 == POSITION_CANCELLED_TOPIC_0` $\rightarrow$ `_onPositionCancelled(log)`
>    - `log.topic_0 == UNISWAP_V2_SYNC_TOPIC_0` $\rightarrow$ `_onPoolSync(log)`

---

## Phase 7: `PulseTrailReactive.sol` — Rolling Volatility Engine & Adaptive Trail Math
**Prompt:**
> Implement the mathematical core in `contracts/PulseTrailReactive.sol`:
> 1. Implement `_decodeSyncPrice(bytes calldata data, bool isToken0) internal pure returns (uint256 price1e18)`:
>    - Decode `(uint112 reserve0, uint112 reserve1) = abi.decode(data, (uint112, uint112))`.
>    - Require `reserve0 > 0 && reserve1 > 0`.
>    - Return `isToken0 ? (uint256(reserve1) * 1e18) / uint256(reserve0) : (uint256(reserve0) * 1e18) / uint256(reserve1)`.
> 2. Implement `_updateVolatility(ReactivePosition storage pos, uint256 newPrice) internal returns (uint256 volatilityBps)`:
>    - Ignore micro-noise if `pos.bufferCount > 0` and the change from the last recorded price is `< 5 bps` (`0.05%`), returning `pos.currentVolatilityBps` to save gas.
>    - Write `newPrice` into `pos.priceBuffer[pos.bufferIndex]`, advance `pos.bufferIndex = (pos.bufferIndex + 1) % 8`, and increment `pos.bufferCount` up to `8`.
>    - If `pos.bufferCount < 2`, return `0`.
>    - Iterate through the active ring buffer in chronological order, summing `absDiff * 10000 / prevPrice`, and divide by `pos.bufferCount - 1`.
>    - Store and return `pos.currentVolatilityBps`.
> 3. Implement `_getEffectiveTrailBps(ReactivePosition storage pos, uint8 stage) internal view returns (uint16)`:
>    - Compute `uint256 addonBps = (pos.currentVolatilityBps * pos.volatilityMultiplierBps) / 10000`.
>    - Cap `if (addonBps > pos.maxWideningBps) addonBps = pos.maxWideningBps`.
>    - Compute `uint256 totalTrail = uint256(pos.baseTrailBps[stage - 1]) + addonBps`.
>    - Cap `if (totalTrail > 9000) totalTrail = 9000` (max 90% trail).
>    - Return `uint16(totalTrail)`.

---

## Phase 8: `PulseTrailReactive.sol` — Profit Activation, HWM Ratchet & Multi-Stage Callback Dispatch
**Prompt:**
> Complete `_evaluatePosition(uint256 positionId, uint256 currentPrice)` in `contracts/PulseTrailReactive.sol`:
> 1. Skip if `!pos.active || pos.remainingBalance == 0`.
> 2. Update rolling volatility via `_updateVolatility(pos, currentPrice)`.
> 3. **Hard Floor Circuit Breaker (Valid in Any Stage):**
>    - If `pos.hardFloorPrice > 0 && currentPrice <= pos.hardFloorPrice`:
>      - Set `uint256 sellAmt = pos.remainingBalance`, `pos.remainingBalance = 0`, `pos.currentStage = 4`, `pos.active = false`.
>      - Calculate `minOut` with `pos.maxSlippageBps` and emit `Callback` for stage `4` (100% emergency exit). Return.
> 4. **Stage 0 (Dormant — Waiting for Profit Activation):**
>    - If `pos.currentStage == 0`:
>      - Check `if (currentPrice >= pos.activationPrice)`:
>        - Set `pos.currentStage = 1`.
>        - Set `pos.highWaterMark = currentPrice`.
>        - Emit `ProfitActivated(positionId, pos.activationPrice, currentPrice, block.timestamp)`.
>      - Return (do not check pullback on the exact tick of activation).
> 5. **Stages 1, 2, and 3 (Active Trailing):**
>    - Compute `uint16 effTrailBps = _getEffectiveTrailBps(pos, pos.currentStage)`.
>    - **Ratchet High-Water Mark Upward:**
>      - If `currentPrice > pos.highWaterMark`:
>        - uint256 oldHwm = pos.highWaterMark;
>        - `pos.highWaterMark = currentPrice;`
>        - uint256 newStop = (currentPrice * (10000 - effTrailBps)) / 10000;
>        - Emit `HighWaterMarkUpdated(positionId, pos.currentStage, oldHwm, currentPrice, effTrailBps, newStop)`.
>        - Return.
>    - **Check Pullback Trigger:**
>      - Compute `uint256 stopPrice = (pos.highWaterMark * (10000 - effTrailBps)) / 10000`.
>      - If `currentPrice <= stopPrice`:
>        - `uint8 triggeredStage = pos.currentStage;`
>        - Compute `amountToSell`:
>          - For Stage 1 or 2: `uint256 portion = (pos.initialBalance * pos.exitPortionBps[triggeredStage - 1]) / 10000; amountToSell = portion > pos.remainingBalance ? pos.remainingBalance : portion;`
>          - For Stage 3: `amountToSell = pos.remainingBalance;`
>        - Compute `minAmountOut = (((amountToSell * currentPrice) / 1e18) * (10000 - pos.maxSlippageBps)) / 10000`.
>        - **Atomic State Update (Before Callback!):**
>          - `pos.remainingBalance -= amountToSell;`
>          - If `triggeredStage == 3 || pos.remainingBalance == 0`: `pos.currentStage = 4; pos.active = false;`
>          - Else: `pos.currentStage = triggeredStage + 1; pos.highWaterMark = currentPrice;` (resets HWM baseline for the next stage).
>        - Emit `StageTriggered(positionId, triggeredStage, currentPrice, pos.highWaterMark, amountToSell, minAmountOut)`.
>        - Encode payload `abi.encodeWithSignature("executeStageExit(address,uint256,uint8,uint256,uint256)", address(0), positionId, triggeredStage, amountToSell, minAmountOut)` and `emit Callback(originChainId, callbackContract, CALLBACK_GAS_LIMIT, payload)`.

---

## Phase 9: Mock Contracts for Comprehensive Local Simulation
**Prompt:**
> Build realistic mock contracts in `test/mocks/` to test every edge case thoroughly:
> 1. `test/mocks/MockERC20.sol`: Standard mintable ERC-20.
> 2. `test/mocks/MockFeeOnTransferERC20.sol`: ERC-20 with configurable `transferTaxBps` (e.g., 500 = 5% tax burned on every `transfer` / `transferFrom`).
> 3. `test/mocks/MockHoneypotERC20.sol`: ERC-20 with a `setHoneypotMode(bool)` toggle that reverts on `transfer` / `transferFrom` when selling to the pair/router.
> 4. `test/mocks/MockUniswapV2Pair.sol`: Implements `token0()`, `token1()`, `getReserves()`, `setReserves(uint112 r0, uint112 r1)` which emits `Sync(r0, r1)`.
> 5. `test/mocks/MockUniswapV2Router.sol`: Implements `getAmountsOut` and `swapExactTokensForTokensSupportingFeeOnTransferTokens` based on the pair's current reserve ratio, enforcing `amountOut >= amountOutMin` and transferring output tokens to `to`.

---

## Phase 10: Unit Test Suite — `PulseTrailCallback.t.sol`
**Prompt:**
> Create `test/PulseTrailCallback.t.sol` using Foundry (`forge-std/Test.sol`) to test `PulseTrailCallback.sol`:
> 1. Test position registration (`createPosition`) with standard ERC-20 and verify `PositionRegistered` event fields.
> 2. Test position registration with `MockFeeOnTransferERC20` (5% tax) and prove `initialBalance` and `remainingBalance` record the exact post-tax amount (`95 tokens` instead of `100`).
> 3. Test `checkPoolLiquidity` warning when position size exceeds 5% of pool reserves.
> 4. Test authenticated `executeStageExit` across Stage 1 (40%), Stage 2 (30%), and Stage 3 (30%) and verify user receives exact quote token proceeds.
> 5. Test security guards: revert when called by non-proxy address (`NotAuthorizedSender`) or with wrong `rvm_id` (`InvalidRvmId`), and revert on duplicate stage replay.
> 6. Test honeypot resilience: enable honeypot mode on `MockHoneypotERC20`, call `executeStageExit`, and verify the transaction **succeeds** (does not revert), emits `SwapFailed`, and sets status to `PositionStatus.Failed`.
> 7. Test user emergency withdrawal (`cancelPosition`) in both `Active` and `Failed` states.

---

## Phase 11: Unit & Fuzz Test Suite — `PulseTrailReactive.t.sol`
**Prompt:**
> Create `test/PulseTrailReactive.t.sol` to test `PulseTrailReactive.sol` in ReactVM mode:
> 1. Test hydration of `ReactivePosition` from a simulated `PositionRegistered` `LogRecord`.
> 2. Test Stage 0 dormancy: simulate price fluctuations below `activationPrice` (+15%) and verify no `Callback` is emitted and `currentStage` stays `0`.
> 3. Test Stage 0 Hard Floor trigger: simulate a sudden drop below `hardFloorPrice` and verify immediate Stage 4 emergency 100% exit `Callback`.
> 4. Test Profit Activation (`Stage 0 -> Stage 1`): simulate price crossing `+15%`, verify `ProfitActivated` event and `highWaterMark` initialization.
> 5. Test High-Water Mark ratcheting: simulate price rising from `1.15 -> 1.30 -> 1.50` and verify `highWaterMark` steps up and `Callback` is not emitted.
> 6. Test Rolling Volatility Adaptation: feed 8 choppy price ticks (`±10%` swings) vs. 8 calm price ticks (`±0.5%` swings) and prove `effectiveTrailBps` widens up to `baseTrailBps + maxWideningBps` during high volatility, preventing premature stop-out on a 9% dip when base trail is 8%.
> 7. Test Multi-Stage Partial Exits (`Stage 1 -> Stage 2 -> Stage 3 -> Completed`) and verify atomic stage advancement prevents double-triggers when two identical low-price `Sync` logs arrive back-to-back.
> 8. Add a fuzz test `testFuzz_PriceAndTrailMath(uint112 r0, uint112 r1, uint16 volMult)` verifying no arithmetic overflow or division-by-zero occurs across realistic reserve ranges.

---

## Phase 12: End-to-End Cross-Chain Loop Simulation & Gas Profiling (`PulseTrailEndToEnd.t.sol`)
**Prompt:**
> Create `test/PulseTrailEndToEnd.t.sol` that wires `PulseTrailCallback`, `PulseTrailReactive`, `MockUniswapV2Pair`, and `MockUniswapV2Router` together in a full cross-chain relay harness:
> 1. Simulate a trader buying 10,000 MEME tokens at `1.00 USDC` and registering a PulseTrail position (`+20%` activation, `[8%, 6%, 5%]` base trails, `[40%, 30%, 30%]` exits, `1.5x` volatility sensitivity, `200 bps` slippage, `0.80 USDC` hard floor).
> 2. Relay the `PositionRegistered` log to `PulseTrailReactive.react()`.
> 3. Simulate a memecoin rally on the pair (`$1.00 -> $1.10 -> $1.25 -> $1.60 -> $2.00`), relaying each `Sync` event to `PulseTrailReactive.react()`.
> 4. Simulate a pullback to `$1.80` (triggering Stage 1: 40% exit), capture the emitted `Callback` event payload, overwrite the first 32 bytes with `rvm_id` just as Reactive Mainnet does, and deliver it to `PulseTrailCallback.executeStageExit(...)`.
> 5. Simulate a second rally to `$2.50`, a pullback triggering Stage 2 (30% exit), and a final pullback triggering Stage 3 (remaining 30% exit).
> 6. Assert that `pos.status == PositionStatus.Completed`, `pos.remainingBalance == 0`, and the trader's USDC balance reflects all three profitable partial exits.
> 7. Run `forge test --gas-report` and verify `react()` gas usage is well within limits.

---

## Phase 13: Mainnet Deployment Scripts (`DeployBaseMainnet.s.sol` & `DeployReactiveMainnet.s.sol`)
**Prompt:**
> Create Foundry deployment scripts in `script/` for **Base Mainnet (`8453`)** and **Reactive Mainnet (`1597`)**:
> 1. `script/DeployBaseMainnet.s.sol`:
>    - Reads `DEPLOYER_PRIVATE_KEY`, `BASE_CALLBACK_PROXY` (`0x0D3E76De6bC44309083cAAFdB49A088B8a250947`), and `BASE_UNISWAP_V2_ROUTER` (`0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24`).
>    - Deploys `PulseTrailCallback` with value (e.g., `0.002 ETH` initial reserve for callback proxy fees) and calls `coverDebt()`.
>    - Optionally deploys a lightweight demo ERC-20 pair on Base Mainnet if `DEPLOY_DEMO_PAIR=true` so we can execute deterministic price movements on Base Mainnet for pennies in gas.
>    - Logs deployed addresses to `deployments/base-mainnet.json`.
> 2. `script/DeployReactiveMainnet.s.sol`:
>    - Reads `DEPLOYER_PRIVATE_KEY`, `BASE_MAINNET_CHAIN_ID` (`8453`), `PULSE_TRAIL_CALLBACK_ADDR`, and target `UNISWAP_PAIR_ADDR`.
>    - Deploys `PulseTrailReactive` to Reactive Mainnet (`1597`) with `REACT` value to fund subscriptions and callbacks.
>    - Logs deployed addresses to `deployments/reactive-mainnet.json`.

---

## Phase 14: Live Mainnet Full-Loop Execution Script (`scripts/run-mainnet-loop.js`)
**Prompt:**
> Create `scripts/run-mainnet-loop.js` using Ethers v6 to execute and record the verifiable on-chain loop on **Base Mainnet (`8453`)** and **Reactive Mainnet (`1597`)** (Judge Criterion 1: **Execution**):
> 1. Connect to `https://mainnet.base.org` and `https://mainnet-rpc.rnk.dev/`.
> 2. Check contract balances and debt status on both chains (`debt()` on Base Callback Proxy and Reactive `SERVICE_ADDR`).
> 3. Execute Step 1 on Base Mainnet: Approve tokens and call `createPosition(...)` on `PulseTrailCallback`. Record `originRegisterTxHash`.
> 4. Execute Step 2 on Base Mainnet: Trigger a price rise above `activationPrice` on the monitored pair (activating Stage 1 and ratcheting HWM), followed by a pullback breaching the Stage 1 trail. Record `originSyncTxHash`.
> 5. Poll Reactive Mainnet (`1597`) for the `Callback` event emitted by `PulseTrailReactive`. Record `reactiveTxHash` and block number.
> 6. Poll Base Mainnet (`8453`) for the `StageExitExecuted` event emitted by `PulseTrailCallback` (triggered by `0x0D3E76De6bC44309083cAAFdB49A088B8a250947`). Record `destinationCallbackTxHash`.
> 7. Save the complete proof artifact to `deployments/mainnet-loop-proof.json`.

---

## Phase 15: Cross-Chain Latency Benchmarking Script (`scripts/verify-latency.js`)
**Prompt:**
> Create `scripts/verify-latency.js` to benchmark and format the cross-chain execution latency between **Base Mainnet (`8453`)** and **Reactive Mainnet (`1597`)**:
> 1. Read transaction hashes from `deployments/mainnet-loop-proof.json` (or CLI arguments).
> 2. Query Base Mainnet RPC and Reactive Mainnet RPC for the transaction receipts and block timestamps:
>    - $T_0$: Origin `Sync` transaction timestamp & block number on Base Mainnet (`basescan.org/tx/...`).
>    - $T_1$: Reactive `react()` transaction timestamp & block number on Reactive Mainnet (`reactscan.net/tx/...`).
>    - $T_2$: Destination `executeStageExit()` callback transaction timestamp & block number on Base Mainnet (`basescan.org/tx/...`).
> 3. Compute:
>    - Detection & Reaction Latency: $\Delta T_{\text{react}} = T_1 - T_0$
>    - Callback Delivery Latency: $\Delta T_{\text{callback}} = T_2 - T_1$
>    - Total End-to-End Protection Loop: $\Delta T_{\text{total}} = T_2 - T_0$
> 4. Output a clean Markdown report (`doc/latency-benchmark.md`) with clickable explorer links ready for insertion into `README.md`.

---

## Phase 16: Interactive Trader & Judge CLI (`scripts/pulsetrail-cli.js`)
**Prompt:**
> Build an interactive/command-driven CLI tool `scripts/pulsetrail-cli.js` that allows judges and users to interact with PulseTrail from the terminal:
> - `node scripts/pulsetrail-cli.js status <positionId>`: Fetches live state from both `PulseTrailCallback` on Base Mainnet (`8453`) and `PulseTrailReactive` on Reactive Mainnet (`1597`), displaying current stage, Entry Price, Activation Price, High-Water Mark, Rolling Volatility (bps), Effective Adaptive Trail (bps), Stop Trigger Price, and Remaining Balance.
> - `node scripts/pulsetrail-cli.js precheck <pairAddress> <tokenIn> <amount>`: Runs the pre-flight liquidity depth check and router `getAmountsOut` simulation.
> - `node scripts/pulsetrail-cli.js create ...`: Approves and registers a new multi-stage trailing stop position on Base Mainnet.
> - `node scripts/pulsetrail-cli.js cancel <positionId>`: Executes instant emergency withdrawal on Base Mainnet.

---

## Phase 17: High-Frequency Web3 Telemetry Dashboard — Structure & Styling (`frontend/`)
**Prompt:**
> Read `doc/design-system.md`. Create `frontend/index.html` and `frontend/styles.css` implementing the "High-Frequency Telemetry Terminal" UI:
> 1. Dark obsidian aesthetic (`#07090E` canvas, `#0D111A` cards, `#00F0FF` cyan accents, `#7C3AED` Reactive purple, `#0052FF` Base blue) with `Inter` and `JetBrains Mono` (`tabular-nums`) typography.
> 2. **Dual-Chain Telemetry Header Bar:** Shows live connection status and block cadence for **Base Mainnet (`8453` • ~200ms)** and **Reactive Mainnet (`1597` • ~1.0s)**, gas reserve health indicators, and Wallet Connect button.
> 3. **Left Column (Strategy Builder & Pre-Flight Risk Shield):**
>    - Token & Pair input with automatic **Pre-Flight Security & Liquidity Shield** badges (Pool Reserve Depth %, Estimated Transfer Tax %, Honeypot Simulation Pass/Fail).
>    - Interactive sliders/inputs for Profit Activation (`+15%`), 3-Stage Base Trails (`8% / 6% / 5%`), 3-Stage Partial Exits (`40% / 30% / 30%`), Volatility Sensitivity Multiplier (`1.5x`), Max Slippage (`3%`), and Optional Hard Floor.
>    - Preset buttons: `"Blue-Chip Tight Trail"`, `"Memecoin Volatility Shield (Recommended)"`, and `"Moonbag Scaler"`.

---

## Phase 18: High-Frequency Web3 Telemetry Dashboard — Live Ratchet Chart & Cross-Chain Explorer (`frontend/app.js`)
**Prompt:**
> Implement `frontend/app.js` to power the Web3 dashboard with both **Live Base/Reactive Mainnet RPC Telemetry** and an **Interactive Judge Simulation Mode**:
> 1. **Real-Time Ratchet & Adaptive Trail Canvas Chart:**
>    - Plots Live Spot Price, Profit Activation Threshold (dashed emerald), High-Water Mark (stepped cyan ratchet line), and the Volatility-Adaptive Stop Band (amber/crimson shaded zone that widens when volatility spikes).
> 2. **4-Stage Ladder Progress Stepper:**
>    - Visually highlights whether the position is in `Stage 0 (Dormant)`, `Stage 1 (40% Exit)`, `Stage 2 (30% Exit)`, `Stage 3 (30% Closeout)`, or `Completed`, with live readout of `Base Trail + Volatility Addon = Effective Trail`.
> 3. **Interactive Market Scenario Simulator (For Instant Judge Testing):**
>    - Buttons to simulate `"Pump +25% (Activate Trail)"`, `"Volatility Spike (±12% Chop — Watch Trail Widen)"`, `"Pullback -11% (Trigger Stage 1 Callback)"`, `"Second Rally +60% (Ratchet HWM)"`, `"Flash Crash (Trigger Hard Floor)"`, and `"Honeypot Revert (Graceful Catch)"`.
> 4. **Live Mainnet Proof & Latency Table:**
>    - Displays deployed Base Mainnet (`8453`) and Reactive Mainnet (`1597`) contract addresses and clickable `basescan.org` / `reactscan.net` full-loop transaction hashes with end-to-end latency badges.

---

## Phase 19: Master `README.md` & Judge Verification Guide
**Prompt:**
> Write a comprehensive, judge-focused `README.md` in the project root designed to maximize scores across all 4 Reactive judging criteria (**Execution, Integration, Usefulness, Craft**):
> 1. **Header & Executive Summary:** Clear overview of PulseTrail, Track 1 (*Every Second Counts*) alignment, and key differentiators (Profit-Activated Trailing, Volatility-Adaptive Trail, Multi-Stage Partial Exits).
> 2. **Live Mainnet Deployment & Full-Loop Proof Table (Criterion 1 — Execution):**
>    - Table of deployed contract addresses on **Base Mainnet (`8453`)** and **Reactive Mainnet (`1597`)** with `basescan.org` and `reactscan.net` links.
>    - Step-by-step table of verified full-loop transaction hashes (Origin `PositionRegistered` & `Sync` on Base $\rightarrow$ Reactive `react()` & `Callback` emission on Reactive Mainnet $\rightarrow$ Destination `executeStageExit` swap via Callback Proxy `0x0D3E76De6bC44309083cAAFdB49A088B8a250947` on Base Mainnet) with exact block timestamps and latency deltas.
> 3. **Why Reactive Omni Speed (~1s / 200ms) & Stateful Integration Matter (Criterion 2 — Integration):**
>    - Detailed explanation and Mermaid diagrams of the on-chain rolling volatility buffer, HWM ratchet math, and atomic multi-stage state machine inside `PulseTrailReactive.sol`.
> 4. **Real-World Risk Mitigations & Threats Tackled (Criterion 3 — Usefulness):**
>    - Dedicated deep-dive covering Honeypot `try / catch` immunity, Fee-on-Transfer exact balance accounting, Price Gap slippage protection (`minAmountOut`), and Pool Liquidity pre-checks.
> 5. **Future Multi-VM Roadmap: Solana, Raydium & Cross-VM Expansion:**
>    - Explain how PulseTrail natively supports Base Mainnet (`8453`) & BNB Smart Chain (`56`) memecoins (plus bridged Solana memecoins on Base) today, and how Reactive Network's cross-VM expansion (via Hyperlane / SVM adapters) allows extending PulseTrail to native **Solana & Raydium** pools using only a lightweight SVM callback adapter—with **zero changes** to the core `PulseTrailReactive.sol` brain.
> 6. **Quickstart, Testing & Reproduction Guide (Criterion 4 — Craft):**
>    - Copy-pasteable commands to run `forge test -vvv`, launch the frontend terminal, run the CLI, and verify Mainnet transactions.

---

## Phase 20: Final QA Audit, Video Walkthrough Script & Submission Readiness Check
**Prompt:**
> Perform a complete final audit of the PulseTrail repository against the Reactive Omni Buildathon rubric:
> 1. Run the full Foundry test suite (`forge test -vvv`) and verify 100% pass rate with zero compiler warnings.
> 2. Verify all internal links across `README.md`, `plan.md`, and `doc/*.md`.
> 3. Create `doc/demo-video-script.md` containing a crisp, timed `< 3:00 minute` video walkthrough script and storyboard covering:
>    - `0:00–0:30`: The problem with static stops & custodial bots vs. PulseTrail's non-custodial Mainnet architecture.
>    - `0:30–1:15`: Live walkthrough of Pre-Flight Risk Shield (liquidity + honeypot check) and configuring Profit Activation, Volatility-Adaptive Trail, and 3-Stage Partial Exits.
>    - `1:15–2:15`: Live demonstration of the cross-chain loop across Base Mainnet (`basescan.org`) and Reactive Mainnet (`reactscan.net`), highlighting sub-second Base blocks + 1s Reactive blocks.
>    - `2:15–2:55`: Deep dive into `PulseTrailReactive.sol` (rolling volatility math) and `PulseTrailCallback.sol` (`try/catch` honeypot safety & emergency cancel).
> 4. Update `doc/TODO.md`, `doc/memory.md`, and `doc/handoff.md` to reflect 100% completion.

