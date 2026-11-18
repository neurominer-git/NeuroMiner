(function(){
  "use strict";
  let api=null;
  let debounceTimer=null;
  /**
   * el  Return a DOM element by id for the current UI page.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function el(id){return document.getElementById(id);}
  /**
   * SAV  Provide the sav helper used by model-output saving subconfiguration UI panel.
   * It supports model-output saving subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function SAV(S){S.sav=S.sav||{};return S.sav;}
  /**
   * escapeHtml  Build the escape html inserted into the browser UI.
   * It supports model-output saving subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function escapeHtml(s){return String(s==null?"":s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
  /**
   * bool  Provide the bool helper used by model-output saving subconfiguration UI panel.
   * It supports model-output saving subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function bool(x){return !!x && Number(x)!==0;}
  /**
   * setHidden  Provide the set hidden helper used by model-output saving subconfiguration UI panel.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function setHidden(id,tf){let e=el(id);if(e)e.classList.toggle("hidden",!!tf);}
  /**
   * setVal  Provide the set val helper used by model-output saving subconfiguration UI panel.
   * It supports model-output saving subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setVal(id,v){let e=el(id);if(e)e.value=(v==null?"":String(v));}
  /**
   * setChk  Provide the set chk helper used by model-output saving subconfiguration UI panel.
   * It supports model-output saving subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setChk(id,v){let e=el(id);if(e)e.checked=!!v;}
  /**
   * savStatus  Provide the sav status helper used by model-output saving subconfiguration UI panel.
   * It supports model-output saving subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function savStatus(msg,cls){if(api&&api.status)api.status(msg,cls||"info");else window.NMUIMessageTools.setMessage(msg,cls||"info");}
  /**
   * verbStatus  Provide the verb status helper used by model-output saving subconfiguration UI panel.
   * It supports model-output saving subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function verbStatus(msg,cls){if(api&&api.status)api.status(msg,cls||"info");else window.NMUIMessageTools.setMessage(msg,cls||"info");}
  /**
   * savingSummary  Provide the saving summary helper used by model-output saving subconfiguration UI panel.
   * It supports model-output saving subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function savingSummary(S){let s=SAV(S);let nm=s.savMatName||s.savDefaultMatName||"";return (bool(s.savSaveModel)?"Model saving enabled. ":"Model saving disabled. ")+(nm?`Output prefix: ${nm}.`:"No output prefix configured.");}
  /**
   * verbositySummary  Provide the verbosity summary helper used by model-output saving subconfiguration UI panel.
   * It supports model-output saving subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function verbositySummary(S){let s=SAV(S);let v=(typeof S.verbosity!=="undefined")?S.verbosity:s.verbosity;return bool(v)?"Detailed output.":"No output.";}
  /**
   * ensureMainFields  Ensure the main fields prerequisite exists before downstream rendering or requests.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function ensureMainFields(){
    let mliField=el("mliField");
    if(mliField&&!el("savField")){
      let wrap=document.createElement("div");
      wrap.innerHTML=`<div class="field" id="savField"><label>Model saving options</label><div class="summary" id="savSummary">Model saving defaults.</div></div><div class="field" id="verbosityField"><label>Verbosity level</label><div class="summary" id="verbositySummary">Detailed output.</div></div>`;
      let parent=mliField.parentNode;
      parent.insertBefore(wrap.firstElementChild,mliField.nextSibling);
      parent.insertBefore(wrap.firstElementChild,el("savField").nextSibling);
    }
    let openMLI=el("openMLIConfig");
    if(openMLI&&!el("openSAVConfig")){
      let frag=document.createElement("div");
      frag.innerHTML=`<button id="openSAVConfig" class="primary" type="button">Open saving-options configuration</button><button id="openVerbosityConfig" class="primary" type="button">Open verbosity configuration</button>`;
      let parent=openMLI.parentNode;
      parent.insertBefore(frag.firstElementChild,openMLI.nextSibling);
      parent.insertBefore(frag.firstElementChild,el("openSAVConfig").nextSibling);
    }
  }
  /**
   * createModals  Create the modals component or browser-side state object.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function createModals(){
    if(!el("savConfigModal")){
      let div=document.createElement("div");
      div.innerHTML=`<div class="selectorModal" id="savConfigModal"><div class="selectorBox"><div class="selectorHead"><div><b>Saving-options configuration</b><div class="muted"></div></div><button id="closeSAVConfig" type="button">Close</button></div><div class="selectorBody"><div class="field"><label><input id="savSaveModel" type="checkbox"> Save models to disk</label></div><div class="field"><label for="savMatName">Prefix of NM output files</label><div class="savPrefixRow"><input id="savMatName" class="textInput" type="text"><button id="savUseDefaultName" type="button">Use default prefix</button></div></div></div></div></div>`;
      document.body.appendChild(div.firstElementChild);
    }
    if(!el("verbosityConfigModal")){
      let div=document.createElement("div");
      div.innerHTML=`<div class="selectorModal" id="verbosityConfigModal"><div class="selectorBox"><div class="selectorHead"><div><b>Verbosity configuration</b><div class="muted"></div></div><button id="closeVerbosityConfig" type="button">Close</button></div><div class="selectorBody"><div class="field"><label for="verbosityValue">Verbosity level</label><select id="verbosityValue"><option value="1">Detailed output</option><option value="0">No output</option></select></div></div></div></div>`;
      document.body.appendChild(div.firstElementChild);
    }
  }
  /**
   * render  Render the render UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function render(S){
    ensureMainFields();createModals();
    let s=SAV(S);
    if(typeof s.verbosity==="undefined" && typeof S.verbosity!=="undefined")s.verbosity=S.verbosity;
    let ss=el("savSummary");if(ss)ss.textContent=S.savSummary||s.savSummary||savingSummary(S);
    let vs=el("verbositySummary");if(vs)vs.textContent=S.verbositySummary||s.verbositySummary||verbositySummary(S);
    setChk("savSaveModel",bool(s.savSaveModel));
    setVal("savMatName",s.savMatName||s.savDefaultMatName||"");
    setVal("verbosityValue",bool(s.verbosity)||bool(S.verbosity)?1:0);
  }
  /**
   * postApply  Provide the post apply helper used by model-output saving subconfiguration UI panel.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function postApply(source){
    let S=api.getState(),changedPaths=api.changedPathsFor("sav");
    await fetch(api.API("/api/current"),{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(S)}).catch(()=>{});
    let res=await fetch(api.API("/api/matlabservice"),{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({operation:"train_template_apply_sav",state:S,changedPaths:changedPaths,includeCanvas:!(api.deferCanvas&&api.deferCanvas()),timeout:120,source:source||"sav"})}).then(r=>r.json());
    if(res&&res.state&&typeof res.state==="object")api.setState(res.state);else if(res&&res.sav&&typeof res.sav==="object"){api.getState().sav=res.sav;api.getState().verbosity=res.sav.verbosity;api.getState().verbosityValue=res.sav.verbosityValue;api.getState().auditSummary=res.auditSummary;}
    if(res&&res.ok!==false)api.getState().readinessDiagnostic=res.readinessDiagnostic;
    if(res&&res.ok!==false)api.clearChangedPaths(changedPaths);
    if((res&&res.canvasDirty||(res&&res.state&&res.state.canvasDirty))&&api.markCanvasDirty){api.markCanvasDirty(res.canvasDirtyReason||(res.state&&res.state.canvasDirtyReason)||"Canvas refresh pending.");if(api.scheduleCanvasRefresh)api.scheduleCanvasRefresh(150);}
    render(api.getState());
    if(res&&res.error)throw new Error(res.error);
    if(!res||res.ok===false)throw new Error((res&&res.message)||"Saving/verbosity apply failed.");
    api.sync();
    return res;
  }
  /**
   * debounceApply  Provide the debounce apply helper used by model-output saving subconfiguration UI panel.
   * It supports model-output saving subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function debounceApply(source,msgFn){
    if(debounceTimer)clearTimeout(debounceTimer);
    debounceTimer=setTimeout(async()=>{try{await postApply(source);}catch(e){(msgFn||savStatus)("Saving/verbosity options could not be applied: "+e.message,"danger");}},450);
  }
  /**
   * apply  Apply the apply change to local browser state or visible controls.
   * It supports model-output saving subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  async function apply(){
    try{await postApply("close");return true;}
    catch(e){savStatus("Saving/verbosity options could not be applied: "+e.message,"danger");return false;}
  }
  /**
   * bindOnce  Register event handlers for the once controls.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function bindOnce(){
    ensureMainFields();createModals();
    let os=el("openSAVConfig");if(os&&!os.dataset.bound){os.dataset.bound="1";os.onclick=()=>{if(api.getActiveEditor()){api.status("Another configuration window is already open. Return to the main configuration menu first.","warn");return;}api.setActiveEditor("sav");el("savConfigModal").classList.add("open");render(api.getState());};}
    let ov=el("openVerbosityConfig");if(ov&&!ov.dataset.bound){ov.dataset.bound="1";ov.onclick=()=>{if(api.getActiveEditor()){api.status("Another configuration window is already open. Return to the main configuration menu first.","warn");return;}api.setActiveEditor("verbosity");el("verbosityConfigModal").classList.add("open");render(api.getState());};}
    let cs=el("closeSAVConfig");if(cs&&!cs.dataset.bound){cs.dataset.bound="1";cs.onclick=async()=>{let synth=api.getState().fullySyntheticMode;if(synth){clearTimeout(debounceTimer);debounceTimer=null;}else if(!(await apply()))return;el("savConfigModal").classList.remove("open");api.setActiveEditor(null);if(!synth){api.render();api.sync();}};}
    let cv=el("closeVerbosityConfig");if(cv&&!cv.dataset.bound){cv.dataset.bound="1";cv.onclick=async()=>{let synth=api.getState().fullySyntheticMode;if(synth){clearTimeout(debounceTimer);debounceTimer=null;}else if(!(await apply()))return;el("verbosityConfigModal").classList.remove("open");api.setActiveEditor(null);if(!synth){api.render();api.sync();}};}
    let cb=el("savSaveModel");if(cb&&!cb.dataset.bound){cb.dataset.bound="1";cb.onchange=e=>{let S=api.getState();SAV(S).savSaveModel=!!e.target.checked;SAV(S).savDirty=true;render(S);api.sync();debounceApply("saving",savStatus);};}
    let mn=el("savMatName");if(mn&&!mn.dataset.bound){mn.dataset.bound="1";mn.oninput=e=>{let S=api.getState();SAV(S).savMatName=e.target.value;SAV(S).savDirty=true;render(S);api.sync();debounceApply("saving",savStatus);};mn.onblur=()=>debounceApply("saving",savStatus);}
    let def=el("savUseDefaultName");if(def&&!def.dataset.bound){def.dataset.bound="1";def.onclick=()=>{let S=api.getState();SAV(S).savMatName=SAV(S).savDefaultMatName||"";SAV(S).savDirty=true;render(S);api.sync();debounceApply("saving",savStatus);};}
    let vb=el("verbosityValue");if(vb&&!vb.dataset.bound){vb.dataset.bound="1";vb.onchange=e=>{let S=api.getState();let val=Number(e.target.value)!==0;SAV(S).verbosity=val;S.verbosity=val;S.verbosityValue=val?1:0;SAV(S).verbosityValue=S.verbosityValue;SAV(S).savDirty=true;render(S);api.sync();debounceApply("verbosity",verbStatus);};}
  }
  window.NMSAVUI={attach:function(a){api=a;ensureMainFields();createModals();bindOnce();},renderSummary:function(S){ensureMainFields();createModals();bindOnce();render(S);},apply:apply};
})();
