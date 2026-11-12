import {useState} from 'react';
import {useAccount,useConfig,useReadContract,useWriteContract,usePublicClient} from 'wagmi';
import {waitForTransactionReceipt} from 'wagmi/actions';
import {parseUnits,formatUnits,getAddress,isAddress} from 'viem';
import {ADDR,BASE_ID,CALLBACK_ABI,ERC20_ABI,PAIR_ABI,PRESETS,PROTECT,TOKENS,LIMITS,WIGGLE,FACTORY_ADDR,FACTORY_ABI,QUOTE_TOKENS} from '../config/contracts.js';
import {Estimator} from './RatchetChart.jsx';
import RiskShield from './RiskShield.jsx';

const bps=f=>Math.round(f*10000);
function Icon({t}){return t.icon?<img src={t.icon} alt="" width="18" height="18" style={{borderRadius:'50%'}}/>:<s/>}

export default function StrategyBuilder({cfg,setCfg,go}){
 const {address,isConnected}=useAccount(),wc=useConfig(),publicClient=usePublicClient(),{writeContractAsync}=useWriteContract();

 const [customCA,setCustomCA]=useState('');
 const [customToken,setCustomToken]=useState(cfg.customToken||null);
 const [caLoading,setCaLoading]=useState(false);
 const [caErr,setCaErr]=useState('');
 const [manualPair,setManualPair]=useState('');
 const [showManualPair,setShowManualPair]=useState(false);
 const [pairSource,setPairSource]=useState('');

 const tok = (customToken && cfg.tok === customToken.symbol)
   ? customToken
   : (PROTECT.find(t=>t.symbol===cfg.tok) || PROTECT[0]);

 const isValidPair = !!tok?.pair && isAddress(tok.pair);
 const isValidTok = !!tok?.address && isAddress(tok.address);

 const bal=useReadContract({address:tok?.address,abi:ERC20_ABI,functionName:'balanceOf',args:[address],query:{enabled:!!address&&isValidTok}});
 const t0=useReadContract({address:tok?.pair,abi:PAIR_ABI,functionName:'token0',query:{enabled:isValidPair}});
 const t1=useReadContract({address:tok?.pair,abi:PAIR_ABI,functionName:'token1',query:{enabled:isValidPair}});
 const out=t0.data&&t1.data?(t0.data.toLowerCase()===tok?.address?.toLowerCase()?t1.data:t0.data):undefined;

 let amountIn=0n;
 try{amountIn=parseUnits(cfg.amount||'0',tok.decimals)}catch{}

 const [safe,setSafe]=useState(false),[pro,setPro]=useState(false),[st,setSt]=useState('idle'),[err,setErr]=useState('');
 const set=p=>setCfg({...cfg,...p});
 const pick=k=>set({preset:k,act:PRESETS[k].act,trails:PRESETS[k].trails});
 const frac=p=>bal.data!==undefined?set({amount:formatUnits(bal.data*BigInt(p)/100n,tok.decimals)}):null;

 const bad=!isConnected?'Connect your wallet first'
   :!isValidTok?'Enter a valid token address'
   :!isValidPair?'No compatible Uniswap V2 / AMM pair found. Enter pair address below.'
   :amountIn===0n?'Enter an amount'
   :bal.data!==undefined&&amountIn>bal.data?'Amount is more than your balance'
   :(t0.isLoading||t1.isLoading)?'Loading pool reserves…'
   :!out?'Could not read pool reserves from pair'
   :!safe?'Waiting for a passing safety check'
   :cfg.trails.some(t=>bps(t)<LIMITS.minTrailBps||bps(t)>LIMITS.maxTrailBps)?'Buffers must be 0.5% to 50%'
   :'';

 async function handleCaChange(rawVal){
  const val=rawVal.trim();
  setCustomCA(val);
  setCaErr('');
  setShowManualPair(false);
  setPairSource('');

  if(!val){
   setCustomToken(null);
   set({tok:PROTECT[0].symbol,amount:'',customToken:null});
   return;
  }

  if(!val.startsWith('0x')||val.length!==42){
   if(val.length>6) setCaErr('Address must start with 0x and be 42 characters');
   return;
  }

  let formattedCa;
  try{
   formattedCa=getAddress(val.toLowerCase());
  }catch{
   setCaErr('Invalid Base address format');
   return;
  }

  if(!publicClient){
   setCaErr('Web3 provider not ready');
   return;
  }

  setCaLoading(true);
  try{
   const caLower = formattedCa.toLowerCase();

   // 1. Quick check: Is this already a known token in our verified catalog?
   const known = TOKENS.find(t=>t.address.toLowerCase()===caLower);
   if(known && known.pair){
    const tObj={...known,isCustom:true};
    setCustomToken(tObj);
    setPairSource('Verified Catalog');
    set({tok:tObj.symbol,amount:'',customToken:tObj});
    return;
   }

   // 2. Smart check: Did the user paste a Pair/Pool address instead of a token CA?
   try{
    const [p0,p1]=await Promise.all([
     publicClient.readContract({address:formattedCa,abi:PAIR_ABI,functionName:'token0'}),
     publicClient.readContract({address:formattedCa,abi:PAIR_ABI,functionName:'token1'})
    ]);
    if(p0 && p1 && isAddress(p0) && isAddress(p1)){
     const p0Lower=p0.toLowerCase(), p1Lower=p1.toLowerCase();
     const isQuote0 = QUOTE_TOKENS.some(q=>q.address===p0Lower);
     const targetCa = isQuote0 ? p1 : p0;
     const [pSym,pName,pDec]=await Promise.all([
      publicClient.readContract({address:targetCa,abi:ERC20_ABI,functionName:'symbol'}).catch(()=>'POOL_TOKEN'),
      publicClient.readContract({address:targetCa,abi:ERC20_ABI,functionName:'name'}).catch(()=>'Pool Token'),
      publicClient.readContract({address:targetCa,abi:ERC20_ABI,functionName:'decimals'}).catch(()=>18)
     ]);
     const tObj={
      symbol:pSym,
      name:pName,
      address:targetCa.toLowerCase(),
      pair:caLower,
      decimals:Number(pDec||18),
      isCustom:true
     };
     setCustomToken(tObj);
     setPairSource('Pair Address Detected');
     set({tok:tObj.symbol,amount:'',customToken:tObj});
     return;
    }
   }catch{
    // Not a pair contract, proceed
   }

   // 3. Read Token Metadata (symbol, name, decimals)
   const [sym,name,dec]=await Promise.all([
    publicClient.readContract({address:formattedCa,abi:ERC20_ABI,functionName:'symbol'}).catch(()=>'CUSTOM'),
    publicClient.readContract({address:formattedCa,abi:ERC20_ABI,functionName:'name'}).catch(()=>'Custom Token'),
    publicClient.readContract({address:formattedCa,abi:ERC20_ABI,functionName:'decimals'}).catch(()=>18)
   ]);

   // 4. Multi-Quote Factory Check across WETH, USDC, cbBTC, DAI, VIRTUAL, DEGEN
   const zero='0x0000000000000000000000000000000000000000';
   const factoryChecks = await Promise.all(
    QUOTE_TOKENS.map(q=>
     publicClient.readContract({
      address: FACTORY_ADDR,
      abi: FACTORY_ABI,
      functionName: 'getPair',
      args: [formattedCa, q.address]
     }).catch(()=>zero)
    )
   );

   let detectedPair=null;
   let detectedQuote='';
   for(let i=0; i<QUOTE_TOKENS.length; i++){
    const res = factoryChecks[i];
    if(res && isAddress(res) && res.toLowerCase()!==zero){
     detectedPair = res.toLowerCase();
     detectedQuote = QUOTE_TOKENS[i].symbol;
     setPairSource(`Uniswap V2 (${detectedQuote} pool)`);
     break;
    }
   }

   // 5. DexScreener API Auto-Resolution (strictly filter for 42-char contract addresses that support token0)
   let hasV4PoolOnly = false;
   if(!detectedPair){
    try{
     const dsRes = await fetch(`https://api.dexscreener.com/latest/dex/tokens/${formattedCa}`).then(r=>r.json()).catch(()=>null);
     const basePairs = (dsRes?.pairs||[]).filter(p=>p.chainId==='base');
     
     // Detect if all pairs are 66-character Uniswap V4 pool IDs
     if(basePairs.length>0 && basePairs.every(p=>p.pairAddress && p.pairAddress.length>42)){
      hasV4PoolOnly = true;
     }

     const validPairs = basePairs.filter(p=>p.pairAddress && isAddress(p.pairAddress) && p.pairAddress.length===42);
     for(const p of validPairs){
      try{
       const p0 = await publicClient.readContract({
        address: p.pairAddress,
        abi: PAIR_ABI,
        functionName: 'token0'
       });
       if(p0){
        detectedPair = p.pairAddress.toLowerCase();
        detectedQuote = p.quoteToken?.symbol || 'QUOTE';
        setPairSource(`DexScreener: ${p.dexId||'Base'} (${detectedQuote} pool)`);
        break;
       }
      }catch{
       // Not a V2 pair, skip
      }
     }
    }catch{
     // Ignore
    }
   }

   const tObj={
    symbol:sym||'CUSTOM',
    name:name||'Custom Token',
    address:caLower,
    pair:detectedPair,
    decimals:Number(dec||18),
    isCustom:true
   };

   setCustomToken(tObj);
   set({tok:tObj.symbol,amount:'',customToken:tObj});

   if(!detectedPair){
    setShowManualPair(true);
    if(hasV4PoolOnly){
     setCaErr(`Notice: ${sym} trades primarily on Uniswap V4. PulseTrail protects standard Uniswap V2 and Aerodrome Basic AMMs on Base. If a V2 pair exists, paste its pair address below:`);
    }else{
     setCaErr('Custom pair detected: Enter or paste any pool address (Uniswap V2, Sushi, or Aerodrome Basic):');
    }
   }
  }catch(e){
   setCaErr('Failed to load token on Base: '+(e.shortMessage||e.message));
  }finally{
   setCaLoading(false);
  }
 }

 async function handleManualPairChange(rawPair){
  const p=rawPair.trim();
  setManualPair(p);
  if(p.length===42 && isAddress(p)){
   try{
    const fmt=getAddress(p.toLowerCase()).toLowerCase();
    if(publicClient){
     const [p0,p1]=await Promise.all([
      publicClient.readContract({address:fmt,abi:PAIR_ABI,functionName:'token0'}),
      publicClient.readContract({address:fmt,abi:PAIR_ABI,functionName:'token1'})
     ]);
     if(p0 && p1){
      if(customToken){
       const updated={...customToken,pair:fmt};
       setCustomToken(updated);
       setPairSource('Custom User Pool');
       set({customToken:updated});
       setCaErr('');
       return;
      }
     }
    }
   }catch{
    setCaErr('Address is not a valid liquidity pair with token0/token1');
   }
  }
 }

 function resetToPreset(symbol){
  set({tok:symbol,amount:'',customToken:null});
  setCustomCA('');
  setCustomToken(null);
  setCaErr('');
  setShowManualPair(false);
  setManualPair('');
  setPairSource('');
 }

 async function activate(){
  try{
   setErr('');
   setSt('approving');
   const h=await writeContractAsync({chainId:BASE_ID,address:tok.address,abi:ERC20_ABI,functionName:'approve',args:[ADDR.vault,amountIn]});
   await waitForTransactionReceipt(wc,{hash:h});
   setSt('creating');
   const h2=await writeContractAsync({
    chainId:BASE_ID,
    address:ADDR.vault,
    abi:CALLBACK_ABI,
    functionName:'createPosition',
    args:[{
     tokenIn:tok.address,
     tokenOut:out,
     pair:tok.pair,
     amountIn,
     activationProfitBps:bps(cfg.act),
     hardFloorPrice:0n,
     baseTrailBps:cfg.trails.map(bps),
     exitPortionBps:[4000,3000,3000],
     volatilityMultiplierBps:cfg.wiggle?WIGGLE.multBps:0,
     maxWideningBps:cfg.wiggle?WIGGLE.maxBps:0,
     maxSlippageBps:LIMITS.slippageBps
    }]
   });
   await waitForTransactionReceipt(wc,{hash:h2});
   setSt('idle');
   go('positions');
  }catch(e){
   setErr(e.shortMessage||e.message);
   setSt('idle');
  }
 }

 const label={idle:'Activate auto-protection',approving:'Approve in your wallet…',creating:'Creating protection…'}[st];

 return <div className="app">
  <div className="card">
   <div className="tabs" role="group" aria-label="Mode">
    <button aria-pressed={!pro} onClick={()=>setPro(false)}>Simple</button>
    <button aria-pressed={pro} onClick={()=>setPro(true)}>Pro</button>
   </div>

   <label className="l">1 · Token to protect</label>
   <div className="chips">
    {PROTECT.map(t=>(
     <button key={t.symbol} className="chip" aria-pressed={!customToken&&t.symbol===cfg.tok} onClick={()=>resetToPreset(t.symbol)}>
      <Icon t={t}/>{t.symbol}
     </button>
    ))}
    {customToken&&(
     <button className="chip" aria-pressed={true} onClick={()=>set({tok:customToken.symbol,amount:'',customToken})}>
      ✨ {customToken.symbol}
     </button>
    )}
   </div>

   {/* Custom CA / Pair Input Field */}
   <div style={{marginTop:12}}>
    <div style={{display:'flex',gap:8,alignItems:'center'}}>
     <input
      type="text"
      placeholder="Paste Base token CA or Pool address (0x...)"
      value={customCA}
      onChange={e=>handleCaChange(e.target.value)}
      className="mono small"
      style={{
       flex:1,
       padding:'10px 14px',
       border:'2px solid var(--ink)',
       borderRadius:12,
       background:'var(--bg)',
       color:'var(--ink)',
       fontSize:'13px'
      }}
     />
     {customCA&&(
      <button
       type="button"
       className="btn sm"
       onClick={()=>handleCaChange('')}
       style={{padding:'7px 12px',whiteSpace:'nowrap'}}
      >
       Clear
      </button>
     )}
    </div>

    {caLoading&&<p className="small mono" style={{margin:'6px 0 0',color:'var(--mut)'}}>🔍 Scanning Base AMM pairs &amp; DexScreener…</p>}

    {customToken&&!caLoading&&isValidPair&&(
     <div className="pill" style={{marginTop:8,background:'rgba(0, 245, 155, 0.15)',borderColor:'var(--grn)',display:'inline-flex',alignItems:'center',gap:6,flexWrap:'wrap'}}>
      <span className="dot"/> Protecting: <b>{customToken.name} ({customToken.symbol})</b> · Pool: {customToken.pair.slice(0,6)}…{customToken.pair.slice(-4)}
      {pairSource&&<span className="badge" style={{fontSize:'10px',lineHeight:'18px',padding:'0 6px'}}>{pairSource}</span>}
     </div>
    )}

    {caErr&&<p className="small err" style={{margin:'6px 0 0'}}>{caErr}</p>}

    {showManualPair&&(
     <div style={{marginTop:10,background:'var(--bg)',padding:12,borderRadius:10,border:'2px dashed var(--ink)'}}>
      <label className="small mono" style={{display:'block',marginBottom:4,fontWeight:700}}>
       Uniswap V2 / AMM Pair Address on Base:
      </label>
      <input
       type="text"
       placeholder="e.g. 0x1B2b40430FB0263c7BA25cf4B4FF9462c9153394"
       value={manualPair}
       onChange={e=>handleManualPairChange(e.target.value)}
       className="mono small"
       style={{
        width:'100%',
        padding:'8px 12px',
        border:'2px solid var(--ink)',
        borderRadius:8,
        background:'var(--card)',
        color:'var(--ink)'
       }}
      />
      <p className="small" style={{margin:'6px 0 0',color:'var(--mut)'}}>
       💡 <em>Tip:</em> For demo tokens, use <code>0x1B2b40430FB0263c7BA25cf4B4FF9462c9153394</code>. For DexScreener tokens, copy the <b>Pair</b> address.
      </p>
     </div>
    )}
   </div>

   <label className="l">Amount <span style={{float:'right'}}>Balance: {bal.data!==undefined?Number(formatUnits(bal.data,tok.decimals)).toLocaleString(undefined,{maximumFractionDigits:4}):'-'}</span></label>
   <input className="amt" inputMode="decimal" placeholder="0.0" value={cfg.amount} onChange={e=>set({amount:e.target.value.replace(/[^0-9.]/g,'')})}/>
   <div className="chips" style={{marginTop:8}}>
    {[25,50,100].map(p=><button key={p} className="chip" onClick={()=>frac(p)}>{p===100?'MAX':p+'%'}</button>)}
   </div>

   <label className="l">2 · Strategy</label>
   <div className="strat">
    {Object.entries(PRESETS).map(([k,p])=>(
     <button key={k} className="sc" aria-pressed={cfg.preset===k} onClick={()=>pick(k)}>
      <b>{p.name}</b>{p.blurb}
     </button>
    ))}
   </div>

   {pro&&<div>
    <label className="l">Start trailing after gain <span style={{float:'right'}}>+{Math.round(cfg.act*100)}%</span></label>
    <input type="range" min="0" max="50" value={Math.round(cfg.act*100)} style={{width:'100%'}} onChange={e=>set({preset:'custom',act:e.target.value/100})}/>
    <label className="l">Safety buffer (step 1) <span style={{float:'right'}}>{(cfg.trails[0]*100).toFixed(0)}% · steps 2 and 3 tighten</span></label>
    <input type="range" min="3" max="15" value={Math.round(cfg.trails[0]*100)} style={{width:'100%'}} onChange={e=>{const v=e.target.value/100;set({preset:'custom',trails:[v,+(v*.75).toFixed(4),+(v*.6).toFixed(4)]})}}/>
    <label className="l"><input type="checkbox" checked={cfg.wiggle} onChange={e=>set({wiggle:e.target.checked})}/> Smart wiggle room (adds up to +{WIGGLE.maxBps/100}% in wild swings)</label>
   </div>}

   <button className={'btn red big'+(st!=='idle'?' load':'')} disabled={!!bad||st!=='idle'} onClick={activate}>
    <span className="spin"/>{label}
   </button>
   {bad&&<p className="small mono" style={{textAlign:'center'}}>{bad}</p>}
   {err&&<p className="err">{err}</p>}
  </div>

  <div style={{display:'grid',gap:24}}>
   <RiskShield tok={tok} out={out} amountIn={amountIn} onSafe={setSafe}/>
   <Estimator cfg={cfg}/>
  </div>
 </div>;
}
