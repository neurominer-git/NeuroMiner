(function(){
  "use strict";
  let api=null;
  /**
   * num  Provide the num helper used by visualization subconfiguration UI panel.
   * It supports visualization subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function num(x,d){let v=Number(x);return Number.isFinite(v)?v:d;}
  /**
   * Vis  Provide the vis helper used by visualization subconfiguration UI panel.
   * It supports visualization subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function Vis(S){S.vis=S.vis||{};return S.vis;}
  /**
   * el  Return a DOM element by id for the current UI page.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function el(id){return document.getElementById(id);}
  /**
   * setHidden  Provide the set hidden helper used by visualization subconfiguration UI panel.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function setHidden(id,tf){let e=el(id);if(e)e.classList.toggle("hidden",!!tf);}
  /**
   * setVal  Provide the set val helper used by visualization subconfiguration UI panel.
   * It supports visualization subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setVal(id,v){let e=el(id);if(e)e.value=(v==null?"":String(v));}
  /**
   * setChk  Provide the set chk helper used by visualization subconfiguration UI panel.
   * It supports visualization subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setChk(id,v){let e=el(id);if(e)e.checked=!!v;}
  /**
   * mark  Provide the mark helper used by visualization subconfiguration UI panel.
   * It supports visualization subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function mark(S){Vis(S).visDirty=true;}
  /**
   * visStatus  Route visualization-configurator notices through the shared message-strip component.
   */
  function visStatus(msg,cls){window.NMUIMessageTools.setMessage(msg,cls,"nm-vis");}
  /**
   * covarOptions  Provide the covar options helper used by visualization subconfiguration UI panel.
   * It supports visualization subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function covarOptions(S){let v=Vis(S),names=v.visCovariateNames;return names.map((n,i)=>({value:i+1,label:n||("Covariate #"+(i+1))}));}
  /**
   * canUseCovars  Return whether the can use covars condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function canUseCovars(S){let v=Vis(S);return !!(v.visCovariateAvailable&&(v.visExpert||Number(v.visPermMode)===4));}
  /**
   * summaryText  Build the summary text shown to users in the browser UI.
   * It supports visualization subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function summaryText(S){let v=Vis(S);let p=[];if(v.visSigModelSpace)p.push("model-space permutations: "+num(v.visNPerms,5000)+"; significant-component back-projection enabled");if(v.visPermutationInput)p.push("input-space permutations: "+num(v.visNPerms,5000));if(!p.length)return "Visualization defaults: no permutation testing enabled.";let s=p.join("; ");return s.charAt(0).toUpperCase()+s.slice(1)+".";}
  /**
   * createModal  Create the modal component or browser-side state object.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function createModal(){
    if(el("visConfigModal"))return;
    const div=document.createElement("div");
    div.innerHTML=`<div class="selectorModal" id="visConfigModal"><div class="selectorBox wide"><div class="selectorHead"><div><b>Visualization options</b><div class="muted" id="visScopeInfo">Modality-specific settings</div></div><button id="closeVISConfig" type="button">Close</button></div><div class="selectorBody"><div class="rfeMini" id="visInputSpaceBlock"><h3>Input-space permutation test</h3><div class="field"><label><input id="visPermutationInput" type="checkbox"> Perform permutation test in input space</label><div class="muted" id="visInputPermHint">Permutes labels, features, labels and features, or covariates depending on the selected mode.</div></div><div id="visInputPermDetails"><div class="twocol"><div class="field"><label for="visNPerms">Number of permutations</label><input id="visNPerms" class="textInput" type="number" min="1" step="1"></div><div class="field"><label for="visPermMode">Permutation mode</label><select id="visPermMode"><option value="1">Labels</option><option value="2">Features within label</option><option value="3">Labels and features</option></select></div></div><div class="field hidden" id="visCovariateField"><label for="visCovariates">Covariates</label><select id="visCovariates" multiple size="5"></select><div class="muted">Covariate permutation is exposed only when covariates are available and expert mode is active, or when an existing VIS configuration already uses this mode.</div></div></div></div><div class="rfeMini" id="visModelSpaceBlock"><h3>Model-space permutation and significant-component back-projection</h3><div class="field"><label><input id="visSigModelSpace" type="checkbox"> Perform permutations in model space and back-project only significant components</label><div class="muted">Visible only when dimensionality-reference preprocessing is detected.</div></div><div id="visModelSpaceDetails"><div class="field"><label for="visModelNPerms">Number of permutations (shared with input-space test)</label><input id="visModelNPerms" class="textInput" type="number" min="1" step="1"></div><div class="twocol"><div class="field"><label for="visSigCorrection">Component P-value correction</label><select id="visSigCorrection"><option value="1">FDR before back-projection, each model separately</option><option value="2">FDR after cross-validation, globally</option><option value="3">No correction</option></select></div><div class="field"><label for="visSigPThresh" id="visSigPThreshLabel">q threshold for back-projection</label><input id="visSigPThresh" class="textInput" type="number" min="0" step="0.001"></div></div></div></div></div></div></div>`;
    document.body.appendChild(div.firstElementChild);
    NMContextHelp.attachForm(el("visConfigModal"), "VIS_Context_Help.html", "Visualization help", "overview", "overview");
  }
  /**
   * renderCovars  Render the covars UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderCovars(S){let v=Vis(S),sel=el("visCovariates");if(!sel)return;sel.innerHTML="";let chosen=v.visCovariateIndices.map(Number);covarOptions(S).forEach(o=>{let opt=document.createElement("option");opt.value=String(o.value);opt.textContent=o.label;if(chosen.includes(o.value))opt.selected=true;sel.appendChild(opt);});}
  /**
   * render  Render the render UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function render(S){createModal();let v=Vis(S);let sm=el("visSummary");if(sm)sm.textContent=summaryText(S);let scope=el("visScopeInfo");if(scope)scope.textContent=api.activeModalityHeader();setChk("visPermutationInput",v.visPermutationInput);setVal("visNPerms",num(v.visNPerms,5000));setVal("visModelNPerms",num(v.visNPerms,5000));let mode=Number(v.visPermMode||1);let pm=el("visPermMode");if(pm){let has4=[...pm.options].some(o=>Number(o.value)===4);if(canUseCovars(S)&&!has4){let o=document.createElement("option");o.value="4";o.textContent="Covariate(s)";pm.appendChild(o);}else if(!canUseCovars(S)&&has4&&mode!==4){[...pm.options].filter(o=>Number(o.value)===4).forEach(o=>o.remove());}pm.value=String(mode);}setHidden("visInputPermDetails",!v.visPermutationInput);setHidden("visCovariateField",mode!==4);renderCovars(S);setHidden("visModelSpaceBlock",!v.visProjectionAvailable);if(!v.visProjectionAvailable)v.visSigModelSpace=false;setChk("visSigModelSpace",v.visSigModelSpace);setHidden("visModelSpaceDetails",!v.visSigModelSpace);let cor=num(v.visSigCorrection,1);setVal("visSigCorrection",cor);let lab=el("visSigPThreshLabel");if(lab)lab.firstChild.textContent=(cor===1?"q":"α")+" threshold for back-projection";setVal("visSigPThresh",num(v.visSigPThresh,0.05));let imh=el("visInputPermHint");if(imh)imh.textContent=v.visSigModelSpace?"Additional input-space feature-significance permutation test after model-space component testing.":"Primary input-space permutation test.";}
  /**
   * refresh  Refresh the refresh page region after state or artifact availability changes.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function refresh(){let S=api.getState(),changedPaths=api.changedPathsFor("");try{await fetch(api.API("/api/current"),{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(S)});let res=await fetch(api.API("/api/matlabservice"),{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({operation:"train_template_refresh_vis",state:S,changedPaths:changedPaths,includeCanvas:!(api.deferCanvas&&api.deferCanvas()),timeout:60})}).then(r=>r.json());if(res&&res.ok!==false){if(res.state)api.setState(res.state);else if(res.vis){api.getState().vis=res.vis;api.getState().auditSummary=res.auditSummary;}api.clearChangedPaths(changedPaths);if((res.canvasDirty||(res.state&&res.state.canvasDirty))&&api.markCanvasDirty){api.markCanvasDirty(res.canvasDirtyReason||(res.state&&res.state.canvasDirtyReason)||"Canvas refresh pending.");if(api.scheduleCanvasRefresh)api.scheduleCanvasRefresh(150);}render(api.getState());}else if(res&&res.message){visStatus(res.message,"danger");}}catch(e){visStatus("Visualization options could not be refreshed from the current ML configuration: "+e.message,"danger");}}
  /**
   * bindOnce  Register event handlers for the once controls.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function updatePermutationCount(e){let S=api.getState();Vis(S).visNPerms=Number(e.target.value);setVal(e.target.id==="visNPerms"?"visModelNPerms":"visNPerms",e.target.value);mark(S);api.sync();}
  function bindOnce(){createModal();if(el("openVISConfig")&&!el("openVISConfig").dataset.bound){el("openVISConfig").dataset.bound="1";el("openVISConfig").onclick=async()=>{if(api.getActiveEditor()){api.status("Another configuration window is already open. Return to the main configuration menu first.","warn");return;}api.setActiveEditor("vis");el("visConfigModal").classList.add("open");render(api.getState());await refresh();};}if(el("closeVISConfig")&&!el("closeVISConfig").dataset.bound){el("closeVISConfig").dataset.bound="1";el("closeVISConfig").onclick=async()=>{if(!(await apply()))return;el("visConfigModal").classList.remove("open");api.setActiveEditor(null);api.render();api.sync();};}[["visPermutationInput","change",e=>{let S=api.getState();Vis(S).visPermutationInput=!!e.target.checked;mark(S);render(S);api.sync();}], ["visNPerms","input",updatePermutationCount], ["visModelNPerms","input",updatePermutationCount], ["visPermMode","change",e=>{let S=api.getState();Vis(S).visPermMode=Number(e.target.value);mark(S);render(S);api.sync();}], ["visCovariates","change",e=>{let S=api.getState();Vis(S).visCovariateIndices=[...e.target.selectedOptions].map(o=>Number(o.value));mark(S);api.sync();}], ["visSigModelSpace","change",e=>{let S=api.getState();Vis(S).visSigModelSpace=!!e.target.checked;mark(S);render(S);api.sync();}], ["visSigCorrection","change",e=>{let S=api.getState();Vis(S).visSigCorrection=Number(e.target.value);mark(S);render(S);api.sync();}], ["visSigPThresh","input",e=>{let S=api.getState();Vis(S).visSigPThresh=Number(e.target.value);mark(S);api.sync();}]].forEach(b=>{let x=el(b[0]);if(x&&!x.dataset.bound){x.dataset.bound="1";x.addEventListener(b[1],b[2]);}});}
  /**
   * apply  Apply the apply change to local browser state or visible controls.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function apply(){let S=api.getState(),changedPaths=api.changedPathsFor("vis");Vis(S).visDirty=!!Vis(S).visDirty;try{await fetch(api.API("/api/current"),{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(S)});let res=await fetch(api.API("/api/matlabservice"),{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({operation:"train_template_apply_vis",state:S,changedPaths:changedPaths,includeCanvas:!(api.deferCanvas&&api.deferCanvas()),timeout:60})}).then(r=>r.json());if(res&&res.ok!==false){if(res.state)api.setState(res.state);else if(res.vis){api.getState().vis=res.vis;api.getState().auditSummary=res.auditSummary;}api.getState().readinessDiagnostic=res.readinessDiagnostic;api.clearChangedPaths(changedPaths);window.NMUIMessageTools.clearMessage("nm-vis");if((res.canvasDirty||(res.state&&res.state.canvasDirty))&&api.markCanvasDirty){api.markCanvasDirty(res.canvasDirtyReason||(res.state&&res.state.canvasDirtyReason)||"Canvas refresh pending.");if(api.scheduleCanvasRefresh)api.scheduleCanvasRefresh(150);}return true;}else if(res&&res.message){visStatus(res.message,"danger");return false;}return false;}catch(e){visStatus("Visualization configuration could not be applied: "+e.message,"danger");return false;} }
  window.NMVISUI={attach:function(a){api=a;createModal();bindOnce();},renderSummary:function(S){createModal();bindOnce();render(S);},apply:apply};
})();
