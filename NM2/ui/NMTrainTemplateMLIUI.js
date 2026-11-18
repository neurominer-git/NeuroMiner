(function(){
  "use strict";
  let api=null;
  /**
   * arr  Normalize a nullable scalar or array-like value to an array.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function arr(x){return Array.isArray(x)?x:(x==null?[]:[x]);}
  /**
   * el  Return a DOM element by id for the current UI page.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function el(id){return document.getElementById(id);}
  /**
   * num  Provide the num helper used by MLI subconfiguration UI panel in the training-template configurator.
   * It supports MLI subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function num(x,d){let v=Number(x);return Number.isFinite(v)?v:d;}
  /**
   * bool  Provide the bool helper used by MLI subconfiguration UI panel in the training-template configurator.
   * It supports MLI subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function bool(x){return !!x && Number(x)!==0;}
  /**
   * MLI  Provide the mli helper used by MLI subconfiguration UI panel in the training-template configurator.
   * It supports MLI subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function MLI(S){S.mli=S.mli||{};return S.mli;}
  /**
   * setHidden  Provide the set hidden helper used by MLI subconfiguration UI panel in the training-template configurator.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function setHidden(id,tf){let e=el(id);if(e)e.classList.toggle("hidden",!!tf);}
  /**
   * setVal  Provide the set val helper used by MLI subconfiguration UI panel in the training-template configurator.
   * It supports MLI subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setVal(id,v){let e=el(id);if(e)e.value=(v==null?"":String(v));}
  /**
   * setChk  Provide the set chk helper used by MLI subconfiguration UI panel in the training-template configurator.
   * It supports MLI subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setChk(id,v){let e=el(id);if(e)e.checked=!!v;}
  /**
   * mark  Provide the mark helper used by MLI subconfiguration UI panel in the training-template configurator.
   * It supports MLI subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function mark(S){MLI(S).mliDirty=true;}
  /**
   * mliStatus  Provide the mli status helper used by MLI subconfiguration UI panel in the training-template configurator.
   * It supports MLI subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function mliStatus(msg,cls){window.NMUIMessageTools.setMessage(msg,cls,"nm-mli");}
  /**
   * escapeHtml  Build the escape html inserted into the browser UI.
   * It supports MLI subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function escapeHtml(s){return String(s==null?"":s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
  /**
   * splitNums  Provide the split nums helper used by MLI subconfiguration UI panel in the training-template configurator.
   * It supports MLI subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function splitNums(s){return String(s||"").replace(/[\[\],;]/g," ").trim().split(/\s+/).filter(Boolean).map(Number).filter(Number.isFinite);}
  /**
   * isInfText  Return whether the is inf text condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function isInfText(s){return /^\s*[+]?inf(inity)?\s*$/i.test(String(s||""));}
  /**
   * isShapley  Return whether the is shapley condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  /**
   * isPosNeg  Return whether the is pos neg condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  /**
   * isImaging  Return whether the is imaging condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function isImaging(S){let m=MLI(S);if(typeof m.mliIsImaging!=="undefined")return !!m.mliIsImaging;let a=arr(S.modalityIsImaging);let idx=Number(S.activeModality||1)-1;return !!a[idx];}
  /**
   * summaryText  Build the summary text shown to users in the browser UI.
   * It supports MLI subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function summaryText(S){let m=MLI(S),p=[];let methods={posneg:"Upper/lower percentile occlusion",median:"Median occlusion",medianflip:"Median-span flip occlusion",medianmirror:"Median-mirror occlusion",random:"Random-value occlusion",shapley:"Shapley values"};p.push(methods[m.mliMethod]||m.mliMethod||"Upper/lower percentile occlusion");if(m.mliMapFlag)p.push("map-restricted: "+(m.mliMapMap||"cvr"));if(isImaging(S)&&m.mliAtlasFlag){p.push(m.mliAtlasImported?`atlas image imported (${num(m.mliAtlasUniqueCount,0)} labels)`:"atlas image not imported");p.push(m.mliCsvImported?`descriptor table imported (${num(m.mliCsvNumCount,0)} ROI IDs)`:"descriptor table not imported");}p.push(isInfText(m.mliNPermsText)?"automated stopping":`${m.mliNPermsText||1024} iterations`);let s=p.join("; ");return s.charAt(0).toUpperCase()+s.slice(1)+".";}
  /**
   * operatorOptions  Provide the operator options helper used by MLI subconfiguration UI panel in the training-template configurator.
   * It supports MLI subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function operatorOptions(m){let n=splitNums(m.mliMapCutoffText).length;return n>1?[[1,"<, >"],[2,"<=, >="],[3,">, <"],[4,">=, <="]]:[[1,"<"],[2,"<="],[3,">"],[4,">="],[5,"=="],[6,"~="]];}
  /**
   * fillOptions  Provide the fill options helper used by MLI subconfiguration UI panel in the training-template configurator.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * opts.forEach: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function fillOptions(id,opts,val){let e=el(id);if(!e)return;e.innerHTML="";opts.forEach(o=>{let opt=document.createElement("option");opt.value=String(o[0]);opt.textContent=o[1];if(String(o[0])===String(val))opt.selected=true;e.appendChild(opt);});}
  /**
   * createModal  Create the modal component or browser-side state object.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function createModal(){
    if(el("mliConfigModal"))return;
    let div=document.createElement("div");
    div.innerHTML=`<div class="selectorModal" id="mliConfigModal"><div class="selectorBox wide"><div class="selectorHead"><div><b>Interpretable ML configuration</b><div class="muted" id="mliScopeInfo"></div></div><button id="closeMLIConfig" type="button">Close</button></div><div class="selectorBody"><div class="rfeLayout"><div class="rfeSide"><button class="rfeTab active" data-mli-tab="method" type="button">Method</button><button class="rfeTab" data-mli-tab="map" type="button">Feature-space restriction</button><button class="rfeTab" data-mli-tab="norm" type="button">Normalization</button><button class="rfeTab" data-mli-tab="atlas" type="button">Atlas binding</button></div><div><div class="rfePane" id="mliPane_method"><h2>Occlusion / interpretation method</h2><div class="field"><label for="mliMethod">Interpretation method</label><select id="mliMethod"><option value="posneg">Replace feature with upper and lower percentile cutoffs</option><option value="median">Replace feature with median</option><option value="medianflip">Replace feature by adding/subtracting the median quantile</option><option value="medianmirror">Replace feature by its mirror value at the median quantile</option><option value="random">Replace feature by randomly sampling the training distribution</option><option value="shapley">Shapley values</option></select></div><div id="mliPosNegBlock" class="twocol"><div class="field"><label for="mliUpperThresh">Upper percentile</label><input id="mliUpperThresh" class="textInput" type="number" step="0.1"></div><div class="field"><label for="mliLowerThresh">Lower percentile</label><input id="mliLowerThresh" class="textInput" type="number" step="0.1"></div></div><div class="twocol"><div class="field"><label for="mliNPermsText">Number of iterations</label><input id="mliNPermsText" class="textInput" type="text" placeholder="1024 or Inf"><div class="muted">Use Inf for automated stopping in non-Shapley methods.</div></div><div class="field" id="mliFeatureFracField"><label for="mliFeatureFrac">Fraction of features visited per iteration</label><input id="mliFeatureFrac" class="textInput" type="number" min="0" max="1" step="0.01"></div></div><div id="mliAutoStopBlock" class="twocol"><div class="field"><label for="mliNVisited">Minimum visits per feature</label><input id="mliNVisited" class="textInput" type="number" min="1" step="1"></div><div class="field"><label for="mliMaxIter">Maximum iterations</label><input id="mliMaxIter" class="textInput" type="number" min="1" step="1"></div></div><div class="field hidden" id="mliSampleFracField"><label for="mliSampleFrac">Fraction of training samples visited per iteration</label><input id="mliSampleFrac" class="textInput" type="number" min="0" max="1" step="0.01"></div></div><div class="rfePane hidden" id="mliPane_map"><h2>Feature-space restriction from visualization maps</h2><div class="field"><label><input id="mliMapFlag" type="checkbox"> Use map from model visualization to operate in a pre-determined feature space</label></div><div id="mliMapDetails"><div class="field"><label for="mliMapMap">Map type</label><select id="mliMapMap"><option value="cvr">Cross-validation ratio map</option><option value="p_sgn">Sign-based consistency map: p value, uncorrected</option><option value="p_FDR_sgn">Sign-based consistency map: p value, FDR-corrected</option></select></div><div class="twocol"><div class="field"><label for="mliMapCutoffText">Cutoff value: scalar or two-value vector</label><input id="mliMapCutoffText" class="textInput" type="text" placeholder="-2 2"></div><div class="field"><label for="mliMapPercentMode">Cutoff mode</label><select id="mliMapPercentMode"><option value="absolute">Absolute mode</option><option value="percentile">Percentile mode</option></select></div></div><div class="field"><label for="mliMapOperator">Cutoff operator</label><select id="mliMapOperator"></select></div></div></div><div class="rfePane hidden" id="mliPane_norm"><h2>Prediction-change normalization</h2><div class="field" id="mliZNormField"><label for="mliZNormData">Normalize prediction-change estimates at the case level</label><select id="mliZNormData"><option value="1">No, only group-level normalization</option><option value="2">Yes, mean centering at the case level</option><option value="3">Yes, Z-normalization at the case level</option><option value="4">Yes, scaling to [-1,1] at the case level</option></select></div><div id="mliZNormShapleyNote" class="summary hidden">Case-level normalization is not available for Shapley values.</div></div><div class="rfePane hidden" id="mliPane_atlas"><h2>Atlas-bound image modification</h2><div id="mliAtlasUnavailable" class="summary hidden">Atlas binding is available only for imaging modalities.</div><div id="mliAtlasAvailable"><div class="field"><label><input id="mliAtlasFlag" type="checkbox"> Bind data modification to neuroanatomical atlas</label></div><div id="mliAtlasDetails"><div class="field"><label for="mliAtlasFile">Atlas imaging file</label><div class="inlineActions"><button id="mliPickAtlas" type="button">Select and import atlas image...</button><button id="mliImportAtlas" type="button">Import current atlas image</button></div><input id="mliAtlasFile" class="textInput" type="text" placeholder="Path to atlas image"></div><div class="summary" id="mliAtlasImportSummary"></div><div class="field"><label for="mliCsvFile">Atlas descriptor file</label><div class="inlineActions"><button id="mliPickCsv" type="button">Select descriptor file...</button><button id="mliPreviewCsv" type="button">Preview current descriptor file</button><button id="mliImportCsv" type="button">Import descriptor table</button></div><input id="mliCsvFile" class="textInput" type="text" placeholder="Path to .txt/.dat/.csv descriptor"></div><pre class="summary" id="mliCsvPreviewSummary" style="white-space:pre-wrap;max-height:150px;overflow:auto">No atlas descriptor preview available.</pre><div class="twocol"><div class="field"><label for="mliCsvDelim">Descriptor delimiter</label><select id="mliCsvDelim"><option value=";">;</option><option value=",">,</option><option value="tab">tab</option><option value="space">space</option></select></div><div class="field"><label for="mliCsvId">ROI ID column</label><input id="mliCsvId" class="textInput" type="text"></div></div><div class="field"><label for="mliCsvCol">ROI descriptor column</label><input id="mliCsvCol" class="textInput" type="text"></div><div class="summary" id="mliCsvImportSummary"></div></div></div></div></div></div></div></div></div>`;
    document.body.appendChild(div.firstElementChild);
    NMContextHelp.attachForm(el("mliConfigModal"), "MLI_Context_Help.html", "Interpretation help", "overview", "overview");
  }
  let activeTab="method";
  /**
   * showTab  Provide the show tab helper used by MLI subconfiguration UI panel in the training-template configurator.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function showTab(tab){activeTab=tab||"method";document.querySelectorAll("[data-mli-tab]").forEach(b=>b.classList.toggle("active",b.dataset.mliTab===activeTab));["method","map","norm","atlas"].forEach(t=>setHidden("mliPane_"+t,t!==activeTab));}
  /**
   * render  Render the render UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function render(S){createModal();let m=MLI(S);let sm=el("mliSummary");if(sm)sm.textContent=summaryText(S);let scope=el("mliScopeInfo");if(scope)scope.textContent=api.activeModalityHeader();
    setVal("mliMethod",m.mliMethod);setHidden("mliPosNegBlock",m.mliMethod!=="posneg");setVal("mliUpperThresh",num(m.mliUpperThresh,95));setVal("mliLowerThresh",num(m.mliLowerThresh,5));setVal("mliNPermsText",m.mliNPermsText);setHidden("mliAutoStopBlock",!(isInfText(m.mliNPermsText)&&!m.mliMethod==="shapley"));setVal("mliNVisited",num(m.mliNVisited,100));setVal("mliMaxIter",num(m.mliMaxIter,1000));
    setHidden("mliFeatureFracField",m.mliMethod==="shapley");setVal("mliFeatureFrac",num(m.mliFeatureFrac,0.1));setHidden("mliSampleFracField",!m.mliMethod==="shapley");setVal("mliSampleFrac",num(m.mliSampleFrac,0.25));setChk("mliMapFlag",m.mliMapFlag);setHidden("mliMapDetails",!m.mliMapFlag);setVal("mliMapMap",m.mliMapMap);setVal("mliMapCutoffText",m.mliMapCutoffText);setVal("mliMapPercentMode",m.mliMapPercentMode);fillOptions("mliMapOperator",operatorOptions(m),m.mliMapOperator);
    setHidden("mliZNormField",m.mliMethod==="shapley");setHidden("mliZNormShapleyNote",!m.mliMethod==="shapley");setVal("mliZNormData",num(m.mliZNormData,1));let img=isImaging(S);setHidden("mliAtlasUnavailable",img);setHidden("mliAtlasAvailable",!img);let atlasBtn=document.querySelector('[data-mli-tab="atlas"]');if(atlasBtn)atlasBtn.classList.toggle("hidden",!img);if(!img&&activeTab==="atlas")showTab("method");
    setChk("mliAtlasFlag",m.mliAtlasFlag);setHidden("mliAtlasDetails",!m.mliAtlasFlag);setVal("mliAtlasFile",m.mliAtlasFile);let as=el("mliAtlasImportSummary");if(as)as.textContent=m.mliAtlasImportSummary;setVal("mliCsvFile",m.mliCsvFile);setVal("mliCsvDelim",m.mliCsvDelim);setVal("mliCsvId",m.mliCsvId);setVal("mliCsvCol",m.mliCsvCol);
    let ps=el("mliCsvPreviewSummary");if(ps)ps.textContent=m.mliCsvPreviewSummary ? m.mliCsvPreviewSummary : (m.mliCsvFile ? "No descriptor preview available. Use Preview current descriptor file after changing delimiter settings." : "No atlas descriptor preview available.");let cs=el("mliCsvImportSummary");if(cs)cs.textContent=m.mliCsvImportSummary ? m.mliCsvImportSummary : "No atlas descriptor file imported.";showTab(activeTab);}
  /**
   * postService  Provide the post service helper used by MLI subconfiguration UI panel in the training-template configurator.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function postService(operation,extra,timeout){let S=api.getState(),changedPaths=api.changedPathsFor(operation==="train_template_refresh_mli"?"":"mli");await fetch(api.API("/api/current"),{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(S)}).catch(()=>{});let res=await fetch(api.API("/api/matlabservice"),{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(Object.assign({operation:operation,state:S,changedPaths:changedPaths,includeCanvas:!(api.deferCanvas&&api.deferCanvas()),timeout:timeout||120},extra||{}))}).then(r=>r.json());let updated=false;if(res&&res.state&&typeof res.state==="object"){api.setState(res.state);updated=true;}else if(res&&res.mli&&typeof res.mli==="object"){api.getState().mli=res.mli;updated=true;}if(res&&res.ok!==false)api.clearChangedPaths(changedPaths);if((res&&res.canvasDirty||(res&&res.state&&res.state.canvasDirty))&&api.markCanvasDirty){api.markCanvasDirty(res.canvasDirtyReason||(res.state&&res.state.canvasDirtyReason)||"Canvas refresh pending.");if(api.scheduleCanvasRefresh)api.scheduleCanvasRefresh(150);}let S2=api.getState();render(S2);if(updated){await fetch(api.API("/api/current"),{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(S2)}).catch(()=>{});api.sync();}if(res&&res.error)throw new Error(res.error);if(!res||res.ok===false)throw new Error((res&&res.message)||"MATLAB service request failed.");return res;}
  /**
   * refresh  Refresh the refresh page region after state or artifact availability changes.
   * It supports MLI subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  async function refresh(){try{await postService("train_template_refresh_mli",{},60);}catch(e){mliStatus("Interpretable ML state refresh failed: "+e.message,"danger");}}
  /**
   * apply  Apply the apply change to local browser state or visible controls.
   * It supports MLI subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  async function apply(){return postService("train_template_apply_mli",{},120).then(()=>{window.NMUIMessageTools.clearMessage("nm-mli");return true;},e=>{mliStatus("Interpretable ML configuration could not be applied: "+e.message,"danger");return false;});}
  /**
   * pickPath  Provide the pick path helper used by MLI subconfiguration UI panel in the training-template configurator.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function pickPath(kind,filter,initial){let res=await fetch(api.API("/api/pickpath"),{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({kind:kind||"file",multiple:false,filter:filter||"",initial:initial||"",timeout:240})}).then(r=>r.json());if(res&&res.error)throw new Error(res.error);let p=arr(res.paths);return p.length?p[0]:"";}
  /**
   * importAtlas  Provide the import atlas helper used by MLI subconfiguration UI panel in the training-template configurator.
   * It supports MLI subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  async function importAtlas(path){let S=api.getState();let m=MLI(S);if(path)m.mliAtlasFile=path;m.mliAtlasFlag=true;m.mliDirty=true;try{await postService("train_template_mli_import_atlas",{atlasFile:m.mliAtlasFile},600);}catch(e){mliStatus("Atlas image import failed: "+e.message,"danger");}}
  /**
   * previewCsv  Provide the preview csv helper used by MLI subconfiguration UI panel in the training-template configurator.
   * It supports MLI subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  async function previewCsv(path){let S=api.getState();let m=MLI(S);if(path)m.mliCsvFile=path;m.mliAtlasFlag=true;m.mliCsvImported=false;m.mliDirty=true;try{await postService("train_template_mli_preview_descriptor",{csvFile:m.mliCsvFile},120);}catch(e){mliStatus("Atlas descriptor preview failed: "+e.message,"danger");}}
  /**
   * importCsv  Provide the import csv helper used by MLI subconfiguration UI panel in the training-template configurator.
   * It supports MLI subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  async function importCsv(path){let S=api.getState();let m=MLI(S);if(path)m.mliCsvFile=path;m.mliAtlasFlag=true;m.mliDirty=true;try{await postService("train_template_mli_import_descriptor",{csvFile:m.mliCsvFile},240);}catch(e){mliStatus("Atlas descriptor import failed: "+e.message,"danger");}}
  /**
   * bindOnce  Register event handlers for the once controls.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function bindOnce(){createModal();if(el("openMLIConfig")&&!el("openMLIConfig").dataset.bound){el("openMLIConfig").dataset.bound="1";el("openMLIConfig").onclick=async()=>{if(api.getActiveEditor()){api.status("Another configuration window is already open. Return to the main configuration menu first.","warn");return;}api.setActiveEditor("mli");el("mliConfigModal").classList.add("open");render(api.getState());await refresh();};}if(el("closeMLIConfig")&&!el("closeMLIConfig").dataset.bound){el("closeMLIConfig").dataset.bound="1";el("closeMLIConfig").onclick=async()=>{if(!(await apply()))return;el("mliConfigModal").classList.remove("open");api.setActiveEditor(null);api.render();api.sync();};}document.querySelectorAll("[data-mli-tab]").forEach(b=>{if(!b.dataset.bound){b.dataset.bound="1";b.onclick=()=>showTab(b.dataset.mliTab);}});let bindings=[
    ["mliMethod","change",e=>{let S=api.getState();MLI(S).mliMethod=e.target.value;mark(S);render(S);api.sync();}],
    ["mliUpperThresh","input",e=>{let S=api.getState();MLI(S).mliUpperThresh=Number(e.target.value);mark(S);api.sync();}],
    ["mliLowerThresh","input",e=>{let S=api.getState();MLI(S).mliLowerThresh=Number(e.target.value);mark(S);api.sync();}],
    ["mliNPermsText","input",e=>{let S=api.getState();MLI(S).mliNPermsText=e.target.value;MLI(S).mliNPermsIsInf=isInfText(e.target.value);mark(S);render(S);api.sync();}],
    ["mliNVisited","input",e=>{let S=api.getState();MLI(S).mliNVisited=Number(e.target.value);mark(S);api.sync();}],
    ["mliMaxIter","input",e=>{let S=api.getState();MLI(S).mliMaxIter=Number(e.target.value);mark(S);api.sync();}],
    ["mliFeatureFrac","input",e=>{let S=api.getState();MLI(S).mliFeatureFrac=Number(e.target.value);mark(S);api.sync();}],
    ["mliSampleFrac","input",e=>{let S=api.getState();MLI(S).mliSampleFrac=Number(e.target.value);mark(S);api.sync();}],
    ["mliMapFlag","change",e=>{let S=api.getState();MLI(S).mliMapFlag=!!e.target.checked;mark(S);render(S);api.sync();}],
    ["mliMapMap","change",e=>{let S=api.getState();MLI(S).mliMapMap=e.target.value;mark(S);api.sync();}],
    ["mliMapCutoffText","input",e=>{let S=api.getState();MLI(S).mliMapCutoffText=e.target.value;mark(S);render(S);api.sync();}],
    ["mliMapPercentMode","change",e=>{let S=api.getState();MLI(S).mliMapPercentMode=e.target.value;mark(S);api.sync();}],
    ["mliMapOperator","change",e=>{let S=api.getState();MLI(S).mliMapOperator=Number(e.target.value);mark(S);api.sync();}],
    ["mliZNormData","change",e=>{let S=api.getState();MLI(S).mliZNormData=Number(e.target.value);mark(S);api.sync();}],
    ["mliAtlasFlag","change",e=>{let S=api.getState();MLI(S).mliAtlasFlag=!!e.target.checked;mark(S);render(S);api.sync();}],
    ["mliAtlasFile","input",e=>{let S=api.getState();MLI(S).mliAtlasFile=e.target.value;MLI(S).mliAtlasImported=false;mark(S);api.sync();}],
    ["mliCsvFile","input",e=>{let S=api.getState();MLI(S).mliCsvFile=e.target.value;MLI(S).mliCsvImported=false;mark(S);api.sync();}],
    ["mliCsvDelim","change",e=>{let S=api.getState();MLI(S).mliCsvDelim=e.target.value;MLI(S).mliCsvImported=false;mark(S);api.sync();if(MLI(S).mliCsvFile)previewCsv(MLI(S).mliCsvFile);}],
    ["mliCsvId","input",e=>{let S=api.getState();MLI(S).mliCsvId=e.target.value;MLI(S).mliCsvImported=false;mark(S);api.sync();}],
    ["mliCsvCol","input",e=>{let S=api.getState();MLI(S).mliCsvCol=e.target.value;MLI(S).mliCsvImported=false;mark(S);api.sync();}]
  ];bindings.forEach(b=>{let x=el(b[0]);if(x&&!x.dataset.bound){x.dataset.bound="1";x.addEventListener(b[1],b[2]);}});let pa=el("mliPickAtlas");if(pa&&!pa.dataset.bound){pa.dataset.bound="1";pa.onclick=async()=>{try{let p=await pickPath("file","*.nii;*.nii.gz;*.img;*.hdr;*.gii;*.mgz;*.mgh;*.surf;*.curv;*.annot",MLI(api.getState()).mliAtlasFile||"");if(p)await importAtlas(p);}catch(e){mliStatus("Atlas path selection failed: "+e.message,"danger");}};}let ia=el("mliImportAtlas");if(ia&&!ia.dataset.bound){ia.dataset.bound="1";ia.onclick=()=>importAtlas(MLI(api.getState()).mliAtlasFile||"");}let pc=el("mliPickCsv");if(pc&&!pc.dataset.bound){pc.dataset.bound="1";pc.onclick=async()=>{try{let p=await pickPath("file","*.txt;*.dat;*.csv",MLI(api.getState()).mliCsvFile||"");if(p){let S=api.getState();MLI(S).mliCsvFile=p;MLI(S).mliCsvImported=false;render(S);await previewCsv(p);}}catch(e){mliStatus("Descriptor path selection failed: "+e.message,"danger");}};}let vp=el("mliPreviewCsv");if(vp&&!vp.dataset.bound){vp.dataset.bound="1";vp.onclick=()=>previewCsv(MLI(api.getState()).mliCsvFile||"");}let ic=el("mliImportCsv");if(ic&&!ic.dataset.bound){ic.dataset.bound="1";ic.onclick=()=>importCsv(MLI(api.getState()).mliCsvFile||"");}}
  window.NMMLIUI={attach:function(a){api=a;createModal();bindOnce();},renderSummary:function(S){createModal();bindOnce();render(S);},apply:apply};
})();
