import {useState} from 'react';
import {useAccount,useConfig,useReadContract,useReadContracts,useWriteContract} from 'wagmi';
import {waitForTransactionReceipt} from 'wagmi/actions';
import {formatUnits} from 'viem';
import {ConnectButton} from '@rainbow-me/rainbowkit';
import {ADDR,BASE_ID,CALLBACK_ABI,ERC20_ABI,TOKENS} from '../config/contracts.js';
import LadderStepper from './LadderStepper.jsx';

const tk=a=>TOKENS.find(t=>t.address===a.toLowerCase());
const f=(v,d)=>Number(formatUnits(v,d)).toLocaleString(undefined,{maximumFractionDigits:4});
const STATUS=['Protecting','All secured','Cancelled','Failed'];

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

function ShareShieldedPosition({shareText}) {
  const [copied, setCopied] = useState(false);

  const warpcastUrl = `https://warpcast.com/~/compose?text=${encodeURIComponent(shareText)}`;
  const twitterUrl = `https://twitter.com/intent/tweet?text=${encodeURIComponent(shareText)}`;

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(shareText);
      setCopied(true);
      setTimeout(() => setCopied(false), 2200);
    } catch (e) {
      // fallback
    }
  };

  return (
    <div className="share-bar">
      <div className="share-bar-title">
        <span>Share Shielded Position</span>
        <span style={{ fontSize: 10, textTransform: 'none', opacity: 0.8 }}>1-Click Viral</span>
      </div>
      <a
        href={warpcastUrl}
        target="_blank"
        rel="noreferrer"
        className="share-btn farcaster"
        title="Share on Farcaster (Warpcast)"
        onClick={e => e.stopPropagation()}
      >
        <FarcasterIcon />
        <span>Farcaster</span>
      </a>
      <a
        href={twitterUrl}
        target="_blank"
        rel="noreferrer"
        className="share-btn twitter"
        title="Share on Twitter / X"
        onClick={e => e.stopPropagation()}
      >
        <XIcon />
        <span>Twitter / X</span>
      </a>
      <button
        type="button"
        className={`share-btn copy ${copied ? 'copied' : ''}`}
        onClick={e => { e.stopPropagation(); handleCopy(); }}
        title="Copy proof text to clipboard"
      >
        {copied ? '✓ Copied!' : '📋 Copy'}
      </button>
    </div>
  );
}

function PositionCard({id, p, onCancel, onInspect}) {
  const ti = tk(p.tokenIn);
  const to = tk(p.tokenOut);

  // Fetch token symbol & decimals dynamically for custom tokens not in predefined catalog
  const symQuery = useReadContract({
    address: p.tokenIn,
    abi: ERC20_ABI,
    functionName: 'symbol',
    chainId: BASE_ID,
    query: { enabled: !ti && !!p.tokenIn }
  });
  const decQuery = useReadContract({
    address: p.tokenIn,
    abi: ERC20_ABI,
    functionName: 'decimals',
    chainId: BASE_ID,
    query: { enabled: !ti && !!p.tokenIn }
  });

  const symbolIn = ti?.symbol || symQuery.data || (p.tokenIn ? `${p.tokenIn.slice(0, 6)}…${p.tokenIn.slice(-4)}` : 'Token');
  const di = ti?.decimals ?? decQuery.data ?? 18;
  const dout = to?.decimals ?? 18;
  const live = p.status === 0;
  const left = Number(p.remainingBalance * 100n / (p.initialBalance || 1n));
  const profitPct = Math.round((Number(p.activationPrice * 10000n / (p.entryPrice || 1n)) / 10000 - 1) * 100);

  const shareText = `🛡️ Just secured ${f(p.initialBalance, di)} $${symbolIn} with an autonomous volatility-adaptive trailing stop on @base powered by @reactive_net. Non-custodial, 0 private keys shared. #PulseTrail #ReactiveOmni`;

  return (
    <div
      className="card pos-card-clickable"
      role="button"
      tabIndex={0}
      onClick={() => onInspect(id)}
      onKeyDown={e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onInspect(id); } }}
      title="Click to inspect live Reactive Brain telemetry"
    >
      <div className="row">
        <b style={{fontSize: 22, display: 'flex', alignItems: 'center', gap: 6}}>
          {symbolIn} <span style={{opacity: 0.6}}>#{String(id)}</span>
        </b>
        <span className="pill">{live && <span className="dot"/>}{STATUS[p.status] || 'Unknown'}</span>
      </div>
      <p className="small mono">
        Protecting {f(p.initialBalance, di)} · {left}% still held
      </p>
      <div className="row pos-stats-row mono" style={{fontSize: 13, marginTop: 4}}>
        <span>Entry: <b>{Number(formatUnits(p.entryPrice, 18)).toPrecision(4)}</b></span>
        <span>Target: <b>{Number(formatUnits(p.activationPrice, 18)).toPrecision(4)}</b> (+{profitPct}%)</span>
      </div>
      <div className="row" style={{margin: '8px 0'}}>
        <p className="mono" style={{fontWeight: 700, margin: 0}}>
          Banked: {f(p.totalProceeds, dout)} {to?.symbol || 'WETH'}
        </p>
        <span className="pos-inspect-link mono">Inspect telemetry →</span>
      </div>
      <LadderStepper stage={p.currentStage} done={p.status === 1} act={profitPct / 100}/>
      {live && (
        <div className="acts" style={{marginTop: 12}}>
          <button className="btn sm" onClick={e => { e.stopPropagation(); onCancel(id); }}>Cancel and withdraw tokens</button>
        </div>
      )}
      <ShareShieldedPosition shareText={shareText}/>
    </div>
  );
}

export default function PositionInspector({go}){
  const {address,isConnected}=useAccount(),wc=useConfig(),{writeContractAsync}=useWriteContract();
  const ids=useReadContract({address:ADDR.vault,abi:CALLBACK_ABI,functionName:'getUserPositions',args:[address],query:{enabled:!!address,refetchInterval:10000}});
  const list=useReadContracts({contracts:(ids.data||[]).map(id=>({address:ADDR.vault,abi:CALLBACK_ABI,functionName:'getPosition',args:[id]})),query:{enabled:!!ids.data?.length,refetchInterval:10000}});

  async function cancel(id){
    const h=await writeContractAsync({chainId:BASE_ID,address:ADDR.vault,abi:CALLBACK_ABI,functionName:'cancelPosition',args:[id]});
    await waitForTransactionReceipt(wc,{hash:h});
    ids.refetch();
    list.refetch();
  }

  if(!isConnected)return <div className="card empty"><h3>Connect your wallet to see your protections</h3><ConnectButton/></div>;
  if(ids.isLoading)return <div className="card empty">Loading your positions…</div>;
  if(!ids.data?.length)return <div className="card empty"><h3>No protections yet</h3><p className="small">Protect your first token in under a minute.</p><button className="btn red" onClick={()=>go('app')}>Protect my tokens</button></div>;

  return (
    <div className="g3" style={{gridTemplateColumns:'repeat(auto-fill,minmax(min(100%, 340px),1fr))'}}>
      {ids.data.map((id,n)=>{
        const p=list.data?.[n]?.result;
        if(!p)return <div key={id} className="card">Loading #{String(id)}…</div>;
        return <PositionCard key={id} id={id} p={p} onCancel={cancel} onInspect={pid => go('inspect/' + String(pid))}/>;
      })}
    </div>
  );
}
