/* NMRunnerStateManager
 * Projects reconstructible runner setup into nm2_state.json.
 * Scientific/runtime state and computation progress remain owned by MATLAB and the runtime-job layer.
 */
(function(global){
'use strict';

let ADAPTER=null;
let READY=false;
let RECOVERY_ERROR=null;
let RESTORING=false;
let REVISION=0;
let LAST_SIGNATURE='';
let PENDING=Promise.resolve();

function port(){
  const q=new URLSearchParams(global.location&&global.location.search||'');
  return q.get('port')||global.NM_UI_PORT||'4821';
}

function api(path){
  const url=`http://127.0.0.1:${port()}${path}`;
  return global.NMBridgeAuthenticatedURL?global.NMBridgeAuthenticatedURL(url):url;
}

function nextRevision(){
  const now=Math.floor(Date.now()*1000);
  REVISION=Math.max(REVISION+1,now);
  return REVISION;
}

function normalizeSnapshot(value){
  if(!value||typeof value!=='object'||Array.isArray(value)) throw new Error('Runner STATE snapshot must be one JSON object.');
  return value;
}

function snapshot(){
  if(!ADAPTER||typeof ADAPTER.snapshot!=='function') throw new Error('Runner STATE adapter is not registered.');
  return normalizeSnapshot(ADAPTER.snapshot());
}

function signature(value){ return JSON.stringify(value); }

function report(message){
  if(ADAPTER&&typeof ADAPTER.report==='function') ADAPTER.report(message);
  else console.error(message);
}

async function readPersisted(){
  const response=await fetch(api(`/api/nm2state?section=runners&slot=${encodeURIComponent(ADAPTER.key)}`));
  const out=await response.json().catch(()=>null);
  if(response.status===404&&out&&String(out.message||'').startsWith('Runner STATE slot is not initialized:')) return {revision:0,state:null};
  if(!response.ok||!out||out.ok===false) throw new Error(out&&out.message?out.message:`Runner STATE read failed with HTTP ${response.status}.`);
  REVISION=Math.max(REVISION,Number(out.revision)||0);
  return {revision:Number(out.revision)||0,state:out.state&&typeof out.state==='object'&&!Array.isArray(out.state)?out.state:null};
}

async function writePersisted(value,allowRetry){
  const rev=nextRevision();
  const response=await fetch(api('/api/nm2state'),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({section:'runners',slot:ADAPTER.key,revision:rev,state:value})});
  const out=await response.json().catch(()=>null);
  if(response.status===409&&out&&out.stale&&allowRetry!==false){
    REVISION=Math.max(REVISION,Number(out.currentRevision)||0);
    return writePersisted(value,false);
  }
  if(!response.ok||!out||out.ok===false) throw new Error(out&&out.message?out.message:`Runner STATE write failed with HTTP ${response.status}.`);
  REVISION=Math.max(REVISION,Number(out.revision)||rev);
  LAST_SIGNATURE=signature(value);
  return out;
}

function enqueueSnapshot(throwOnError){
  if(!READY||RESTORING||!ADAPTER) return PENDING;
  let value;
  try{ value=snapshot(); }
  catch(error){
    report(`Runner setup could not be captured: ${error.message||String(error)}`);
    return throwOnError?Promise.reject(error):PENDING;
  }
  const sig=signature(value);
  if(sig===LAST_SIGNATURE) return PENDING;
  const writeTask=PENDING.then(()=>writePersisted(value,true));
  PENDING=writeTask.catch(error=>{ report(`Runner setup could not be written to NM2 STATE: ${error.message||String(error)}`); });
  return throwOnError?writeTask:PENDING;
}

function queueSnapshot(){ return enqueueSnapshot(false); }

function sendBeaconSnapshot(){
  if(!READY||RESTORING||!ADAPTER||!navigator.sendBeacon) return;
  try{
    const value=snapshot();
    const sig=signature(value);
    if(sig===LAST_SIGNATURE) return;
    const payload={section:'runners',slot:ADAPTER.key,revision:nextRevision(),state:value};
    const blob=new Blob([JSON.stringify(payload)],{type:'application/json'});
    if(!navigator.sendBeacon(api('/api/nm2state'),blob)) throw new Error('Browser refused to queue the runner STATE beacon.');
    LAST_SIGNATURE=sig;
  }catch(error){ report(`Runner setup could not be queued for NM2 STATE on page exit: ${error.message||String(error)}`); }
}

function registerAdapter(adapter){
  if(ADAPTER) throw new Error('Only one runner STATE adapter may be registered per page.');
  if(!adapter||typeof adapter!=='object'||!adapter.key||typeof adapter.snapshot!=='function'||typeof adapter.restore!=='function')
    throw new Error('Runner STATE adapter requires key, snapshot and restore.');
  ADAPTER=adapter;
  document.addEventListener('change',queueSnapshot);
  global.addEventListener('pagehide',sendBeaconSnapshot);
}

async function markReady(){
  if(!ADAPTER) return;
  try{
    const saved=await readPersisted();
    if(saved.state){
      RESTORING=true;
      try{ await ADAPTER.restore(saved.state); }
      finally{ RESTORING=false; }
    }
    LAST_SIGNATURE=signature(snapshot());
    READY=true;
    RECOVERY_ERROR=null;
  }catch(error){
    READY=false;
    RECOVERY_ERROR=error;
    report(`Runner setup could not be recovered from NM2 STATE: ${error.message||String(error)}`);
    throw error;
  }
}

function markChanged(){ return queueSnapshot(); }
function syncNow(){
  if(!READY) return Promise.reject(new Error(RECOVERY_ERROR
    ? `Runner STATE recovery failed: ${RECOVERY_ERROR.message||String(RECOVERY_ERROR)}`
    : 'Runner STATE recovery has not completed successfully.'));
  return enqueueSnapshot(true);
}

const apiObject=Object.freeze({registerAdapter,markReady,markChanged,syncNow});
global.NMRunnerStateManager=apiObject;
})(window);
