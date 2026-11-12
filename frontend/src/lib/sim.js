import {FEES,WIGGLE} from '../config/contracts.js';
// Mirrors the contract: stage 0 waits for activation, each stage trails its own HWM,
// and the HWM resets to the exit price after every stage.
const K=[[0,1],[10,1.08],[20,1.35],[45,2],[55,1.75],[65,1.55],[79,1.25]];
export const PATH=Array.from({length:80},(_,t)=>{for(let k=0;k<K.length-1;k++){if(t>=K[k][0]&&t<=K[k+1][0]){const f=(t-K[k][0])/(K[k+1][0]-K[k][0]);return K[k][1]+(K[k+1][1]-K[k][1])*f+0.03*Math.sin(t*1.7)}}});
export const PORTIONS=[.4,.3,.3],DEMO_USD=1000,FEE=FEES.swapBps/10000;
// mean absolute % change over the last 8 ticks, ignoring moves under 0.05%
function vol(i){let s=0,n=0;for(let k=Math.max(1,i-7);k<=i;k++){const c=Math.abs(PATH[k]/PATH[k-1]-1);if(c>=.0005){s+=c;n++}}return n?s/n:0}
const add=(wiggle,k)=>wiggle?Math.min(vol(k)*WIGGLE.multBps/10000,WIGGLE.maxBps/10000):0;
export function simulate(i,{act,trails,wiggle}){
 const entry=PATH[0];let stage=0,hwm=entry;const sold=[];
 for(let k=0;k<=i;k++){const p=PATH[k];
  if(stage===0){if(p>=entry*(1+act)){stage=1;hwm=p}continue}
  if(stage>3)continue;
  hwm=Math.max(hwm,p);
  if(p<=hwm*(1-(trails[stage-1]+add(wiggle,k)))){sold.push({k,p,stage,frac:PORTIONS[stage-1]});stage++;hwm=p}
 }
 const live=stage>=1&&stage<=3;
 return{stage,hwm,sold,price:PATH[i],entry,done:stage>3,stop:live?hwm*(1-(trails[stage-1]+add(wiggle,i))):null};
}
export function estimate(notional,cfg){
 const r=simulate(PATH.length-1,cfg);let usd=0,left=1;
 const rows=r.sold.map(s=>{const u=s.frac*notional*s.p*(1-FEE);usd+=u;left-=s.frac;return{label:'Step '+s.stage+' cash-out',usd:u}});
 const rest=left>.001?left*notional*PATH[PATH.length-1]:0;
 return{rows,left,rest,total:usd+rest,pct:((usd+rest)/notional-1)*100};
}
