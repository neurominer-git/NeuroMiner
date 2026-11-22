let SPEC=null,STATE=null,WORKSPACE=[],ACTIVE_STAGE="cv",ACTIVE={subject:0,cv:0},BRIDGE_OK=false,VIEW={kind:"step"},ML_CONTEXT_HELP=null,PREPROC_CONTEXT_HELP=null;
let RULE_PROJECTION={subject:{facts:[],spatialExtractorGate:{}},cv:{facts:[],spatialExtractorGate:{}},errors:[],warnings:[],ok:true};
let RULE_REFRESH_CHAIN=Promise.resolve(RULE_PROJECTION);
let NM2_NAV_REVISION=0,NM2_NAV_LAST="",NM2_PARENT_NAV={};
const URL_PARAMS=new URLSearchParams(location.search);
const PORT=URL_PARAMS.get("port")||"4821";
const MODULE=URL_PARAMS.get("module")||"";
const EMBEDDED_UI=URL_PARAMS.get("embedded")==="1";
const FORCE_NONIMAGING=URL_PARAMS.get("forceNonImaging")==="1";
const FUSION_MIXED=URL_PARAMS.get("fusionMixed")==="1";
const FOCUS_STAGE=String(URL_PARAMS.get("focusStage")||"").toLowerCase();
const FOCUS_MODULE=String(URL_PARAMS.get("focusModule")||"").toLowerCase();
const FOCUS_STEP=Number(URL_PARAMS.get("focusStep")||"");
const RESTORE_NAV=URL_PARAMS.get("restoreNav")==="1";
if(EMBEDDED_UI)document.body.classList.add("embedded");
/**
 * API  Build an absolute local HTTP bridge URL for a browser request.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
const API=p=>{let sep=p.indexOf("?")>=0?"&":"?";let q=`port=${encodeURIComponent(PORT)}`;if(MODULE)q+=`&module=${encodeURIComponent(MODULE)}`;let u=`http://127.0.0.1:${PORT}${p}${sep}${q}`;return window.NMBridgeAuthenticatedURL?window.NMBridgeAuthenticatedURL(u):u;};
/**
 * arr  Normalize a nullable scalar or array-like value to an array.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function arr(x){if(Array.isArray(x))return x;if(x===undefined||x===null)return [];return [x];}
/**
 * ensureStagedState  Ensure the staged state prerequisite exists before downstream rendering or requests.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function ensureStagedState(){if(!STATE)STATE={}; if(!STATE.subject)STATE.subject={executionStage:"subject",sequence:{steps:[]}}; if(!STATE.cv){STATE.cv={executionStage:"cv",sequence:STATE.sequence||{steps:[]}};} if(!STATE.subject.sequence)STATE.subject.sequence={steps:[]}; if(!STATE.cv.sequence)STATE.cv.sequence={steps:[]}; if(!Array.isArray(STATE.subject.sequence.steps))STATE.subject.sequence.steps=arr(STATE.subject.sequence.steps); if(!Array.isArray(STATE.cv.sequence.steps))STATE.cv.sequence.steps=arr(STATE.cv.sequence.steps); STATE.sequence=STATE.cv.sequence;}
/**
 * ensureGlobalState  Ensure the global state prerequisite exists before downstream rendering or requests.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function ensureGlobalState(){ensureStagedState();STATE.global ??= clone(Object.assign({},SPEC && SPEC.globalOptions && SPEC.globalOptions.defaultState));return STATE.global;}
/** OOCV application editing policy projected by the MATLAB authority. */
function editPolicy(){return (SPEC&&SPEC.editPolicy)||{};}
function isOOCVApplicationMode(){return String(editPolicy().mode||"").toLowerCase()==="oocv_application";}
function globalOptionsLocked(){return !!editPolicy().lockGlobalOptions;}
function allowedModulesForStage(stage){let by=(editPolicy().allowedModulesByStage||{});return arr(by[stage]).map(canon);}
function moduleAllowedByPolicy(stage,id){return !isOOCVApplicationMode()||allowedModulesForStage(stage).includes(canon(id));}
function applicationModulePresent(stage,id){return isOOCVApplicationMode()&&getSteps(stage).some(st=>!stepInherited(st)&&canon(st&&st.moduleId)===canon(id));}
function stepInherited(st){return isOOCVApplicationMode()&&String((st&&st.editRole)||"").toLowerCase()==="inherited";}
function stepEditable(stage,i){let st=getSteps(stage)[i];return !!st&&!stepInherited(st);}
function applicationLabelSpec(){return ((SPEC&&SPEC.applicationOptions&&SPEC.applicationOptions.labelImpute)||{});}
function applicationLabelState(){ensureStagedState();if(!STATE.applicationOptions||typeof STATE.applicationOptions!=="object")STATE.applicationOptions={};let li=STATE.applicationOptions.labelImpute;if(!li||typeof li!=="object")li={};let sp=applicationLabelSpec().moduleSpec||{};let cfg=Object.assign(defaults(sp),li.config||{});li={active:!!li.active,config:cfg};STATE.applicationOptions.labelImpute=li;return li;}
function applicationLabelVisible(){if(!isOOCVApplicationMode())return false;let sp=applicationLabelSpec(),st=applicationLabelState();return !!sp.available||!!st.active;}
function setApplicationLabelActive(tf){let st=applicationLabelState();st.active=!!tf;if(tf&&labelImputeMethod(st.config)==="none"){st.config.method="manhattan";st.config.k=labelImputeK(st.config);}}
function readonlyFieldset(){let fs=document.createElement("fieldset");fs.disabled=true;fs.style.cssText="border:0;padding:0;margin:0;min-width:0";return fs;}
/**
 * isLabelImputeId  Return whether the is label impute id condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function isLabelImputeId(id){return canon(id)==="labelimpute";}
/**
 * isLabelImputeStep  Return whether the is label impute step condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function isLabelImputeStep(st){return !!st&&isLabelImputeId(st.moduleId);}
/**
 * labelImputeMethod  Provide the label impute method helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 * cfg.LABELIMPUTE: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.method: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 */
function labelImputeMethod(cfg){cfg=cfg||{};let m=(cfg.method!==undefined?cfg.method:(cfg.LABELIMPUTE&&cfg.LABELIMPUTE.method));return canon(m||"none");}
/**
 * labelImputeK  Provide the label impute k helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 * cfg.LABELIMPUTE: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.k: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 */
function labelImputeK(cfg){cfg=cfg||{};let k=(cfg.k!==undefined?cfg.k:(cfg.LABELIMPUTE&&cfg.LABELIMPUTE.k));k=Number(k);return Number.isFinite(k)&&k>0?Math.round(k):7;}
/**
 * labelImputeStepFromGlobal  Provide the label impute step from global helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function labelImputeStepFromGlobal(){let g=ensureGlobalState();let sp=moduleSpec("labelimpute","cv");let cfg=Object.assign(defaults(sp),{method:g.labelImputeMethod||"none",k:labelImputeK({k:g.labelImputeK})});return {moduleId:"labelimpute",enabled:true,config:cfg};}
/**
 * hasCVLabelImpute  Return whether the has cvlabel impute condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function hasCVLabelImpute(){return getSteps("cv").some(isLabelImputeStep);}
/**
 * globalLabelImputeSpec  Provide the global label impute spec helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function globalLabelImputeSpec(){return ((SPEC&&SPEC.globalOptions&&SPEC.globalOptions.labelImpute)||{});}
/**
 * globalLabelImputeAvailable  Provide the global label impute available helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function globalLabelImputeAvailable(){return !!globalLabelImputeSpec().available;}
/**
 * globalLabelImputeActive  Provide the global label impute active helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function globalLabelImputeActive(){let g=ensureGlobalState();return !!g.enableLabelImpute&&labelImputeMethod({method:g.labelImputeMethod})==="none";}
/**
 * setGlobalLabelImputeActive  Provide the set global label impute active helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function setGlobalLabelImputeActive(tf){let g=ensureGlobalState();g.enableLabelImpute=!!tf;g.labelImputeMethod="none";if(!g.labelImputeK)g.labelImputeK=7;markChildChangedPath("global.enableLabelImpute","global.labelImputeMethod","global.labelImputeK");}
/**
 * canOfferGlobalLabelImpute  Return whether the can offer global label impute condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canOfferGlobalLabelImpute(){return globalLabelImputeAvailable()&&!globalLabelImputeActive()&&!hasCVLabelImpute();}
/**
 * globalTargetSpec  Provide the global target spec helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function globalTargetSpec(){return ((SPEC&&SPEC.globalOptions&&SPEC.globalOptions.targetTransform)||{});}
/**
 * globalTargetAvailable  Provide the global target available helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function globalTargetAvailable(){return !!globalTargetSpec().available;}
/**
 * globalTargetActive  Provide the global target active helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function globalTargetActive(){let g=ensureGlobalState();return !!g.enableTargetTransform||!!g.targetScale||!!g.usePolynomial;}
/**
 * setGlobalTargetActive  Provide the set global target active helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function setGlobalTargetActive(tf){let g=ensureGlobalState();g.enableTargetTransform=!!tf;if(!tf){g.targetScale=false;g.usePolynomial=false;g.polynomial=1;}else if(g.polynomial===undefined||g.polynomial===null){g.polynomial=1;}markChildChangedPath("global.enableTargetTransform","global.targetScale","global.usePolynomial","global.polynomial");}
/**
 * canOfferGlobalTarget  Return whether the can offer global target condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canOfferGlobalTarget(){return globalTargetAvailable()&&!globalTargetActive();}
/**
 * normalizeLabelImputePlacementUI  Normalize label impute placement ui payloads into the browser-side model used by the UI.
 * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
 */
function normalizeLabelImputePlacementUI(){ensureStagedState();let changed=false;let g=ensureGlobalState();let cv=getSteps("cv").slice();let movedToGlobal=false;for(let i=cv.length-1;i>=0;i--){let st=cv[i];if(isLabelImputeStep(st)&&labelImputeMethod(st.config)==="none"){setGlobalLabelImputeActive(true);g.labelImputeK=labelImputeK(st.config);cv.splice(i,1);changed=true;movedToGlobal=true;}}let method=labelImputeMethod({method:g.labelImputeMethod});if(g.enableLabelImpute&&method!=="none"){let st=labelImputeStepFromGlobal();let idx=cv.findIndex(isLabelImputeStep);if(idx<0){idx=cv.length;cv.push(st);}else{cv[idx].config=st.config;}setGlobalLabelImputeActive(false);changed=true;}if(g.enableLabelImpute&&cv.some(isLabelImputeStep)){setGlobalLabelImputeActive(false);changed=true;showWarning("Global label imputation was disabled because a CV-bound label-imputation step is already present.");}if(changed){getStageState("cv").sequence.steps=cv;markChildChangedPath("cv.sequence.steps","global.enableLabelImpute","global.labelImputeMethod","global.labelImputeK");syncLegacySequence();if(movedToGlobal)showWarning("Label-imputation method none was moved to the global/final label-handling area because it belongs outside the CV-bound preprocessing sequence.");}return changed;}
/**
 * getStageState  Provide the get stage state helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function getStageState(stage){ensureStagedState();return stage==="subject"?STATE.subject:STATE.cv;}
/**
 * getSteps  Provide the get steps helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function getSteps(stage){stage=stage||ACTIVE_STAGE;let ss=getStageState(stage);return ss.sequence.steps;}
/**
 * canon  Return whether the canon condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canon(id){return String(id||"").toLowerCase();}
/**
 * moduleInfo  Provide the module info helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function moduleInfo(id){return arr(SPEC.allModules).find(m=>canon(m.id)===canon(id))||{id:id,displayName:id};}
/**
 * moduleSpec  Provide the module spec helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function moduleSpec(id,stage){let src=stage?stageSpec(stage):SPEC;return arr(src.moduleSpecs||SPEC.moduleSpecs).find(m=>canon(m.id)===canon(id));}
/**
 * stageSpec  Provide the stage spec helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function stageSpec(stage){return (SPEC.stageSpecs&&SPEC.stageSpecs[stage])?SPEC.stageSpecs[stage]:SPEC;}
/** MATLAB-owned derived preprocessing-rule facts for one stage. */
function seedRuleProjectionFromSpec(){
    ["subject","cv"].forEach(stage=>{let sp=stageSpec(stage)||{};RULE_PROJECTION[stage]={facts:arr(sp.resolvedStepFacts),spatialExtractorGate:clone(sp.spatialExtractorGate||{})};});
    RULE_PROJECTION.errors=[...new Set(["subject","cv"].flatMap(stage=>arr(RULE_PROJECTION[stage].facts).map(f=>String((f&&f.mixedEarlyFusionReason)||"")).filter(Boolean)))];RULE_PROJECTION.warnings=[];RULE_PROJECTION.ok=!RULE_PROJECTION.errors.length;
}
function setRuleProjection(p){
    if(!p||typeof p!=="object")return;
    ["subject","cv"].forEach(stage=>{let src=p[stage];RULE_PROJECTION[stage]={facts:arr(src.facts),spatialExtractorGate:clone(src.spatialExtractorGate)};
        arr(src.stepIssues).forEach((issue,i)=>{let st=getSteps(stage)[i];st.invalid=!!issue.hasIssue;st.invalidSeverity=issue.severity;st.invalidReason=issue.message;});});
    RULE_PROJECTION.errors=arr(p.errors).map(String);RULE_PROJECTION.warnings=arr(p.warnings).map(String);RULE_PROJECTION.ok=p.ok!==false&&!RULE_PROJECTION.errors.length;
}
function defaultRuleFacts(stage,id){let rec=arr(stageSpec(stage).defaultRuleFacts).find(x=>canon(x&&x.id)===canon(id));return (rec&&rec.facts)||{};}
function stepRuleFacts(st){
    if(!st)return {};
    for(let stage of ["subject","cv"]){let steps=getSteps(stage),idx=steps.indexOf(st);if(idx<0)continue;let facts=arr(RULE_PROJECTION[stage]&&RULE_PROJECTION[stage].facts)[idx];if(!facts||canon(facts.moduleId)!==canon(st.moduleId))throw new Error(`MATLAB rule projection is out of sync for ${st.moduleId}.`);return facts;}
    return {};
}
function currentSpatialGate(stage){let g=RULE_PROJECTION[stage]&&RULE_PROJECTION[stage].spatialExtractorGate;return (g&&Object.keys(g).length)?g:(stageSpec(stage).spatialExtractorGate||{});}
function currentRuleState(){ensureStagedState();return {global:clone(ensureGlobalState()),subject:clone(STATE.subject),cv:clone(STATE.cv),sequence:clone(STATE.cv.sequence)};}
function requestRuleProjection(subjectSteps,cvSteps,strict){
    if(!BRIDGE_OK)return Promise.reject(new Error("MATLAB bridge is required to validate preprocessing changes."));
    let state=currentRuleState();
    if(subjectSteps!==undefined)state.subject.sequence.steps=clone(subjectSteps);
    if(cvSteps!==undefined){state.cv.sequence.steps=clone(cvSteps);state.sequence=state.cv.sequence;}
    let payload={operation:"preproc_resolve_rule_state",state:state,context:(SPEC&&SPEC.context)||{},timeout:60};
    payload.draft=strict!==true;
    let run=async()=>{let res=await postJson("/api/matlabservice",payload);if(res&&res.error)throw new Error(res.error);if(!res||res.ok===false||!res.ruleProjection)throw new Error((res&&res.message)||"MATLAB preprocessing rule projection failed.");return res.ruleProjection;};
    RULE_REFRESH_CHAIN=RULE_REFRESH_CHAIN.then(run,run);
    return RULE_REFRESH_CHAIN;
}
async function refreshRuleProjection(){let p=await requestRuleProjection();setRuleProjection(p);return p;}
/** Refresh MATLAB-owned rule facts after an accepted preprocessing-step configuration edit. */
async function refreshRulesAfterConfigEdit(){normalizeLabelImputePlacementUI();try{await refreshRuleProjection();}catch(e){showError("Preprocessing validation failed: "+e.message);return;}render();}
/** Global options need a rule refresh only when they relocate label-imputation sequence state. */
async function refreshRulesAfterGlobalConfigEdit(){if(!normalizeLabelImputePlacementUI()){render();return;}try{await refreshRuleProjection();}catch(e){showError("Preprocessing validation failed: "+e.message);return;}render();}
/**
 * hasStagedSpec  Return whether the has staged spec condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function hasStagedSpec(){return !!(SPEC.stageSpecs&&SPEC.stageSpecs.subject&&SPEC.stageSpecs.cv);}
/**
 * ruleFor  Provide the rule for helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function ruleFor(id){return arr(SPEC.rules&&SPEC.rules.modules).find(r=>canon(r.id)===canon(id))||{};}
/**
 * ctxVal  Provide the ctx val helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function ctxVal(k){let c=SPEC.context||{};return c[k];}
/**
 * setStatus  Provide the set status helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function setStatus(t,cls){window.NMUIMessageTools.setMessage(t,cls);}
/**
 * get  Provide the get helper used by preprocessing template browser editor.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function get(p){let r=await fetch(API(p),{cache:"no-store"}); if(!r.ok)throw new Error(`${p}: HTTP ${r.status}`); return await r.json();}
/**
 * post  Provide the post helper used by preprocessing template browser editor.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function post(p,o){let r=await fetch(API(p),{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(o||{})}); if(!r.ok)throw new Error(`${p}: HTTP ${r.status}`); return true;}
/**
 * postJson  Send a JSON request to the local MATLAB bridge and parse the JSON response.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function postJson(p,o){let r=await fetch(API(p),{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(o||{})});let t=await r.text().catch(()=>"");if(!r.ok)throw new Error(`${p}: HTTP ${r.status} ${t}`);try{return t?JSON.parse(t):{};}catch(e){throw new Error(`${p}: invalid JSON response from MATLAB bridge (${e.message}); response length=${t.length}; first bytes=${t.slice(0,180)}`);}}
function nextNM2NavigationRevision(){let now=Math.floor(Date.now()*1000);NM2_NAV_REVISION=Math.max(NM2_NAV_REVISION+1,now);return NM2_NAV_REVISION;}
function childNavigationState(){return Object.assign({},NM2_PARENT_NAV||{},{moduleKey:"template",subview:isMLMode()?"ml":"preproc",editorKind:isMLMode()?"ml":"preproc",editorModule:String(MODULE||""),childStage:String(ACTIVE_STAGE||""),childActive:clone(ACTIVE),childView:clone(VIEW)});}
async function persistChildNavigation(){if(!BRIDGE_OK)return;let state=childNavigationState(),key=JSON.stringify(state);if(key===NM2_NAV_LAST)return;let revision=nextNM2NavigationRevision();let r=await fetch(API("/api/nm2state"),{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({section:"navigation",revision:revision,state:state})});let out=await r.json().catch(()=>({}));if(!r.ok&&!(out&&out.stale))throw new Error(out.message||`Navigation position could not be saved: HTTP ${r.status}`);if(out&&out.stale&&Number(out.currentRevision||0)>NM2_NAV_REVISION)NM2_NAV_REVISION=Number(out.currentRevision||0);if(r.ok){NM2_NAV_LAST=key;NM2_PARENT_NAV=clone(state);}}
async function loadChildNavigation(){let r=await fetch(API("/api/nm2state?section=navigation"),{cache:"no-store"});if(!r.ok)return null;let out=await r.json();NM2_NAV_REVISION=Math.max(NM2_NAV_REVISION,Number(out.revision||0));let state=out&&out.state&&typeof out.state==="object"?out.state:null;if(state)NM2_PARENT_NAV=clone(state);return state;}
function restoreChildNavigation(nav){if(!nav||typeof nav!=="object"||String(nav.editorModule||"")!==String(MODULE||""))return false;if(isMLMode()){if(nav.childView&&typeof nav.childView==="object")VIEW=clone(nav.childView);return true;}let stage=String(nav.childStage||"").toLowerCase();if(stage==="subject"||stage==="cv")ACTIVE_STAGE=stage;if(nav.childActive&&typeof nav.childActive==="object"){ACTIVE.subject=Math.max(0,Number(nav.childActive.subject||0));ACTIVE.cv=Math.max(0,Number(nav.childActive.cv||0));}ACTIVE.subject=Math.max(0,Math.min(ACTIVE.subject,Math.max(0,getSteps("subject").length-1)));ACTIVE.cv=Math.max(0,Math.min(ACTIVE.cv,Math.max(0,getSteps("cv").length-1)));if(nav.childView&&typeof nav.childView==="object")VIEW=clone(nav.childView);return true;}
let CURRENT_CONFIG_TIMER=null,CURRENT_CONFIG_DIRTY=false;
let CURRENT_CONFIG_LAST_OBSERVED="",CURRENT_CONFIG_WRITE_CHAIN=Promise.resolve(true);
const CHILD_CHANGED_PATHS=new Set();
function markChildChangedPath(...paths){paths.flat().forEach(p=>{if(p)CHILD_CHANGED_PATHS.add(String(p));});}
function pendingChildChangedPaths(){return Array.from(CHILD_CHANGED_PATHS);}
function childStatePathForField(cfg,f,st){
    let fp=fieldPath(f);
    if(!fp)return "";
    if(isMLMode()){
        if(VIEW&&VIEW.kind==="subconfig"&&VIEW.field&&cfg!==STATE)return `${VIEW.field}.${fp}`;
        return fp;
    }
    if(st){
        let stage=ACTIVE_STAGE;
        let idx=getSteps(stage).indexOf(st);
        if(idx<0)return "";
        let base=`${stage}.sequence.steps.${idx+1}.config`;
        if(VIEW&&VIEW.kind==="subconfig"&&VIEW.field)base+=`.${VIEW.field}`;
        return `${base}.${fp}`;
    }
    try{if(cfg===ensureGlobalState())return `global.${fp}`;}catch(_){ }
    return fp;
}
let NUMERIC_EXPRESSION_COMMIT_CHAIN=Promise.resolve({ok:true});
/**
 * queueNumericExpressionCommit  Serialize focus-loss expression commits so intentional scope exit can wait for MATLAB fallback completion.
 */
