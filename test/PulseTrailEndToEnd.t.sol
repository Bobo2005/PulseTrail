// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { PulseTrailCallback } from "../contracts/PulseTrailCallback.sol";
import { PulseTrailReactive } from "../contracts/PulseTrailReactive.sol";
import { IPulseTrailCallback } from "../contracts/interfaces/IPulseTrailCallback.sol";
import { IPulseTrailReactive } from "../contracts/interfaces/IPulseTrailReactive.sol";
import { IReactive, LogRecord } from "../contracts/interfaces/IReactive.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockUniswapV2Pair } from "./mocks/MockUniswapV2Pair.sol";
import { MockUniswapV2Router } from "./mocks/MockUniswapV2Router.sol";

/**
 * @title PulseTrailEndToEndTest
 * @notice Full cross-chain end-to-end simulation harness wiring `PulseTrailCallback` (Base Mainnet `8453`),
 *         `PulseTrailReactive` (Reactive Mainnet `1597`), `MockUniswapV2Pair`, and `MockUniswapV2Router`.
 *         Simulates event relay from Base -> Reactive and callback delivery from Reactive -> Base Callback Proxy.
 */
contract PulseTrailEndToEndTest is Test {
    uint256 internal constant BASE_CHAIN_ID = 8453;
    address internal constant BASE_CALLBACK_PROXY = 0x0D3E76De6bC44309083cAAFdB49A088B8a250947;

    bytes32 internal constant CALLBACK_EVENT_SIG =
        keccak256("Callback(uint256,address,uint64,bytes)");

    address internal rvmId;
    address internal trader = address(0xBEEF);

    MockERC20 internal memeToken;
    MockERC20 internal usdcToken;
    MockUniswapV2Pair internal pair;
    MockUniswapV2Router internal router;
    PulseTrailCallback internal callback;
    PulseTrailReactive internal reactive;

    function setUp() public {
        rvmId = address(this);

        // 1. Deploy tokens and Uniswap V2 pair on Base Mainnet (1M MEME : 1M USDC -> $1.00 initial price)
        memeToken = new MockERC20("PulseMeme", "PMEME", 18);
        usdcToken = new MockERC20("USD Coin", "USDC", 18);

        pair = new MockUniswapV2Pair(
            address(memeToken),
            address(usdcToken),
            1_000_000 ether,
            1_000_000 ether
        );

        router = new MockUniswapV2Router(address(pair));

        // 2. Deploy PulseTrailCallback on Base Mainnet (8453)
        callback = new PulseTrailCallback{ value: 1 ether }(
            BASE_CALLBACK_PROXY,
            address(router)
        );

        // 3. Deploy PulseTrailReactive on Reactive Mainnet (1597) in ReactVM mode
        reactive = new PulseTrailReactive(
            BASE_CHAIN_ID,
            address(callback),
            address(pair)
        );

        // 4. Fund trader with 10,000 MEME (worth $10,000 USDC at $1.00 entry) and router with USDC liquidity
        memeToken.mint(trader, 10_000 ether);
        usdcToken.mint(address(router), 5_000_000 ether);
    }

    // -------------------------------------------------------------------------
    // Cross-Chain Relay Helpers (Base -> Reactive & Reactive -> Base)
    // -------------------------------------------------------------------------

    /**
     * @notice Updates pair reserves on Base Mainnet to reflect `newPrice1e18`, captures the emitted
     *         `Sync` event, relays it to `PulseTrailReactive.react()`, and if `Callback` is emitted,
     *         overwrites the first 32 bytes of `payload` with `rvmId` and delivers it via `BASE_CALLBACK_PROXY`.
     */
    function _setPairPriceAndRelayLoop(uint256 newPrice1e18) internal returns (bool callbackTriggered) {
        uint112 r0 = uint112(1_000_000 ether);
        uint112 r1 = uint112((newPrice1e18 * 1_000_000 ether) / 1e18);

        // Update reserves on Base Mainnet
        pair.setReserves(r0, r1);

        // Build relayed LogRecord for Reactive Mainnet
        LogRecord memory syncLog = LogRecord({
            chain_id: BASE_CHAIN_ID,
            _contract: address(pair),
            topic_0: reactive.UNISWAP_V2_SYNC_TOPIC_0(),
            topic_1: 0,
            topic_2: 0,
            topic_3: 0,
            data: abi.encode(r0, r1),
            block_number: block.number,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });

        vm.recordLogs();
        uint256 gasBefore = gasleft();
        reactive.react(syncLog);
        uint256 gasUsed = gasBefore - gasleft();
        assertLt(gasUsed, 200_000, "react() gas consumption must stay lightweight");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == address(reactive) && logs[i].topics[0] == CALLBACK_EVENT_SIG) {
                address targetContract = address(uint160(uint256(logs[i].topics[2])));
                (, bytes memory payload) = abi.decode(logs[i].data, (uint64, bytes));

                // Reactive Network overwrites the first 32-byte argument (after 4-byte selector) with rvmId
                address injectedRvmId = rvmId;
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    mstore(add(payload, 36), injectedRvmId)
                }

                // Deliver callback on Base Mainnet from official Callback Proxy
                vm.prank(BASE_CALLBACK_PROXY);
                (bool success, ) = targetContract.call(payload);
                require(success, "Cross-chain callback execution failed");
                callbackTriggered = true;
            }
        }
    }

    // -------------------------------------------------------------------------
    // Full Cross-Chain Lifecycle Test (Base 8453 <-> Reactive 1597 <-> Base 8453)
    // -------------------------------------------------------------------------

    function test_EndToEnd_MultiStageTrailingStopLoop() public {
        // 1. Trader registers 10,000 MEME at $1.00 USDC (+20% activation, [8%, 6%, 5%] base trails,
        //    [40%, 30%, 30%] exits, 1.5x volatility multiplier, 200 bps max widening, 200 bps slippage, $0.80 hard floor)
        IPulseTrailCallback.CreatePositionParams memory params = IPulseTrailCallback
            .CreatePositionParams({
                tokenIn: address(memeToken),
                tokenOut: address(usdcToken),
                pair: address(pair),
                amountIn: 10_000 ether,
                activationProfitBps: 2000, // +20% -> $1.20 activation
                hardFloorPrice: 0.80e18,   // $0.80 hard floor
                baseTrailBps: [uint16(800), uint16(600), uint16(500)],
                exitPortionBps: [uint16(4000), uint16(3000), uint16(3000)],
                volatilityMultiplierBps: 15000, // 1.5x volatility sensitivity
                maxWideningBps: 200,            // +2% max widening (so Stage 1 effective trail = 10% at high vol)
                maxSlippageBps: 200             // 200 bps (2%) max slippage
            });

        vm.recordLogs();
        vm.startPrank(trader);
        memeToken.approve(address(callback), 10_000 ether);
        uint256 posId = callback.createPosition(params);
        vm.stopPrank();

        // 2. Relay PositionRegistered log from Base Mainnet to PulseTrailReactive.react()
        Vm.Log[] memory regLogs = vm.getRecordedLogs();
        bool relayedReg = false;
        for (uint256 i = 0; i < regLogs.length; ++i) {
            if (
                regLogs[i].emitter == address(callback) &&
                uint256(regLogs[i].topics[0]) == reactive.POSITION_REGISTERED_TOPIC_0()
            ) {
                LogRecord memory regRecord = LogRecord({
                    chain_id: BASE_CHAIN_ID,
                    _contract: address(callback),
                    topic_0: uint256(regLogs[i].topics[0]),
                    topic_1: uint256(regLogs[i].topics[1]),
                    topic_2: uint256(regLogs[i].topics[2]),
                    topic_3: uint256(regLogs[i].topics[3]),
                    data: regLogs[i].data,
                    block_number: block.number,
                    op_code: 0,
                    block_hash: 0,
                    tx_hash: 0,
                    log_index: i
                });
                reactive.react(regRecord);
                relayedReg = true;
            }
        }
        assertTrue(relayedReg, "PositionRegistered log must be relayed");

        // 3. Simulate Memecoin Rally: $1.00 -> $1.10 (Dormant) -> $1.25 (Activates Stage 1) -> $1.60 -> $2.00 (HWM Ratchet)
        assertFalse(_setPairPriceAndRelayLoop(1.10e18), "Stage 0 below $1.20 should not trigger");
        assertFalse(_setPairPriceAndRelayLoop(1.25e18), "Crossing $1.20 activates Stage 1 without selling");
        assertFalse(_setPairPriceAndRelayLoop(1.60e18), "Rally to $1.60 ratchets HWM");
        assertFalse(_setPairPriceAndRelayLoop(2.00e18), "Rally to $2.00 ratchets HWM");

        IPulseTrailReactive.ReactivePosition memory rPos = reactive.getReactivePosition(posId);
        assertEq(rPos.currentStage, 1);
        assertEq(rPos.highWaterMark, 2.00e18);

        // 4. Pullback to $1.80 (-10% from $2.00 HWM) triggers Stage 1 (40% = 4,000 MEME sold at $1.80 -> 7,200 USDC)
        assertTrue(_setPairPriceAndRelayLoop(1.80e18), "Pullback to $1.80 must trigger Stage 1 callback");

        IPulseTrailCallback.CallbackPosition memory cPosAfter1 = callback.getPosition(posId);
        assertEq(cPosAfter1.currentStage, 1);
        assertEq(cPosAfter1.remainingBalance, 6_000 ether);
        assertEq(usdcToken.balanceOf(trader), 7_200 ether);

        // 5. Second Rally to $2.50, then pullback to $2.25 triggers Stage 2 (30% = 3,000 MEME sold at $2.25 -> 6,750 USDC)
        assertFalse(_setPairPriceAndRelayLoop(2.50e18), "Rally to $2.50 ratchets Stage 2 HWM");
        assertTrue(_setPairPriceAndRelayLoop(2.25e18), "Pullback to $2.25 must trigger Stage 2 callback");

        IPulseTrailCallback.CallbackPosition memory cPosAfter2 = callback.getPosition(posId);
        assertEq(cPosAfter2.currentStage, 2);
        assertEq(cPosAfter2.remainingBalance, 3_000 ether);
        assertEq(usdcToken.balanceOf(trader), 13_950 ether);

        // 6. Final Pullback to $2.00 triggers Stage 3 (remaining 30% = 3,000 MEME sold at $2.00 -> 6,000 USDC)
        assertTrue(_setPairPriceAndRelayLoop(2.00e18), "Pullback to $2.00 must trigger Stage 3 closeout");

        IPulseTrailCallback.CallbackPosition memory cPosFinal = callback.getPosition(posId);
        assertEq(uint256(cPosFinal.status), uint256(IPulseTrailCallback.PositionStatus.Completed));
        assertEq(cPosFinal.remainingBalance, 0);
        assertEq(cPosFinal.currentStage, 3);
        assertEq(cPosFinal.totalProceeds, 19_950 ether);
        assertEq(usdcToken.balanceOf(trader), 19_950 ether);

        rPos = reactive.getReactivePosition(posId);
        assertFalse(rPos.active);
        assertEq(rPos.remainingBalance, 0);
        assertEq(rPos.currentStage, 4);
    }
}

