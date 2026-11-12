import {useEffect,useState} from 'react';
import Header from './components/Header.jsx';
import Footer from './components/Footer.jsx';
import RatchetChart from './components/RatchetChart.jsx';
import StrategyBuilder from './components/StrategyBuilder.jsx';
import PositionInspector from './components/PositionInspector.jsx';
import ProofTable from './components/ProofTable.jsx';
import {PRESETS} from './config/contracts.js';
import homeHtml from './content/home.html?raw';
import docsHtml from './content/docs.html?raw';

const R=['home','app','positions','proof','docs'];
const cur=()=>{const h=location.hash.slice(1);return R.includes(h)?h:'home'};

export default function App({theme, onToggleTheme}){
 const [route,setRoute]=useState(cur()),[demo,setDemo]=useState(0);
 const [cfg,setCfg]=useState({tok:'PTRAIL',amount:'',preset:'rocket',act:PRESETS.rocket.act,trails:PRESETS.rocket.trails,wiggle:false});

 useEffect(()=>{
  const f=()=>{setRoute(cur());window.scrollTo(0,0)};
  addEventListener('hashchange',f);
  return()=>removeEventListener('hashchange',f);
 },[]);

 const go=v=>{location.hash=v};
 const page=t=>(<section><div className="wrap"><h2>{t[0]}</h2><p className="sub">{t[1]}</p>{t[2]}</div></section>);

 return (
  <div className="app-shell">
   <Header route={route} theme={theme} onToggleTheme={onToggleTheme}/>
   <main>
    {route==='home'&&<>
     <div className="wrap hero"><div>
      <h1>Ride the pump. Lock the gains. Sleep.</h1>
      <p className="lead">Autonomous smart stop-losses that ratchet up as your tokens climb, then cash you out into USDC in three steps if they dip. Your keys never leave your wallet.</p>
      <div className="cta"><button className="btn red" onClick={()=>setDemo(d=>d+1)}>Play a simulated pump</button><a className="ln" href="#app">Protect a position</a></div>
      <p className="small mono">Non-custodial. Runs on Base smart contracts. No Telegram bot holds your key.</p></div>
      <div className="frame"><RatchetChart cfg={cfg} demoKey={demo}/></div></div>
     <div dangerouslySetInnerHTML={{__html:homeHtml}}/></>}
    {route==='app'&&page(['Protect my tokens','Pick a token and a strategy. The chart below shows how it would behave.',<><StrategyBuilder cfg={cfg} setCfg={setCfg} go={go}/><div className="card" style={{marginTop:24}}><RatchetChart cfg={cfg}/></div></>])}
    {route==='positions'&&page(['My positions','Loaded straight from the vault contract when your wallet is connected.',<PositionInspector go={go}/>])}
    {route==='proof'&&page(['Checked on chain','Everything a judge or careful trader needs to verify.',<ProofTable/>])}
    {route==='docs'&&<div dangerouslySetInnerHTML={{__html:docsHtml}}/>}
   </main>
   <Footer/>
  </div>
 );
}
