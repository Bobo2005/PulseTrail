import {useEffect} from 'react';
import {useReadContract} from 'wagmi';
import {isAddress} from 'viem';
import {ADDR,CALLBACK_ABI,LIMITS} from '../config/contracts.js';

export default function RiskShield({tok,out,amountIn,onSafe}){
 const hasValidPair = !!tok?.pair && isAddress(tok.pair);
 const hasValidToken = !!tok?.address && isAddress(tok.address);
 const on = !!out && amountIn > 0n && hasValidPair && hasValidToken;

 const liq = useReadContract({
  address: ADDR.vault,
  abi: CALLBACK_ABI,
  functionName: 'checkPoolLiquidity',
  args: [tok?.pair, tok?.address, amountIn],
  query: { enabled: on }
 });

 const sell = useReadContract({
  address: ADDR.vault,
  abi: CALLBACK_ABI,
  functionName: 'estimateSellOutput',
  args: [tok?.address, out, amountIn, LIMITS.slippageBps],
  query: { enabled: on }
 });

 const canSell = sell.data?.[0], share = liq.data ? Number(liq.data[1]) : null, healthy = liq.data?.[0];
 const deep = share !== null && share < LIMITS.liquidityWarnBps;

 useEffect(() => {
  onSafe(!!canSell && !!healthy && deep);
 }, [canSell, healthy, deep, onSafe]);

 const rows = [
  [canSell, 'Honeypot shield: this token can be sold safely', 'Checking whether you can sell…'],
  [deep, 'Pool depth: your trade is ' + (share !== null ? (share / 100).toFixed(2) : '?') + '% of the pool', 'Checking pool depth…'],
  [healthy, 'Pool health: reserves are healthy', 'Checking pool reserves…']
 ];

 return <div className="card">
  <b>Safety check</b> <span className="small mono">{tok?.symbol}</span>
  {!hasValidPair ? (
   <p className="small" style={{color:'var(--mut)'}}>Waiting for a valid Uniswap V2 / AMM pool pair…</p>
  ) : amountIn === 0n ? (
   <p className="small">Enter an amount to run the check.</p>
  ) : null}
  <ul className="chk">
   {rows.map((r, n) => (
    <li key={n}>
     <span className="ok" style={{background: r[0] ? undefined : on ? '#ef4444' : 'var(--dot)', color: r[0] ? undefined : '#fff'}}>
      {r[0] ? '✓' : on && r[0] === false ? '!' : '·'}
     </span>
     {r[0] !== undefined || !on ? r[1] : r[2]}
    </li>
   ))}
  </ul>
  {share !== null && share >= LIMITS.liquidityWarnBps && (
   <p className="err">Warning: this order is over 5% of the pool and may move the price.</p>
  )}
 </div>;
}
