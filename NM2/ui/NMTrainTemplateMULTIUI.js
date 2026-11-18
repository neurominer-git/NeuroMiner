(function(){
  "use strict";
  let api=null;
  /**
   * Multi  Provide the multi helper used by multi-group/ensemble subconfiguration UI panel in the training-template configurator.
   * It supports multi-group/ensemble subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function Multi(S){S.multi=S.multi||{};return S.multi;}
  /**
   * el  Return a DOM element by id for the current UI page.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function el(id){return document.getElementById(id);}
  /**
   * num  Provide the num helper used by multi-group/ensemble subconfiguration UI panel in the training-template configurator.
   * It supports multi-group/ensemble subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function num(x,d){let v=Number(x);return Number.isFinite(v)?v:d;}
  /**
   * setHidden  Provide the set hidden helper used by multi-group/ensemble subconfiguration UI panel in the training-template configurator.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function setHidden(id,tf){let e=el(id);if(e)e.classList.toggle("hidden",!!tf);}
  /**
   * setChk  Provide the set chk helper used by multi-group/ensemble subconfiguration UI panel in the training-template configurator.
   * It supports multi-group/ensemble subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setChk(id,v){let e=el(id);if(e)e.checked=!!v;}
  /**
   * setVal  Provide the set val helper used by multi-group/ensemble subconfiguration UI panel in the training-template configurator.
   * It supports multi-group/ensemble subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setVal(id,v){let e=el(id);if(e)e.value=String(v==null?"":v);}
  /**
   * mark  Provide the mark helper used by multi-group/ensemble subconfiguration UI panel in the training-template configurator.
   * It supports multi-group/ensemble subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function mark(S){Multi(S).multiDirty=true;}
  /**
   * available  Provide the available helper used by multi-group/ensemble subconfiguration UI panel in the training-template configurator.
   * It supports multi-group/ensemble subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function available(S){return (typeof S.isMultiClassProblem==="boolean")?!!S.isMultiClassProblem:!!Multi(S).multiAvailable;}
  /**
   * methodLabel  Build the method label shown to users in the browser UI.
   * It supports multi-group/ensemble subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function methodLabel(v){v=num(v,2);return v===1?"Simple pairwise decoding":(v===3?"Directed acyclic graph":"Error-correcting output codes");}
  /**
   * summaryText  Build the summary text shown to users in the browser UI.
   * It supports multi-group/ensemble subconfiguration UI panel in the training-template configurator at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function summaryText(S){let m=Multi(S);if(!available(S))return "Binary or regression problem: multi-class configuration unavailable.";let n=num(m.multiClassCount,0);if(!m.multiFlag)return `Multi-class problem detected (${n} classes); multi-class predictor disabled.`;let train=m.multiTrain?"multi-class optimized":"binary-optimized";return `Multi-class predictor enabled (${n} classes): ${methodLabel(m.multiMethod)}; ${train}.`;}
  /**
   * createModal  Create the modal component or browser-side state object.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function createModal(){
    if(el("multiConfigModal"))return;
    const div=document.createElement("div");
    div.innerHTML=`<div class="selectorModal" id="multiConfigModal"><div class="selectorBox wide"><div class="selectorHead"><div><b>Multi-class configuration</b><div class="muted"></div></div><button id="closeMULTIConfig" type="button">Close</button></div><div class="selectorBody"><div id="multiScopeInfo" class="summary">NM.TrainParam.MULTI</div><div class="rfeMini"><h3>Availability</h3><div class="summary" id="multiClassInfo">Multi-class status unknown.</div></div><div class="rfeMini"><h3>Training</h3><div class="field"><label><input id="multiFlag" type="checkbox"> Train multi-class predictor</label></div><div id="multiOptions"><div class="field"><label><input id="multiTrain" type="checkbox"> Optimize NM training process for multi-group classification performance</label></div><div class="field" id="multiBinBindField"><label><input id="multiBinBind" type="checkbox"> Bind multi-class optimum to binary classifiers' optimal hyperparameters</label><div class="muted">Visible only when multi-class optimization is disabled, matching nk_Multi_config.</div></div></div></div><div class="rfeMini" id="multiDecisionBlock"><h3>Decision mechanism</h3><div class="field"><label for="multiMethod">Multi-class decision method</label><select id="multiMethod"><option value="1">Simple pairwise decoding (maximum-wins)</option><option value="2">Error-correcting output codes</option></select><div class="muted" id="multiDagHint">DAG is hidden when RAND.Decompose == 2.</div></div><div class="field" id="multiDecisionTypeField"><label for="multiDecisionType">Pairwise decision type</label><select id="multiDecisionType"><option value="1">Sum of decision values</option><option value="2">Mean of decision values</option><option value="3">Product of decision values</option><option value="4">Majority voting</option><option value="5">Median of decision values</option></select></div><div class="field" id="multiDecodingField"><label for="multiDecoding">ECOC decoding method</label><select id="multiDecoding"><option value="1">Hamming distance</option><option value="2">Euclidean distance</option><option value="3">Laplacian decoding</option><option value="4">Attenuated euclidean distance</option><option value="5">Linear loss-based decoding</option></select><div class="muted">Coding is fixed to pairwise, as in the legacy configurator.</div></div></div><div class="summary" id="multiSummaryModal">Multi-class configuration unavailable.</div></div></div></div>`;
    document.body.appendChild(div.firstElementChild);
  }
  /**
   * renderMethodOptions  Render the method options UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderMethodOptions(S){let m=Multi(S),sel=el("multiMethod");if(!sel)return;let cur=num(m.multiMethod,2);let hasDag=[...sel.options].some(o=>Number(o.value)===3);if(m.multiDagAvailable&&!hasDag){let o=document.createElement("option");o.value="3";o.textContent="Directed acyclic graph";sel.appendChild(o);}else if(!m.multiDagAvailable&&hasDag){[...sel.options].filter(o=>Number(o.value)===3).forEach(o=>o.remove());if(cur===3){cur=2;m.multiMethod=2;}}
    sel.value=String(cur);
  }
  /**
   * render  Render the render UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function render(S){createModal();let m=Multi(S);renderSummary(S);let scope=el("multiScopeInfo");if(scope)scope.textContent=m.multiScope||"NM.TrainParam.MULTI";let ci=el("multiClassInfo");if(ci){let labels=Array.isArray(m.multiClassLabels)?m.multiClassLabels.join(", "):"";ci.textContent=available(S)?`Detected ${num(m.multiClassCount,0)} classes${labels?": "+labels:""}.`:"Multi-class configuration is available only for classification with more than two non-missing classes.";}setChk("multiFlag",m.multiFlag);setHidden("multiOptions",!m.multiFlag);setHidden("multiDecisionBlock",!m.multiFlag);setChk("multiTrain",m.multiTrain);setHidden("multiBinBindField",!!m.multiTrain);setChk("multiBinBind",m.multiBinBind);renderMethodOptions(S);let method=num(m.multiMethod,2);setHidden("multiDecisionTypeField",method!==1);setHidden("multiDecodingField",method!==2);setVal("multiDecisionType",num(m.multiDecisionType,1));setVal("multiDecoding",num(m.multiDecoding,1));let hint=el("multiDagHint");if(hint)hint.textContent=m.multiDagAvailable?"DAG is available for the current cross-validation decomposition.":"DAG is hidden because RAND.Decompose == 2.";let sm=el("multiSummaryModal");if(sm)sm.textContent=summaryText(S);}
  /**
   * renderSummary  Render the summary UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderSummary(S){let m=Multi(S);let can=available(S);setHidden("multiField",!can);setHidden("openMULTIConfig",!can);let sm=el("multiSummary");if(sm)sm.textContent=summaryText(S);}
  /**
   * bindOnce  Register event handlers for the once controls.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function bindOnce(){createModal();let open=el("openMULTIConfig");if(open&&!open.dataset.bound){open.dataset.bound="1";open.onclick=()=>{let S=api.getState();if(api.getActiveEditor()){api.status("Another configuration window is already open. Return to the main configuration menu first.","warn");return;}if(!available(S)){api.status("Multi-class configuration is available only when more than two classes are detected in the active label vector.","warn");return;}api.setActiveEditor("multi");el("multiConfigModal").classList.add("open");render(S);};}
    let close=el("closeMULTIConfig");if(close&&!close.dataset.bound){close.dataset.bound="1";close.onclick=async()=>{if(!(await apply()))return;el("multiConfigModal").classList.remove("open");api.setActiveEditor(null);api.render();api.sync();};}
    [["multiFlag","change",e=>{let S=api.getState();Multi(S).multiFlag=!!e.target.checked;mark(S);render(S);api.sync();}], ["multiTrain","change",e=>{let S=api.getState();let m=Multi(S);m.multiTrain=!!e.target.checked;if(m.multiTrain)m.multiBinBind=false;mark(S);render(S);api.sync();}], ["multiBinBind","change",e=>{let S=api.getState();Multi(S).multiBinBind=!!e.target.checked;mark(S);api.sync();}], ["multiMethod","change",e=>{let S=api.getState();let m=Multi(S);m.multiMethod=Number(e.target.value);if(m.multiMethod===2)m.multiCoding=1;mark(S);render(S);api.sync();}], ["multiDecisionType","change",e=>{let S=api.getState();Multi(S).multiDecisionType=Number(e.target.value);mark(S);api.sync();}], ["multiDecoding","change",e=>{let S=api.getState();Multi(S).multiDecoding=Number(e.target.value);Multi(S).multiCoding=1;mark(S);api.sync();}]].forEach(b=>{let x=el(b[0]);if(x&&!x.dataset.bound){x.dataset.bound="1";x.addEventListener(b[1],b[2]);}});
  }
  /**
   * apply  Apply the apply change to local browser state or visible controls.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function apply() {
    let S = api.getState();
    let changedPaths = api.changedPathsFor("multi");
    return fetch(api.API("/api/current"), {
      method: "POST", headers: {"Content-Type":"application/json"}, body: JSON.stringify(S)
    }).then(() => fetch(api.API("/api/matlabservice"), {
      method: "POST", headers: {"Content-Type":"application/json"},
      body: JSON.stringify({operation:"train_template_apply_multi", state:S,
        changedPaths:changedPaths, includeCanvas:!(api.deferCanvas&&api.deferCanvas()), timeout:60})
    })).then(r => r.json()).then(res => {
      if (res && res.error) {
        api.status(res.error, "danger");
        return false;
      }
      if (!res || res.ok === false) {
        let message = "Multi-class configuration could not be applied.";
        if (res && res.message) message = res.message;
        api.status(message, "danger");
        return false;
      }
      if (res.state) api.setState(res.state);
      else if (res.multi) api.getState().multi = res.multi;
      api.clearChangedPaths(changedPaths);
      if ((res.canvasDirty || (res.state && res.state.canvasDirty)) && api.markCanvasDirty) {
        let reason = res.canvasDirtyReason;
        if (!reason && res.state) reason = res.state.canvasDirtyReason;
        if (!reason) reason = "Canvas refresh pending.";
        api.markCanvasDirty(reason);
        if (api.scheduleCanvasRefresh) api.scheduleCanvasRefresh(150);
      }
      return true;
    }).then(ok => ok, e => {
      api.status("Multi-class configuration could not be applied: " + e.message, "danger");
      return false;
    });
  }
  window.NMMULTIUI={attach:function(a){api=a;createModal();bindOnce();},renderSummary:function(S){createModal();bindOnce();renderSummary(S);},apply:apply};
})();
