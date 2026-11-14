import {useEffect, useMemo, useState} from 'react';
import {useAccount, useConfig, usePublicClient, useReadContract, useWriteContract} from 'wagmi';
import {waitForTransactionReceipt} from 'wagmi/actions';
import {createPublicClient, defineChain, formatUnits, http, parseAbi, parseAbiItem} from 'viem';
import {ADDR, BASE_ID, CALLBACK_ABI, ERC20_ABI, REACTIVE_ID, TOKENS} from '../config/contracts.js';
import LadderStepper from './LadderStepper.jsx';

const tk = a => TOKENS.find(t => t.address === a?.toLowerCase());
const fNum = (v, d, maxFrac = 4) => Number(formatUnits(v || 0n, d)).toLocaleString(undefined, {maximumFractionDigits: maxFrac});
const fmtPrice = (val1e18) => {
  const n = Number(formatUnits(val1e18 || 0n, 18));
  if (!Number.isFinite(n) || n === 0) return '0';
  if (n >= 1) return n.toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 4});
  return n.toPrecision(4);
};
const shortAddr = a => (a ? `${a.slice(0, 5)}…${a.slice(-4)}` : '—');
const STATUS = ['Protecting', 'All secured', 'Cancelled', 'Failed'];

const reactiveMainnet = defineChain({
  id: REACTIVE_ID,
  name: 'Reactive Mainnet',
  nativeCurrency: {name: 'REACT', symbol: 'REACT', decimals: 18},
  rpcUrls: {default: {http: ['https://mainnet-rpc.rnk.dev/']}}
});

const reactiveClient = createPublicClient({
  chain: reactiveMainnet,
  transport: http('https://mainnet-rpc.rnk.dev/')
});

const REACTIVE_ABI = parseAbi([
  'function getReactivePosition(uint256 positionId) external view returns ((uint256 positionId, address owner, address pair, bool isToken0, uint256 entryPrice, uint256 activationPrice, uint256 hardFloorPrice, uint256 highWaterMark, uint256 initialBalance, uint256 remainingBalance, uint16[3] baseTrailBps, uint16[3] exitPortionBps, uint16 volatilityMultiplierBps, uint16 maxWideningBps, uint16 maxSlippageBps, uint8 currentStage, bool active, uint256[8] priceBuffer, uint8 bufferIndex, uint8 bufferCount, uint256 currentVolatilityBps))',
  'function getEffectiveTrailAndStopPrice(uint256 positionId) external view returns (uint16 effectiveTrailBps, uint256 stopPrice)'
]);

const SYNC_EVENT = parseAbiItem('event Sync(uint112 reserve0, uint112 reserve1)');
const REGISTERED_EVENT = parseAbiItem('event PositionRegistered(uint256 indexed positionId, address indexed owner, address indexed pair, address tokenIn, address tokenOut, bool isToken0, uint256 initialBalance, uint256 entryPrice, uint256 activationPrice, uint256 hardFloorPrice, uint16[3] baseTrailBps, uint16[3] exitPortionBps, uint16 volatilityMultiplierBps, uint16 maxWideningBps, uint16 maxSlippageBps)');
const EXIT_EVENT = parseAbiItem('event StageExitExecuted(uint256 indexed positionId, uint8 indexed stage, uint256 amountSold, uint256 proceedsReceived, uint256 remainingBalance)');
const CANCELLED_EVENT = parseAbiItem('event PositionCancelled(uint256 indexed positionId, address indexed owner, uint256 refundedBalance)');

const FarcasterIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <path d="M18.24.24H5.76A5.76 5.76 0 0 0 0 6v12a5.76 5.76 0 0 0 5.76 5.76h12.48A5.76 5.76 0 0 0 24 18V6A5.76 5.76 0 0 0 18.24.24m.816 17.16h-2.136v-6.792c0-1.008-.432-1.584-1.392-1.584-.96 0-1.488.576-1.488 1.584v6.792h-2.136v-6.792c0-1.008-.432-1.584-1.392-1.584-.96 0-1.488.576-1.488 1.584v6.792H6.936V8.16h2.136v1.176c.48-.84 1.344-1.32 2.376-1.32 1.152 0 1.968.576 2.376 1.512.504-.936 1.416-1.512 2.544-1.512 1.632 0 2.688 1.056 2.688 2.856z"/>
  </svg>
);