function queueNumericExpressionCommit(work){
    let run=()=>Promise.resolve().then(work);
    NUMERIC_EXPRESSION_COMMIT_CHAIN=NUMERIC_EXPRESSION_COMMIT_CHAIN.then(run,run);
    return NUMERIC_EXPRESSION_COMMIT_CHAIN;
}
/**
 * currentConfigPayload  Provide the current config payload helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function currentConfigPayload(){if(isMLMode())return STATE;syncLegacySequence();return STATE;}
/**
 * syncCurrentConfigNow  Synchronize the current config now browser state with related controls.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function syncCurrentConfigNow(reason){
    if(!BRIDGE_OK||!STATE)return false;
    if(CURRENT_CONFIG_TIMER){clearTimeout(CURRENT_CONFIG_TIMER);CURRENT_CONFIG_TIMER=null;}
    let payload=clone(currentConfigPayload());
    let snapshot=JSON.stringify(payload);
    CURRENT_CONFIG_LAST_OBSERVED=snapshot;
    CURRENT_CONFIG_DIRTY=true;
    let write=async()=>{
        try{
            await postJson("/api/current",payload);
            if(snapshot===CURRENT_CONFIG_LAST_OBSERVED){
                CURRENT_CONFIG_DIRTY=false;
                if(isMLMode())window.NMUIMessageTools.clearMessage("nm-ml-save");
            }
            return true;
        }catch(e){
            if(snapshot===CURRENT_CONFIG_LAST_OBSERVED){
                CURRENT_CONFIG_DIRTY=true;
                window.NMUIMessageTools.setMessage("Current configuration could not be saved","danger",isMLMode()?"nm-ml-save":"");
            }
            console.warn("NM current_config save failed",e);
            return false;
        }
    };
    CURRENT_CONFIG_WRITE_CHAIN=CURRENT_CONFIG_WRITE_CHAIN.then(write,write);
    return CURRENT_CONFIG_WRITE_CHAIN;
}
/**
 * scheduleCurrentConfigSync  Provide the schedule current config sync helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function scheduleCurrentConfigSync(reason){
    if(!BRIDGE_OK||!STATE)return;
    let serialized=JSON.stringify(currentConfigPayload());
    if(serialized===CURRENT_CONFIG_LAST_OBSERVED)return;
    CURRENT_CONFIG_LAST_OBSERVED=serialized;
    CURRENT_CONFIG_DIRTY=true;
    if(CURRENT_CONFIG_TIMER)clearTimeout(CURRENT_CONFIG_TIMER);
    CURRENT_CONFIG_TIMER=setTimeout(()=>{CURRENT_CONFIG_TIMER=null;syncCurrentConfigNow(reason||"edit");},350);
}
/**
 * syncCurrentConfigBeacon  Synchronize the current config beacon browser state with related controls.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
function syncCurrentConfigBeacon(){try{if(!BRIDGE_OK||!STATE||!CURRENT_CONFIG_DIRTY)return;syncLegacySequence();let blob=new Blob([JSON.stringify(STATE)],{type:"application/json"});if(navigator.sendBeacon){let u=API("/api/current");if(window.NMBridgeAuthenticatedURL)u=window.NMBridgeAuthenticatedURL(u);navigator.sendBeacon(u,blob);}else fetch(API("/api/current"),{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(STATE),keepalive:true});}catch(e){}}
window.addEventListener("pagehide",syncCurrentConfigBeacon);
window.addEventListener("beforeunload",syncCurrentConfigBeacon);
document.addEventListener("change",()=>{syncCurrentConfigNow("change");});
document.addEventListener("focusout",()=>{syncCurrentConfigNow("focusout");});
/**
 * normVal  Provide the norm val helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function normVal(v){return String(v===undefined?"":v);}
/**
 * pathParts  Provide the path parts helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function pathParts(path){return String(path||"").split(".").filter(Boolean);}
/**
 * getPath  Provide the get path helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function getPath(obj,path,def){let cur=obj;if(!path)return cur;for(let p of pathParts(path)){if(cur&&typeof cur==="object"&&Object.prototype.hasOwnProperty.call(cur,p))cur=cur[p];else return def;}return cur;}
/**
 * setPath  Provide the set path helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function setPath(obj,path,val){let ps=pathParts(path);if(!ps.length)return;let cur=obj;for(let i=0;i<ps.length-1;i++){let p=ps[i];if(!cur[p]||typeof cur[p]!=="object"||Array.isArray(cur[p]))cur[p]={};cur=cur[p];}cur[ps[ps.length-1]]=val;}
/**
 * hasPath  Return whether the has path condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function hasPath(obj,path){return getPath(obj,path,undefined)!==undefined;}
/**
 * fieldPath  Provide the field path helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function fieldPath(f){return (f&&(f.path||f.name))||"";}
/**
 * enumOptions  Provide the enum options helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function enumOptions(f){
    if(!f)return [];
    if(f.values!==undefined)return arr(f.values);
    if(f.options!==undefined)return arr(f.options);
    if(f.enumValues!==undefined)return arr(f.enumValues);
    if(f.enum!==undefined)return arr(f.enum);
    return [];
}
/**
 * enumEntryValue  Provide the enum entry value helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function enumEntryValue(v){
    if(v&&typeof v==="object"&&!Array.isArray(v)){
        if(Object.prototype.hasOwnProperty.call(v,"value"))return v.value;
        if(Object.prototype.hasOwnProperty.call(v,"id"))return v.id;
        if(Object.prototype.hasOwnProperty.call(v,"name"))return v.name;
    }
    return v;
}
/**
 * enumEntryLabel  Build the enum entry label shown to users in the browser UI.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function enumEntryLabel(v){
    if(v&&typeof v==="object"&&!Array.isArray(v)){
        if(Object.prototype.hasOwnProperty.call(v,"label"))return String(v.label);
        if(Object.prototype.hasOwnProperty.call(v,"displayName"))return String(v.displayName);
        if(Object.prototype.hasOwnProperty.call(v,"text"))return String(v.text);
        if(Object.prototype.hasOwnProperty.call(v,"name")&&!Object.prototype.hasOwnProperty.call(v,"value"))return String(v.name);
    }
    let val=enumEntryValue(v);
    if(Array.isArray(val))return rangeToText(val);
    if(val===undefined||val===null)return "";
    return String(val);
}
/**
 * scalarNumericLike  Provide the scalar numeric like helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function scalarNumericLike(v){
    if(Array.isArray(v)||v===null||v===undefined||typeof v==="object")return false;
    if(typeof v==="boolean")return false;
    let n=Number(v);
    return !Number.isNaN(n);
}
/**
 * valuesEqual  Provide the values equal helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function valuesEqual(a,b){
    if(a===b)return true;
    if(scalarNumericLike(a)&&scalarNumericLike(b)){
        let na=Number(a),nb=Number(b);
        if(Number.isNaN(na)&&Number.isNaN(nb))return true;
        return na===nb;
    }
    try{return JSON.stringify(a)===JSON.stringify(b);}catch(_){return String(a)===String(b);}
}
/**
 * enumValueAt  Provide the enum value at helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function enumValueAt(f,idx){
    let opts=enumOptions(f);
    let i=Math.max(0,Math.min(Number(idx)||0,Math.max(opts.length-1,0)));
    return clone(enumEntryValue(opts[i]));
}
/**
 * fieldValue  Provide the field value helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function fieldValue(cfg,f){return getPath(cfg,fieldPath(f),undefined);}
/**
 * setFieldValue  Provide the set field value helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function setFieldValue(cfg,f,val){setPath(cfg,fieldPath(f),val);}
/**
 * visibleRuleOk  Provide the visible rule ok helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function visibleRuleOk(v,c){if(!v)return true;c=c||{};let val=v.field?normVal(getPath(c,v.field,undefined)):undefined;if(v.field){if(Object.prototype.hasOwnProperty.call(v,"equals")&&val!==normVal(v.equals))return false;if(Object.prototype.hasOwnProperty.call(v,"notEquals")&&val===normVal(v.notEquals))return false;if(v.in&&arr(v.in).map(normVal).indexOf(val)<0)return false;if(v.notIn&&arr(v.notIn).map(normVal).indexOf(val)>=0)return false;} if(v.andField){let av=normVal(getPath(c,v.andField,undefined));if(Object.prototype.hasOwnProperty.call(v,"andEquals")&&av!==normVal(v.andEquals))return false;if(Object.prototype.hasOwnProperty.call(v,"andNotEquals")&&av===normVal(v.andNotEquals))return false;if(v.andIn&&arr(v.andIn).map(normVal).indexOf(av)<0)return false;if(v.andNotIn&&arr(v.andNotIn).map(normVal).indexOf(av)>=0)return false;} if(v.nonEmptyField){let ev=getPath(c,v.nonEmptyField,undefined);if(ev===undefined||ev===null||String(ev).length===0)return false;} if(v.emptyField){let ev=getPath(c,v.emptyField,undefined);if(!(ev===undefined||ev===null||String(ev).length===0))return false;} if(v.all){for(let r of arr(v.all)){if(!visibleRuleOk(r,c))return false;}} if(v.any){let ok=false;for(let r of arr(v.any)){if(visibleRuleOk(r,c)){ok=true;break;}}if(!ok)return false;} return true;}
/**
 * fieldVisibleFor  Provide the field visible for helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function fieldVisibleFor(f,cfg){return visibleRuleOk(f&&f.visibleIf,cfg||{});}
/**
 * fieldVisible  Provide the field visible helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function fieldVisible(f,st){if(f&&f.visibleIfDownstreamExternalRanking){let stage=ACTIVE_STAGE,idx=ACTIVE[stage];if(!waveletStepNeedsExternalWeightControl(stage,idx,st,getSteps("subject"),getSteps("cv")))return false;}return fieldVisibleFor(f,(st&&st.config)||{});}
/**
 * workspaceMatches  Provide the workspace matches helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function workspaceMatches(w,f){let flt=(f&&f.workspaceFilter)||{}; if(flt.numericOnly&&!w.isNumeric)return false; if(flt.featureCompatible&&!w.featureCompatible)return false; if(flt.featureDim2EqualsContextField){let n=ctxVal(flt.featureDim2EqualsContextField); if(n!==undefined&&n!==null&&n!==""&&Number(w.dim2)!==Number(n))return false;} if(flt.columnVectorRowsFromContext){let n=ctxVal(flt.columnVectorRowsFromContext); if(n!==undefined&&n!==null&&n!==""&&!(Array.isArray(w.size)&&Number(w.size[0])===Number(n)&&Number(w.size[1])===1))return false;} if(flt.rowCountFromContext){let n=ctxVal(flt.rowCountFromContext); if(n!==undefined&&n!==null&&n!==""&&!(Array.isArray(w.size)&&Number(w.size[0])===Number(n)))return false;} return true;}
/**
 * parseNumVector  Parse a plain numeric vector for legacy preprocessing field fallbacks.
 * Prefer NMExpressionTools for MATLAB-like range expressions; this helper remains for simple whitespace/comma-delimited vectors.
 */
function parseNumVector(raw){raw=String(raw||'').trim(); if(raw==='')return []; return raw.split(/[ ,;]+/).map(x=>x.toLowerCase()==='inf'?Infinity:Number(x));}
/**
 * nmExpressionTools  Return the shared constrained numeric-expression utility.
 * Keeping this lookup local preserves existing function names while centralizing the parser implementation in NMExpressionTools.js.
 */
function nmExpressionTools(){if(window.NMExpressionTools)return window.NMExpressionTools;throw new Error('Shared numeric-expression parser asset NMExpressionTools.js is not loaded.');}
/**
 * interpretNumericExpression  Interpret a numeric expression through the shared browser parser and restricted MATLAB bridge fallback.
 */
async function interpretNumericExpression(raw,kind){return nmExpressionTools().interpretNumericExpression(raw,kind,{bridgeOk:BRIDGE_OK,matlabService:(payload)=>postJson('/api/matlabservice',payload)});}
/**
 * rangeToText  Build the range to text shown to users in the browser UI.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function rangeToText(v){if(Array.isArray(v))return v.map(x=>Number.isNaN(x)?"NaN":(x===Infinity?"Inf":(x===-Infinity?"-Inf":String(x)))).join(" ");if(v===undefined||v===null)return "";return String(v);}
/**
 * defaults  Provide the defaults helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function defaults(sp){let c={}; arr(sp&&sp.fields).forEach(f=>{setFieldValue(c,f,(f.default===undefined?null:clone(f.default)))}); return c;}
/**
 * clone  Provide the clone helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function clone(x){return JSON.parse(JSON.stringify(x));}
/**
 * isMLMode  Return whether the is mlmode condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function isMLMode(){return !!(SPEC&&(SPEC.kind==="ml-module"||(SPEC.layout&&SPEC.layout.mode==="fixed-section-cards")));}
/**
 * ensureMLState  Ensure the canonical ML browser state exists without replacing its object identity.
 * Event handlers rendered from STATE retain direct references to this object, so normalization must
 * add only missing top-level defaults in place. Replacing STATE during rendering detaches those
 * handlers from the canonical state and causes visible edits to be lost.
 */
function ensureMLState(){
    let defaultsState=SPEC&&SPEC.defaultState&&typeof SPEC.defaultState==="object"?SPEC.defaultState:{};
    if(!STATE||typeof STATE!=="object"||Array.isArray(STATE)){
        STATE=clone(defaultsState);
    }else{
        Object.keys(defaultsState).forEach(k=>{if(!Object.prototype.hasOwnProperty.call(STATE,k))STATE[k]=clone(defaultsState[k]);});
    }
    if(!STATE.algorithm&&defaultsState.algorithm)STATE.algorithm=defaultsState.algorithm;
    if(!VIEW||VIEW.kind==="step")VIEW={kind:"mlSection",section:firstVisibleMLSectionId()};
}
/**
 * firstVisibleMLSectionId  Resolve the first visible mlsection id identifier used to connect UI state with NeuroMiner payload metadata.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function firstVisibleMLSectionId(){let secs=arr(SPEC&&SPEC.layout&&SPEC.layout.sections).filter(s=>!s.uiHidden);return secs.length?secs[0].id:"criterion";}
/**
 * subSpecFor  Provide the sub spec for helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function subSpecFor(f,cfg){let key=canon(getPath(cfg,f.subconfigSelector||"algorithm",undefined)); let m=f.subconfigSpecs||{}; if(Array.isArray(m)){return m.find(x=>canon(x.id||x.name||"")===key)||null;} return m[key]||m[key.replace(/-/g,"_")]||null;}
/**
 * summarize  Provide the summarize helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function summarize(x,depth){depth=depth||0; if(x===null||x===undefined)return x; if(typeof x!=="object")return x; if(Array.isArray(x)){if(x.every(v=>typeof v==="number"||typeof v==="boolean")){return x.length>12?`<numeric/logical 1x${x.length}>`:x;} if(x.every(v=>Array.isArray(v)&&v.every(z=>typeof z==="number"||typeof z==="boolean"))){let r=x.length,c=x[0]?x[0].length:0; return (r*c>24)?`<numeric/logical ${r}x${c}>`:x;} return x.map(v=>summarize(v,depth+1));} let out={}; Object.keys(x).forEach(k=>{out[k]=depth>6?"<nested object>":summarize(x[k],depth+1)}); return out;}
/**
 * selectedIds  Apply the ed ids selection to browser state and dependent controls.
 * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
 */
