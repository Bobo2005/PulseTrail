import {ADDR} from '../config/contracts.js';
import logoImg from '../assets/logo.png';

export default function Footer(){
 return (
  <footer>
   <div className="wrap">
    <span className="logo" style={{display: 'inline-flex', alignItems: 'center', gap: '8px', fontSize: '20px'}}>
     <img src={logoImg} alt="" width="24" height="25" style={{imageRendering: 'pixelated'}} />
     PulseTrail
    </span>
    <a href={'https://basescan.org/address/' + ADDR.vault} target="_blank" rel="noreferrer">Vault contract</a>
    <a href="#proof">On-chain proof</a>
    <a href="#docs">Docs</a>
    <span className="small">Autonomous smart stop-losses that ratchet up as your tokens climb. Not financial advice.</span>
   </div>
  </footer>
 );
}
