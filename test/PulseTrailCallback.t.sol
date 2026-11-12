// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { PulseTrailCallback } from "../contracts/PulseTrailCallback.sol";
import { IPulseTrailCallback } from "../contracts/interfaces/IPulseTrailCallback.sol";
import { AbstractPayer } from "../contracts/abstract/AbstractPayer.sol";
import { AbstractCallback } from "../contracts/abstract/AbstractCallback.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockFeeOnTransferERC20 } from "./mocks/MockFeeOnTransferERC20.sol";
import { MockHoneypotERC20 } from "./mocks/MockHoneypotERC20.sol";
import { MockUniswapV2Pair } from "./mocks/MockUniswapV2Pair.sol";
import { MockUniswapV2Router } from "./mocks/MockUniswapV2Router.sol";

/**
 * @title PulseTrailCallbackTest
 * @notice Comprehensive Foundry unit test suite for `PulseTrailCallback.sol` on Base Mainnet (`8453`).
 *         Covers registration, fee-on-transfer balance accounting, liquidity depth warnings,
 *         authenticated multi-stage exits, security guards, honeypot `try/catch` isolation,
 *         and user emergency withdrawals.
 */
contract PulseTrailCallbackTest is Test {
    address internal constant BASE_CALLBACK_PROXY = 0x0D3E76De6bC44309083cAAFdB49A088B8a250947;

    address internal deployer;
    address internal trader = address(0xBEEF);
    address internal attacker = address(0xBAD);

    MockERC20 internal memeToken;
    MockERC20 internal usdcToken;
    MockUniswapV2Pair internal pair;
    MockUniswapV2Router internal router;
    PulseTrailCallback internal callback;

    function setUp() public {
        deployer = address(this);

        // Deploy tokens & pool with 1,000,000 MEME and 1,000,000 USDC (1.00 USDC spot price)
        memeToken = new MockERC20("PulseMeme", "PMEME", 18);
        usdcToken = new MockERC20("USD Coin", "USDC", 18);

        pair = new MockUniswapV2Pair(
            address(memeToken),
            address(usdcToken),
            1_000_000 ether,
            1_000_000 ether
        );

        router = new MockUniswapV2Router(address(pair));

        // Deploy PulseTrailCallback with 1 ETH reserve for callback debt
        callback = new PulseTrailCallback{ value: 1 ether }(
            BASE_CALLBACK_PROXY,
            address(router)
        );

        // Fund trader with 200,000 MEME and router with 2,000,000 USDC
        memeToken.mint(trader, 200_000 ether);
        usdcToken.mint(address(router), 2_000_000 ether);
    }

    function _defaultParams(uint256 amountIn)
        internal
        view
        returns (IPulseTrailCallback.CreatePositionParams memory)
    {
        return
            IPulseTrailCallback.CreatePositionParams({
                tokenIn: address(memeToken),
                tokenOut: address(usdcToken),
                pair: address(pair),
                amountIn: amountIn,
                activationProfitBps: 1500, // +15%
                hardFloorPrice: 0.70e18,   // $0.70 hard floor
                baseTrailBps: [uint16(800), uint16(600), uint16(500)],
                exitPortionBps: [uint16(4000), uint16(3000), uint16(3000)],
                volatilityMultiplierBps: 15000, // 1.5x
                maxWideningBps: 1000,           // +10% max widening
                maxSlippageBps: 300             // 3% max slippage
            });
    }

    // -------------------------------------------------------------------------
    // 1. Standard ERC-20 Registration & Event Verification
    // -------------------------------------------------------------------------

    function test_CreatePosition_StandardERC20() public {
        uint256 amountIn = 10_000 ether; // 1% of pool (healthy)
        IPulseTrailCallback.CreatePositionParams memory params = _defaultParams(amountIn);

        vm.startPrank(trader);
        memeToken.approve(address(callback), amountIn);

        vm.expectEmit(true, true, true, true, address(callback));
        emit IPulseTrailCallback.PositionRegistered(
            1,
            trader,
            address(pair),
            address(memeToken),
            address(usdcToken),
            true,
            amountIn,
            1e18,
            1.15e18,
            0.70e18,
            params.baseTrailBps,
            params.exitPortionBps,
            params.volatilityMultiplierBps,
            params.maxWideningBps,
            params.maxSlippageBps
        );

        uint256 posId = callback.createPosition(params);
        vm.stopPrank();

        assertEq(posId, 1);

        IPulseTrailCallback.CallbackPosition memory pos = callback.getPosition(posId);
        assertEq(pos.owner, trader);
        assertEq(pos.initialBalance, amountIn);
        assertEq(pos.remainingBalance, amountIn);
        assertEq(pos.entryPrice, 1e18);
        assertEq(pos.activationPrice, 1.15e18);
        assertEq(uint256(pos.status), uint256(IPulseTrailCallback.PositionStatus.Active));
    }

    // -------------------------------------------------------------------------
    // 2. Fee-on-Transfer Token Registration (Exact Post-Tax Balance Accounting)
    // -------------------------------------------------------------------------

    function test_CreatePosition_FeeOnTransferToken() public {
        // Deploy a 5% transfer-tax token (500 bps)
        MockFeeOnTransferERC20 taxedToken = new MockFeeOnTransferERC20(
            "TaxedMeme",
            "TMEME",
            18,
            500
        );
        MockUniswapV2Pair taxedPair = new MockUniswapV2Pair(
            address(taxedToken),
            address(usdcToken),
            1_000_000 ether,
            1_000_000 ether
        );
        router.registerPair(address(taxedPair));

        uint256 depositAmount = 100 ether;
        taxedToken.mint(trader, depositAmount);

        IPulseTrailCallback.CreatePositionParams memory params = _defaultParams(depositAmount);
        params.tokenIn = address(taxedToken);
        params.pair = address(taxedPair);

        vm.startPrank(trader);
        taxedToken.approve(address(callback), depositAmount);
        uint256 posId = callback.createPosition(params);
        vm.stopPrank();

        IPulseTrailCallback.CallbackPosition memory pos = callback.getPosition(posId);
        // 5% tax burned on transfer -> exactly 95 tokens received and tracked
        assertEq(pos.initialBalance, 95 ether, "Should record 95 post-tax tokens");
        assertEq(pos.remainingBalance, 95 ether, "Remaining balance should equal 95 tokens");
    }

    // -------------------------------------------------------------------------
    // 3. Pre-Flight Liquidity Depth Check & Warning (> 5% of Pool Reserves)
    // -------------------------------------------------------------------------

    function test_CheckPoolLiquidity_AndWarningEmission() public {
        // 80,000 tokens out of 1,000,000 reserve = 800 bps (8% > 5% threshold)
        uint256 largeAmount = 80_000 ether;
        (bool isHealthy, uint256 shareBps, uint256 spotPrice, , ) = callback.checkPoolLiquidity(
            address(pair),
            address(memeToken),
            largeAmount
        );

        assertFalse(isHealthy, "8% of pool should be flagged unhealthy");
        assertEq(shareBps, 800);
        assertEq(spotPrice, 1e18);

        IPulseTrailCallback.CreatePositionParams memory params = _defaultParams(largeAmount);

        vm.startPrank(trader);
        memeToken.approve(address(callback), largeAmount);

        vm.expectEmit(true, false, false, true, address(callback));
        emit IPulseTrailCallback.LiquidityWarning(
            address(pair),
            800,
            "Position exceeds 5% of pool reserves; high price impact possible"
        );

        callback.createPosition(params);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // 4. Multi-Stage Exit Execution (Stage 1: 40%, Stage 2: 30%, Stage 3: 30%)
    // -------------------------------------------------------------------------

    function test_ExecuteStageExit_ThreeStagesFullLifecycle() public {
        uint256 amountIn = 10_000 ether;
        vm.startPrank(trader);
        memeToken.approve(address(callback), amountIn);
        uint256 posId = callback.createPosition(_defaultParams(amountIn));
        vm.stopPrank();

        // Simulate price appreciation to $1.50 USDC (1M MEME : 1.5M USDC)
        pair.setReserves(1_000_000 ether, 1_500_000 ether);

        // Stage 1: Sell 40% (4,000 MEME) at $1.50 -> 6,000 USDC
        vm.prank(BASE_CALLBACK_PROXY);
        callback.executeStageExit(deployer, posId, 1, 4_000 ether, 5_800 ether);

        IPulseTrailCallback.CallbackPosition memory posAfter1 = callback.getPosition(posId);
        assertEq(posAfter1.remainingBalance, 6_000 ether);
        assertEq(posAfter1.currentStage, 1);
        assertEq(posAfter1.totalProceeds, 6_000 ether);
        assertEq(uint256(posAfter1.status), uint256(IPulseTrailCallback.PositionStatus.Active));

        // Stage 2: Sell 30% (3,000 MEME) at $1.50 -> 4,500 USDC
        vm.prank(BASE_CALLBACK_PROXY);
        callback.executeStageExit(deployer, posId, 2, 3_000 ether, 4_300 ether);

        IPulseTrailCallback.CallbackPosition memory posAfter2 = callback.getPosition(posId);
        assertEq(posAfter2.remainingBalance, 3_000 ether);
        assertEq(posAfter2.currentStage, 2);
        assertEq(posAfter2.totalProceeds, 10_500 ether);
        assertEq(uint256(posAfter2.status), uint256(IPulseTrailCallback.PositionStatus.Active));

        // Stage 3: Sell remaining 30% (3,000 MEME) at $1.50 -> 4,500 USDC
        vm.prank(BASE_CALLBACK_PROXY);
        callback.executeStageExit(deployer, posId, 3, 3_000 ether, 4_300 ether);

        IPulseTrailCallback.CallbackPosition memory posAfter3 = callback.getPosition(posId);
        assertEq(posAfter3.remainingBalance, 0);
        assertEq(posAfter3.currentStage, 3);
        assertEq(posAfter3.totalProceeds, 15_000 ether);
        assertEq(uint256(posAfter3.status), uint256(IPulseTrailCallback.PositionStatus.Completed));
        assertEq(usdcToken.balanceOf(trader), 15_000 ether);
    }

    // -------------------------------------------------------------------------
    // 5. Security Guards: Proxy Auth, RVM ID Check & Replay Protection
    // -------------------------------------------------------------------------

    function test_SecurityGuards_RevertOnUnauthorizedOrReplay() public {
        uint256 amountIn = 10_000 ether;
        vm.startPrank(trader);
        memeToken.approve(address(callback), amountIn);
        uint256 posId = callback.createPosition(_defaultParams(amountIn));
        vm.stopPrank();

        // 5a. Revert when called by non-proxy address
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(AbstractPayer.NotAuthorizedSender.selector, attacker)
        );
        callback.executeStageExit(deployer, posId, 1, 4_000 ether, 3_800 ether);

        // 5b. Revert when called by proxy but with spoofed rvm_id
        vm.prank(BASE_CALLBACK_PROXY);
        vm.expectRevert(
            abi.encodeWithSelector(AbstractCallback.InvalidRvmId.selector, deployer, attacker)
        );
        callback.executeStageExit(attacker, posId, 1, 4_000 ether, 3_800 ether);

        // 5c. Execute Stage 1 validly, then verify duplicate Stage 1 replay reverts
        vm.prank(BASE_CALLBACK_PROXY);
        callback.executeStageExit(deployer, posId, 1, 4_000 ether, 3_800 ether);

        vm.prank(BASE_CALLBACK_PROXY);
        vm.expectRevert(
            abi.encodeWithSelector(
                PulseTrailCallback.InvalidOrDuplicateStage.selector,
                uint8(1),
                uint8(1)
            )
        );
        callback.executeStageExit(deployer, posId, 1, 4_000 ether, 3_800 ether);
    }

    // -------------------------------------------------------------------------
    // 6. Honeypot Resilience (`try/catch` Isolation & Graceful Failure)
    // -------------------------------------------------------------------------

    function test_HoneypotResilience_GracefulCatchAndRecovery() public {
        MockHoneypotERC20 honeypot = new MockHoneypotERC20("TrapToken", "TRAP", 18);
        MockUniswapV2Pair trapPair = new MockUniswapV2Pair(
            address(honeypot),
            address(usdcToken),
            1_000_000 ether,
            1_000_000 ether
        );
        router.registerPair(address(trapPair));

        uint256 amountIn = 5_000 ether;
        honeypot.mint(trader, amountIn);

        IPulseTrailCallback.CreatePositionParams memory params = _defaultParams(amountIn);
        params.tokenIn = address(honeypot);
        params.pair = address(trapPair);

        // Deposit succeeds while honeypotMode is false
        vm.startPrank(trader);
        honeypot.approve(address(callback), amountIn);
        uint256 posId = callback.createPosition(params);
        vm.stopPrank();

        // Malicious developer activates honeypot transfer block before callback lands
        honeypot.setHoneypotMode(true);

        // Callback execution MUST NOT revert; instead it emits SwapFailed and sets status to Failed
        vm.prank(BASE_CALLBACK_PROXY);
        vm.expectEmit(true, true, false, true, address(callback));
        emit IPulseTrailCallback.SwapFailed(
            posId,
            1,
            2_000 ether,
            "Honeypot: Token transfer blocked"
        );
        callback.executeStageExit(deployer, posId, 1, 2_000 ether, 1_900 ether);

        IPulseTrailCallback.CallbackPosition memory pos = callback.getPosition(posId);
        assertEq(uint256(pos.status), uint256(IPulseTrailCallback.PositionStatus.Failed));
        assertEq(pos.currentStage, 1);
        assertEq(pos.remainingBalance, amountIn);
    }

    // -------------------------------------------------------------------------
    // 7. User Emergency Withdrawal (`cancelPosition` in Active & Failed States)
    // -------------------------------------------------------------------------

    function test_CancelPosition_ActiveAndFailedStates() public {
        uint256 amountIn = 10_000 ether;
        uint256 balanceBefore = memeToken.balanceOf(trader);

        vm.startPrank(trader);
        memeToken.approve(address(callback), amountIn);
        uint256 posId = callback.createPosition(_defaultParams(amountIn));

        // Execute Stage 1 (40% = 4,000 sold, 6,000 remaining)
        vm.stopPrank();
        vm.prank(BASE_CALLBACK_PROXY);
        callback.executeStageExit(deployer, posId, 1, 4_000 ether, 3_800 ether);

        // Trader cancels remaining 6,000 tokens
        vm.prank(trader);
        callback.cancelPosition(posId);

        IPulseTrailCallback.CallbackPosition memory pos = callback.getPosition(posId);
        assertEq(uint256(pos.status), uint256(IPulseTrailCallback.PositionStatus.Cancelled));
        assertEq(pos.remainingBalance, 0);
        assertEq(memeToken.balanceOf(trader), balanceBefore - 4_000 ether);
    }
}