function selectedIds(stage){return getSteps(stage).map(s=>canon(s.moduleId));}
/**
 * selectedIdsAll  Apply the ed ids all selection to browser state and dependent controls.
 * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
 */
function selectedIdsAll(){return selectedIds("subject").concat(selectedIds("cv"));}
/**
 * capOf  Provide the cap of helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function capOf(id){return moduleInfo(id).capabilities||{};}
/** MATLAB-owned rule fact for one current preprocessing step. */
function stepIsSpatialFeatureExtractor(st){return !!stepRuleFacts(st).isSpatialFeatureExtractor;}
/** MATLAB-owned external-weight fact for one current preprocessing step. */
function stepUsesExternalFeatureWeights(st){return !!stepRuleFacts(st).usesExternalFeatureWeights;}
/** Return whether a module's default configuration requires the spatial extractor gate. */
function idRequiresSpatialExtractorFlagForStage(id,stage){return !!defaultRuleFacts(stage,id).requiresSpatialFeatureExtractionAllowed;}
/** Return MATLAB's current insertion gate for a spatial feature extractor. */
function spatialExtractorGate(stage){return currentSpatialGate(stage);}
/** Browser availability consumes the MATLAB-owned default facts and current insertion gate. */
function moduleHasLegalSpatialFlagPosition(stage,id){if(!idRequiresSpatialExtractorFlagForStage(id,stage))return true;if(anySpatialFeatureExtractorSelected())return false;return !!spatialExtractorGate(stage).allowed;}
/** Return whether MATLAB's current rule projection contains a spatial feature extractor. */
function anySpatialFeatureExtractorSelected(){return getSteps("subject").some(stepIsSpatialFeatureExtractor)||getSteps("cv").some(stepIsSpatialFeatureExtractor);}
/** Parent-owned mixed-fusion policy lookup for a candidate module. */
function mixedEarlyFusionCandidateBlocked(stage,m){return !!defaultRuleFacts(stage,m&&m.id).mixedEarlyFusionBlocked;}
/** Return any persisted import/rehydration issue carried by a stored step. */
function storedStepIssueReason(s){return s&&s.invalidReason?s.invalidReason:"";}
/** Build the stored step issue label shown to users in the browser UI. */
function storedStepIssueLabel(s){let r=storedStepIssueReason(s);return r?r+" Remove or replace this card before using the current preprocessing setup for runtime execution.":"";}
/** Surface persisted conversion/import issues without interpreting scientific validity in JavaScript. */
function storedStepWarnings(steps){return arr(steps).filter(s=>s.invalidSeverity==="warning").map(storedStepIssueReason).filter(Boolean);}
/** Browser availability uses intrinsic capabilities plus MATLAB-owned insertion facts. */
function clientAvailable(stage,m){let mi=moduleInfo(m.id),cap=mi.capabilities||{},seq=mi.sequence||{};let id=canon(m.id);if(mixedEarlyFusionCandidateBlocked(stage,m))return false;if(FORCE_NONIMAGING&&!FUSION_MIXED&&cap.imagingOnly)return false;if(isLabelImputeId(id)){if(stage!=="cv")return false;if(globalLabelImputeActive())return false;if(selectedIds("cv").includes(id))return false;}if(cap.uniqueAcrossStages&&selectedIdsAll().includes(id))return false;if(seq.allowMultiple===false&&selectedIds(stage).includes(id))return false;if(!moduleHasLegalSpatialFlagPosition(stage,id))return false;return true;}
/** Return the parent-projected mixed-fusion issue for one current step. */
function mixedEarlyFusionIncompatibleReason(st,facts){facts=facts||stepRuleFacts(st);return String((facts&&facts.mixedEarlyFusionReason)||"");}
/**
 * stepIsWaveletSpatial  Provide the step is wavelet spatial helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function stepIsWaveletSpatial(st){return canon(st&&st.moduleId)==="waveletspatial";}
/**
 * waveletRecoAppliesToExternalWeightMap  Provide the wavelet reco applies to external weight map helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 * cfg.reconstructionMode: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 */
function waveletRecoAppliesToExternalWeightMap(cfg){let m=canon((cfg&&cfg.reconstructionMode)||"approximation");return ["approximation","denoised"].includes(m);}
/**
 * waveletRecommendedExternalWeightMap  Provide the wavelet recommended external weight map helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function waveletRecommendedExternalWeightMap(st){return waveletRecoAppliesToExternalWeightMap((st&&st.config)||{});}
/**
 * hasDownstreamExternalFeatureWeights  Return whether the has downstream external feature weights condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function hasDownstreamExternalFeatureWeights(stage,index,subjectSteps,cvSteps){subjectSteps=arr(subjectSteps===undefined?getSteps("subject"):subjectSteps);cvSteps=arr(cvSteps===undefined?getSteps("cv"):cvSteps);let downstream=[];if(stage==="subject"){downstream=subjectSteps.slice(index+1).concat(cvSteps);}else{downstream=cvSteps.slice(index+1);}return downstream.some(stepUsesExternalFeatureWeights);}
/**
 * waveletStepNeedsExternalWeightControl  Provide the wavelet step needs external weight control helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function waveletStepNeedsExternalWeightControl(stage,index,st,subjectSteps,cvSteps){return stepIsWaveletSpatial(st)&&hasDownstreamExternalFeatureWeights(stage,index,subjectSteps,cvSteps);}
/**
 * syncWaveletExternalWeightDefaults  Synchronize the wavelet external weight defaults browser state with related controls.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function syncWaveletExternalWeightDefaults(){let subjectSteps=getSteps("subject"),cvSteps=getSteps("cv");[["subject",subjectSteps],["cv",cvSteps]].forEach(pair=>{let stage=pair[0],steps=pair[1];arr(steps).forEach((st,i)=>{if(!waveletStepNeedsExternalWeightControl(stage,i,st,subjectSteps,cvSteps))return;let cfg=st.config||(st.config={});if(cfg.applyWaveletToExternalWeightMapManualOverride===undefined)cfg.applyWaveletToExternalWeightMapManualOverride=false;let rec=waveletRecommendedExternalWeightMap(st);if(cfg.applyWaveletToExternalWeightMap===undefined||cfg.applyWaveletToExternalWeightMap===null||!cfg.applyWaveletToExternalWeightMapManualOverride){cfg.applyWaveletToExternalWeightMap=rec;}});});}
/**
 * waveletExternalWeightWarnings  Provide the wavelet external weight warnings helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function waveletExternalWeightWarnings(subjectSteps,cvSteps){let warns=[];subjectSteps=arr(subjectSteps===undefined?getSteps("subject"):subjectSteps);cvSteps=arr(cvSteps===undefined?getSteps("cv"):cvSteps);[["subject",subjectSteps],["cv",cvSteps]].forEach(pair=>{let stage=pair[0],steps=pair[1];arr(steps).forEach((st,i)=>{if(!waveletStepNeedsExternalWeightControl(stage,i,st,subjectSteps,cvSteps))return;let cfg=(st&&st.config)||{};let rec=waveletRecommendedExternalWeightMap(st);let val=!!cfg.applyWaveletToExternalWeightMap;if(!!cfg.applyWaveletToExternalWeightMapManualOverride&&val!==rec){let mode=(cfg.reconstructionMode||"approximation");let auto=rec?"apply the same wavelet reconstruction to the external weighting image":"keep the external weighting image unchanged and replicate it across wavelet branches";warns.push(`Wavelet spatial reconstruction: external weighting-image handling was manually overridden for reconstruction mode ${mode}. Automatic recommendation would ${auto}.`);}});});return warns;}
/** Return MATLAB-owned preprocessing validation/policy errors. */
function projectionErrors(projection){return Array.from(new Set(arr(projection&&projection.errors).map(String)));}
/** Render MATLAB warnings plus presentation-only stored/wavelet notices. */
function projectionWarnings(projection,subjectSteps,cvSteps){return Array.from(new Set(arr(projection&&projection.warnings).map(String).concat(storedStepWarnings(subjectSteps),storedStepWarnings(cvSteps),waveletExternalWeightWarnings(subjectSteps,cvSteps))));}
/**
 * renderGlobalOptions  Render the global options UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderGlobalOptions(){let panel=document.getElementById("globalPanel"),root=document.getElementById("globalOptions");if(!panel||!root)return;let gs=(SPEC&&SPEC.globalOptions)||{};let fields=arr(gs.fields);let showLabel=globalLabelImputeAvailable()||globalLabelImputeActive();let showTarget=globalTargetAvailable()||globalTargetActive();let showApplicationLabel=applicationLabelVisible();if(!fields.length&&!showLabel&&!showTarget&&!showApplicationLabel){panel.style.display="none";return;}panel.style.display="block";let cfg=ensureGlobalState();root.innerHTML="";let desc=document.createElement("div");desc.className="muted";desc.textContent=gs.description||"";root.appendChild(desc);let inheritedRoot=root;if(globalOptionsLocked()){let note=document.createElement("div");note.className="muted";note.textContent="Inherited trained global settings — read only.";root.appendChild(note);inheritedRoot=readonlyFieldset();root.appendChild(inheritedRoot);}fields.forEach(f=>{if(!f.uiHidden&&fieldVisibleFor(f,cfg))inheritedRoot.appendChild(renderField(cfg,f,()=>{refreshRulesAfterGlobalConfigEdit();},null));});if(!globalOptionsLocked())renderGlobalAddDropdown(inheritedRoot);renderGlobalModuleCards(inheritedRoot);renderApplicationLabelImpute(root);}
/**
 * renderGlobalModuleCards  Render the global module cards UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 */
