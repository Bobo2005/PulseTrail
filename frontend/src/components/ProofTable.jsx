import {useState} from 'react';
import {ADDR, TXS, LOOP_BENCHMARK} from '../config/contracts.js';

const CHECKSUM = {
  vault: '0xCacFaA320D05Ab1b96CD48C8e8bafe4E4928fAde',
  callbackProxy: '0x0D3E76De6bC44309083cAAFdB49A088B8a250947',
  router: '0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24',
  demoPool: '0x1B2b40430FB0263c7BA25cf4B4FF9462c9153394',
  brain: '0x43613f719a59D8484ABDF416ecea590D397e1058'
};

const txExplorer = (net, hash) =>
  String(net).toLowerCase().includes('reactive') || net === 1597
    ? `https://reactscan.net/tx/${hash}`
    : `https://basescan.org/tx/${hash}`;

const addrExplorer = (isReactive, addr) =>
  isReactive ? `https://reactscan.net/address/${addr}` : `https://basescan.org/address/${addr}`;

function CopyButton({text}) {
  const [copied, setCopied] = useState(false);
  const handleCopy = async (e) => {
    e.stopPropagation();
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    } catch (err) {}
  };
  return (
    <button
      type="button"
      className="copy-mini-btn"
      onClick={handleCopy}
      title={`Copy hash: ${text}`}
      aria-label="Copy hash"
    >
      {copied ? '✓' : '📋'}
    </button>
  );
}

