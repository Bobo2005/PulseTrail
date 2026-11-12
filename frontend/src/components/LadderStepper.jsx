export default function LadderStepper({stage,done,act,hwm}){
 const sub=['Waiting for +'+Math.round((act||0)*100)+'% profit','Sells 40% on a dip','Sells 30% next','Sells the last 30%'];
 const idx=Math.min(stage,3);
 return <div className="steps">{['Monitoring','Step 1: 40%','Step 2: 30%','Step 3: 30%'].map((t,n)=>
  <div key={n} className={'st'+((done||n===idx)?' on':'')} title={t}>
   <b>{t}</b>
   <span>{n===idx&&stage>=1&&hwm&&!done?'Trailing peak $'+hwm.toFixed(2):sub[n]}</span>
  </div>)}</div>;
}