function renderGlobalModuleCards(root){if(globalTargetActive())renderGlobalTargetCard(root);if(globalLabelImputeActive())renderGlobalLabelImputeCard(root);}
/** Render the OOCV-only label-imputation option outside the trained ACTPARAM chain. */
function renderApplicationLabelImpute(root){if(!applicationLabelVisible())return;let spec=applicationLabelSpec(),st=applicationLabelState();if(st.active){let d=document.createElement("div");d.className="step"+(VIEW.kind==="applicationLabelImpute"?" active":"");d.onclick=()=>navigateFromSubconfig(()=>{showError("");VIEW={kind:"applicationLabelImpute"};render();});let method=labelImputeMethod(st.config);d.innerHTML=`<b>${spec.displayName}</b><div class="muted">OOCV application setting · fully preprocessed CV1 representation</div><div class="muted">method: ${method}</div>`;let row=document.createElement("div");row.className="row stepActionRow";row.style.marginTop="8px";row.appendChild(makeActionButton("remove","Remove label operation",()=>navigateFromSubconfig(()=>{setApplicationLabelActive(false);if(VIEW.kind==="applicationLabelImpute")VIEW={kind:"step"};showError("");render();}),false));PREPROC_CONTEXT_HELP.button(row,"preproc-workflow-application",spec.displayName);d.appendChild(row);root.appendChild(d);return;}if(spec.available){let row=document.createElement("div");row.className="row moduleToolbar applicationLabelToolbar";let label=document.createElement("span");label.className="moduleToolbarLabel";label.textContent=spec.displayName;row.appendChild(label);row.appendChild(makeActionButton("add",`Add ${spec.displayName}`,()=>navigateFromSubconfig(()=>{setApplicationLabelActive(true);VIEW={kind:"applicationLabelImpute"};showError("");render();}),false));root.appendChild(row);}}
/**
 * renderGlobalLabelImputeCard  Render the global label impute card UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderGlobalLabelImputeCard(root){let d=document.createElement("div");d.className="step"+(VIEW.kind==="globalLabelImpute"?" active":"");d.onclick=()=>navigateFromSubconfig(()=>{showError("");VIEW={kind:"globalLabelImpute"};render();});d.innerHTML=`<b>Label imputation</b><div class="muted">global / final label handling</div><div class="muted">method: none</div>`;let row=document.createElement("div");row.className="row stepActionRow";row.style.marginTop="8px";row.appendChild(makeActionButton("remove","Remove label operation",()=>navigateFromSubconfig(()=>{setGlobalLabelImputeActive(false);if(VIEW.kind==="globalLabelImpute")VIEW={kind:"step"};showError("");syncLegacySequence();render();}),false));PREPROC_CONTEXT_HELP.button(row,"preproc-workflow-global-label","Global label handling");d.appendChild(row);root.appendChild(d);}
/**
 * renderGlobalTargetCard  Render the global target card UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderGlobalTargetCard(root){let tt=globalTargetSpec();let g=ensureGlobalState();let d=document.createElement("div");d.className="step"+(VIEW.kind==="globalTargetTransform"?" active":"");d.onclick=()=>navigateFromSubconfig(()=>{showError("");VIEW={kind:"globalTargetTransform"};render();});let details=[];details.push(g.targetScale?"target scaling enabled":"target scaling disabled");if(g.usePolynomial)details.push(`exponent: ${g.polynomial||1}`);d.innerHTML=`<b>${tt.displayName}</b><div class="muted">global regression target handling</div><div class="muted">${details.join(", ")}</div>`;let row=document.createElement("div");row.className="row stepActionRow";row.style.marginTop="8px";row.appendChild(makeActionButton("remove","Remove label operation",()=>navigateFromSubconfig(()=>{setGlobalTargetActive(false);if(VIEW.kind==="globalTargetTransform")VIEW={kind:"step"};showError("");syncLegacySequence();render();}),false));PREPROC_CONTEXT_HELP.button(row,"preproc-workflow-target",tt.displayName);d.appendChild(row);root.appendChild(d);}
/**
 * renderGlobalAddDropdown  Render the global add dropdown UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderGlobalAddDropdown(root){let choices=[];if(canOfferGlobalTarget()){let tt=globalTargetSpec();choices.push({id:"targetmod",label:tt.displayName});}if(canOfferGlobalLabelImpute()){let li=globalLabelImputeSpec();choices.push({id:"labelimpute",label:li.displayName});}if(!choices.length)return;let row=document.createElement("div");row.className="row moduleToolbar globalModuleToolbar";let sel=document.createElement("select");sel.className="moduleSelect";choices.forEach(c=>{let o=document.createElement("option");o.value=c.id;o.textContent=c.label;sel.appendChild(o);});row.appendChild(sel);row.appendChild(makeActionButton("add","Add selected label operation",()=>navigateFromSubconfig(()=>{if(sel.value==="labelimpute"){setGlobalLabelImputeActive(true);VIEW={kind:"globalLabelImpute"};}else if(sel.value==="targetmod"){setGlobalTargetActive(true);VIEW={kind:"globalTargetTransform"};}showError("");syncLegacySequence();render();}),false));root.appendChild(row);}
/**
 * tryApplySteps  Provide the try apply steps helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
async function tryApplySteps(stage,steps,activeIndex,discardCurrent=false){if(!discardCurrent&&!(await exitSubconfig()))return false;let subjectSteps=(stage==="subject"?steps:getSteps("subject")),cvSteps=(stage==="cv"?steps:getSteps("cv"));return requestRuleProjection(subjectSteps,cvSteps).then(projection=>{let errs=projectionErrors(projection,subjectSteps,cvSteps);if(errs.length){showError(errs.join("\n"));return false;}getStageState(stage).sequence.steps=steps;markChildChangedPath(`${stage}.sequence.steps`);ACTIVE_STAGE=stage;ACTIVE[stage]=Math.max(0,Math.min(activeIndex,steps.length-1));setRuleProjection(projection);let warns=projectionWarnings(projection,subjectSteps,cvSteps);if(warns.length)showWarning(warns.join("\n"));else showError("");return true;},e=>{showError("Preprocessing validation failed: "+e.message);return false;});}
/**
 * initAddMenu  Provide the init add menu helper used by preprocessing template browser editor.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
const PREPROC_CATALOG_GROUPS=[
    {label:"Feature transformation",ids:["scale","standardize","unitnormalize","discsym","smoothing","waveletspatial"]},
    {label:"Feature correction",ids:["correctnuis","remmeandiff","elimzero","skewcorr","remvarcomp","impute"]},
    {label:"Feature selection / dimensionality reduction",ids:["reducedim","extdim","rankfeat","extfeat","devmap","graphcomputation","graphsparsity","graphmetrics","juspace","roimeans"]},
    {label:"Label processing",ids:["labelimpute"]}
];
const PREPROC_CATALOG_LABELS={discsym:"Discretization / symbolization",correctnuis:"Nuisance / batch effects correction",remmeandiff:"Offset correction",elimzero:"Pruning of uninformative features",remvarcomp:"Removal of variance components",rankfeat:"Feature selection & weighting",graphsparsity:"Graph sparsity"};
function catalogDisplayName(m){return PREPROC_CATALOG_LABELS[canon(m.id)]||m.displayName||m.id;}
function appendCatalogOptions(sel,mods){let byId=new Map(mods.map(m=>[canon(m.id),m]));PREPROC_CATALOG_GROUPS.forEach(group=>{let members=group.ids.map(canon).map(id=>byId.get(id)).filter(Boolean);if(!members.length)return;let optgroup=document.createElement("optgroup");optgroup.label=group.label;members.forEach(m=>{let o=document.createElement("option");o.value=m.id;o.textContent=catalogDisplayName(m);optgroup.appendChild(o);byId.delete(canon(m.id));});sel.appendChild(optgroup);});let other=Array.from(byId.values()).sort((a,b)=>String(a.displayName||a.id).localeCompare(String(b.displayName||b.id)));if(other.length){let optgroup=document.createElement("optgroup");optgroup.label="Other";other.forEach(m=>{let o=document.createElement("option");o.value=m.id;o.textContent=m.displayName||m.id;optgroup.appendChild(o);});sel.appendChild(optgroup);}}
function actionIcon(kind){if(kind==="help")return "?";if(kind==="add")return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>';if(kind==="insert")return '<svg viewBox="0 0 28 24" aria-hidden="true"><rect x="10" y="2.5" width="14" height="5" rx="1.3"/><rect class="filled" x="3" y="9.5" width="14" height="5" rx="1.3"/><rect x="10" y="16.5" width="14" height="5" rx="1.3"/></svg>';if(kind==="remove")return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 7h14M9 7V4.5h6V7M7.2 7l.8 12.5h8L16.8 7M10.5 10.5v5.5M13.5 10.5v5.5"/></svg>';if(kind==="drag")return '<svg viewBox="0 0 28 24" aria-hidden="true"><path d="M4 4v16M1.8 6.3 4 4l2.2 2.3M1.8 17.7 4 20l2.2-2.3"/><path d="M11 13V8.5a1.4 1.4 0 0 1 2.8 0V12M13.8 12V6.8a1.4 1.4 0 0 1 2.8 0V12M16.6 12V8a1.4 1.4 0 0 1 2.8 0v4M19.4 12v-1.8a1.4 1.4 0 0 1 2.8 0v4.4c0 3.4-2.2 5.9-5.4 5.9h-.8c-2 0-3.4-.7-4.5-2.2l-2.2-3a1.4 1.4 0 0 1 2.2-1.7L13 15"/></svg>';return "";}
function decorateActionButton(button,kind,label,active){if(!button)return;button.classList.add("iconButton",kind+"Action");button.innerHTML=actionIcon(kind);button.title=label;button.setAttribute("aria-label",label);if(kind==="help"){button.classList.toggle("isActive",!!active);button.setAttribute("aria-pressed",active?"true":"false");}}
function makeActionButton(kind,label,run,active){let b=document.createElement("button");decorateActionButton(b,kind,label,active);b.onclick=e=>{e.stopPropagation();run();};return b;}
function initAddMenu(stage){let panel=document.getElementById(stage+"Panel"); if(stage==="subject"&&!hasStagedSpec()){if(panel)panel.style.display="none";return;} let sp=stageSpec(stage);let sel=document.getElementById(stage+"ModuleSelect"); if(!sel)return;let toolbar=sel.closest(".row");if(toolbar)toolbar.classList.add("moduleToolbar"); sel.innerHTML="";let mods=arr(sp.availableModules).slice();if(stage==="subject"&&!mods.length&&!getSteps("subject").length){if(panel)panel.style.display="none";return;}if(panel)panel.style.display="block";if(stage==="cv"&&!isOOCVApplicationMode()&&globalLabelImputeAvailable()&&!globalLabelImputeActive()&&!hasCVLabelImpute()&&!mods.some(m=>isLabelImputeId(m.id))){let mi=moduleInfo("labelimpute");mods.push({id:"labelimpute",displayName:mi.displayName||"Label imputation"});}mods=mods.filter(m=>canon(m.id)!=="copyfeat"&&moduleAllowedByPolicy(stage,m.id)&&!applicationModulePresent(stage,m.id)&&clientAvailable(stage,m));appendCatalogOptions(sel,mods);let disabled=!mods.length;sel.disabled=disabled;let add=document.getElementById(stage+"AddBtn"),ins=document.getElementById(stage+"InsertBtn");decorateActionButton(add,"add","Add selected procedure");decorateActionButton(ins,"insert","Insert selected procedure before selected step");if(add)add.disabled=disabled;if(ins)ins.disabled=disabled;}
/**
 * initAddMenus  Provide the init add menus helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function initAddMenus(){initAddMenu("subject");initAddMenu("cv");}
/**
 * newModuleBlock  Provide the new module block helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function newModuleBlock(id,stage){let sp=moduleSpec(id,stage);let cfg=defaults(sp);if(isLabelImputeId(id)&&stage==="cv"&&labelImputeMethod(cfg)==="none"){cfg.method="manhattan";cfg.k=labelImputeK(cfg);}let first={moduleId:id,enabled:true,config:cfg};if(isOOCVApplicationMode()){first.editRole="application";first.trainedIndex=0;}let block=[first];let r=ruleFor(id);let child=r.sequence&&r.sequence.autoAddChild;if(child){let csp=moduleSpec(child,stage),extra={moduleId:child,enabled:true,config:defaults(csp)};if(isOOCVApplicationMode()){extra.editRole="application";extra.trainedIndex=0;}block.push(extra);}return block;}
/**
 * addModule  Provide the add module helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
async function addModule(stage,insert){let sel=document.getElementById(stage+"ModuleSelect"),id=sel?sel.value:"";if(!id)return;if(!moduleAllowedByPolicy(stage,id)){showError("This module is not permitted in OOCV application preprocessing.");return;}if(isLabelImputeId(id)&&globalLabelImputeActive()){showError("Remove the global label-imputation module before adding CV-bound label imputation.");return;}let a=getSteps(stage).slice();let block=newModuleBlock(id,stage);let at=a.length;if(idRequiresSpatialExtractorFlagForStage(id,stage)){let gate=spatialExtractorGate(stage);if(!gate.allowed){showError(gate.reason||"JuSpace/ROImeans/KL graph construction cannot be added because the spatial-extractor allow flag is disabled.");return;}if(insert){at=(a.length?Math.max(0,Math.min(ACTIVE[stage],a.length)):0);if(at>gate.insertIndex){showError("JuSpace/ROImeans/KL graph construction must be inserted before the first step that leaves imaging space. Use Add to place it at the last legal position.");return;}}else{at=gate.insertIndex;}}else if(insert){at=(a.length?Math.max(0,Math.min(ACTIVE[stage],a.length)):0);}let proposed=a.slice();proposed.splice(at,0,...block);if(!(await tryApplySteps(stage,proposed,at+block.length-1)))return;if(isLabelImputeId(id))setGlobalLabelImputeActive(false);VIEW={kind:"step"};syncLegacySequence();render();}
document.getElementById("subjectAddBtn").onclick=()=>addModule("subject",false);
document.getElementById("subjectInsertBtn").onclick=()=>addModule("subject",true);
document.getElementById("cvAddBtn").onclick=()=>addModule("cv",false);
document.getElementById("cvInsertBtn").onclick=()=>addModule("cv",true);
/**
 * applyUrlFocus  Apply the url focus change to local browser state or visible controls.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function applyUrlFocus(){
    if(isMLMode())return;
    ensureStagedState();
    let stage=(FOCUS_STAGE==="subject"||FOCUS_STAGE==="cv")?FOCUS_STAGE:"";
    if(!stage&&FOCUS_MODULE){
        ["subject","cv"].some(stg=>{
            let k=getSteps(stg).findIndex(x=>canon(x&&x.moduleId)===canon(FOCUS_MODULE));
            if(k>=0){stage=stg;return true;}
            return false;
        });
    }
    if(!stage)return;
    let steps=getSteps(stage);
    let idx=-1;
    if(Number.isFinite(FOCUS_STEP)&&FOCUS_STEP>0&&FOCUS_STEP<=steps.length)idx=Math.round(FOCUS_STEP)-1;
    if(idx<0&&FOCUS_MODULE)idx=steps.findIndex(x=>canon(x&&x.moduleId)===canon(FOCUS_MODULE));
    if(idx<0)idx=0;
    ACTIVE_STAGE=stage;
    ACTIVE[stage]=Math.max(0,Math.min(idx,Math.max(0,steps.length-1)));
    VIEW={kind:"step"};
}
/**
 * syncLegacySequence  Synchronize the legacy sequence browser state with related controls.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function syncLegacySequence(){if(isMLMode())return;ensureStagedState();STATE.sequence=STATE.cv.sequence;}
/**
 * validateCurrentStateForClose  Provide the validate current state for close helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
async function validateCurrentStateForClose(){ensureStagedState();normalizeLabelImputePlacementUI();return requestRuleProjection(undefined,undefined,true).then(projection=>{setRuleProjection(projection);let errs=projectionErrors(projection,getSteps("subject"),getSteps("cv"));if(errs.length){showError("Cannot close an invalid preprocessing sequence:\n"+errs.join("\n"));return false;}return true;},e=>{showError("Cannot validate preprocessing before close: "+e.message);return false;});}
/**
 * finishModule  Provide the finish module helper used by preprocessing template browser editor.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
async function finishModule(){try{let expressionResult=await NUMERIC_EXPRESSION_COMMIT_CHAIN;if(expressionResult&&expressionResult.ok===false)return;if(isMLMode()){ensureMLState();}else{if(!(await validateCurrentStateForClose()))return;syncLegacySequence();}let ok=await syncCurrentConfigNow("finish");if(!ok)throw new Error("Current configuration could not be written to disk.");if(EMBEDDED_UI){window.parent.postMessage({type:"nm-module-done",module:MODULE||"",title:(SPEC&&SPEC.title)||"",changedPaths:pendingChildChangedPaths()},"*");return;}await post("/api/close",{closed:true});document.body.innerHTML=`<p style="font-family:system-ui;padding:20px">Current configuration saved. You can close this tab.</p>`;}catch(e){showError("Configuration could not be saved: "+e.message+". The changes were not applied.");}}
let exportBtn=document.getElementById("exportMatrixScaffold");if(exportBtn)exportBtn.onclick=exportMatrixScaffold;let finishBtn=document.getElementById("finish");if(finishBtn&&EMBEDDED_UI)finishBtn.textContent="Close";if(finishBtn)finishBtn.onclick=finishModule;window.addEventListener("message",ev=>{if(ev&&ev.data&&ev.data.type==="nm-request-finish")finishModule();});
/**
 * showMessage  Provide the show message helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function showMessage(msg,cls){
    window.NMUIMessageTools.setMessage(msg || "", cls || "danger");
  }
/**
 * showError  Provide the show error helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function showError(msg){showMessage(msg,"danger");}
/**
 * showWarning  Provide the show warning helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function showWarning(msg){showMessage(msg,"warn");}
/**
 * refreshStateWarnings  Refresh the state warnings page region after state or artifact availability changes.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function refreshStateWarnings(){let subjectSteps=getSteps("subject"),cvSteps=getSteps("cv"),errs=projectionErrors(RULE_PROJECTION,subjectSteps,cvSteps),warns=projectionWarnings(RULE_PROJECTION,subjectSteps,cvSteps),msg=[];if(errs.length)msg.push(errs.join("\n"));if(warns.length)msg.push(warns.join("\n"));if(msg.length)showMessage(msg.join("\n"),errs.length?"danger":"warn");else showError("");}

/**
 * ensureMLShell  Ensure the mlshell prerequisite exists before downstream rendering or requests.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function ensureMLShell(){
    let title=document.querySelector("header b");if(title)title.textContent=SPEC.title;
    let scaffold=document.getElementById("exportMatrixScaffold");if(scaffold)scaffold.style.display="none";
    let layout=document.querySelector(".layout");if(!layout)return;
    layout.classList.add("mlLayout");
    let aside=layout.querySelector("aside"),main=layout.querySelector("main");
    if(aside&&!document.getElementById("mlSectionCards"))aside.innerHTML='<div class="stagepanel" id="mlPanel"><h3>ML configuration</h3><div class="stagehint">Configure the learner, optimization and model-selection settings for this analysis.</div><div id="mlSectionCards"></div></div>';
    if(main&&!ML_CONTEXT_HELP){
        let grid=document.getElementById("editorGrid");
        ML_CONTEXT_HELP=NMContextHelp.attach(grid,grid,"ML_Context_Help.html","ML configuration help");
    }
}
/**
 * mlFieldsForSection  Provide the ml fields for section helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function mlFieldsForSection(sectionId){return arr(SPEC.fields).filter(f=>!f.uiHidden&&String(f.section||"")===String(sectionId||"")).filter(f=>fieldVisibleFor(f,STATE));}
/**
 * mlVisibleSections  Provide the ml visible sections helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function mlVisibleSections(){ensureMLState();return arr(SPEC.layout&&SPEC.layout.sections).filter(s=>!s.uiHidden).filter(s=>!(s.hideWhenEmpty&&mlFieldsForSection(s.id).length===0));}
/**
 * mlCurrentSection  Provide the ml current section helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function mlCurrentSection(){ensureMLState();let secs=mlVisibleSections();let id=VIEW&&VIEW.section;if(!id||!secs.some(s=>String(s.id)===String(id))){id=secs.length?secs[0].id:"criterion";VIEW={kind:"mlSection",section:id};}return secs.find(s=>String(s.id)===String(id))||{id:id,title:id,description:""};}
/** Resolve stable documentation topics from the schema-defined parameter identities. */
function mlHelpSlug(value){return canon(value).replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,"");}
function mlFieldHelpTopic(f){
    let rule=arr(f.visibleIf&&f.visibleIf.all?f.visibleIf.all:[f.visibleIf]).find(r=>r&&r.field==="algorithm"&&r.equals);
    return "ml-"+mlHelpSlug(f.section)+"-"+(rule?mlHelpSlug(rule.equals)+"-":"")+mlHelpSlug(fieldPath(f));
}
function mlParameterHelpTopic(row,schema,opts){
    let alg=schema.algorithm,key=mlHelpSlug(row.name);
    if(opts.nested&&(/^\s*-t\s|kernel/i.test(alg)))return "ml-kernel-"+mlHelpSlug(alg)+"-"+key;
    if(schema.backendField==="matLearn")return "ml-matlearn-"+mlHelpSlug(matLearnAlgoFromSelectorValue(alg))+"-"+key;
    return "ml-param-"+mlHelpSlug(alg)+"-"+key;
}
/** Route preprocessing fields by the owning module and selected nested algorithm. */
function preprocFieldHelpTopic(f,st){
    if(!st)return VIEW.kind==="applicationLabelImpute"?"preproc-labelimpute-"+mlHelpSlug(f.name):"preproc-global-"+mlHelpSlug(f.name);
    let prefix="preproc-"+mlHelpSlug(st.moduleId)+"-";
    if(VIEW.kind==="subconfig"){
        let parent=arr(moduleSpec(st.moduleId,ACTIVE_STAGE).fields).find(x=>x.name===VIEW.field);
        let alg=mlHelpSlug(getPath(st.config,parent.subconfigSelector));
        if(st.moduleId==="remvarcomp"&&VIEW.field==="fastICAParams")alg="fastica";
        prefix+=alg+"-";
    }
    return prefix+mlHelpSlug(f.name);
}
/** Attach the shared HTML panel once; help navigation makes no MATLAB requests. */
function ensurePreprocHelp(){
    if(PREPROC_CONTEXT_HELP)return;
    let layout=document.querySelector(".layout"),grid=document.getElementById("editorGrid");
    layout.classList.add("preprocLayout");
    PREPROC_CONTEXT_HELP=NMContextHelp.attach(grid,grid,"Preproc_Context_Help.html","Preprocessing context help");
    [["globalPanel","global"],["subjectPanel","subject"],["cvPanel","cv"]].forEach(([id,key])=>{
        let h=document.querySelector("#"+id+" h3");
        PREPROC_CONTEXT_HELP.button(h,"preproc-workflow-"+key,h.textContent);
    });
}
/**
 * renderMLSectionCards  Render the mlsection cards UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderMLSectionCards(){let root=document.getElementById("mlSectionCards");if(!root)return;root.innerHTML="";mlVisibleSections().forEach(sec=>{let d=document.createElement("div");d.className="step"+(VIEW.kind==="mlSection"&&String(VIEW.section)===String(sec.id)?" active":"");d.onclick=()=>{VIEW={kind:"mlSection",section:sec.id};render();};d.innerHTML=`<b>${esc(sec.title||sec.id)}</b><div class="muted">${esc(sec.description||"")}</div>`;ML_CONTEXT_HELP.button(d.querySelector("b"),"ml-section-"+sec.id,sec.title||sec.id);root.appendChild(d);});}
/**
 * renderMLEditor  Render the mleditor UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderMLEditor(){let ed=document.getElementById("editor");if(!ed)return;let sec=mlCurrentSection();let fields=mlFieldsForSection(sec.id);ed.innerHTML=`<h2>${esc(sec.title||sec.id)}</h2>`;ML_CONTEXT_HELP.button(ed.querySelector("h2"),"ml-section-"+sec.id,sec.title||sec.id);if(!fields.length){let m=document.createElement("div");m.className="subcard muted";m.textContent="No fields are visible in this section for the current learner/settings.";ed.appendChild(m);return;}fields.forEach(f=>ed.appendChild(renderField(STATE,f,(changedField)=>{mlRefreshAfterFieldEdit(changedField);},null)));}
/**
 * renderML  Render the ml UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 */
function renderML(){ensureMLState();ensureMLShell();renderMLSectionCards();renderMLEditor();renderPreview();persistChildNavigation().catch(e=>showMessage("Navigation position could not be saved: "+e.message,"info"));}

/**
 * render  Render the render UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 */
function render(){if(isMLMode()){renderML();document.body.classList.remove("editor-loading");return;}ensureStagedState();ensureGlobalState();normalizeLabelImputePlacementUI();syncWaveletExternalWeightDefaults();ensurePreprocHelp();renderGlobalOptions();initAddMenus(); renderAllSteps(); renderBreadcrumb(); renderEditor(); renderPreview();refreshStateWarnings();persistChildNavigation().catch(e=>showMessage("Navigation position could not be saved: "+e.message,"info"));document.body.classList.remove("editor-loading");}
/**
 * stageLabel  Build the stage label shown to users in the browser UI.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function stageLabel(stage){return stage==="subject"?"Subject-specific preprocessing":"CV-bound preprocessing";}
/**
 * renderBreadcrumb  Render the breadcrumb UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderBreadcrumb(){let b=document.getElementById("breadcrumb"); if(VIEW.kind==="globalLabelImpute"){b.textContent="Label / target preprocessing / Label imputation";return;} if(VIEW.kind==="globalTargetTransform"){b.textContent="Label / target preprocessing / Label / target transformation";return;} let a=getSteps(ACTIVE_STAGE); if(!a.length){b.innerHTML=stageLabel(ACTIVE_STAGE);return;} let st=a[ACTIVE[ACTIVE_STAGE]]||a[0]; let m=moduleInfo(st.moduleId); if(VIEW.kind==="subconfig"){b.innerHTML=`<button onclick="exitSubconfig()">${stageLabel(ACTIVE_STAGE)} / Step ${ACTIVE[ACTIVE_STAGE]+1}: ${m.displayName||st.moduleId}</button> / ${VIEW.label||"Nested configuration"}`;} else {b.textContent=`${stageLabel(ACTIVE_STAGE)} / Step ${ACTIVE[ACTIVE_STAGE]+1}: ${m.displayName||st.moduleId}`;}}
/**
 * renderAllSteps  Render the all steps UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 */