const XIcon = () => (
  <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/>
  </svg>
);

export default function PositionDetailInspector({id, go}) {
  const posId = useMemo(() => {
    try { return BigInt(id); } catch { return null; }
  }, [id]);

  const {address} = useAccount();
  const wc = useConfig();
  const baseClient = usePublicClient({chainId: BASE_ID});
  const {writeContractAsync} = useWriteContract();

  const [copied, setCopied] = useState(false);
  const [cancelling, setCancelling] = useState(false);
  const [telemetry, setTelemetry] = useState([]);
  const [telemetryMeta, setTelemetryMeta] = useState({
    loading: true,
    hwm: null,
    volBps: 0,
    wiggleBps: 0,
    effTrailBps: null,
    spotPrice: null,
    exits: []
  });

  const posQuery = useReadContract({
    address: ADDR.vault,
    abi: CALLBACK_ABI,
    functionName: 'getPosition',
    args: posId !== null ? [posId] : undefined,
    chainId: BASE_ID,
    query: {enabled: posId !== null, refetchInterval: 10000}
  });

  const p = posQuery.data;
  const ti = tk(p?.tokenIn);
  const to = tk(p?.tokenOut);

  const symInQuery = useReadContract({
    address: p?.tokenIn,
    abi: ERC20_ABI,
    functionName: 'symbol',
    chainId: BASE_ID,
    query: {enabled: !!p?.tokenIn && !ti}
  });
  const decInQuery = useReadContract({
    address: p?.tokenIn,
    abi: ERC20_ABI,
    functionName: 'decimals',
    chainId: BASE_ID,
    query: {enabled: !!p?.tokenIn && !ti}
  });
  const symOutQuery = useReadContract({
    address: p?.tokenOut,
    abi: ERC20_ABI,
    functionName: 'symbol',
    chainId: BASE_ID,
    query: {enabled: !!p?.tokenOut && !to}
  });
  const decOutQuery = useReadContract({
    address: p?.tokenOut,
    abi: ERC20_ABI,
    functionName: 'decimals',
    chainId: BASE_ID,
    query: {enabled: !!p?.tokenOut && !to}
  });

  const poolQuery = useReadContract({
    address: ADDR.vault,
    abi: CALLBACK_ABI,
    functionName: 'checkPoolLiquidity',
    args: p ? [p.pair, p.tokenIn, p.initialBalance || 1n] : undefined,
    chainId: BASE_ID,
    query: {enabled: !!p?.pair && p?.pair !== '0x0000000000000000000000000000000000000000', refetchInterval: 10000}
  });

  // Fetch on-chain telemetry from Base Mainnet & Reactive Mainnet (1597)
  useEffect(() => {
    if (!p || !baseClient || posId === null) return;
    let cancelled = false;

    async function loadTelemetry() {
      const items = [];
      let rPos = null;
      let rTrail = null;

      // 1. Try reading live state from Reactive Mainnet (1597)
      try {
        const [rp, rt] = await Promise.all([
          reactiveClient.readContract({address: ADDR.brain, abi: REACTIVE_ABI, functionName: 'getReactivePosition', args: [posId]}),
          reactiveClient.readContract({address: ADDR.brain, abi: REACTIVE_ABI, functionName: 'getEffectiveTrailAndStopPrice', args: [posId]})
        ]);
        if (rp && rp.positionId > 0n) {
          rPos = rp;
          rTrail = rt;
        }
      } catch {
        // ReactVM state may only live inside private ReactVM context depending on node RPC
      }

      // 2. Fetch Base Mainnet logs around recent blocks (safe 10,000 block lookback for public Base RPC)
      let latestBlock = 0n;
      let syncLogs = [];
      let regLogs = [];
      let exitLogs = [];
      let cancelLogs = [];

      try {
        latestBlock = await baseClient.getBlockNumber();
        const ageSecs = BigInt(Math.max(0, Math.floor(Date.now() / 1000) - Number(p.createdAt || 0n)));
        // Base produces ~1 block per 2s (or Flashblocks); look back up to 45,000 blocks (~25h) capped cleanly
        const estBlocksAgo = ageSecs / 2n + 500n;
        const lookback = estBlocksAgo < 9500n ? estBlocksAgo : 9500n;
        const fromBlock = latestBlock > lookback ? latestBlock - lookback : 0n;

        const [sLogs, rLogs, eLogs, cLogs] = await Promise.all([
          baseClient.getLogs({address: p.pair, event: SYNC_EVENT, fromBlock, toBlock: latestBlock}).catch(() => []),
          baseClient.getLogs({address: ADDR.vault, event: REGISTERED_EVENT, args: {positionId: posId}, fromBlock, toBlock: latestBlock}).catch(() => []),
          baseClient.getLogs({address: ADDR.vault, event: EXIT_EVENT, args: {positionId: posId}, fromBlock, toBlock: latestBlock}).catch(() => []),
          baseClient.getLogs({address: ADDR.vault, event: CANCELLED_EVENT, args: {positionId: posId}, fromBlock, toBlock: latestBlock}).catch(() => [])
        ]);
        syncLogs = sLogs;
        regLogs = rLogs;
        exitLogs = eLogs;
        cancelLogs = cLogs;
      } catch {
        // Ignore RPC log query errors gracefully
      }

      if (cancelled) return;

      // Subscription / Registration card
      const regBlock = regLogs[0]?.blockNumber ? `#${regLogs[0].blockNumber.toString()}` : 'Base 8453';
      items.push({
        tag: `[Block ${regBlock}]`,
        tone: 'green',
        text: `Subscribed to Base Pair ${shortAddr(p.pair)} Sync(r0,r1)`
      });

      // Compute 8-tick rolling volatility & peak tracking from real Sync events
      const spotNow = poolQuery.data?.[2] || p.entryPrice;
      let maxSpot = p.entryPrice > spotNow ? p.entryPrice : spotNow;
      const prices1e18 = [];
      for (const lg of syncLogs) {
        const r0 = BigInt(lg.args.reserve0 || 0n);
        const r1 = BigInt(lg.args.reserve1 || 0n);
        if (r0 === 0n || r1 === 0n) continue;
        const px = p.isToken0 ? (r1 * 10n ** 18n) / r0 : (r0 * 10n ** 18n) / r1;
        prices1e18.push({px, block: lg.blockNumber});
        if (px > maxSpot) maxSpot = px;
      }

      // Compute circular 8-tick volatility (exact PulseTrailReactive.sol logic)
      const filtered = [];
      for (const pt of prices1e18) {
        if (filtered.length === 0) {
          filtered.push(pt);
        } else {
          const prev = filtered[filtered.length - 1].px;
          const diff = pt.px > prev ? pt.px - prev : prev - pt.px;
          const chBps = prev > 0n ? (diff * 10000n) / prev : 0n;
          if (chBps >= 5n) filtered.push(pt);
        }
      }
      const win = filtered.slice(-8);
      let volBps = 0;
      if (win.length >= 2) {
        let sumBps = 0n;
        for (let i = 1; i < win.length; i++) {
          const prev = win[i - 1].px;
          const curr = win[i].px;
          const absD = curr > prev ? curr - prev : prev - curr;
          if (prev > 0n) sumBps += (absD * 10000n) / prev;
        }
        volBps = Number(sumBps / BigInt(win.length - 1));
      }

      if (rPos && rPos.currentVolatilityBps > 0n) {
        volBps = Number(rPos.currentVolatilityBps);
      }

      const stageIdx = Math.min(Number(p.currentStage || 0), 2);
      const baseTrailBps = Number(p.baseTrailBps?.[stageIdx] || 800);
      const rawAddon = Math.floor((volBps * Number(p.volatilityMultiplierBps || 0)) / 10000);
      const wiggleBps = Math.min(rawAddon, Number(p.maxWideningBps || 0));
      const effTrailBps = rTrail && rTrail[0] > 0 ? Number(rTrail[0]) : Math.min(baseTrailBps + wiggleBps, 9000);
      const hwm = rPos && rPos.highWaterMark > 0n ? rPos.highWaterMark : (p.currentStage > 0 || maxSpot >= p.activationPrice ? maxSpot : p.entryPrice);

      const actPct = Math.round((Number(p.activationPrice * 10000n / (p.entryPrice || 1n)) / 10000 - 1) * 100);

      // Activation / Monitoring card
      if (p.currentStage >= 1 || p.status === 1 || maxSpot >= p.activationPrice) {
        items.push({
          tag: '[ProfitActivated]',
          tone: 'purple',
          text: `Spot ${fmtPrice(hwm)} >= Activation ${fmtPrice(p.activationPrice)} (+${actPct}%) -> Stage 0 -> 1`
        });
      } else {
        items.push({
          tag: `[Live Spot · ${syncLogs.length} Syncs]`,
          tone: 'purple',
          text: `Spot ${fmtPrice(spotNow)} monitoring below Activation ${fmtPrice(p.activationPrice)} (+${actPct}%)`
        });
      }

      // High-Water Mark card
      const hwmGainPct = p.entryPrice > 0n ? ((Number(hwm * 10000n / p.entryPrice) / 10000 - 1) * 100).toFixed(1) : '0.0';
      items.push({
        tag: '[High-Water Mark]',
        tone: 'amber',
        text: `Peak Ratcheted: ${fmtPrice(hwm)} (${Number(hwmGainPct) >= 0 ? '+' : ''}${hwmGainPct}% vs entry)`
      });

      // Rolling 8-Tick Volatility card
      items.push({
        tag: '[8-Tick Volatility]',
        tone: 'ink',
        text: `8-Tick Volatility sigma = ${volBps} bps -> Trail widened to ${(effTrailBps / 100).toFixed(1)}%`
      });

      // Stage Exit or Cancellation cards
      for (const ex of exitLogs) {
        items.push({
          tag: `[Stage ${ex.args.stage} Triggered]`,
          tone: 'red',
          text: `Callback(8453, 350k gas) -> Sold Stage ${ex.args.stage} tranche`
        });
      }
      if (p.status === 2 || cancelLogs.length > 0) {
        items.push({
          tag: '[PositionUntracked]',
          tone: 'red',
          text: 'Cancelled by owner on Base Mainnet · Escrowed tokens withdrawn'
        });
      } else if (p.status === 1) {
        items.push({
          tag: '[All Stages Complete]',
          tone: 'green',
          text: 'All 3 laddered tranches settled to owner wallet on Base (8453)'
        });
      } else if (p.currentStage > 0) {
        const stopPx = (hwm * BigInt(10000 - effTrailBps)) / 10000n;
        items.push({
          tag: `[Stage ${p.currentStage} Armed]`,
          tone: 'green',
          text: `Trailing Stop Trigger @ ${fmtPrice(stopPx)} (-${(effTrailBps / 100).toFixed(1)}% from peak)`
        });
      } else {
        items.push({
          tag: '[Stage 0 Dormant]',
          tone: 'ink',
          text: `Trailing armed on +${actPct}% · Base Trail ${(baseTrailBps / 100).toFixed(1)}% (+${(Number(p.maxWideningBps || 0) / 100).toFixed(1)}% max wiggle)`
        });
      }

      setTelemetry(items);
      setTelemetryMeta({
        loading: false,
        hwm,
        volBps,
        wiggleBps,
        effTrailBps,
        spotPrice: spotNow,
        exits: exitLogs
      });
    }

    loadTelemetry();
    const timer = setInterval(loadTelemetry, 12000);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [p, baseClient, posId, poolQuery.data]);

  async function handleCancel() {
    if (posId === null) return;
    setCancelling(true);
    try {
      const h = await writeContractAsync({
        chainId: BASE_ID,
        address: ADDR.vault,
        abi: CALLBACK_ABI,
        functionName: 'cancelPosition',
        args: [posId]
      });
      await waitForTransactionReceipt(wc, {hash: h});
      await posQuery.refetch();
    } finally {
      setCancelling(false);
    }
  }

  if (posId === null) {
    return (
      <div className="card empty">
        <h3>Invalid position ID</h3>
        <button className="btn" onClick={() => go('positions')}>Back to My positions</button>
      </div>
    );
  }

  if (posQuery.isLoading) {
    return (
      <div>
        <button type="button" className="inspect-back" onClick={() => go('positions')}>← Back to My positions</button>
        <div className="card empty">Loading Position #{id} from Base Mainnet…</div>
      </div>
    );
  }

  if (!p || p.owner === '0x0000000000000000000000000000000000000000') {
    return (
      <div>
        <button type="button" className="inspect-back" onClick={() => go('positions')}>← Back to My positions</button>
        <div className="card empty">
          <h3>Position #{id} not found</h3>
          <p className="small">No position with this ID exists on the Base Mainnet vault.</p>
        </div>
      </div>
    );
  }

  const symbolIn = ti?.symbol || symInQuery.data || shortAddr(p.tokenIn);
  const symbolOut = to?.symbol || symOutQuery.data || 'USDC';
  const di = ti?.decimals ?? decInQuery.data ?? 18;
  const dout = to?.decimals ?? decOutQuery.data ?? 18;

  const live = p.status === 0;
  const done = p.status === 1;
  const isOwner = address && p.owner.toLowerCase() === address.toLowerCase();
  const left = Number((p.remainingBalance * 100n) / (p.initialBalance || 1n));
  const profitPct = Math.round((Number((p.activationPrice * 10000n) / (p.entryPrice || 1n)) / 10000 - 1) * 100);

  const hwmVal = telemetryMeta.hwm || p.entryPrice;
  const hwmPct = p.entryPrice > 0n ? Math.round((Number((hwmVal * 10000n) / p.entryPrice) / 10000 - 1) * 100) : 0;

  const stageIdx = Math.min(Number(p.currentStage || 0), 2);
  const baseTrailPct = (Number(p.baseTrailBps?.[stageIdx] || 800) / 100).toFixed(1).replace(/\.0$/, '');
  const wigglePct = (telemetryMeta.wiggleBps / 100).toFixed(1).replace(/\.0$/, '');
  const effTrailPct = ((telemetryMeta.effTrailBps ?? Number(p.baseTrailBps?.[stageIdx] || 800)) / 100).toFixed(1).replace(/\.0$/, '');

  const shareText = `Just secured ${fNum(p.initialBalance, di)} $${symbolIn} with an autonomous volatility-adaptive trailing stop on @base powered by @0xReactive. 0 keys shared. #PulseTrail`;
  const warpcastUrl = `https://warpcast.com/~/compose?text=${encodeURIComponent(shareText)}`;
  const twitterUrl = `https://twitter.com/intent/tweet?text=${encodeURIComponent(shareText)}`;

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(shareText);
      setCopied(true);
      setTimeout(() => setCopied(false), 2200);
    } catch {
      // ignore
    }
  };

  return (
    <div className="inspect-page">
      <div className="inspect-topbar">
        <button type="button" className="inspect-back" onClick={() => go('positions')}>
          ← Back to My positions
        </button>
        <a
          className="pill mono"
          href={`https://basescan.org/address/${ADDR.vault}`}
          target="_blank"
          rel="noreferrer"
          style={{textDecoration: 'none'}}
        >
          Vault: {shortAddr(ADDR.vault)} ↗
        </a>
      </div>

      <div className="inspect-grid">
        {/* LEFT COLUMN: Position Overview & Controls */}
        <div className="card inspect-left">
          <div className="row" style={{alignItems: 'flex-start'}}>
            <div>
              <div style={{display: 'flex', alignItems: 'baseline', gap: 10}}>
                <b style={{fontSize: 'clamp(24px, 3vw, 30px)', lineHeight: 1.1}}>{symbolIn}</b>
                <span className="mono" style={{fontSize: 18, fontWeight: 700, color: 'var(--mut)'}}>#{String(posId)}</span>
              </div>
              <p className="small mono" style={{margin: '6px 0 0'}}>
                Protecting {fNum(p.initialBalance, di)} {symbolIn} · {left}% still held in vault
              </p>
            </div>
            <span className="pill">
              {live && <span className="dot"/>}
              {STATUS[p.status] || 'Unknown'}
            </span>
          </div>

          {/* Stats & Adaptive Trail Box */}
          <div className="inspect-stats-box">
            <div className="inspect-stats-row mono">
              <span>Entry: <b>{fmtPrice(p.entryPrice)}</b></span>
              <span style={{color: 'var(--pur)', fontWeight: 700}}>
                Activation: {fmtPrice(p.activationPrice)} (+{profitPct}%)
              </span>
              <span style={{color: 'var(--org)', fontWeight: 700}}>
                Peak: {fmtPrice(hwmVal)} ({hwmPct >= 0 ? '+' : ''}{hwmPct}%)
              </span>
            </div>
            <div className="mono" style={{fontSize: 12, color: 'var(--mut)', marginTop: 8}}>
              Adaptive Trail: {baseTrailPct}% + {wigglePct}% vol wiggle = <b>{effTrailPct}% effective buffer</b>
            </div>
          </div>

          {/* Banked Proceeds Banner */}
          <div className="inspect-proceeds-banner mono">
            <span>Banked Proceeds: <b>{fNum(p.totalProceeds, dout)} {symbolOut}</b></span>
            <span style={{opacity: 0.85, fontSize: 12}}> (sent directly to {shortAddr(p.owner)})</span>
          </div>

          {/* 4-Stage Stepper */}
          <div style={{marginTop: 14}}>
            <LadderStepper
              stage={p.currentStage}
              done={done}
              act={profitPct / 100}
              hwm={fmtPrice(hwmVal)}
            />
          </div>

          {/* Cancel Button */}
          {live && isOwner && (
            <div className="acts" style={{marginTop: 18}}>
              <button className="btn" onClick={handleCancel} disabled={cancelling}>
                {cancelling ? 'Withdrawing…' : 'Cancel and withdraw tokens'}
              </button>
            </div>
          )}

          {/* Share Shielded Position */}
          <div className="share-bar" style={{marginTop: 20}}>
            <div className="share-bar-title">
              <span>Share Shielded Position</span>
              <span style={{fontSize: 10, textTransform: 'none', opacity: 0.8}}>1-Click Viral</span>
            </div>
            <a href={warpcastUrl} target="_blank" rel="noreferrer" className="share-btn farcaster">
              <FarcasterIcon />
              <span>Farcaster</span>
            </a>
            <a href={twitterUrl} target="_blank" rel="noreferrer" className="share-btn twitter">
              <XIcon />
              <span>Twitter / X</span>
            </a>
            <button type="button" className={`share-btn copy ${copied ? 'copied' : ''}`} onClick={handleCopy}>
              {copied ? '✓ Copied!' : '📋 Copy'}
            </button>
            <div className="share-preview mono">
              &ldquo;{shareText}&rdquo;
            </div>
          </div>
        </div>

        {/* RIGHT COLUMN: Reactive Brain Telemetry (Chain 1597) */}
        <div className="card inspect-right">
          <h3 style={{margin: '0 0 10px', fontSize: 20, fontWeight: 800}}>
            Reactive Brain Telemetry (Chain 1597)
          </h3>
          <a
            href={`https://reactscan.net/address/${ADDR.brain}`}
            target="_blank"
            rel="noreferrer"
            className="telemetry-contract-pill mono"
          >
            Contract: {ADDR.brain}
          </a>

          <div className="telemetry-feed">
            {telemetryMeta.loading && telemetry.length === 0 ? (
              <div className="telemetry-item mono">
                <div className="telemetry-tag tone-purple">[Syncing ReactVM]</div>
                <div className="telemetry-msg">Querying Base (8453) &amp; Reactive (1597) logs…</div>
              </div>
            ) : (
              telemetry.map((item, idx) => (
                <div key={idx} className="telemetry-item mono">
                  <div className={`telemetry-tag tone-${item.tone}`}>{item.tag}</div>
                  <div className="telemetry-msg">{item.text}</div>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
