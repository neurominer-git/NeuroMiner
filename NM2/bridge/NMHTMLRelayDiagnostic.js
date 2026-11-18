// Temporary profile-only uihtml trace. No relay requests or MATLAB callbacks originate here.
(function(global){
  'use strict';
  const origin=global.performance.now();
  const lines=['NM2 embedded relay trace (NM_UI_PROFILE=1)'];
  let panel=null;
  function display(){
    if(panel) panel.textContent=lines.join('\n');
  }
  global.NMRelayTrace=function(message){
    lines.push(((global.performance.now()-origin)/1000).toFixed(3)+'s  '+String(message));
    if(lines.length>36) lines.splice(9,1);
    display();
  };
  global.addEventListener('error',event=>{
    global.NMRelayTrace('JS ERROR '+String(event.message)+' (line '+String(event.lineno)+')');
  });
  global.addEventListener('unhandledrejection',event=>{
    const reason=event.reason;
    global.NMRelayTrace('JS REJECTION '+String(reason instanceof Error?reason.message:reason));
  });
  global.document.addEventListener('DOMContentLoaded',()=>{
    panel=global.document.createElement('pre');
    panel.id='nm2RelayTrace';
    panel.setAttribute('aria-hidden','true');
    panel.style.cssText='position:fixed;right:8px;bottom:8px;z-index:2147483647;'+
      'max-width:68vw;width:490px;max-height:62vh;overflow:hidden;pointer-events:none;'+
      'padding:10px;border-radius:6px;background:rgba(16,23,34,.92);color:white;'+
      'font:12px/1.38 monospace;white-space:pre-wrap;overflow-wrap:anywhere;'+
      'box-shadow:0 2px 10px rgba(0,0,0,.35)';
    global.document.body.appendChild(panel);
    global.NMRelayTrace('A DOMContentLoaded title='+global.document.title);
  },{once:true});
  global.NMRelayTrace('A diagnostic prelude entered, bridge port='+global.NM_HTML_RELAY_CONFIG.port);
})(window);