function renderAllSteps(){renderSteps("subject");renderSteps("cv");}
/**
 * renderSteps  Render the steps UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderSteps(stage){let box=document.getElementById(stage+"Steps"); if(!box)return; box.innerHTML=""; getSteps(stage).forEach((s,i)=>{let m=moduleInfo(s.moduleId); let d=document.createElement("div"); let mixedReason=mixedEarlyFusionIncompatibleReason(s); let storedReason=storedStepIssueLabel(s); let issueReason=mixedReason?(mixedReason+" Remove this card explicitly if you want to keep the current mixed early-fusion setting."):storedReason; let inherited=stepInherited(s); d.className="step"+((stage===ACTIVE_STAGE&&i===ACTIVE[stage])?" active":"")+(issueReason?" invalidStep":""); d.onclick=()=>navigateFromSubconfig(()=>{if(ACTIVE_STAGE!==stage||ACTIVE[stage]!==i||VIEW.kind!=="step")showError("");ACTIVE_STAGE=stage;ACTIVE[stage]=i;VIEW={kind:"step"};render();}); d.innerHTML=`<b>${i+1}. ${m.displayName||s.moduleId}</b>`;if(isOOCVApplicationMode()){let role=document.createElement("div");role.className="muted";role.textContent=inherited?"Inherited trained step · read only":"OOCV application step";d.appendChild(role);} if(issueReason){let warn=document.createElement("div");warn.className="danger stepIssue";warn.textContent=issueReason;d.appendChild(warn);} let row=document.createElement("div"); row.className="row stepActionRow"; row.style.marginTop="8px";if(!isOOCVApplicationMode()){let h=document.createElement("span");h.className="dragHandle";h.innerHTML=actionIcon("drag");h.setAttribute("aria-label","Drag to reorder within this stage");installStepDragHandlers(d,h,stage,i);row.appendChild(h);}if(!inherited){[["↑","Move step up",()=>moveBlock(stage,i,-1)],["↓","Move step down",()=>moveBlock(stage,i,1)]].forEach(x=>{let b=document.createElement("button");b.className="stepActionButton";b.textContent=x[0];b.title=x[1];b.setAttribute("aria-label",x[1]);b.onclick=e=>{e.stopPropagation();x[2]();};row.appendChild(b);});row.appendChild(makeActionButton("remove","Remove step",()=>rem(stage,i),false));}PREPROC_CONTEXT_HELP.button(row,"preproc-module-"+mlHelpSlug(s.moduleId),m.displayName||s.moduleId); d.appendChild(row); box.appendChild(d);});}
/**
 * isChildOf  Return whether the is child of condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function isChildOf(childId,parentId){let r=ruleFor(childId); let req=arr(r.sequence&&r.sequence.requiresImmediatePreviousAny).map(canon); return req.includes(canon(parentId));}
/**
 * childSeq  Provide the child seq helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function childSeq(childId){return ruleFor(childId).sequence||{};}
/**
 * parentSeq  Provide the parent seq helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function parentSeq(parentId){return ruleFor(parentId).sequence||{};}
/**
 * childMovesWithParent / parentMovesWithChild  Consume directional move grammar exported by NMPreprocRuleSet.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function childMovesWithParent(childId,parentId){let cs=childSeq(childId);return isChildOf(childId,parentId)&&!!cs.moveWithParent;}
function parentMovesWithChild(parentId,childId){let ps=parentSeq(parentId);return isChildOf(childId,parentId)&&!!ps.moveWithChild;}
/**
 * childDeletesParent  Provide the child deletes parent helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function childDeletesParent(childId,parentId){let cs=childSeq(childId);return isChildOf(childId,parentId)&&!!cs.deleteWithParent;}
/**
 * parentDeletesChild  Provide the parent deletes child helper used by preprocessing template browser editor.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function parentDeletesChild(parentId,childId){let ps=parentSeq(parentId);return isChildOf(childId,parentId)&&!!ps.deleteWithChild;}
let DRAG_STATE=null;function clearDragMarks(){if(DRAG_STATE&&DRAG_STATE.ghost)DRAG_STATE.ghost.remove();document.querySelectorAll(".step.dragging,.step.dropBefore,.step.dropAfter").forEach(e=>e.classList.remove("dragging","dropBefore","dropAfter"));DRAG_STATE=null;}function dragDropSlot(stage,e){let zone=document.getElementById(stage+"Panel"),hit=document.elementFromPoint(e.clientX,e.clientY);if(!hit||!zone.contains(hit))return null;let cards=Array.from(document.getElementById(stage+"Steps").children),slot=cards.findIndex(c=>e.clientY<c.getBoundingClientRect().top+c.getBoundingClientRect().height/2);return {cards,slot:slot<0?cards.length:slot};}async function moveBlockTo(stage,i,targetIndex){let a=getSteps(stage);if(!a.length)return false;let b=blockFor(stage,i).slice().sort((x,y)=>x-y);if(b.some(k=>stepInherited(a[k]))){showError("Inherited trained preprocessing steps cannot be moved.");return false;}let start=b[0],end=b[b.length-1];targetIndex=Math.max(0,Math.min(Number(targetIndex),a.length));if(targetIndex>=start&&targetIndex<=end+1)return false;let activeOffset=b.indexOf(ACTIVE[stage]);if(activeOffset<0)activeOffset=b.indexOf(i);if(activeOffset<0)activeOffset=0;let items=b.map(k=>a[k]);let rest=a.filter((_,k)=>!b.includes(k));let removedBefore=b.filter(k=>k<targetIndex).length;let insertAt=targetIndex-removedBefore;insertAt=Math.max(0,Math.min(insertAt,rest.length));let proposed=rest.slice();proposed.splice(insertAt,0,...items);if(!(await tryApplySteps(stage,proposed,insertAt+activeOffset)))return false;VIEW={kind:"step"};syncLegacySequence();render();return true;}function installStepDragHandlers(card,handle,stage,i){handle.style.touchAction="none";handle.title="Drag to reorder within this stage";handle.onclick=e=>e.stopPropagation();handle.onpointerdown=e=>{if(e.button!==0)return;DRAG_STATE={stage,index:i,card,handle,x:e.clientX,y:e.clientY,started:false,ghost:null};handle.setPointerCapture(e.pointerId);};handle.onpointermove=e=>{let p=DRAG_STATE;if(!p||p.handle!==handle)return;if(!p.started&&Math.hypot(e.clientX-p.x,e.clientY-p.y)<5)return;if(!p.started){p.started=true;p.ghost=document.createElement("div");p.ghost.style.cssText="position:fixed;z-index:1000;pointer-events:none;opacity:.9;width:"+card.getBoundingClientRect().width+"px";let cards=document.getElementById(stage+"Steps").children;for(let k of blockFor(stage,i)){let preview=cards[k].cloneNode(true);cards[k].classList.add("dragging");preview.style.cssText="background:#fff;box-shadow:0 6px 16px #0003";p.ghost.appendChild(preview);}document.body.appendChild(p.ghost);}p.ghost.style.left=(e.clientX+12)+"px";p.ghost.style.top=(e.clientY+12)+"px";let landing=dragDropSlot(stage,e),box=document.getElementById(stage+"Steps");box.querySelectorAll(".dropBefore,.dropAfter").forEach(c=>c.classList.remove("dropBefore","dropAfter"));if(landing){let dest=landing.cards[landing.slot]||landing.cards[landing.cards.length-1];if(dest)dest.classList.add(landing.slot===landing.cards.length?"dropAfter":"dropBefore");}};handle.onpointerup=e=>{let p=DRAG_STATE;if(!p||p.handle!==handle)return;let landing=p.started?dragDropSlot(stage,e):null;clearDragMarks();if(landing)moveBlockTo(stage,p.index,landing.slot);};handle.onpointercancel=clearDragMarks;handle.onlostpointercapture=clearDragMarks;}function blockFor(stage,i){let a=getSteps(stage);let b=[i];if(i>0&&childMovesWithParent(a[i].moduleId,a[i-1].moduleId))return [i-1,i];if(i<a.length-1&&parentMovesWithChild(a[i].moduleId,a[i+1].moduleId))return [i,i+1];return b;}
/**
 * removalFor  Provide the removal for helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function removalFor(stage,i){let a=getSteps(stage);let b=[i];if(i>0&&childDeletesParent(a[i].moduleId,a[i-1].moduleId))b.push(i-1);if(i<a.length-1&&parentDeletesChild(a[i].moduleId,a[i+1].moduleId))b.push(i+1);return Array.from(new Set(b)).sort((x,y)=>x-y);}
/**
 * moveBlock  Provide the move block helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
async function moveBlock(stage,i,dir){let a=getSteps(stage); if(!a.length)return; let b=blockFor(stage,i).slice().sort((x,y)=>x-y); if(b.some(k=>stepInherited(a[k]))){showError("Inherited trained preprocessing steps cannot be moved.");return;} let start=b[0], end=b[b.length-1]; if(dir<0&&start===0)return; if(dir>0&&end>=a.length-1)return; let target=dir<0?blockFor(stage,start-1):blockFor(stage,end+1); target=target.slice().sort((x,y)=>x-y); let activeOffset=b.indexOf(ACTIVE[stage]); if(activeOffset<0)activeOffset=b.indexOf(i); if(activeOffset<0)activeOffset=0;  let items=b.map(k=>a[k]); let rest=a.filter((_,k)=>!b.includes(k)); let insertAt; if(dir<0){insertAt=target[0];}else{insertAt=target[target.length-1]+1-b.length;} if(insertAt<0)insertAt=0; if(insertAt>rest.length)insertAt=rest.length; let proposed=rest.slice(); proposed.splice(insertAt,0,...items); if(!(await tryApplySteps(stage,proposed,insertAt+activeOffset)))return;  VIEW={kind:"step"}; syncLegacySequence();render();} function move(i,j){moveBlock(ACTIVE_STAGE,i,j>i?1:-1);} async function rem(stage,i){let a=getSteps(stage),b=removalFor(stage,i);if(b.some(k=>stepInherited(a[k]))){showError("Inherited trained preprocessing steps cannot be removed.");return;}let proposed=a.filter((_,k)=>!b.includes(k)),nextIndex=Math.max(0,Math.min(ACTIVE[stage],proposed.length-1));if(!(await tryApplySteps(stage,proposed,nextIndex,VIEW.kind==="subconfig"&&stage===ACTIVE_STAGE&&b.includes(ACTIVE[stage]))))return;VIEW={kind:"step"};syncLegacySequence();render();}
/**
 * esc  Escape text before inserting it into HTML markup.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function esc(s){return String(s||"").replace(/[<>&]/g,c=>({"<":"&lt;",">":"&gt;","&":"&amp;"}[c]));}
/**
 * renderEditor  Render the editor UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderEditor(){let ed=document.getElementById("editor"); ed.innerHTML="";if(VIEW.kind==="applicationLabelImpute"){let spec=applicationLabelSpec(),state=applicationLabelState(),sp=spec.moduleSpec||{};ed.innerHTML=`<h2>${spec.displayName||"OOCV label imputation"}</h2><p class="muted">${spec.description||"Application-specific label imputation using the fully preprocessed CV1 training representation."}</p>`;PREPROC_CONTEXT_HELP.button(ed.querySelector("h2"),"preproc-workflow-application",spec.displayName||"OOCV label imputation");arr(sp.fields).filter(f=>!f.uiHidden&&fieldVisibleFor(f,state.config)).forEach(f=>ed.appendChild(renderField(state.config,f,()=>render(),null)));return;} if(VIEW.kind==="globalLabelImpute"){ed.innerHTML=`<h2>Label imputation</h2><p class="muted">Global handling of missing labels. The current mode leaves missing labels unchanged and has no additional settings.${globalOptionsLocked()?" This inherited trained setting is read only.":""}</p>`;PREPROC_CONTEXT_HELP.button(ed.querySelector("h2"),"preproc-workflow-global-label","Global label handling");return;} if(VIEW.kind==="globalTargetTransform"){let g=ensureGlobalState();let tt=globalTargetSpec();ed.innerHTML=`<h2>${tt.displayName||"Label / target transformation"}</h2><p class="muted">${tt.description||"Regression target transformation."}${globalOptionsLocked()?" Inherited trained settings are read only.":""}</p>`;PREPROC_CONTEXT_HELP.button(ed.querySelector("h2"),"preproc-workflow-target",tt.displayName||"Label / target transformation");let host=globalOptionsLocked()?readonlyFieldset():ed;if(host!==ed)ed.appendChild(host);arr(tt.fields).filter(f=>!f.uiHidden&&fieldVisibleFor(f,g)).forEach(f=>host.appendChild(renderField(g,f,()=>{g.enableTargetTransform=true;syncLegacySequence();render();},null)));return;} let a=getSteps(ACTIVE_STAGE); if(!a.length){ed.innerHTML=`<h3>No steps in ${stageLabel(ACTIVE_STAGE)}</h3><p class=muted>Add a module from the corresponding panel on the left.</p>`; return;} let st=a[ACTIVE[ACTIVE_STAGE]]; let sp=moduleSpec(st.moduleId,ACTIVE_STAGE); let m=moduleInfo(st.moduleId); if(!sp){ed.innerHTML=`<h3>${st.moduleId}</h3><p class=danger>No schema found for this module.</p>`; return;}if(VIEW.kind==="subconfig"&&stepInherited(st))VIEW={kind:"step"}; if(VIEW.kind==="subconfig"){renderSubconfigEditor(ed,st,sp);return;} let inherited=stepInherited(st);ed.innerHTML=`<h2>${m.displayName||st.moduleId}</h2><p class="muted">${stageLabel(ACTIVE_STAGE)}. ${sp.description||""}${inherited?" Inherited trained step — read only.":""}</p>`; PREPROC_CONTEXT_HELP.button(ed.querySelector("h2"),"preproc-module-"+mlHelpSlug(st.moduleId),m.displayName||st.moduleId);let sr=storedStepIssueLabel(st); if(sr){let warn=document.createElement("div");warn.className="danger stepIssue";warn.textContent=sr;ed.appendChild(warn);}let host=inherited?readonlyFieldset():ed;if(host!==ed)ed.appendChild(host);arr(sp.fields).filter(f=>!f.uiHidden).filter(f=>fieldVisible(f,st)).forEach(f=>host.appendChild(renderField(st.config,f,()=>{refreshRulesAfterConfigEdit();},st)));}
/** Keep ordinary navigation synchronous, but validate before leaving an open nested editor. */
function navigateFromSubconfig(action){if(VIEW.kind==="subconfig")exitSubconfig().then(ok=>{if(ok)action();});else action();}
/** Enforce complete method-specific settings on every nested-editor exit. */
async function exitSubconfig(){
    if(VIEW.kind!=="subconfig")return true;
    return NUMERIC_EXPRESSION_COMMIT_CHAIN.then(pending=>{
        if(pending&&pending.ok===false)return false;
        return requestRuleProjection(undefined,undefined,true).then(projection=>{
            let issue=arr(projection[ACTIVE_STAGE].stepIssues)[ACTIVE[ACTIVE_STAGE]];
            if(issue&&issue.severity==="error"){showError("Cannot leave an incomplete configuration:\n"+issue.message);return false;}
            VIEW={kind:"step"};showError("");render();return true;
        },e=>{showError("Cannot validate nested configuration: "+e.message);return false;});
    },e=>{showError("Cannot commit nested expression: "+e.message);return false;});
}
/**
 * renderSubconfigEditor  Render the subconfig editor UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderSubconfigEditor(ed,st,sp){let field=arr(sp.fields).find(f=>f.name===VIEW.field); if(!field){ed.innerHTML="<p class=danger>Nested field not found.</p>";return;} let sub=subSpecFor(field,st.config); if(!sub){ed.innerHTML="<p class=muted>No algorithm-specific configuration page for the current selection.</p>";return;} if(!st.config[field.name]||typeof st.config[field.name]!=="object")st.config[field.name]=defaults(sub); st.config[field.name]=Object.assign(defaults(sub),st.config[field.name]); st.config[field.name].__algorithm=st.config[field.subconfigSelector]; ed.innerHTML=`<h2>${sub.title||field.label}</h2><p class="muted">${sub.description}</p>`;PREPROC_CONTEXT_HELP.button(ed.querySelector("h2"),"preproc-module-"+mlHelpSlug(st.moduleId),sub.title||field.label); arr(sub.fields).filter(f=>!f.uiHidden).filter(f=>fieldVisibleFor(f,st.config[field.name])).forEach(f=>ed.appendChild(renderField(st.config[field.name],f,()=>{refreshRulesAfterConfigEdit();},st))); let back=document.createElement("button");back.textContent=`Back to ${moduleInfo(st.moduleId).displayName||st.moduleId}`;back.onclick=exitSubconfig;ed.appendChild(back);}
/**
 * covarOptions  Provide the covar options helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function covarOptions(){let c=SPEC.context||{};return arr(c.covarOptions);}
/**
 * asNumArray  Convert the supplied value into the as num array representation expected by the UI.
 * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
 */
function asNumArray(x){return arr(x).map(Number).filter(v=>Number.isFinite(v));}
/**
 * covarLabel  Build the covar label shown to users in the browser UI.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function covarLabel(c){return c.label||((c.index||"")+" | "+(c.name||"covariate"));}
/**
 * covarByIndex  Provide the covar by index helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function covarByIndex(idx){return covarOptions().find(c=>Number(c.index)===Number(idx))||{index:idx,name:"Covariate "+idx,label:idx+" | Covariate "+idx,inferredType:"continuous"};}
/**
 * canonCovType  Return whether the canon cov type condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canonCovType(t){t=String(t||"continuous").toLowerCase();if(["k","cat","categorical","b","bin","binary","logical","bool","boolean"].includes(t))return "categorical";if(["o","ord","ordinal"].includes(t))return "ordinal";if(["c","cont","continuous"].includes(t))return "continuous";return "continuous";}
/**
 * covarInferredType  Provide the covar inferred type helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function covarInferredType(c){return canonCovType(c&&c.inferredType);}
/**
 * parseCovTypes  Provide the parse cov types helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function parseCovTypes(x){if(Array.isArray(x))return x.map(canonCovType);if(typeof x==="string")return x.split(/[,;\s]+/).filter(Boolean).map(canonCovType);return [];}
/**
 * canonSplineDF  Return whether the canon spline df condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canonSplineDF(v){let n=Number(v);if(!Number.isFinite(n)||n<2)return 0;n=Math.round(n);if(n<2)return 0;if(n>5)return 5;return n;}
/**
 * syncCombatCovariateRows  Synchronize the combat covariate rows browser state with related controls.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 * cfg.covariateDetails: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.covariateTypes: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.covariates: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.removeCovariatePositions: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.splineDF: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 */
