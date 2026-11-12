import {ConnectButton} from '@rainbow-me/rainbowkit';
import logoImg from '../assets/logo.png';

const SunIcon = () => (
 <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
  <circle cx="12" cy="12" r="5"/>
  <line x1="12" y1="1" x2="12" y2="3"/>
  <line x1="12" y1="21" x2="12" y2="23"/>
  <line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/>
  <line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/>
  <line x1="1" y1="12" x2="3" y2="12"/>
  <line x1="21" y1="12" x2="23" y2="12"/>
  <line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/>
  <line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/>
 </svg>
);

const MoonIcon = () => (
 <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
  <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>
 </svg>
);

export const Mascot=()=>(
 <img
  src={logoImg}
  alt="PulseTrail Mascot"
  width="32"
  height="33"
  style={{
   display: 'block',
   imageRendering: 'pixelated',
   flexShrink: 0,
   borderRadius: '4px'
  }}
 />
);

export default function Header({route, theme, onToggleTheme}){
 const L=[['app','Protect'],['positions','My positions'],['proof','Proof'],['docs','Docs']];
 const isWhite = theme === 'light';

 return (
  <header>
   <div className="wrap hdr-wrap">
    <div className="hdr-left">
     <a className="logo" href="#home"><Mascot/>PulseTrail <span className="badge">BASE</span></a>
    </div>
    <nav className="hdr-nav">
     {L.map(([k,t])=><a key={k} href={'#'+k} className={route===k?'cur':''}>{t}</a>)}
    </nav>
    <div className="hdr-actions">
     <span className="pill hide-mobile"><span className="dot"/>Base · fast (&lt;2s)</span>
     <button
      type="button"
      className="theme-toggle"
      onClick={onToggleTheme}
      role="switch"
      aria-checked={isWhite}
      aria-label={isWhite ? 'Switch to dark mode' : 'Switch to white mode'}
      title={isWhite ? 'Switch to dark mode' : 'Switch to white mode'}
     >
      <span className="theme-toggle-track">
       <span className={`theme-toggle-thumb ${isWhite ? 'is-white' : 'is-dark'}`}>
        {isWhite ? <SunIcon/> : <MoonIcon/>}
       </span>
      </span>
      <span className="theme-toggle-label">{isWhite ? 'White' : 'Dark'}</span>
     </button>
     <ConnectButton chainStatus="icon" showBalance={false}/>
    </div>
   </div>
  </header>
 );
}
