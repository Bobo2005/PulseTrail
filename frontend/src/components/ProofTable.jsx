import {ADDR, TXS, LOOP_BENCHMARK} from '../config/contracts.js';

const CHECKSUM = {
  vault: '0xCacFaA320D05Ab1b96CD48C8e8bafe4E4928fAde',
  callbackProxy: '0x0D3E76De6bC44309083cAAFdB49A088B8a250947',
  router: '0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24',
  demoPool: '0x1B2b40430FB0263c7BA25cf4B4FF9462c9153394',
  brain: '0x43613f719a59D8484ABDF416ecea590D397e1058'
};

const txExplorer = (net, hash) =>
  net === 'Reactive' ? `https://reactscan.net/tx/${hash}` : `https://basescan.org/tx/${hash}`;

const addrExplorer = (isReactive, addr) =>
  isReactive ? `https://reactscan.net/address/${addr}` : `https://basescan.org/address/${addr}`;

export default function ProofTable() {
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
                  <a
                    href={txExplorer(t.net, t.hash)}
                    target="_blank"
                    rel="noreferrer"
                    style={{ color: 'inherit', textDecoration: 'underline' }}
                  >
                    {t.hash.slice(0, 10)}…{t.hash.slice(-6)} ↗
                  </a>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h3 style={{ margin: '28px 0 12px' }}>
        Benchmarked Cross-Chain Protection Loop (T₀ → T₁ → T₂){' '}
        <span className="small" style={{ fontWeight: 'normal', color: 'var(--mut)' }}>
          (Measured 2.0s Latency Benchmark)
        </span>
      </h3>
      <div className="tw">
        <table>
          <thead>
            <tr>
              <th>Phase</th>
              <th>Network</th>
              <th>Action / Event</th>
              <th>Timestamp Offset</th>
              <th>Measured Latency</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {LOOP_BENCHMARK.map((b, idx) => (
              <tr key={idx}>
                <td>{b.step}</td>
                <td>{b.chain}</td>
                <td><code>{b.event}</code></td>
                <td className="mono small">{b.timing}</td>
                <td className="mono small" style={{ color: 'var(--accent-pulse, #00f59b)', fontWeight: 'bold' }}>
                  {b.latency}
                </td>
                <td className="small">{b.status}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="small" style={{ marginTop: '10px', color: 'var(--mut)' }}>
        ℹ️ <strong>Latency Proof Details:</strong> Detection &amp; reaction latency: 1.00s (Base ~200ms Flashblocks → ReactVM 1.0s blocks). Callback delivery latency: 1.00s. Total cross-chain protection loop: 2.00s. Recorded in <code>deployments/mainnet-loop-proof.json</code> and documented in <code>doc/latency-benchmark.md</code>.
      </p>
    </div>
  );
}