function syncCombatCovariateRows(cfg){if(!cfg||typeof cfg!=="object")return [];let selected=asNumArray(cfg.covariates);let opts=covarOptions();if(!opts.length&&selected.length)opts=selected.map(i=>covarByIndex(i));let prev=arr(cfg.covariateDetails&&cfg.covariateDetails.rows);let prevBy={};prev.forEach(r=>{if(r&&r.index!==undefined)prevBy[Number(r.index)]=r;});let types=parseCovTypes(cfg.covariateTypes);let dfs=asNumArray(cfg.splineDF);let rem=asNumArray(cfg.removeCovariatePositions);let rows=opts.map(o=>{let idx=Number(o.index),pos=selected.indexOf(idx),old=prevBy[idx]||{};let sel=pos>=0||old.selected===true||old.use===true;let inferred=covarInferredType(o);let importedType=(sel&&types[pos])?canonCovType(types[pos]):"";let manualType=(old.typeManual===true||old.manualType===true)?canonCovType(old.type):"";let typ=importedType||manualType||inferred;let manual=!!(importedType||manualType);let df=canonSplineDF(old.splineDF!==undefined?old.splineDF:((sel&&dfs[pos]!==undefined)?dfs[pos]:0));let rm=!!(old.remove!==undefined?old.remove:(old.removeVariance!==undefined?old.removeVariance:(sel&&rem.includes(pos+1))));return {index:idx,name:o.name||("Covariate "+idx),selected:sel,remove:rm,type:typ,inferredType:inferred,typeManual:manual,splineDF:df};});applyCombatCovariateRows(cfg,rows,false);return rows;}
/**
 * applyCombatCovariateRows  Apply the combat covariate rows change to local browser state or visible controls.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 * cfg.covariateDetails: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.covariateTypes: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.covariates: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.removeCovariatePositions: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.splineDF: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 */
function applyCombatCovariateRows(cfg,rows,writeRows){rows=arr(rows);let sel=rows.filter(r=>r.selected);cfg.covariates=sel.map(r=>Number(r.index));cfg.removeCovariatePositions=sel.map((r,i)=>r.remove?i+1:null).filter(v=>v!==null);cfg.covariateTypes=sel.map(r=>canonCovType(r.type||r.inferredType));cfg.splineDF=sel.map(r=>canonSplineDF(r.splineDF));cfg.covariateDetails={rows:writeRows===false?rows:rows};}
/**
 * splitPathString  Provide the split path string helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function splitPathString(v){v=String(v||"").trim();if(!v)return [];return v.split(/\s*;\s*/).filter(Boolean);}
/**
 * joinPaths  Provide the join paths helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function joinPaths(paths){return arr(paths).filter(Boolean).join("; ");}
/**
 * isRankExternalFileField  Return whether the is rank external file field condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 * cfg.algorithm: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.externalSource: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 */
function isRankExternalFileField(cfg,f){return !!cfg&&!!f&&f.name==="externalFile"&&canon(cfg.algorithm)==="extern"&&canon(cfg.externalSource)==="file";}
/**
 * clearRankExternalFileImport  Clear the rank external file import UI state, cache or rendered content.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 * cfg.externalFileImportSummary: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.externalFileResolvedMat: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.externalFileThresholdSummary: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 */
function clearRankExternalFileImport(cfg){if(!cfg)return;cfg.externalFileResolvedMat="";cfg.externalFileImportSummary="";cfg.externalFileThresholdSummary="";}
/**
 * loadRankExternalFile  Load rank external file data from injected state, local cache or the MATLAB bridge.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * cfg.externalFile: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.externalFileImportSummary: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function loadRankExternalFile(cfg,onChange){if(!cfg||!cfg.externalFile){clearRankExternalFileImport(cfg);onChange&&onChange();return;}try{setStatus("Loading external ranking image...","info");let res=await postJson("/api/matlabservice",{operation:"rankfeat_import_external_file",config:cfg,context:(SPEC&&SPEC.context)||{},timeout:600});if(res&&res.error)throw new Error(res.error);if(!res||res.ok===false)throw new Error((res&&res.message)||"Unknown external-image import failure");if(res.configPatch){Object.assign(cfg,res.configPatch);}let msg=(res&&res.message)||"External ranking image loaded.";setStatus("External ranking image loaded","ok");onChange&&onChange();}catch(e){clearRankExternalFileImport(cfg);let msg="External ranking image could not be loaded: "+e.message;cfg.externalFileImportSummary=msg;setStatus("External ranking image load failed","danger");showMessage(msg,"danger");onChange&&onChange();}}
/**
 * pickPathForField  Provide the pick path for field helper used by preprocessing template browser editor.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function pickPathForField(cfg,f,onChange){let mode=f.selectorMode||(String(f.type||"").toLowerCase()==="directory_path"?"directory":"file");let multiple=!!f.multiple;try{setStatus("Waiting for file chooser...","info");let res=await postJson("/api/pickpath",{kind:mode,multiple:multiple,initial:cfg[f.name]||"",filter:f.fileFilter||"",timeout:240});if(res&&res.error){throw new Error(res.error);}let paths=arr(res.paths);if(paths.length){cfg[f.name]=multiple?joinPaths(paths):paths[0];if(f.name==="brainMapsDir"){await scanJuSpaceBrainMaps(cfg,onChange,false);onChange();setStatus("Path selected","ok");return;}if(isRankExternalFileField(cfg,f)){clearRankExternalFileImport(cfg);await loadRankExternalFile(cfg,onChange);return;}onChange();setStatus("Path selected","ok");}else{setStatus("Path selection cancelled","info");}}catch(e){setStatus("Path selector failed","danger");showError("Path selection failed. You can paste the path manually. Details: "+e.message);}}
/**
 * renderPathField  Render the path field UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * cfg.externalFile: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.externalFileImportSummary: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.externalFileResolvedMat: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderPathField(cfg,f,val,onChange){let wrap=document.createElement("div");wrap.className="row";let inp=document.createElement("input");inp.type="text";inp.style.minWidth="520px";inp.placeholder=(f.selectorMode==="directory"||String(f.type||"").toLowerCase()==="directory_path")?"Select or paste a directory":"Select or paste file path(s)";inp.value=val??"";inp.onchange=async()=>{cfg[f.name]=inp.value;if(isRankExternalFileField(cfg,f)){clearRankExternalFileImport(cfg);await loadRankExternalFile(cfg,onChange);return;}if(f.name==="brainMapsDir")await scanJuSpaceBrainMaps(cfg,onChange,false);onChange();};let b=document.createElement("button");b.type="button";b.textContent="Browse...";b.onclick=()=>pickPathForField(cfg,f,onChange);wrap.appendChild(inp);wrap.appendChild(b);if(isRankExternalFileField(cfg,f)){let lb=document.createElement("button");lb.type="button";lb.textContent="Reload/validate in NM";lb.disabled=!String(cfg.externalFile||"").trim();lb.onclick=()=>loadRankExternalFile(cfg,onChange);wrap.appendChild(lb);if(cfg.externalFileImportSummary){let stat=document.createElement("span");stat.className=cfg.externalFileResolvedMat?"ok":"danger";stat.textContent=cfg.externalFileImportSummary;wrap.appendChild(stat);}}return wrap;}
/**
 * brainMapStem  Provide the brain map stem helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function brainMapStem(name){name=String(name||"");return name.replace(/\.nii\.gz$/i,"").replace(/\.nii$/i,"");}
/**
 * mapRowKey  Resolve the map row key identifier used to connect UI state with NeuroMiner payload metadata.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function mapRowKey(r){return String((r&&(r.path||r.file||r.name||r.id))||"");}
/**
 * syncJuSpaceBrainRows  Synchronize the ju space brain rows browser state with related controls.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 * cfg.availableBrainMaps: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.brainMapRows: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 */
function syncJuSpaceBrainRows(cfg){let rows=arr(cfg.brainMapRows).map(x=>Object.assign({},x));let byKey={};rows.forEach(r=>{byKey[mapRowKey(r)]=r;});arr(cfg.availableBrainMaps).forEach((m,i)=>{let key=mapRowKey(m);if(!key)return;if(!byKey[key]){let nm=m.name||m.file||m.path||`map_${i+1}`;let stem=brainMapStem(nm);byKey[key]={selected:false,id:m.id||stem,name:stem,altName:stem,file:m.file||nm,path:m.path||"",listidx:m.listidx||i+1,NT:m.NT||m.id||stem,tracer:m.tracer||"NA",N:m.N||"NA",source:m.source||"NA"};}});rows=Object.values(byKey);rows.sort((a,b)=>String(a.name||a.id||a.file).localeCompare(String(b.name||b.id||b.file)));cfg.brainMapRows=rows;return rows;}
/**
 * applyJuSpaceBrainRows  Apply the ju space brain rows change to local browser state or visible controls.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 * cfg.brainMapNames: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.brainMapRows: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 */
function applyJuSpaceBrainRows(cfg,rows){cfg.brainMapRows=rows;let sel=rows.filter(r=>r.selected);cfg.brainMapNames=sel.map(r=>r.altName||r.id||r.name);}
/**
 * scanJuSpaceBrainMaps  Provide the scan ju space brain maps helper used by preprocessing template browser editor.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * cfg.availableBrainMaps: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.brainMapsDir: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.scanStatus: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function scanJuSpaceBrainMaps(cfg,onChange,force){if(!cfg.brainMapsDir){cfg.availableBrainMaps=[];cfg.scanStatus="";return;} if(!force&&arr(cfg.availableBrainMaps).length)return;cfg.scanStatus="Scanning brain maps directory...";onChange&&onChange();try{let res=await postJson("/api/listdir",{path:cfg.brainMapsDir,extensions:[".nii",".nii.gz"]});cfg.availableBrainMaps=arr(res.files);cfg.scanStatus=cfg.availableBrainMaps.length?`${cfg.availableBrainMaps.length} NIfTI brain map(s) found.`:"No .nii/.nii.gz brain maps found.";syncJuSpaceBrainRows(cfg);}catch(e){cfg.scanStatus="Scan failed: "+e.message;showError(cfg.scanStatus);}onChange&&onChange();}
/**
 * renderJuSpaceBrainMapTable  Render the ju space brain map table UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * cfg.brainMapsDir: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.scanStatus: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderJuSpaceBrainMapTable(cfg,f,val,onChange){let wrap=document.createElement("div");let rows=syncJuSpaceBrainRows(cfg);let top=document.createElement("div");top.className="row";let scan=document.createElement("button");scan.type="button";scan.textContent="Scan directory";scan.onclick=()=>scanJuSpaceBrainMaps(cfg,onChange,true);top.appendChild(scan);let selectAll=document.createElement("button");selectAll.type="button";selectAll.textContent="Select all";selectAll.disabled=!rows.length;selectAll.onclick=()=>{let rr=syncJuSpaceBrainRows(cfg);rr.forEach(r=>{r.selected=true;if(!r.altName)r.altName=r.id||r.name||brainMapStem(r.file);});applyJuSpaceBrainRows(cfg,rr);onChange();};top.appendChild(selectAll);let unselectAll=document.createElement("button");unselectAll.type="button";unselectAll.textContent="Unselect all";unselectAll.disabled=!rows.length;unselectAll.onclick=()=>{let rr=syncJuSpaceBrainRows(cfg);rr.forEach(r=>{r.selected=false;});applyJuSpaceBrainRows(cfg,rr);onChange();};top.appendChild(unselectAll);let stat=document.createElement("span");stat.className="muted";stat.textContent=cfg.scanStatus||"Select/scan the brain-map directory to populate the table.";top.appendChild(stat);wrap.appendChild(top);if(!cfg.brainMapsDir){let m=document.createElement("div");m.className="subcard muted";m.textContent="Define the brain maps directory first.";wrap.appendChild(m);return wrap;}if(!rows.length){let m=document.createElement("div");m.className="subcard muted";m.textContent="No brain maps are currently listed. Press Scan directory or paste a directory containing .nii/.nii.gz files.";wrap.appendChild(m);return wrap;}let tbl=document.createElement("table");tbl.className="covtbl";tbl.innerHTML="<thead><tr><th>Use</th><th>Brain map</th><th>File</th><th>Alternative name</th></tr></thead><tbody></tbody>";let tb=tbl.querySelector("tbody");let commit=()=>{applyJuSpaceBrainRows(cfg,rows);onChange();};rows.forEach((r,i)=>{let tr=document.createElement("tr");let cb=document.createElement("input");cb.type="checkbox";cb.checked=!!r.selected;cb.onchange=()=>{r.selected=cb.checked;if(r.selected&&!r.altName)r.altName=r.id||r.name||brainMapStem(r.file);commit();};let td0=document.createElement("td");td0.appendChild(cb);let td1=document.createElement("td");td1.innerHTML=`<b>${esc(r.id||r.name||brainMapStem(r.file))}</b>${r.tracer&&r.tracer!=="NA"?`<br><span class=muted>${esc(r.tracer)}</span>`:""}`;let td2=document.createElement("td");td2.innerHTML=`<span class=muted>${esc(r.file||r.path||"")}</span>`;let name=document.createElement("input");name.type="text";name.value=r.altName||r.id||r.name||"";name.disabled=!r.selected;name.onchange=()=>{r.altName=name.value;commit();};let td3=document.createElement("td");if(r.selected)td3.appendChild(name);else td3.innerHTML="<span class=muted>—</span>";[td0,td1,td2,td3].forEach(td=>tr.appendChild(td));tb.appendChild(tr);});wrap.appendChild(tbl);let note=document.createElement("div");note.className="help";note.textContent="Checked rows define the JuSpace brain maps used by this preprocessing step. Alternative names can be assigned here. Use Select all / Unselect all for batch selection after scanning the directory.";wrap.appendChild(note);return wrap;}
/**
 * renderCombatCovariateTable  Render the combat covariate table UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderCombatCovariateTable(cfg,f,val,onChange){let rows=syncCombatCovariateRows(cfg);let wrap=document.createElement("div");if(!rows.length){let m=document.createElement("div");m.className="subcard muted";m.textContent="No covariates are available in the current context.";wrap.appendChild(m);return wrap;}let tbl=document.createElement("table");tbl.className="covtbl";tbl.innerHTML="<thead><tr><th>Use</th><th>Covariate</th><th>Remove variance</th><th>Measurement scale</th><th>Spline df</th></tr></thead><tbody></tbody>";let tb=tbl.querySelector("tbody");let commit=()=>{applyCombatCovariateRows(cfg,rows,true);onChange();};rows.forEach((r,i)=>{let tr=document.createElement("tr");let opt=covarByIndex(r.index);let cUse=document.createElement("input");cUse.type="checkbox";cUse.checked=!!r.selected;cUse.onchange=()=>{r.selected=cUse.checked;if(r.selected){r.inferredType=covarInferredType(opt);if(!r.typeManual)r.type=r.inferredType;r.splineDF=canonSplineDF(r.splineDF);}else{r.remove=false;}commit();};let td0=document.createElement("td");td0.appendChild(cUse);let td1=document.createElement("td");td1.innerHTML=`<b>${esc(covarLabel(opt))}</b>${opt.inferredType?`<br><span class="muted">autodetected: ${esc(canonCovType(opt.inferredType))}</span>`:""}`;let rm=document.createElement("input");rm.type="checkbox";rm.checked=!!r.remove;rm.disabled=!r.selected;rm.onchange=()=>{r.remove=rm.checked;commit();};let td2=document.createElement("td");if(r.selected)td2.appendChild(rm);else td2.innerHTML="<span class=muted>—</span>";let typ=document.createElement("select");["categorical","ordinal","continuous"].forEach(v=>{let o=document.createElement("option");o.value=v;o.textContent=v;if(canonCovType(r.type)===v)o.selected=true;typ.appendChild(o);});typ.disabled=!r.selected;typ.onchange=()=>{r.type=typ.value;r.typeManual=true;commit();};let td3=document.createElement("td");if(r.selected)td3.appendChild(typ);else td3.innerHTML="<span class=muted>—</span>";let df=document.createElement("select");[[0,"none"],[2,"2"],[3,"3"],[4,"4"],[5,"5"]].forEach(pair=>{let o=document.createElement("option");o.value=pair[0];o.textContent=pair[1];if(canonSplineDF(r.splineDF)===pair[0])o.selected=true;df.appendChild(o);});df.disabled=!r.selected;df.onchange=()=>{r.splineDF=canonSplineDF(df.value);commit();};let td4=document.createElement("td");if(r.selected)td4.appendChild(df);else td4.innerHTML="<span class=muted>—</span>";[td0,td1,td2,td3,td4].forEach(td=>tr.appendChild(td));tb.appendChild(tr);});wrap.appendChild(tbl);let note=document.createElement("div");note.className="help";note.textContent="Checked rows are included as additional ComBat covariates. Measurement scale is inferred automatically and can be overridden; binary-like variables are treated as categorical; spline df can be set to none or 2–5.";wrap.appendChild(note);return wrap;}
/**
 * renderCovariateField  Render the covariate field UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderCovariateField(cfg,f,val,onChange){
    const opts=covarOptions();
    if(f.type==="covariate_indices"){
        const root=document.createElement("div");
        const selected=new Set(arr(val).map(Number));
        root.style.cssText="max-height:240px;overflow-y:auto;border:1px solid #cbd5e1;border-radius:9px;background:white;padding:3px";
        if(!opts.length){root.textContent="<no covariates available>";return root;}
        opts.forEach(c=>{
            const index=Number(c.index);
            const row=document.createElement("label");
            const box=document.createElement("input");
            const name=document.createElement("span");
            row.style.cssText="display:flex;align-items:center;gap:6px;margin:0;padding:2px 6px;line-height:18px;cursor:pointer;font-weight:400;font-size:13px";
            box.type="checkbox";
            box.value=String(index);
            box.checked=selected.has(index);
            box.style.cssText="margin:0;padding:0;width:15px;height:15px;flex:0 0 auto";
            name.textContent=covarLabel(c);
            box.onchange=()=>{
                if(box.checked)selected.add(index);
                else selected.delete(index);
                cfg[f.name]=opts.filter(o=>selected.has(Number(o.index))).map(o=>Number(o.index));
                onChange();
            };
            row.appendChild(box);
            row.appendChild(name);
            root.appendChild(row);
        });
        return root;
    }
    const inp=document.createElement("select"),empty=document.createElement("option");
    empty.value="";empty.textContent="<none>";inp.appendChild(empty);
    if(!opts.length){let o=document.createElement("option");o.disabled=true;o.textContent="<no covariates available>";inp.appendChild(o);}
    opts.forEach(c=>{let o=document.createElement("option");o.value=Number(c.index);o.textContent=covarLabel(c);if(Number(val)===Number(c.index))o.selected=true;inp.appendChild(o);});
    inp.onchange=()=>{cfg[f.name]=inp.value===""?[]:Number(inp.value);onChange();};
    return inp;
}
/**
 * mlFieldRequiresFullRender  Provide the ml field requires full render helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function mlFieldRequiresFullRender(f){
    if(!isMLMode()||!f)return true;
    let p=fieldPath(f);
    let full={
        "algorithm":true,
        "kernelSettings.kernstr":true,
        "optimizationSettings.type":true,
        "optimizationSettings.Bayes.mode":true,
        "modelSelectionSettings.NodeSelect.mode":true,
        "fixedSettings.classifier":true,
        "fixedSettings.Weighting":true,
        "fixedSettings.bias":true,
        "fixedSettings.AutoC":true,
        "fixedSettings.LIBSVMver":true,
        "fixedSettings.predict_time":true,
        "fixedSettings.algo":true
    };
    return !!full[p];
}
/**
 * mlRefreshAfterFieldEdit  Persist and render an edited canonical ML field.
 * The browser STATE value is the authoritative pending child-editor value. Each edit schedules the
 * module-scoped current_config write consumed by the template apply service before refreshing the
 * dependent cards, preview and help. It does not directly mutate MATLAB or materialize TrainParam.
 * Side effects: schedules one debounced bridge write and updates the active browser presentation.
 */
