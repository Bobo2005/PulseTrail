// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { PulseTrailReactive } from "../contracts/PulseTrailReactive.sol";
import { IPulseTrailReactive } from "../contracts/interfaces/IPulseTrailReactive.sol";
import { IReactive, LogRecord } from "../contracts/interfaces/IReactive.sol";

/**
 * @title PulseTrailReactiveTest
 * @notice Comprehensive Foundry unit & fuzz test suite for `PulseTrailReactive.sol` on Reactive Mainnet (`1597`).
 *         Tests ReactVM state hydration, Stage 0 dormancy, Hard Floor circuit breakers,
 *         Profit Activation, High-Water Mark ratcheting, Rolling 8-Tick Volatility adaptation,
 *         Multi-Stage Partial Exits (`40% -> 30% -> 30%`), and anti-double-trigger atomicity.
 */
contract PulseTrailReactiveTest is Test {
    uint256 internal constant BASE_CHAIN_ID = 8453;

    address internal callbackAddr = address(0xCA11BAC);
    address internal pairAddr = address(0xCAFE);
    address internal trader = address(0xBEEF);
    address internal memeToken = address(0x1111);
    address internal usdcToken = address(0x2222);

    PulseTrailReactive internal reactive;

    function setUp() public {
        // In local Foundry tests, 0x000...fffFfF has no bytecode so detectVm() sets vm = true (ReactVM mode)
        reactive = new PulseTrailReactive(BASE_CHAIN_ID, callbackAddr, pairAddr);
    }

    // -------------------------------------------------------------------------
    // Helpers for Building Simulated Base Mainnet LogRecords
    // -------------------------------------------------------------------------

    function _buildRegisterLog(
        uint256 posId,
        uint256 initialBalance,
        uint256 entryPrice,
        uint256 activationPrice,
        uint256 hardFloorPrice
    ) internal view returns (LogRecord memory) {
        uint16[3] memory baseTrails = [uint16(800), uint16(600), uint16(500)]; // 8%, 6%, 5%
        uint16[3] memory exitPortions = [uint16(4000), uint16(3000), uint16(3000)]; // 40%, 30%, 30%

        bytes memory data = abi.encode(
            memeToken,
            usdcToken,
            true, // isToken0
            initialBalance,
            entryPrice,
            activationPrice,
            hardFloorPrice,
            baseTrails,
            exitPortions,
            uint16(15000), // 1.5x volatility multiplier
            uint16(1000),  // +10% (1000 bps) max widening cap
            uint16(300)    // 3% max slippage
        );

        return
            LogRecord({
                chain_id: BASE_CHAIN_ID,
                _contract: callbackAddr,
                topic_0: reactive.POSITION_REGISTERED_TOPIC_0(),
                topic_1: posId,
                topic_2: uint256(uint160(trader)),
                topic_3: uint256(uint160(pairAddr)),
                data: data,
                block_number: block.number,
                op_code: 0,
                block_hash: 0,
                tx_hash: 0,
                log_index: 0
            });
    }

    function _buildSyncLog(uint256 price1e18) internal view returns (LogRecord memory) {
        // Reserve0 = 1,000,000e18, Reserve1 = price1e18 * 1,000,000
        uint112 reserve0 = uint112(1_000_000 ether);
        uint112 reserve1 = uint112((price1e18 * 1_000_000 ether) / 1e18);

        return
            LogRecord({
                chain_id: BASE_CHAIN_ID,
                _contract: pairAddr,
                topic_0: reactive.UNISWAP_V2_SYNC_TOPIC_0(),
                topic_1: 0,
                topic_2: 0,
                topic_3: 0,
                data: abi.encode(reserve0, reserve1),
                block_number: block.number,
                op_code: 0,
                block_hash: 0,
                tx_hash: 0,
                log_index: 0
            });
    }

    // -------------------------------------------------------------------------
    // 1. Hydration of ReactivePosition from Simulated PositionRegistered Log
    // -------------------------------------------------------------------------

    function test_HydratePositionFromLog() public {
        LogRecord memory regLog = _buildRegisterLog(
            1,
            10_000 ether,
            1.00e18,
            1.15e18,
            0.70e18
        );

        vm.expectEmit(true, true, false, true, address(reactive));
        emit IPulseTrailReactive.PositionTracked(1, pairAddr, 1.00e18, 1.15e18);

        reactive.react(regLog);

        IPulseTrailReactive.ReactivePosition memory pos = reactive.getReactivePosition(1);
        assertEq(pos.positionId, 1);
        assertEq(pos.owner, trader);
        assertEq(pos.pair, pairAddr);
        assertTrue(pos.isToken0);
        assertEq(pos.entryPrice, 1.00e18);
        assertEq(pos.activationPrice, 1.15e18);
        assertEq(pos.hardFloorPrice, 0.70e18);
        assertEq(pos.initialBalance, 10_000 ether);
        assertEq(pos.remainingBalance, 10_000 ether);
        assertEq(pos.currentStage, 0);
        assertTrue(pos.active);
    }

    // -------------------------------------------------------------------------
    // 2. Stage 0 Dormancy (Price Fluctuations Below +15% Activation Threshold)
    // -------------------------------------------------------------------------

    function test_Stage0Dormancy_NoPrematureCallback() public {
        reactive.react(_buildRegisterLog(1, 10_000 ether, 1.00e18, 1.15e18, 0.70e18));

        vm.recordLogs();
        // Fluctuate between $0.85 and $1.14 (never crossing $1.15 activation or $0.70 hard floor)
        reactive.react(_buildSyncLog(1.05e18));
        reactive.react(_buildSyncLog(0.92e18));
        reactive.react(_buildSyncLog(1.14e18));
        reactive.react(_buildSyncLog(0.85e18));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 callbackSig = keccak256("Callback(uint256,address,uint64,bytes)");
        for (uint256 i = 0; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != callbackSig, "Should not emit Callback in Stage 0");
        }

        IPulseTrailReactive.ReactivePosition memory pos = reactive.getReactivePosition(1);
        assertEq(pos.currentStage, 0);
        assertEq(pos.remainingBalance, 10_000 ether);
    }

    // -------------------------------------------------------------------------
    // 3. Stage 0 Hard Floor Emergency Exit Trigger (Stage 4 -> 100% Sell)
    // -------------------------------------------------------------------------

    function test_Stage0HardFloor_TriggersImmediateFullExit() public {
        reactive.react(_buildRegisterLog(1, 10_000 ether, 1.00e18, 1.15e18, 0.70e18));

        // Flash drop to $0.65 (below $0.70 hard floor)
        uint256 crashPrice = 0.65e18;
        uint256 expectedMinOut = (((10_000 ether * crashPrice) / 1e18) * (10_000 - 300)) / 10_000;

        bytes memory expectedPayload = abi.encodeWithSignature(
            "executeStageExit(address,uint256,uint8,uint256,uint256)",
            address(0),
            uint256(1),
            uint8(4),
            10_000 ether,
            expectedMinOut
        );

        vm.expectEmit(true, true, false, true, address(reactive));
        emit IReactive.Callback(BASE_CHAIN_ID, callbackAddr, 350_000, expectedPayload);

        reactive.react(_buildSyncLog(crashPrice));

        IPulseTrailReactive.ReactivePosition memory pos = reactive.getReactivePosition(1);
        assertEq(pos.currentStage, 4);
        assertEq(pos.remainingBalance, 0);
        assertFalse(pos.active);
    }

    // -------------------------------------------------------------------------
    // 4 & 5. Profit Activation (Stage 0 -> Stage 1) & High-Water Mark Ratchet
    // -------------------------------------------------------------------------

    function test_ProfitActivation_AndHighWaterMarkRatchet() public {
        reactive.react(_buildRegisterLog(1, 10_000 ether, 1.00e18, 1.15e18, 0.70e18));

        // Cross +15% threshold at $1.15
        vm.expectEmit(true, false, false, true, address(reactive));
        emit IPulseTrailReactive.ProfitActivated(1, 1.15e18, 1.15e18, block.timestamp);
        reactive.react(_buildSyncLog(1.15e18));

        IPulseTrailReactive.ReactivePosition memory pos = reactive.getReactivePosition(1);
        assertEq(pos.currentStage, 1);
        assertEq(pos.highWaterMark, 1.15e18);

        // Ratchet upward: $1.15 -> $1.30 -> $1.50
        reactive.react(_buildSyncLog(1.30e18));
        pos = reactive.getReactivePosition(1);
        assertEq(pos.highWaterMark, 1.30e18);

        reactive.react(_buildSyncLog(1.50e18));
        pos = reactive.getReactivePosition(1);
        assertEq(pos.highWaterMark, 1.50e18);
        assertEq(pos.currentStage, 1);
        assertEq(pos.remainingBalance, 10_000 ether);
    }

    // -------------------------------------------------------------------------
    // 6. Rolling Volatility Adaptation: Choppy vs. Calm Markets
    // -------------------------------------------------------------------------

    function test_RollingVolatilityAdaptation_WidensTrailToPreventShakeout() public {
        // Position 1: Calm market ticks (~0.5% steps)
        reactive.react(_buildRegisterLog(1, 10_000 ether, 1.00e18, 1.15e18, 0.50e18));
        uint256[8] memory calmTicks = [
            uint256(1.150e18),
            uint256(1.156e18),
            uint256(1.162e18),
            uint256(1.168e18),
            uint256(1.174e18),
            uint256(1.180e18),
            uint256(1.186e18),
            uint256(1.200e18)
        ];
        for (uint256 i = 0; i < 8; ++i) {
            reactive.react(_buildSyncLog(calmTicks[i]));
        }
        (uint16 calmEffTrailBps, ) = reactive.getEffectiveTrailAndStopPrice(1);

        // Position 2: Choppy memecoin market (~10%+ swings per tick)
        PulseTrailReactive choppyReactive = new PulseTrailReactive(
            BASE_CHAIN_ID,
            callbackAddr,
            pairAddr
        );
        choppyReactive.react(_buildRegisterLog(1, 10_000 ether, 1.00e18, 1.15e18, 0.50e18));
        uint256[8] memory choppyTicks = [
            uint256(1.20e18),
            uint256(1.35e18),
            uint256(1.22e18),
            uint256(1.40e18),
            uint256(1.26e18),
            uint256(1.45e18),
            uint256(1.31e18),
            uint256(1.50e18)
        ];
        for (uint256 i = 0; i < 8; ++i) {
            choppyReactive.react(_buildSyncLog(choppyTicks[i]));
        }
        (uint16 choppyEffTrailBps, ) = choppyReactive.getEffectiveTrailAndStopPrice(1);

        // Calm trail should stay close to 800 bps base, while choppy trail widens to cap (800 + 1000 = 1800 bps)
        assertLt(calmEffTrailBps, 950, "Calm market trail should remain tight");
        assertEq(choppyEffTrailBps, 1800, "Choppy market trail should widen to 1800 bps cap");

        // Now simulate a -9% pullback from $1.50 peak ($1.365):
        // Base trail is 8% ($1.38), so a fixed 8% trail would get stopped out at $1.365!
        // Because PulseTrail widened the trail to 18% ($1.23 stop), Position 2 is NOT stopped out!
        choppyReactive.react(_buildSyncLog(1.365e18));
        IPulseTrailReactive.ReactivePosition memory posAfterDip = choppyReactive
            .getReactivePosition(1);
        assertEq(posAfterDip.currentStage, 1, "Widened adaptive trail prevented premature stop-out");
        assertEq(posAfterDip.remainingBalance, 10_000 ether);
    }

    // -------------------------------------------------------------------------
    // 7. Multi-Stage Partial Exits (40% -> 30% -> 30%) & Anti-Double-Trigger
    // -------------------------------------------------------------------------

    function test_MultiStageExits_AndAntiDoubleTrigger() public {
        reactive.react(_buildRegisterLog(1, 10_000 ether, 1.00e18, 1.15e18, 0.50e18));

        // Activate at $1.20 and smoothly step to $1.50
        reactive.react(_buildSyncLog(1.20e18));
        reactive.react(_buildSyncLog(1.50e18));

        // Pullback to $1.20 (-20% from $1.50 peak) triggers Stage 1 (40% = 4,000 tokens)
        reactive.react(_buildSyncLog(1.20e18));
        IPulseTrailReactive.ReactivePosition memory pos = reactive.getReactivePosition(1);
        assertEq(pos.currentStage, 2, "Should advance atomically to Stage 2");
        assertEq(pos.remainingBalance, 6_000 ether, "40% should be deducted");
        assertEq(pos.highWaterMark, 1.20e18, "HWM should reset to $1.20 for Stage 2");

        // Anti-double-trigger proof: a second identical Sync log at $1.20 arrives 200ms later
        reactive.react(_buildSyncLog(1.20e18));
        pos = reactive.getReactivePosition(1);
        assertEq(pos.currentStage, 2, "Duplicate Sync tick must not double-trigger Stage 2");
        assertEq(pos.remainingBalance, 6_000 ether);

        // Rally to $1.80, then pullback to $1.40 (-22.2% from $1.80) triggers Stage 2 (30% = 3,000 tokens)
        reactive.react(_buildSyncLog(1.80e18));
        reactive.react(_buildSyncLog(1.40e18));
        pos = reactive.getReactivePosition(1);
        assertEq(pos.currentStage, 3, "Should advance to Stage 3");
        assertEq(pos.remainingBalance, 3_000 ether, "30% should be deducted");

        // Pullback to $1.10 triggers Stage 3 (final 30% = 3,000 tokens -> Closed)
        reactive.react(_buildSyncLog(1.10e18));
        pos = reactive.getReactivePosition(1);
        assertEq(pos.currentStage, 4, "Should transition to Stage 4 (Completed)");
        assertEq(pos.remainingBalance, 0);
        assertFalse(pos.active);
    }

    // -------------------------------------------------------------------------
    // 8. Fuzz Test: Spot Price Decoding & Adaptive Trail Math
    // -------------------------------------------------------------------------

    function testFuzz_PriceAndTrailMath(
        uint112 r0,
        uint112 r1,
        uint16 volMult
    ) public view {
        uint112 safeR0 = uint112(bound(uint256(r0), 1e6, type(uint112).max));
        uint112 safeR1 = uint112(bound(uint256(r1), 1e6, type(uint112).max));
        uint16 safeMult = uint16(bound(uint256(volMult), 100, 50_000));

        bytes memory syncData = abi.encode(safeR0, safeR1);
        uint256 priceToken0 = reactive.decodeSyncPrice(syncData, true);
        uint256 priceToken1 = reactive.decodeSyncPrice(syncData, false);

        assertEq(priceToken0, (uint256(safeR1) * 1e18) / uint256(safeR0));
        assertEq(priceToken1, (uint256(safeR0) * 1e18) / uint256(safeR1));

        uint16 effTrail = reactive.calculateEffectiveTrailBps(800, 1200, safeMult, 1500);
        assertGe(uint256(effTrail), 800);
        assertLe(uint256(effTrail), 2300);
    }
}