function LatencyReplayConsole({activeStep, countdown, isRunning, onPlay, onReset}) {
  const progressPct = Math.min(100, Math.max(0, ((2.0 - countdown) / 2.0) * 100));

  return (
    <div className="latency-replayer-box">
      <div className="replay-ctrl-row">
        <div>
          <b style={{fontSize: 16, display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap'}}>
            ⏱️ Visual Latency Countdown Simulator
            <span className="badge">TRACK 1: EVERY SECOND COUNTS</span>
          </b>
          <p className="small" style={{margin: '4px 0 0', color: 'var(--mut)'}}>
            Observe the autonomous cross-chain protection loop in action (T₀ → T₁ → T₂):
          </p>
        </div>
        <div style={{display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap'}}>
          <div className="countdown-clock">
            <span style={{fontSize: 12, opacity: 0.7}}>COUNTDOWN:</span>
            <span>{countdown.toFixed(2)}s</span>
          </div>
          <button
            type="button"
            className="btn sm red"
            onClick={onPlay}
            disabled={isRunning}
            style={{minHeight: 36}}
          >
            {isRunning ? 'Running Loop…' : '▶ Play 2.0s Replay'}
          </button>
          <button
            type="button"
            className="btn sm"
            onClick={onReset}
            disabled={isRunning}
            style={{minHeight: 36}}
          >
            Reset
          </button>
        </div>
      </div>

      <div className="replay-track">
        <div className="replay-fill" style={{width: `${progressPct}%`}}/>
      </div>

      <div className="replay-checkpoints">
        <span style={{color: activeStep >= 1 ? 'var(--ink)' : 'var(--mut)', fontWeight: activeStep === 1 ? '800' : 'normal'}}>
          🟢 T₀: Origin Dip (0.0s)
        </span>
        <span style={{color: activeStep >= 2 ? 'var(--ink)' : 'var(--mut)', fontWeight: activeStep === 2 ? '800' : 'normal'}}>
          ⚡ T₁: ReactVM Decision (+1.0s)
        </span>
        <span style={{color: activeStep >= 3 ? 'var(--ink)' : 'var(--mut)', fontWeight: activeStep === 3 ? '800' : 'normal'}}>
          🎯 T₂: Swap Executed (+2.0s)
        </span>
      </div>

      {activeStep === 3 && (
        <div style={{marginTop: 10, padding: '8px 12px', background: 'rgba(0, 245, 155, 0.15)', border: '2px solid var(--grn)', borderRadius: 8, fontSize: 13, fontWeight: 700}} className="mono">
          ✓ Loop Complete in 2.00s! 4,000 PTRAIL sold on Base for 5,280 dUSDC autonomously with 0 off-chain bots.
        </div>
      )}
    </div>
  );
}

export default function ProofTable() {
  const [activeStep, setActiveStep] = useState(0);
  const [countdown, setCountdown] = useState(2.00);
  const [isRunning, setIsRunning] = useState(false);

  const runReplay = () => {
    if (isRunning) return;
    setIsRunning(true);
    setActiveStep(1);
    setCountdown(2.00);

    const startTime = Date.now();
    const duration = 2000;

    const timer = setInterval(() => {
      const elapsed = Date.now() - startTime;
      const remaining = Math.max(0, (duration - elapsed) / 1000);
      setCountdown(remaining);

      if (elapsed < 1000) {
        setActiveStep(1);
      } else if (elapsed < 2000) {
        setActiveStep(2);
      } else {
        setActiveStep(3);
        setCountdown(0.00);
        setIsRunning(false);
        clearInterval(timer);
      }
    }, 40);
  };

  const resetReplay = () => {
    setIsRunning(false);
    setActiveStep(0);
    setCountdown(2.00);
  };

  const contracts = [
    { name: 'Vault and executor (Base)', addr: CHECKSUM.vault, isReactive: false },
    { name: 'Callback proxy (Base)', addr: CHECKSUM.callbackProxy, isReactive: false },
    { name: 'Uniswap V2 router (Base)', addr: CHECKSUM.router, isReactive: false },
    { name: 'Demo pool PTRAIL / dUSDC (Base)', addr: CHECKSUM.demoPool, isReactive: false },
    { name: 'Reactive brain (Reactive 1597)', addr: CHECKSUM.brain, isReactive: true }
  ];

  return (
    <div>
      <div className="g3">
        <div className="card">
          <b className="px">2.0s</b>
          <p className="small">Base to Reactive and back (1s each way)</p>
        </div>
        <div className="card">
          <b className="px">0.00%</b>
          <p className="small">PulseTrail fee. Only the 0.30% pool fee and gas apply.</p>
        </div>
        <div className="card">
          <b className="px">0 keys</b>
          <p className="small">Held by PulseTrail. Fully non-custodial.</p>
        </div>
      </div>

      <h3 style={{ margin: '28px 0 12px' }}>Contracts</h3>
      <div className="tw">
        <table>
          <tbody>
            {contracts.map(({ name, addr, isReactive }) => (
              <tr key={addr}>
                <td>{name}</td>
                <td className="mono small" style={{ wordBreak: 'break-all' }}>
                  <a
                    href={addrExplorer(isReactive, addr)}
                    target="_blank"
                    rel="noreferrer"
                    style={{ color: 'inherit', textDecoration: 'underline' }}
                  >
                    {addr} ↗
                  </a>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h3 style={{ margin: '28px 0 12px' }}>
        Live On-Chain Broadcast Transactions{' '}
        <span className="small" style={{ fontWeight: 'normal', color: 'var(--mut)' }}>
          (Confirmed on BaseScan &amp; ReactScan)
        </span>
      </h3>
      <div className="tw">
        <table>
          <thead>
            <tr>
              <th>Deployment / Action</th>
              <th>Network</th>
              <th>Action Details</th>
              <th>Block</th>
              <th>Transaction Hash</th>
            </tr>
          </thead>
          <tbody>
            {TXS.map((t) => (
              <tr key={t.hash}>
                <td>{t.n}</td>
                <td><span className="pill" style={{padding:'2px 8px', fontSize:11}}>{t.net}</span></td>
                <td>{t.act}</td>
                <td className="mono small">
                  <a
                    href={t.net === 'Reactive' ? `https://reactscan.net/blocks/${t.block}` : `https://basescan.org/block/${t.block}`}
                    target="_blank"
                    rel="noreferrer"
                    style={{textDecoration: 'underline'}}
                    title="View block on explorer"
                  >
                    #{t.block.toLocaleString()} ↗
                  </a>
                </td>
                <td className="mono small">
                  <div style={{display: 'flex', alignItems: 'center', gap: 6}}>
                    <a
                      href={txExplorer(t.net, t.hash)}
                      target="_blank"
                      rel="noreferrer"
                      className="tx-link"
                      title={`View transaction on ${t.net === 'Reactive' ? 'Reactscan' : 'BaseScan'}: ${t.hash}`}
                    >
                      {t.hash.slice(0, 10)}…{t.hash.slice(-6)} ↗
                    </a>
                    <CopyButton text={t.hash}/>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h3 style={{ margin: '32px 0 12px' }}>
        Benchmarked Cross-Chain Protection Loop (T₀ → T₁ → T₂){' '}
        <span className="small" style={{ fontWeight: 'normal', color: 'var(--mut)' }}>
          (Measured 2.0s Latency Benchmark)
        </span>
      </h3>

      <LatencyReplayConsole
        activeStep={activeStep}
        countdown={countdown}
        isRunning={isRunning}
        onPlay={runReplay}
        onReset={resetReplay}
      />

      <div className="tw">
        <table>
          <thead>
            <tr>
              <th>Phase &amp; Step</th>
              <th>Network</th>
              <th>Action / Event</th>
              <th>Explorer Transaction Hash</th>
              <th>Timestamp Offset</th>
              <th>Latency Countdown Badge</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {LOOP_BENCHMARK.map((b, idx) => {
              const isHighlighted = activeStep === idx;
              return (
                <tr key={idx} className={isHighlighted ? 'row-highlight' : ''}>
                  <td><b>{b.step}</b></td>
                  <td>
                    <span className="pill" style={{padding:'2px 8px', fontSize:11}}>
                      {b.chain}
                    </span>
                  </td>
                  <td><code>{b.event}</code></td>
                  <td className="mono small">
                    <div style={{display: 'flex', alignItems: 'center', gap: 6}}>
                      <a
                        href={txExplorer(b.chain, b.hash)}
                        target="_blank"
                        rel="noreferrer"
                        className="tx-link"
                        title={`View on ${b.chain.includes('Reactive') ? 'Reactscan' : 'BaseScan'}: ${b.hash}`}
                      >
                        {b.hash.slice(0, 10)}…{b.hash.slice(-6)} ↗
                      </a>
                      <CopyButton text={b.hash}/>
                    </div>
                    <div className="small mono" style={{opacity: 0.65, fontSize: 11, marginTop: 2}}>
                      Block #{b.block.toLocaleString()}
                    </div>
                  </td>
                  <td className="mono small">
                    <b>{b.timing}</b>
                  </td>
                  <td>
                    <div style={{display: 'flex', flexDirection: 'column', gap: 4}}>
                      <span className={`latency-countdown-badge ${idx === 0 ? 'baseline' : idx === 1 ? 't0' : idx === 2 ? 't1' : 't2'}`}>
                        <span className={`badge-beacon ${idx === 0 ? 'gray' : idx === 1 ? 'green' : idx === 2 ? 'amber' : 'purple'}`}/>
                        {b.countdown}
                      </span>
                      <span className="mono small" style={{color: 'var(--accent-pulse, #00f59b)', fontWeight: 'bold'}}>
                        {b.latency}
                      </span>
                    </div>
                  </td>
                  <td>
                    <span className="badge" style={{fontSize: 10, padding: '2px 8px'}}>
                      ✓ {b.status}
                    </span>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <p className="small" style={{ marginTop: '12px', color: 'var(--mut)' }}>
        ℹ️ <strong>Latency Proof Details:</strong> Detection &amp; reaction latency: 1.00s (Base ~200ms Flashblocks → ReactVM 1.0s blocks). Callback delivery latency: 1.00s. Total cross-chain protection loop: 2.00s. Recorded in <code>deployments/mainnet-loop-proof.json</code> and documented in <code>doc/latency-benchmark.md</code>.
      </p>
    </div>
  );
}