function mlRefreshAfterFieldEdit(f){
    ensureMLState();
    if(['fixedSettings.Optimization.b','fixedSettings.b'].includes(fieldPath(f)))mlReplaceUnavailableECE();
    if(mlFieldRequiresFullRender(f)){
        render();
    }else{
        renderMLSectionCards();
        renderPreview();
    }
}
/**
 * mlApplyCriterionDefaults  Change only criterion-derived percentile defaults.
 * Explicitly edited percentile values are preserved; the criterion field remains the sole direction
 * authority through the selected enum records supplied by NMLearnerLibrary.
 */
function mlECEAvailable(){
    let alg=getPath(STATE,'algorithm','');
    let rule=arr(SPEC.eceEligibilityRules).find(r=>r.algorithm===alg);
    return !!rule&&(!arr(rule.paths).length||arr(rule.paths).some(p=>!!getPath(STATE,p,false)));
}
function mlReplaceUnavailableECE(){
    if(Number(getPath(STATE,'performanceCriterion',0))!==21||mlECEAvailable())return;
    let field=arr(SPEC.fields).find(f=>fieldPath(f)==='performanceCriterion');
    let options=enumOptions(field);
    setPath(STATE,'performanceCriterion',14);
    mlApplyCriterionDefaults(STATE,options.find(o=>Number(enumEntryValue(o))===21),options.find(o=>Number(enumEntryValue(o))===14));
    markChildChangedPath('performanceCriterion','modelSelectionSettings.NodeSelect.perc','modelSelectionSettings.NodeSelect.percvec');
    showWarning('ECE requires predicted probabilities. Optimization criterion changed to balanced accuracy (BAC).');
}
function mlApplyCriterionDefaults(cfg,oldEntry,newEntry){
    let oldLow=oldEntry&&oldEntry.direction==="minimize";
    let newLow=newEntry&&newEntry.direction==="minimize";
    if(oldLow===newLow)return;
    let oldPerc=oldLow?5:95,newPerc=newLow?5:95;
    let oldVec=oldLow?[5,10,15,20,25]:[75,80,85,90,95];
    let newVec=newLow?[5,10,15,20,25]:[75,80,85,90,95];
    let perc=getPath(cfg,"modelSelectionSettings.NodeSelect.perc",undefined);
    let percvec=getPath(cfg,"modelSelectionSettings.NodeSelect.percvec",undefined);
    if(valuesEqual(perc,oldPerc))setPath(cfg,"modelSelectionSettings.NodeSelect.perc",newPerc);
    if(valuesEqual(percvec,oldVec))setPath(cfg,"modelSelectionSettings.NodeSelect.percvec",newVec);
}
/**
 * mlApplyAlgorithmDefaults  Provide the ml apply algorithm defaults helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function mlApplyAlgorithmDefaults(algorithm){
    let alg=String(algorithm||"");
    let defaults=(SPEC&&SPEC.defaultStates&&SPEC.defaultStates[alg])?clone(SPEC.defaultStates[alg]):null;
    if(!defaults)return;
    let oldPerf=getPath(STATE,"performanceCriterion",undefined);
    let oldLegacySVM=getPath(STATE,"legacySVM",{});
    let oldLegacyGRD=getPath(STATE,"legacyGRD",{});
    STATE=defaults;
    if(oldPerf!==undefined){
        let criterionField=arr(SPEC&&SPEC.fields).find(f=>fieldPath(f)==="performanceCriterion");
        let criterionOptions=enumOptions(criterionField);
        let defaultPerf=getPath(STATE,"performanceCriterion",undefined);
        let defaultEntry=criterionOptions.find(v=>valuesEqual(enumEntryValue(v),defaultPerf));
        let restoredEntry=criterionOptions.find(v=>valuesEqual(enumEntryValue(v),oldPerf));
        setPath(STATE,"performanceCriterion",oldPerf);
        mlApplyCriterionDefaults(STATE,defaultEntry,restoredEntry);
    }
    setPath(STATE,"legacySVM",oldLegacySVM||{});
    setPath(STATE,"legacyGRD",oldLegacyGRD||{});
    mlReplaceUnavailableECE();
    scheduleCurrentConfigSync("learner change");
}
/**
 * mlApplyMatLearnAlgorithmDefaults  Provide the ml apply mat learn algorithm defaults helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function mlApplyMatLearnAlgorithmDefaults(algo){
    let field=arr(SPEC&&SPEC.fields).find(f=>fieldPath(f)==="hyperparameters.learnerParams");
    let schema=field&&field.paramSchemaByAlgorithm&&field.paramSchemaByAlgorithm.matLRN;
    let sub=schema&&schema.schemasByAlgorithm&&schema.schemasByAlgorithm[String(algo||"")];
    if(sub){
        setPath(STATE,"hyperparameters.learnerParams",learnerParamDefaultRowsFromSchema(sub));
        setPath(STATE,"fixedSettings.learner.framework",schema.framework||getPath(STATE,"fixedSettings.learner.framework","binaryclass"));
        scheduleCurrentConfigSync("matLearn learner change");
    }
}
/**
 * safeSetStatus  Provide the safe set status helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function safeSetStatus(t,cls){try{setStatus(t,cls);}catch(e){try{console.warn("NM UI status update failed",e);}catch(_){}}}
/**
 * commitNumericExpressionInput  Return or interpret the commit numeric expression input control used by the page.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
async function commitNumericExpressionInput(inp,cfg,f,t){
    let raw=String(inp.value||"").trim();
    let kind=(t==="numeric_vector")?"numeric_vector":"number";
    let res;
    try{
        res=await interpretNumericExpression(raw,kind);
    }catch(e){
        res={ok:false,error:e&&e.message?e.message:String(e)};
    }
    if(res&&res.ok){
        let value=res.value;
        if(t==="integer"&&Number.isFinite(value))value=Math.round(value);
        setFieldValue(cfg,f,value);
        inp.value=Array.isArray(value)?rangeToText(value):String(value);
        inp.setAttribute("aria-invalid","false");
        safeSetStatus("Expression interpreted successfully","ok");
        return {ok:true,value:value,source:res.source||"local"};
    }
    inp.setAttribute("aria-invalid","true");
    let label=String((f&&(f.label||f.name))||"Numeric field");
    let detail=(res&&res.error)?String(res.error):"Expression did not evaluate to a numeric value.";
    showError(label+": value was not applied because the expression could not be interpreted. "+detail);
    safeSetStatus("Expression not applied","danger");
    return {ok:false,error:detail};
}
/**
 * refreshEditorAfterExpressionEdit  Refresh the editor after expression edit page region after state or artifact availability changes.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function refreshEditorAfterExpressionEdit(f,onChange){
    if(isMLMode()){
        if(onChange)onChange(f);
        try{renderMLEditor();}catch(e){try{console.warn("Could not refresh ML editor after expression edit",e);}catch(_){}}
    }else{
        if(onChange)onChange(f);
    }
}

/**
 * mlParamSchemaForCurrent  Provide the ml param schema for current helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function mlParamSchemaForCurrent(f){
    let alg=String(getPath(STATE,"algorithm","")||"");
    let all=(f&&f.paramSchemaByAlgorithm)||{};
    let sch=all[alg];
    if(alg==="matLRN"&&sch){
        let a=String(getPath(STATE,"fixedSettings.algo",sch.defaultAlgorithm||"")||"");
        let sub=(sch.schemasByAlgorithm||{})[a];
        if(sub)return sub;
    }
    return sch||null;
}
/**
 * schemaRowsByName  Provide the schema rows by name helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function schemaRowsByName(schema){let m={};arr(schema&&schema.params).forEach(r=>{if(r&&r.name)m[String(r.name)]=r;});return m;}
/**
 * learnerParamDefaultRowsFromSchema  Provide the learner param default rows from schema helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function learnerParamDefaultRowsFromSchema(schema){return arr(schema&&schema.params).map(r=>({name:r.name,range:clone(r.defaultValue)}));}
/**
 * learnerParamVisible  Provide the learner param visible helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function learnerParamVisible(r,sch,f){
    let mode=String((f&&f.displayMode)||"normal").toLowerCase();
    if(sch&&sch.visibleIf&&!visibleRuleOk(sch.visibleIf,STATE))return false;
    if(mode==="expert")return sch?sch.visibleExpert!==false:true;
    return sch?sch.visibleNormal!==false:true;
}
/**
 * schemaSafeKey  Resolve the schema safe key identifier used to connect UI state with NeuroMiner payload metadata.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function schemaSafeKey(v){let s=String(v||"").replace(/[^A-Za-z0-9_]/g,"_");if(!s)s="empty";if(!/^[A-Za-z]/.test(s))s="x_"+s;return s;}
/**
 * selectorOptionsFromSchema  Apply the or options from schema selection to browser state and dependent controls.
 * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
 */
function selectorOptionsFromSchema(sch){
    let raw=arr((sch&&sch.selectorValues&&arr(sch.selectorValues).length)?sch.selectorValues:(sch&&sch.allowedValues));
    return raw.map((v,i)=>{
        if(v&&typeof v==="object"&&!Array.isArray(v))return {value:String(v.value??""),label:String(v.label??v.value??("Option "+(i+1))),key:String(v.key||schemaSafeKey(v.value??""))};
        return {value:String(v??""),label:String(v??""),key:schemaSafeKey(v??"")};
    });
}
/**
 * matLearnAlgoFromSelectorValue  Provide the mat learn algo from selector value helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function matLearnAlgoFromSelectorValue(v){
    let s=String(v||"");
    let m=s.match(/^@ml_[^_]+_(.+)$/);
    return m?m[1]:s;
}
/**
 * selectedNestedSchema  Apply the ed nested schema selection to browser state and dependent controls.
 * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
 */
function selectedNestedSchema(sch, selectorValue){
    let S=(sch&&sch.nestedSchemasByValue)||{};
    if(!selectorValue)return null;
    let keys=[String(selectorValue),schemaSafeKey(selectorValue),matLearnAlgoFromSelectorValue(selectorValue),schemaSafeKey(matLearnAlgoFromSelectorValue(selectorValue))];
    for(let k of keys){if(S&&S[k])return S[k];}
    return null;
}
/**
 * findParamRow  Provide the find param row helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function findParamRow(rows,name){return arr(rows).find(r=>r&&String(r.name||"")===String(name||""));}
/**
 * findParamIndex  Provide the find param index helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function findParamIndex(rows,name){return arr(rows).findIndex(r=>r&&String(r.name||"")===String(name||""));}
/**
 * getParamRange  Provide the get param range helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function getParamRange(rows,name){let r=findParamRow(rows,name);return r?r.range:undefined;}
/**
 * setParamRange  Provide the set param range helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function setParamRange(rows,name,range){let i=findParamIndex(rows,name);if(i>=0)rows[i].range=range;}
/**
 * defaultNestedRows  Provide the default nested rows helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function defaultNestedRows(schema){return learnerParamDefaultRowsFromSchema(schema);}
/**
 * ensureArrayRows  Ensure the array rows prerequisite exists before downstream rendering or requests.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function ensureArrayRows(x){return arr(x).map(r=>Object.assign({},r));}
/**
 * renderParamTextEditor  Render the param text editor UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 */
function renderParamTextEditor(row, rows, index, commit, onChange, rerender){
    let wrap=document.createElement("div");
    let inp=document.createElement("input");inp.type="text";inp.value=rangeToText(row.range);
    let applying=false;
    /**
     * apply  Interpret and commit one learner-parameter expression when its field loses focus.
     */
    let apply=()=>queueNumericExpressionCommit(async()=>{
        if(applying)return {ok:true,skipped:true}; applying=true;
        try{
            let raw=String(inp.value||"").trim();
            let res;
            try{res=await interpretNumericExpression(raw,"numeric_vector");}catch(e){res={ok:false,error:e&&e.message?e.message:String(e)};}
            if(!(res&&res.ok)){
                inp.setAttribute("aria-invalid","true");
                let detail=(res&&res.error)?String(res.error):"Expression did not evaluate to a numeric vector.";
                showError(`Learner parameter ${String(row&&row.name||index+1)}: value was not applied because the expression could not be interpreted. ${detail}`);
                safeSetStatus("Expression not applied","danger");
                return {ok:false,error:detail};
            }
            rows[index].range=res.value;
            inp.value=rangeToText(res.value);
            inp.setAttribute("aria-invalid","false");
            safeSetStatus("Expression interpreted successfully","ok");
            commit();
            syncCurrentConfigNow("numeric expression focusout");
            if(rerender)rerender();
            return {ok:true,value:res.value,source:res.source||"local"};
        }finally{applying=false;}
    });
    inp.onkeydown=e=>{if(e.key==="Enter"){e.preventDefault();inp.blur();}};
    inp.addEventListener("focusout",e=>{e.stopPropagation();apply();});
    wrap.appendChild(inp);
    return wrap;
}
/**
 * schemaFormatLabels  Provide the schema format labels helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function schemaFormatLabels(sch){
    let f=String((sch&&sch.format)||"");
    return f.indexOf("|")>=0?f.split("|").map(x=>x.trim()):[];
}
/**
 * paramChoiceOptionsFromSchema  Provide the param choice options from schema helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function paramChoiceOptionsFromSchema(sch){
    let labels=schemaFormatLabels(sch);
    let vals=arr(sch&&sch.allowedValues);
    if(!vals.length&&labels.length)vals=labels.slice();
    if(!labels.length&&String(sch&&sch.kind||"")==="boolean")labels=["yes","no"];
    if(!vals.length&&String(sch&&sch.kind||"")==="boolean")vals=[1,0];
    let n=Math.max(vals.length,labels.length);
    let opts=[];
    for(let i=0;i<n;i++){
        let raw=(i<vals.length)?vals[i]:labels[i];
        let value=(raw&&typeof raw==="object"&&!Array.isArray(raw))?(raw.value??raw.label??""):raw;
        let label=(raw&&typeof raw==="object"&&!Array.isArray(raw))?(raw.label??raw.value??""):(i<labels.length?labels[i]:String(value??""));
        opts.push({value:value,label:String(label),index:i+1});
    }
    return opts;
}
/**
 * valuesSameForChoice  Provide the values same for choice helper used by preprocessing template browser editor.
 * It supports preprocessing template browser editor at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function valuesSameForChoice(a,b){
    if(Array.isArray(a)||Array.isArray(b))return JSON.stringify(a)===JSON.stringify(b);
    if(a===b)return true;
    let sa=String(a??""), sb=String(b??"");
    if(sa===sb)return true;
    let na=Number(a), nb=Number(b);
    return Number.isFinite(na)&&Number.isFinite(nb)&&na===nb;
}
/**
 * selectedChoiceIndex  Apply the ed choice index selection to browser state and dependent controls.
 * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
 * options.length: browser-side field consumed from options while translating UI state to MATLAB-service requests.
 */
