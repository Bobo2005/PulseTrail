export default function LadderStepper({stage,done,act,hwm,exitLabels}){
 const actPct=Math.round((act||0)*100);
 const sub=[
  (stage>=1||done)?'Cleared +'+actPct+'% hurdle':'Waiting for +'+actPct+'% profit',
  exitLabels?.[0]||'Sells 40% on a dip',
  exitLabels?.[1]||'Sells 30% next',
  exitLabels?.[2]||'Sells the last 30%'
 ];
 const idx=Math.min(stage,3);
 const hwmStr=typeof hwm==='number'?'$'+hwm.toFixed(2):hwm;
 return <div className="steps">{['Monitoring','Step 1: 40%','Step 2: 30%','Step 3: 30%'].map((t,n)=>{
  const isDone=done||n<idx;
  const isOn=!done&&n===idx;
  return (
   <div key={n} className={'st'+(isOn?' on':'')+(isDone?' done':'')} title={t}>
    <b>{isDone?'✓ ':''}{t}</b>
    <span>{isOn&&stage>=1&&hwmStr?'Trailing peak '+hwmStr:sub[n]}</span>
   </div>
  );
 })}</div>;
}
