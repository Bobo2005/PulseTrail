import {useEffect,useMemo,useState} from 'react';
import {PATH,simulate,estimate,DEMO_USD} from '../lib/sim.js';
import {FEES} from '../config/contracts.js';
import LadderStepper from './LadderStepper.jsx';
const W=560,H=290,LO=.8,HI=2.2,X=k=>10+k/79*540,Y=v=>H-14-(v-LO)/(HI-LO)*(H-34);
export default function RatchetChart({cfg,demoKey}){
 const [i,setI]=useState(0),[play,setPlay]=useState(false);
 useEffect(()=>{if(demoKey){setI(0);setPlay(true)}},[demoKey]);
 useEffect(()=>{if(!play)return;const t=setInterval(()=>setI(v=>{if(v>=79){setPlay(false);return v}return v+1}),110);return()=>clearInterval(t)},[play]);
 const r=useMemo(()=>simulate(i,cfg),[i,cfg]);
 const line=(v,c,l,d)=><g key={l}><line x1="10" x2="550" y1={Y(v)} y2={Y(v)} stroke={c} strokeWidth="2.5" strokeDasharray={d?'6 5':undefined}/><text x="14" y={Y(v)-5} fontSize="10" fontWeight="700" fill={c}>{l}</text></g>;
 const d=PATH.slice(0,i+1).map((p,k)=>(k?'L':'M')+X(k)+' '+Y(p)).join('');
 const last=r.sold[r.sold.length-1];
 return <div>
  <div className="row"><h3>Price vs. your protection</h3><span className="pill"><span className="dot"/>Pulse brain online</span></div>
  <svg id="chart" viewBox={`0 0 ${W} ${H}`} role="img" aria-label="Price with the stop price ratcheting upward" style={{width:'100%',display:'block',borderRadius:14,background:'var(--bg)',border:'2px solid var(--ink)'}}>
   {line(1,'#1fbf4b','Entry $1.00',1)}{line(1+cfg.act,'#6a3df0','Starts at +'+Math.round(cfg.act*100)+'%',1)}
   {r.stage>=1&&line(r.hwm,'#f59e0b','Peak $'+r.hwm.toFixed(2))}{r.stop&&line(r.stop,'#ef4444','Stop $'+r.stop.toFixed(2))}
   <path d={d} fill="none" stroke="currentColor" strokeWidth="4" strokeLinejoin="round" style={{color:'var(--ink)'}}/>
   {r.sold.map(s=><g key={s.stage}><circle cx={X(s.k)} cy={Y(s.p)} r="11" fill="#ef4444" stroke="#111" strokeWidth="3"/><text x={X(s.k)-4} y={Y(s.p)+4} fontSize="11" fontWeight="700" fill="#fff">{s.stage}</text></g>)}
   <circle cx={X(i)} cy={Y(r.price)} r="7" fill="#00f59b" stroke="#111" strokeWidth="3"/>
  </svg>
  <div className="ctrl"><button className="btn sm" onClick={()=>{if(i>=79)setI(0);setPlay(p=>!p)}}>{play?'Pause':'Play'}</button>
   <input type="range" min="0" max="79" value={i} onChange={e=>{setPlay(false);setI(+e.target.value)}} aria-label="Drag to move the price through time"/>
   <span className="mono small" style={{minWidth:64,textAlign:'right'}}>${r.price.toFixed(2)}</span></div>
  <div className="legend"><span><i style={{background:'#1fbf4b'}}/>Entry</span><span><i style={{background:'#6a3df0'}}/>Starts at</span><span><i style={{background:'#f59e0b'}}/>Peak</span><span><i style={{background:'#ef4444'}}/>Stop</span></div>
  {last&&<p className="mono" style={{fontWeight:700,margin:'10px 0 0'}}>Batch {last.stage} sold! +${Math.round(last.frac*DEMO_USD*last.p)} USDC secured</p>}
  <LadderStepper stage={r.stage} done={r.done} act={cfg.act} hwm={r.hwm}/>
 </div>;
}
export function Estimator({cfg}){
 const e=useMemo(()=>estimate(DEMO_USD,cfg),[cfg]);
 return <div className="card calc"><b>What you would get</b><div className="small">Per ${DEMO_USD} protected if price follows the demo path, after the {FEES.swapBps/100}% swap fee. No PulseTrail fee.</div>
  {e.rows.map(r=><div key={r.label}><span>{r.label}</span><span>${Math.round(r.usd)}</span></div>)}
  {e.rest>0&&<div><span>Still holding {Math.round(e.left*100)}%</span><span>${Math.round(e.rest)}</span></div>}
  <div className="tot"><span>Estimated total</span><span>~${Math.round(e.total).toLocaleString()} ({e.pct>=0?'+':''}{e.pct.toFixed(0)}%)</span></div></div>;
}