function selectedChoiceIndex(options,current,kind){
    for(let i=0;i<options.length;i++)if(valuesSameForChoice(options[i].value,current))return i;
    if(String(kind||"")==="categorical"&&Number.isInteger(Number(current))){
        let idx=Number(current)-1;
        if(idx>=0&&idx<options.length)return idx;
    }
    return -1;
}
/**
 * renderParamChoiceEditor  Render the param choice editor UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderParamChoiceEditor(row, rows, index, sch, commit, rerender){
    let wrap=document.createElement("div");
    let sel=document.createElement("select");
    let options=paramChoiceOptionsFromSchema(sch);
    let cur=row.range;
    let selected=selectedChoiceIndex(options,cur,sch&&sch.kind);
    options.forEach((o,i)=>{let opt=document.createElement("option");opt.value=String(i);opt.textContent=o.label;if(i===selected)opt.selected=true;sel.appendChild(opt);});
    if(selected<0&&options.length){sel.value="0";}
    sel.onchange=()=>{
        let i=Number(sel.value);
        rows[index].range=options[i]?clone(options[i].value):sel.value;
        commit();
        if(rerender)rerender();
    };
    wrap.appendChild(sel);
    return wrap;
}
/**
 * renderParamSelector  Render the param selector UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderParamSelector(row, rows, index, sch, commit, dependentName, nestedSchemaProvider){
    let wrap=document.createElement("div");
    let sel=document.createElement("select");
    let empty=document.createElement("option");empty.value="";empty.textContent="<not selected>";sel.appendChild(empty);
    let options=selectorOptionsFromSchema(sch);
    let cur=String(row.range??"");
    let selected=false;
    options.forEach(o=>{let opt=document.createElement("option");opt.value=o.value;opt.textContent=o.label;if(String(o.value)===cur){opt.selected=true;selected=true;}sel.appendChild(opt);});
    if(!selected&&Number.isInteger(Number(row.range))){
        let idx=Number(row.range)-1;
        if(idx>=0&&idx<options.length)sel.value=options[idx].value;
    }
    sel.onchange=()=>{
        rows[index].range=sel.value;
        if(dependentName){
            let nsch=nestedSchemaProvider?nestedSchemaProvider(sel.value):selectedNestedSchema(sch,sel.value);
            setParamRange(rows,dependentName,nsch?defaultNestedRows(nsch):[]);
        }
        commit();
        if(isMLMode())try{renderMLEditor();}catch(_){ }
    };
    wrap.appendChild(sel);
    return wrap;
}
/**
 * renderNestedParams  Render the nested params UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderNestedParams(row, rows, sch, commit, dependentValue, emptyMessage){
    let wrap=document.createElement("div");
    let nsch=selectedNestedSchema(sch, dependentValue);
    if(!dependentValue){let m=document.createElement("div");m.className="subcard muted";m.textContent=emptyMessage||"Select the dependent option first.";wrap.appendChild(m);return wrap;}
    if(!nsch||!arr(nsch.params).length){let m=document.createElement("div");m.className="subcard muted";m.textContent="The selected option has no nested parameters.";wrap.appendChild(m);return wrap;}
    let nestedRows=ensureArrayRows(row.range);
    if(!nestedRows.length)nestedRows=defaultNestedRows(nsch);
    let nested=renderLearnerParamTableCore(nestedRows,nsch,{displayMode:"normal",nested:true,onCommit:(nr)=>{row.range=nr;commit();}});
    wrap.appendChild(nested);
    return wrap;
}
/**
 * renderLearnerParamTableCore  Render the learner param table core UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * opts.displayMode: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderLearnerParamTableCore(rows, schema, opts){
    opts=opts||{};
    let byName=schemaRowsByName(schema);
    let wrap=document.createElement("div");
    if(!rows.length){let m=document.createElement("div");m.className="subcard muted";m.textContent="No learner-specific Params are defined for the selected learner.";wrap.appendChild(m);return wrap;}
    let visibleRows=rows.map((r,i)=>({r:r,i:i,sch:byName[String(r.name||"")]})).filter(x=>learnerParamVisible(x.r,x.sch,{displayMode:opts.displayMode||"normal"}));
    if(!visibleRows.length){let m=document.createElement("div");m.className="subcard muted";m.textContent="This learner has no parameters available in the current display mode. Additional expert settings remain unchanged.";wrap.appendChild(m);return wrap;}
    let tbl=document.createElement("table");tbl.className="covtbl";tbl.innerHTML="<thead><tr><th>Parameter</th><th>Search range / value</th></tr></thead><tbody></tbody>";
    let tb=tbl.querySelector("tbody");
    /**
     * commit  Provide the commit helper used by preprocessing template browser editor.
     * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
     * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
     */
    let commit=()=>{if(opts.onCommit)opts.onCommit(rows);};
    visibleRows.forEach(x=>{
        let r=x.r,i=x.i,sch=x.sch||{};
        let tr=document.createElement("tr");
        let td0=document.createElement("td");
        let label=sch.label||r.name||("Param "+(i+1));
        td0.innerHTML=`<b>${esc(label)}</b><br><span class="muted">${esc(r.name||("Param "+(i+1)))}</span>`;if(isMLMode())ML_CONTEXT_HELP.button(td0.querySelector("b"),mlParameterHelpTopic(r,schema,opts),label);
        let td1=document.createElement("td");
        let editor;
        let k=String(sch.kind||"");
        if(k==="model_selector"){
            editor=renderParamSelector(r,rows,i,sch,commit,"subOptions",val=>selectedNestedSchema(byName.subOptions,val));
        }else if(k==="options_selector"){
            editor=renderNestedParams(r,rows,sch,commit,getParamRange(rows,"subModel"),"Select a submodel learner first.");
        }else if(k==="kernel_func_selector"){
            editor=renderParamSelector(r,rows,i,sch,commit,"kernelOptions",val=>selectedNestedSchema(byName.kernelOptions,val));
        }else if(k==="kernel_params_selector"){
            editor=renderNestedParams(r,rows,sch,commit,getParamRange(rows,"kernelFunc"),"Select a kernel function first.");
        }else if(k==="boolean"||k==="categorical"){
            editor=renderParamChoiceEditor(r,rows,i,sch,commit,()=>{if(isMLMode())try{renderMLEditor();}catch(_){ }});
        }else{
            editor=renderParamTextEditor(r,rows,i,commit,null,()=>{if(isMLMode())try{renderMLEditor();}catch(_){ }});
        }
        td1.appendChild(editor);
        if(sch.allowedValues&&arr(sch.allowedValues).length&&!["model_selector","kernel_func_selector"].includes(k)){
            let av=document.createElement("div");av.className="help";av.textContent="Allowed values: "+arr(sch.allowedValues).map(x=>String((x&&typeof x==="object")?(x.label||x.value):x)).join(", ");td1.appendChild(av);
        }
        [td0,td1].forEach(td=>tr.appendChild(td));tb.appendChild(tr);
    });
    wrap.appendChild(tbl);
    return wrap;
}
/**
 * renderLearnerParamTable  Render the learner param table UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 */
function renderLearnerParamTable(cfg,f,val,onChange){
    let schema=mlParamSchemaForCurrent(f);
    let rows=arr(val).map(r=>Object.assign({},r));
    if(schema&&(!rows.length||!rows.some(r=>r&&r.name))){
        rows=learnerParamDefaultRowsFromSchema(schema);
        setFieldValue(cfg,f,rows);
    }
    return renderLearnerParamTableCore(rows,schema,{displayMode:(f&&f.displayMode)||"normal",onCommit:(r)=>{setFieldValue(cfg,f,r);onChange&&onChange(f);}});
}
/**
 * renderField  Render the field UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * cfg.applyWaveletToExternalWeightMap: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * cfg.applyWaveletToExternalWeightMapManualOverride: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderField(cfg,f,onChange,st){
    let downstreamOnChange=onChange;
    onChange=(changedField)=>{let cf=changedField||f;let p=childStatePathForField(cfg,cf,st);if(p)markChildChangedPath(p);if(cf.type==="covariate_indices"&&st){renderPreview();refreshRuleProjection().then(()=>{renderAllSteps();refreshStateWarnings();},e=>showError("Preprocessing validation failed: "+e.message));return;}if(downstreamOnChange)downstreamOnChange(cf);};
    let div=document.createElement("div"); div.className="field";
    let lab=document.createElement("label"); lab.textContent=f.label||f.name; div.appendChild(lab);(isMLMode()?ML_CONTEXT_HELP:PREPROC_CONTEXT_HELP).button(lab,isMLMode()?mlFieldHelpTopic(f):preprocFieldHelpTopic(f,st),f.label||f.name);
    let val=cfg?fieldValue(cfg,f):undefined;
    if(val===undefined){val=(f.default===undefined?null:clone(f.default)); if(cfg&&fieldPath(f))setFieldValue(cfg,f,val);}
    let t=(f.type||"string").toLowerCase(); let inp;
    if(t==="subconfig"){
        let sub=subSpecFor(f,cfg); let card=document.createElement("div"); card.className="subcard"; let alg=getPath(cfg,f.subconfigSelector||"algorithm",undefined);
        card.innerHTML=`<div><b>${sub?(sub.title||alg):"No nested configuration"}</b></div><div class="muted">${sub?(sub.description||""):"The selected algorithm has no separate configurator."}</div>`;
        let b=document.createElement("button"); b.textContent=sub?"Open nested configurator":"No nested options"; b.disabled=!sub||!arr(sub.fields).length;
        b.onclick=()=>{if(!fieldValue(cfg,f)||typeof fieldValue(cfg,f)!=="object")setFieldValue(cfg,f,defaults(sub)); VIEW={kind:"subconfig",field:f.name,label:f.label||f.name};render();};
        card.appendChild(b); div.appendChild(card); return div;
    }
    if(t==="readonly"){
        let ro=document.createElement("div");ro.className="subcard muted";ro.textContent=String(val??"");div.appendChild(ro);return div;
    }
    if(t==="boolean"||t==="logical"){
        inp=document.createElement("input");inp.type="checkbox";inp.checked=!!val;
        inp.onchange=()=>{setFieldValue(cfg,f,inp.checked);if(f.name==="applyWaveletToExternalWeightMap")cfg.applyWaveletToExternalWeightMapManualOverride=true;onChange&&onChange(f);};
    } else if(t==="enum"||t==="select"){
        inp=document.createElement("select");let opts=enumOptions(f);if(isMLMode()&&fieldPath(f)==='performanceCriterion'&&!mlECEAvailable())opts=opts.filter(o=>Number(enumEntryValue(o))!==21);let selectedIndex=-1;
        opts.forEach((v,idx)=>{let value=enumEntryValue(v);let label=enumEntryLabel(v);let o=document.createElement("option");o.value=String(idx);o.textContent=label;if(valuesEqual(value,val)){o.selected=true;selectedIndex=idx;}inp.appendChild(o);});
        if(selectedIndex<0){let invalid=document.createElement("option");invalid.value="-1";invalid.textContent=`Unsupported stored value: ${String(val)}`;invalid.disabled=true;invalid.selected=true;inp.insertBefore(invalid,inp.firstChild);}
        inp.value=String(selectedIndex);
        inp.onchange=()=>{
            let idx=Number(inp.value);if(idx<0||idx>=opts.length)return;let next=clone(enumEntryValue(opts[idx]));let previous=fieldValue(cfg,f);let oldEntry=opts.find(v=>valuesEqual(enumEntryValue(v),previous));let nextEntry=opts[idx];
            setFieldValue(cfg,f,next);
            if(isMLMode()&&fieldPath(f)==="performanceCriterion"){mlApplyCriterionDefaults(cfg,oldEntry,nextEntry);markChildChangedPath("modelSelectionSettings.NodeSelect.perc","modelSelectionSettings.NodeSelect.percvec");}
            if(isMLMode()&&fieldPath(f)==="algorithm"){
                mlApplyAlgorithmDefaults(next);markChildChangedPath("*");VIEW={kind:"mlSection",section:"learner"};onChange&&onChange(f);return;
            }
            if(isMLMode()&&fieldPath(f)==="fixedSettings.algo"&&getPath(cfg,"algorithm","")==="matLRN"){
                mlApplyMatLearnAlgorithmDefaults(next);markChildChangedPath("hyperparameters.learnerParams","fixedSettings.learner.framework");VIEW={kind:"mlSection",section:"hyperparameters"};onChange&&onChange(f);return;
            }
            if(f.name==="reconstructionMode"&&(cfg.applyWaveletToExternalWeightMapManualOverride===undefined||!cfg.applyWaveletToExternalWeightMapManualOverride)){
                cfg.applyWaveletToExternalWeightMap=waveletRecoAppliesToExternalWeightMap(cfg);
            }
            if(st&&canon(st.moduleId)==="rankfeat"&&f.name==="algorithm"&&canon(next)!=="extern"){
                clearRankExternalFileImport(cfg);
            }
            if(st&&canon(st.moduleId)==="rankfeat"&&f.name==="externalSource"&&!["file","nm_weight_map","legacy"].includes(canon(next))){
                clearRankExternalFileImport(cfg);
            }
            onChange&&onChange(f);
        };
    } else if(t==="sequence_matrix"){
        inp=NMSequenceBuilder.field(val, SPEC.sequenceSources, (matrix)=>{
            setFieldValue(cfg,f,matrix);
            onChange(f);
        }, (message,kind)=>showMessage(message,kind));
    } else if(t==="learner_param_table"){
        inp=renderLearnerParamTable(cfg,f,val,onChange);
    } else if(t==="combat_covariate_table"){
        inp=renderCombatCovariateTable(cfg,f,val,onChange);
    } else if(t==="covariate_indices"||t==="covar_indices"||t==="covariate_index"||t==="covar_index"){
        inp=renderCovariateField(cfg,f,val,onChange);
    } else if(t==="number"||t==="integer"||t==="numeric_vector"){
        let wrap=document.createElement("div");wrap.className="exprInputWrap";
        let inputEl=document.createElement("input");inputEl.type="text";inputEl.value=Array.isArray(val)?rangeToText(val):(val??"");
        let applying=false;
        /**
         * apply  Interpret and commit one numeric expression when its field loses focus.
         */
        let apply=()=>queueNumericExpressionCommit(async()=>{
            if(applying)return {ok:true,skipped:true};applying=true;
            try{
                let result=await commitNumericExpressionInput(inputEl,cfg,f,t);
                if(!result.ok)return result;
                syncCurrentConfigNow("numeric expression focusout");
                refreshEditorAfterExpressionEdit(f,onChange);
                return result;
            }finally{applying=false;}
        });
        inputEl.onkeydown=e=>{if(e.key==="Enter"){e.preventDefault();inputEl.blur();}};
        inputEl.addEventListener("focusout",e=>{e.stopPropagation();apply();});
        wrap.appendChild(inputEl);inp=wrap;
    } else if(t==="workspace_var"||t==="workspace_variable"){
        inp=document.createElement("select");let empty=document.createElement("option");empty.value="";empty.textContent="<none>";inp.appendChild(empty);let shown=0;
        arr(WORKSPACE).filter(w=>workspaceMatches(w,f)).forEach(w=>{shown++;let o=document.createElement("option");o.value=w.name;let compat=w.featureCompatible?", feature-compatible":"";o.textContent=`${w.name} (${w.class||""}, ${Array.isArray(w.size)?w.size.join("x"):""}${compat})`;if(w.name===val)o.selected=true;inp.appendChild(o);});
        if(!shown){let o=document.createElement("option");o.disabled=true;o.textContent="<no matching workspace variables>";inp.appendChild(o);}
        inp.onchange=()=>{setFieldValue(cfg,f,inp.value); if(f.autoSetTaskField){let ww=arr(WORKSPACE).find(x=>x.name===inp.value); if(ww&&ww.taskHint&&ww.taskHint!=="ambiguous"){setPath(cfg,f.autoSetTaskField,ww.taskHint);} if(f.autoSetTaskHintField){setPath(cfg,f.autoSetTaskHintField,ww?`${ww.taskHint||"ambiguous"}${ww.taskHintReason?" ("+ww.taskHintReason+")":""}`:"");}} onChange&&onChange(f);};
    } else if(t==="file_path"||t==="directory_path"){
        inp=renderPathField(cfg,f,val,onChange);
    } else if(t==="juspace_brainmap_table"){
        inp=renderJuSpaceBrainMapTable(cfg,f,val,onChange);
    } else {
        inp=document.createElement("input");inp.type="text";inp.value=val??"";inp.onchange=()=>{setFieldValue(cfg,f,inp.value);onChange&&onChange(f);};
    }
    div.appendChild(inp);
    return div;
}
/**
 * renderPreview  Render the preview UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 */
function renderPreview(){if(!isMLMode())syncLegacySequence();let preview=document.getElementById("preview");if(preview)preview.textContent=JSON.stringify(summarize(STATE),null,2);scheduleCurrentConfigSync("edit");}
(async function boot(){let savedNav=null;try{SPEC=await get("/api/spec");STATE=await get("/api/state");try{WORKSPACE=await get("/api/workspace");}catch(e){WORKSPACE=[];}BRIDGE_OK=true;try{savedNav=await loadChildNavigation();}catch(e){showMessage("Previous navigation position could not be restored; the default view was opened instead. "+e.message,"info");}setStatus("Connected to NeuroMiner","ok");}catch(e){SPEC=window.NM_EMBEDDED_SPEC||{};STATE=window.NM_EMBEDDED_STATE||{cv:{executionStage:"cv",sequence:{steps:[]}},subject:{executionStage:"subject",sequence:{steps:[]}}};WORKSPACE=window.NM_EMBEDDED_WORKSPACE||[];BRIDGE_OK=false;setStatus("NeuroMiner connection unavailable; read-only mode","warn");showError("Connection to NeuroMiner was lost. This page is read-only until the connection is restored. Details: "+e.message);} CURRENT_CONFIG_LAST_OBSERVED=JSON.stringify(currentConfigPayload());try{if(isMLMode()){ensureMLState();if(RESTORE_NAV)restoreChildNavigation(savedNav);render();}else{ensureStagedState();let normalized=normalizeLabelImputePlacementUI();seedRuleProjectionFromSpec();if(normalized&&BRIDGE_OK){try{await refreshRuleProjection();}catch(e){showError("Initial preprocessing rule validation failed: "+e.message);}}initAddMenus();if(RESTORE_NAV)restoreChildNavigation(savedNav);else applyUrlFocus();render();if(FORCE_NONIMAGING&&FUSION_MIXED)showWarning("Early fusion mixes imaging and non-imaging modalities. Imaging-specific preprocessing modules are unavailable for this shared preprocessing branch.");}}catch(e){showError("UI render failed: "+(e.stack||e.message));}})();
/**
 * exportMatrixScaffold  Provide the export matrix scaffold helper used by preprocessing template browser editor.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function exportMatrixScaffold(){
  try{
    await syncCurrentConfigNow("matrix scaffold export");
    setStatus("Waiting for export-folder chooser...","info");
    let pick=await postJson("/api/pickpath",{kind:"directory",multiple:false,initial:"",timeout:240});
    if(pick&&pick.error)throw new Error(pick.error);
    let paths=arr(pick&&pick.paths).filter(x=>String(x||"").trim());
    if(!paths.length){
      setStatus("Preprocessing scaffold export cancelled","info");
      return;
    }
    let exportRoot=paths[0];
    setStatus("Exporting preprocessing scaffold...","info");
    let res=await postJson("/api/matlabservice",{operation:"preproc_export_matrix_scaffold",exportRoot:exportRoot,timeout:600});
    if(res&&res.error)throw new Error(res.error);
    if(!res||res.ok===false)throw new Error((res&&res.message)||"Unknown scaffold export failure");
    let msg=(res.message||"Preprocessing scaffold exported.");
    if(res.exportDir)msg += "\nExport folder: "+res.exportDir;
    if(res.files&&res.files.length)msg += "\nFiles: "+res.files.join(", ");
    setStatus("Preprocessing scaffold exported","ok");
    showMessage(msg,"ok");
  }catch(e){
    let msg="Preprocessing scaffold export failed: "+e.message;
    setStatus("Preprocessing scaffold export failed","danger");
    showMessage(msg,"danger");
  }
}
