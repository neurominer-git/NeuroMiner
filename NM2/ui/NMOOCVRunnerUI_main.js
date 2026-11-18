(function(){
  const PARAMS = new URLSearchParams(window.location.search);
  const PORT = PARAMS.get('port') || window.NM_UI_PORT || '4821';
  const API_BASE = `http://127.0.0.1:${PORT}`;
  let STATE = window.NM_OOCV_RUNNER_STATE || {};
  let SELECTED_ANALYSIS = finiteIndex(STATE.selectedAnalysisIndex);
  let SELECTED_OOCV = null;
  let GRID_ACT = gridForAnalysis(SELECTED_ANALYSIS);
  let MANUAL_FILES = {oocvDataMasterFile:'',oocvDataFiles:[]};
  let MANUAL_FILE_LIST = null;
  const reconcileGrid = window.NMRuntimeGridPicker.reconciler([SELECTED_ANALYSIS]);
  let ANALYSIS_SELECTOR = null;
  let GRID_PICKER = null;
  let RUNTIME_PROGRESS_VIEWER = null;
  let RUNTIME_JOB_CLIENT = null;
  let RUNTIME_JOB_ACTIVE = false;
  let ACTIVE_APPLICATION_PREPROC = null;
  const RUNTIME_PROGRESS_POLL_MS = 80;
  const RUNTIME_PROGRESS_WRITE_INTERVAL_SECONDS = 0.10;

  function arr(x){ return x == null ? [] : (Array.isArray(x) ? x : [x]); }
  function el(id){ return document.getElementById(id); }
  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function finiteIndex(x){ const n=Number(x); return Number.isFinite(n) && n>=1 ? Math.round(n) : null; }
  function bool(x){ return x === true || x === 1 || x === 'true'; }
  function selectedCount(G){ return arr(G).reduce((n,row)=>n+arr(row).filter(Boolean).length,0); }

  function appContext(){ return STATE && STATE.appContext && typeof STATE.appContext === 'object' ? STATE.appContext : {}; }
  function API(path){ return `${API_BASE}${path}`; }

  async function postJson(path, payload){
    const response = await fetch(API(path), {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload||{})});
    let obj = null;
    try{ obj = await response.json(); }catch(_e){ obj = {ok:false,message:`HTTP ${response.status}`}; }
    if(obj && typeof obj === 'object' && !obj.httpStatus) obj.httpStatus = response.status;
    return obj;
  }
  async function matlabService(payload){ return postJson('/api/matlabservice', payload); }

  function serviceMessage(out,fallback){
    if(out && out.message) return String(out.message);
    if(out && out.error) return String(out.error);
    return fallback || 'MATLAB service request failed.';
  }
  function serviceSeverity(out,fallback){ return out && out.ok ? 'success' : (fallback || 'danger'); }
  function setMsg(message,severity){
    window.NMUIMessageTools.setMessage(message || "", severity || "info");
  }

  function runtimeJobClient(){
    if(!RUNTIME_JOB_CLIENT && window.NMRuntimeJobClient){
      RUNTIME_JOB_CLIENT = new window.NMRuntimeJobClient({port:PORT,storageKey:`nm2_oocv_runtime_job_${PORT}`,pollMs:750});
    }
    return RUNTIME_JOB_CLIENT;
  }
  function createRuntimeProgressTaskId(prefix){
    if(window.NMRuntimeProgressViewer && typeof window.NMRuntimeProgressViewer.createTaskId === 'function'){
      return window.NMRuntimeProgressViewer.createTaskId(prefix || 'oocv');
    }
    return `${prefix||'oocv'}_${Date.now()}_${Math.random().toString(36).slice(2,9)}`.replace(/[^A-Za-z0-9_-]/g,'');
  }
  function runtimeProgressViewer(){
    if(!RUNTIME_PROGRESS_VIEWER && window.NMRuntimeProgressViewer){
      const viewer = new window.NMRuntimeProgressViewer({
        port:PORT,title:'NM OOCV Application Progress',overallTitle:'Overall CV2 progress',
        lowerTitle:'OOCV application progress',pollMs:RUNTIME_PROGRESS_POLL_MS
      });
      const baseUpdate = viewer.update.bind(viewer);
      viewer.update = (payload)=>{
        baseUpdate(payload);
        renderOOCVPerformanceProgress(payload);
      };
      RUNTIME_PROGRESS_VIEWER = viewer;
    }
    return RUNTIME_PROGRESS_VIEWER;
  }
  function showRuntimeProgress(taskId){
    const viewer=runtimeProgressViewer();
    if(viewer) viewer.open(taskId,'Preparing OOCV model application.');
  }
  function finishRuntimeProgress(){
    if(RUNTIME_PROGRESS_VIEWER) RUNTIME_PROGRESS_VIEWER.scheduleAutoClose(900);
  }

  function containers(){ return STATE && STATE.oocv && typeof STATE.oocv === 'object' ? arr(STATE.oocv.containers) : []; }
  function analyses(){ return arr(STATE.analyses); }
  function analysisByIndex(index){ return analyses().find(a=>a.enabled && Number(a.index)===Number(index)); }
  function containerByIndex(index){ return containers().find(c=>Number(c.index)===Number(index)) || null; }
  function readinessFor(analysisIndex,oocvIndex){
    return arr(STATE.readiness).find(r=>Number(r.analysisIndex)===Number(analysisIndex) && Number(r.oocvIndex)===Number(oocvIndex)) || null;
  }
  function selectableContainers(analysisIndex){
    const idx=finiteIndex(analysisIndex);
    if(!idx)return [];
    return containers().filter(c=>{
      const r=readinessFor(idx,c.index);
      return !!(r&&(bool(r.ready)||(r.applicationPreproc&&bool(r.applicationPreproc.hasConfigurableBranch))));
    });
  }
  function mode(){ return el('operationMode').value; }
  function manualMode(){ return el('manualArtifactMode').value; }
  function artifactPaths(){ return arr(MANUAL_FILES.oocvDataMasterFile ? MANUAL_FILES.oocvDataMasterFile : MANUAL_FILES.oocvDataFiles).filter(Boolean); }
  function fileSpec(paths){
    const files=arr(paths).filter(Boolean);
    const master=files.length===1 && /OOCVdatamatMaster/i.test(files[0].split(/[\\/]/).pop());
    return {oocvDataMasterFile:master?files[0]:'',oocvDataFiles:master?[]:files};
  }
  function artifactGrid(){
    const a=analysisByIndex(SELECTED_ANALYSIS),s=STATE.artifactSummary;
    if(!a)return null;
    if(mode()!=='precomputed')return a.GridAct;
    const valid=s && s.precomputedSupported && Number(s.analysisIndex)===Number(SELECTED_ANALYSIS) && Number(s.oocvIndex)===Number(SELECTED_OOCV)
      && !!s.permutationTest === !!el('permutationTest').checked && (!s.permutationTest || Number(s.nPerms)===Number(el('nPerms').value));
    return valid ? s.availableGrid : window.NMRuntimeGridPicker.normalizeGrid(a.ix,a.jx,[]);
  }
  function effectiveGrid(){
    const a=analysisByIndex(SELECTED_ANALYSIS);
    return a ? window.NMRuntimeGridPicker.permitted(GRID_ACT,a.ix,a.jx,artifactGrid()) : [];
  }
  function renderArtifactSummary(){
    const s=STATE.artifactSummary,host=el('artifactSummary'),list=el('manualArtifactSummary');
    const selected=s && Number(s.analysisIndex)===Number(SELECTED_ANALYSIS) && Number(s.oocvIndex)===Number(SELECTED_OOCV);
    if(selected){
      const source=mode()==='precomputed'?(manualMode()==='none'?'Automatic':'Manual'):(manualMode()==='none'?'Automatic':'Automatic (manual pending)');
      const coverage=!s.precomputedSupported?'Multistream replay unsupported':`${s.nAvailable}/${s.nExpected} ${mode()==='precomputed'?'verified':'matched (unverified)'}`;
      host.innerHTML=`<div class="nmRuntimeArtifactTitle">OOCVdatamat artifact inventory</div><table class="nmRuntimeArtifactTable oocvArtifactTable"><thead><tr><th>Analysis / OOCV</th><th>Artifact source</th><th>CV2 coverage</th><th>Files</th><th>Artifact directory</th></tr></thead><tbody><tr><td>${esc(SELECTED_ANALYSIS)} / ${esc(SELECTED_OOCV)}</td><td>${esc(source)}</td><td>${esc(coverage)}</td><td>${esc(s.nFiles)}</td><td class="nmRuntimeArtifactPath" title="${esc(s.directory)}">${esc(s.directory)}</td></tr></tbody></table>`;
    }else host.textContent=SELECTED_ANALYSIS && SELECTED_OOCV ? 'Artifact coverage is not available for this selection.' : 'Select an analysis and OOCV dataset to inspect artifacts.';
    if(manualMode()==='none'){
      MANUAL_FILE_LIST=null;list.textContent='';return;
    }
    const paths=artifactPaths();
    const opts={paths,title:'OOCVdatamat master / CV2 files',emptyText:'No manual artifacts selected.',
      onChange:files=>{MANUAL_FILES=fileSpec(files);renderArtifactSummary();refresh().catch(e=>setMsg(e.message,'danger'));window.NMRunnerStateManager.markChanged();}};
    if(!MANUAL_FILE_LIST){list.innerHTML='';MANUAL_FILE_LIST=window.NMManualArtifactFileList.create(list,opts);}
    else MANUAL_FILE_LIST.update(paths,opts);
  }
  async function pickArtifact(){
    const a=analysisByIndex(SELECTED_ANALYSIS),s=STATE.artifactSummary;
    if(!a)return;
    const id=s && s.dataId ? s.dataId : '';
    const out=await postJson('/api/pickpath',{kind:'file',multiple:true,initial:s && s.directory ? s.directory : a.rootdir,
      filter:`*OOCVdatamat*_ID${id}.mat;*OOCVdatamat*.mat`,title:'Select OOCVdatamat master or CV2 files',timeout:600});
    const picked=arr(out && (out.paths || out.files || out.path || out.file)).filter(Boolean);
    if(!picked.length)return;
    MANUAL_FILES=fileSpec(window.NMManualArtifactFileList.uniquePaths(artifactPaths().concat(picked)));
    el('manualArtifactMode').value='oocvdatamat';
    window.NMRunnerStateManager.markChanged();await refresh();
  }

  function selectedReadiness(){ return readinessFor(SELECTED_ANALYSIS,SELECTED_OOCV); }
  function selectedApplicationPreproc(){
    const r=selectedReadiness();
    return r&&r.applicationPreproc&&typeof r.applicationPreproc==='object'?r.applicationPreproc:null;
  }
  function applicationPreprocBranches(){
    const p=selectedApplicationPreproc();
    return p&&Array.isArray(p.branches)?p.branches:[];
  }
  function hasSelectedAdmissibleOOCV(){
    const c=containerByIndex(SELECTED_OOCV), r=selectedReadiness();
    return !!(c&&r&&bool(r.ready));
  }
  function reconcileOOCVSelection(clearAmbiguous){
    const selectable=selectableContainers(SELECTED_ANALYSIS);
    if(selectable.length===1){ SELECTED_OOCV=finiteIndex(selectable[0].index); return selectable; }
    if(clearAmbiguous || !selectable.some(c=>Number(c.index)===Number(SELECTED_OOCV))) SELECTED_OOCV=null;
    return selectable;
  }
  function noAdmissibleMessage(){
    const a=analysisByIndex(SELECTED_ANALYSIS);
    if(!a) return 'Select one trained analysis before choosing OOCV data.';
    const rows=containers();
    if(!rows.length) return 'No OOCV/application datasets are available. Import and complete OOCV data in DataIO first.';
    const firstBlocker=rows.map(c=>readinessFor(SELECTED_ANALYSIS,c.index)).find(r=>r&&r.message);
    const prefix=`No OOCV/application dataset is suitable for ${a.id||`Analysis ${a.index}`}.`;
    return firstBlocker ? `${prefix} ${firstBlocker.message}` : `${prefix} The required analysis modalities are not available in a compatible completed OOCV container.`;
  }
  function gridForAnalysis(index){
    const a=analysisByIndex(index);
    return a && Array.isArray(a.GridAct) ? a.GridAct : [];
  }


  function renderDatasetSelector(){
    const selectable=reconcileOOCVSelection(false);
    const r=selectedReadiness();
    window.NMOOCVContainerSelector.renderControl(document.querySelector('.oocvDatasetField'),{
      containers:selectable,selectedIndex:SELECTED_OOCV,label:'OOCV/application dataset',
      emptyText:'Select suitable OOCV data for model application',
      unavailableText:'No suitable OOCV data available for model application',
      detail:!selectable.length?noAdmissibleMessage():(r&&!bool(r.ready)?r.message:''),
      disabled:RUNTIME_JOB_ACTIVE,onClick:openDatasetModal
    });
  }

  function openDatasetModal(){
    if(!window.NMModal){ setMsg('OOCV dataset selector modal is unavailable.','danger'); return; }
    const selectable=selectableContainers(SELECTED_ANALYSIS);
    window.NMOOCVContainerSelector.open({
      containers:selectable,selectedIndex:SELECTED_OOCV,
      title:'Select OOCV data for model application',
      intro:'Ready OOCV containers and structurally valid containers requiring configurable OOCV-specific preprocessing are listed.',
      confirmLabel:'Use selected OOCV data',pendingStatus:'special preprocessing required',
      isReady:c=>bool(readinessFor(SELECTED_ANALYSIS,c.index).ready),
      onSelect:index=>{
        SELECTED_OOCV=index;
        renderSelectionDependent();
        refresh().catch(e=>setMsg(e.message,'danger'));
        if(window.NMRunnerStateManager)window.NMRunnerStateManager.markChanged();
      }
    });
  }

  function renderAnalyses(){
    const host=el('analysisList'); if(!host) return;
    if(!window.NMAnalysisCardSelector){
      host.innerHTML='<div class="empty">Analysis selector component unavailable.</div>'; return;
    }
    if(!analysisByIndex(SELECTED_ANALYSIS)) SELECTED_ANALYSIS=null;
    const selected=SELECTED_ANALYSIS?[SELECTED_ANALYSIS]:[];
    const options={
      multiSelect:false,selected,expandMode:'doubleClick',emptyText:STATE.loading?'Loading trained analyses...':'No trained analyses are configured.', 
      onChange:(indices)=>{
        const next=arr(indices).map(Number).filter(Number.isFinite);
        SELECTED_ANALYSIS=next.length?next[0]:null;
        SELECTED_OOCV=null;
        reconcileOOCVSelection(false);
        renderSelectionDependent();
        refresh().catch(e=>setMsg(e.message,'danger'));
        if(window.NMRunnerStateManager)window.NMRunnerStateManager.markChanged();
      }
    };
    if(!ANALYSIS_SELECTOR) ANALYSIS_SELECTOR=window.NMAnalysisCardSelector.create(host,STATE.analyses||[],options);
    else ANALYSIS_SELECTOR.update(STATE.analyses||[],options);
  }

  function renderSelectionDependent(){
    renderDatasetSelector();
    renderApplicationPreproc();
    renderOptions();
    renderArtifactSummary();
    renderGrid();
  }

  function renderApplicationPreproc(){
    const field=el('applicationPreprocField'),host=el('applicationPreprocBranches'),status=el('applicationPreprocStatus');
    if(!field||!host)return;
    const ap=selectedApplicationPreproc();
    const branches=applicationPreprocBranches().filter(b=>bool(b.canConfigure));
    const show=!!(ap&&bool(ap.supported)&&branches.length&&finiteIndex(SELECTED_ANALYSIS)&&finiteIndex(SELECTED_OOCV));
    field.classList.toggle('hidden',!show);
    if(!show){host.innerHTML='';if(status)status.textContent='';return;}
    if(status)status.textContent=branches.some(b=>bool(b.configured))?'application-specific settings stored':'special preprocessing available';
    host.innerHTML='';
    branches.forEach(b=>{
      const row=document.createElement('div');row.className='oocvGridSummary';
      const details=[];
      if(bool(b.featureImputationAvailable))details.push(`${Number(b.nMissingPredictorRows||0)} active row(s) with missing predictors`);
      if(bool(b.labelImputationAvailable))details.push(`${Number(b.nMissingLabelRows||0)} active row(s) with missing labels`);
      if(bool(b.configured))details.push('configured');
      const mods=arr(b.modalities).map(Number).filter(Number.isFinite).join(', ');
      const label=String(b.fusionMode||'')==='early'?`Effective early-fusion branch (modalities ${mods||'—'})`:`PREPROC{${Number(b.preprocIndex)}} / modality ${mods||Number(b.preprocIndex)}`;
      const text=document.createElement('div');text.innerHTML=`<strong>${esc(label)}</strong><div class="muted">${esc(details.join(' · ')||'Application-specific preprocessing available.')}</div>`;
      const btn=document.createElement('button');btn.type='button';btn.className='nmActionButton';btn.textContent=bool(b.configured)?'Modify special preprocessing…':'Configure special preprocessing…';
      btn.disabled=RUNTIME_JOB_ACTIVE||!!ACTIVE_APPLICATION_PREPROC;
      btn.addEventListener('click',()=>openApplicationPreproc(Number(b.preprocIndex)).catch(e=>setMsg(e.message||String(e),'danger')));
      row.appendChild(text);row.appendChild(btn);host.appendChild(row);
    });
  }

  async function openApplicationPreproc(preprocIndex){
    if(ACTIVE_APPLICATION_PREPROC)return;
    if(!finiteIndex(SELECTED_ANALYSIS)||!finiteIndex(SELECTED_OOCV))throw new Error('Select one trained analysis and OOCV/application dataset first.');
    const p=finiteIndex(preprocIndex);if(!p)throw new Error('Invalid OOCV application preprocessing branch.');
    const branch=applicationPreprocBranches().find(b=>Number(b.preprocIndex)===p);
    if(!branch||!bool(branch.canConfigure))throw new Error(`PREPROC{${p}} has no configurable OOCV-specific preprocessing requirement.`);
    const out=await matlabService({operation:'oocv_runner_prepare_preproc',analysisIndex:SELECTED_ANALYSIS,oocvIndex:SELECTED_OOCV,preprocIndex:p,timeout:600});
    if(!out||out.ok===false||out.error)throw new Error(serviceMessage(out,'Preparing OOCV application preprocessing failed.'));
    ACTIVE_APPLICATION_PREPROC={analysisIndex:SELECTED_ANALYSIS,oocvIndex:SELECTED_OOCV,preprocIndex:p,module:out.module||`preproc_var${p}`};
    const a=analysisByIndex(SELECTED_ANALYSIS),c=containerByIndex(SELECTED_OOCV);
    const title=el('applicationPreprocModalTitle'),path=el('applicationPreprocModalPath');
    if(title)title.textContent='OOCV application preprocessing';
    if(path)path.textContent=`${a?(a.id||`Analysis ${a.index}`):`Analysis ${SELECTED_ANALYSIS}`} → ${c?(c.description||`OOCV ${c.index}`):`OOCV ${SELECTED_OOCV}`} → PREPROC{${p}}`;
    const url=`nm_preproc_pipeline_ui.html?port=${encodeURIComponent(PORT)}&module=${encodeURIComponent(ACTIVE_APPLICATION_PREPROC.module)}&embedded=1&restoreNav=0`;
    const frame=el('applicationPreprocFrame');if(frame)frame.src=window.NMBridgeNavigationURL?window.NMBridgeNavigationURL(url):url;
    const modal=el('applicationPreprocModal');if(modal)modal.classList.add('open');
    renderRunState();renderApplicationPreproc();
  }

  function requestApplicationPreprocFinish(){
    if(!ACTIVE_APPLICATION_PREPROC){closeApplicationPreproc();return;}
    const frame=el('applicationPreprocFrame');
    try{if(frame&&frame.contentWindow){frame.contentWindow.postMessage({type:'nm-request-finish'},'*');return;}}catch(_e){}
    setMsg('Could not contact the embedded preprocessing configurator.','danger');
  }

  function closeApplicationPreproc(){
    const frame=el('applicationPreprocFrame');if(frame)frame.src='about:blank';
    const modal=el('applicationPreprocModal');if(modal)modal.classList.remove('open');
    ACTIVE_APPLICATION_PREPROC=null;renderRunState();renderApplicationPreproc();
  }

  async function applyFinishedApplicationPreproc(data){
    if(!ACTIVE_APPLICATION_PREPROC)return;
    const sel=ACTIVE_APPLICATION_PREPROC;
    const module=String((data&&data.module)||'');
    if(module&&module!==sel.module)throw new Error(`Unexpected preprocessing child module ${module}; expected ${sel.module}.`);
    const out=await matlabService({operation:'oocv_runner_apply_preproc',analysisIndex:sel.analysisIndex,oocvIndex:sel.oocvIndex,preprocIndex:sel.preprocIndex,timeout:600});
    if(!out||out.ok===false||out.error)throw new Error(serviceMessage(out,'Saving OOCV application preprocessing failed.'));
    if(out.state){
      const keepA=SELECTED_ANALYSIS,keepO=SELECTED_OOCV;
      STATE=out.state;SELECTED_ANALYSIS=analysisByIndex(keepA)?keepA:finiteIndex(STATE.selectedAnalysisIndex);SELECTED_OOCV=keepO;
      reconcileOOCVSelection(false);ANALYSIS_SELECTOR=null;GRID_PICKER=null;
    }
    closeApplicationPreproc();await refresh().catch(e=>setMsg(`Preprocessing saved, but OOCV artifact refresh failed: ${e.message}`,'warning'));
  }

  function renderOptions(){
    const c=containerByIndex(SELECTED_OOCV);
    const labelsKnown=!!(c&&hasSelectedAdmissibleOOCV()&&bool(c.labelsKnown));
    const permGroup=el('permutationGroup'); if(permGroup) permGroup.classList.toggle('hidden',!labelsKnown);
    const perm=el('permutationTest');
    if(perm && !labelsKnown) perm.checked=false;
    const nrow=el('nPermsRow'); if(nrow) nrow.classList.toggle('hidden',!(labelsKnown&&perm&&perm.checked));
    const save=el('saveParams');
    const saveCV1Row=el('saveCV1Row'); if(saveCV1Row) saveCV1Row.classList.toggle('hidden',!(save&&save.checked));
    renderRunState();
  }

  function renderGrid(){
    const host=el('gridPicker'); if(!host) return;
    const a=analysisByIndex(SELECTED_ANALYSIS);
    if(!a || !(Number(a.ix)>0) || !(Number(a.jx)>0)){
      host.innerHTML='<div class="empty">Select a trained analysis with a CV2 grid.</div>';
      return;
    }
    GRID_ACT = reconcileGrid(GRID_ACT, {visible:true, ix:Number(a.ix), jx:Number(a.jx), GridAct:a.GridAct}, [SELECTED_ANALYSIS]);
    const n=selectedCount(GRID_ACT), executable=selectedCount(effectiveGrid());
    window.NMRuntimeGridPicker.renderSummary(host, {
      ix:a.ix, jx:a.jx, selectedCount:n, executableCount:executable,
      buttonId:'editGrid', onEdit:()=>openGridModal(a),
      disabled:RUNTIME_JOB_ACTIVE||!hasSelectedAdmissibleOOCV()
    });
  }

  function openGridModal(a){
    if(!window.NMModal||!window.NMRuntimeGridPicker){ setMsg('Grid picker components are unavailable.','danger'); return; }
    const allowed=artifactGrid();
    let working=window.NMRuntimeGridPicker.permitted(GRID_ACT,a.ix,a.jx,allowed);
    window.NMModal.open({
      title:'Select CV2 partitions',className:'oocvGridModal',
      render:(body)=>{
        const host=document.createElement('div'); body.appendChild(host);
        GRID_PICKER=window.NMRuntimeGridPicker.create(host,{ix:a.ix,jx:a.jx,GridAct:working,enabledMask:allowed,requireAny:true}, {onChange:(G)=>{working=G;}});
      },
      actions:[
        {label:'Cancel',onClick:m=>m.close()},
        {label:'Apply',variant:'primary',onClick:m=>{
          const current=window.NMRuntimeGridPicker.permitted(GRID_ACT,a.ix,a.jx,allowed);
          GRID_ACT=GRID_ACT.map((row,i)=>row.map((v,j)=>v&&!current[i][j]||working[i][j]));
          GRID_PICKER=null;renderGrid();renderRunState();window.NMRunnerStateManager.markChanged();m.close();}}
      ],
      onClose:()=>{GRID_PICKER=null;}
    });
  }

  function collectOptions(){
    return {
      operationMode:mode(),manualArtifactMode:manualMode(),manualFiles:MANUAL_FILES,
      overwrite:!!(el('overwriteExisting')&&el('overwriteExisting').checked),
      saveparam:!!(el('saveParams')&&el('saveParams').checked),
      saveCV1:!!(el('saveCV1')&&el('saveCV1').checked),
      permutationTest:!!(el('permutationTest')&&el('permutationTest').checked),
      nPerms:Math.max(1,Math.round(Number(el('nPerms')&&el('nPerms').value)||1000))
    };
  }
  function collectPlan(){ return {analysisIndex:SELECTED_ANALYSIS,oocvIndex:SELECTED_OOCV,gridAction:GRID_ACT,options:collectOptions()}; }

  function validateRunState(){
    if(STATE.loading) return {ok:false,code:'loading',message:'OOCV runner state is still loading.'};
    if(!(STATE.defs&&bool(STATE.defs.analyses_locked))) return {ok:false,code:'mode',message:'Activate Application/OOCV mode before applying trained models.'};
    if(!STATE.backendAvailable) return {ok:false,code:'backend',message:'The OOCV application backend is unavailable on the MATLAB path.'};
    const a=analysisByIndex(SELECTED_ANALYSIS); if(!a) return {ok:false,code:'analysis',message:'Select one trained analysis.'};
    const selectable=selectableContainers(SELECTED_ANALYSIS);
    if(!selectable.length) return {ok:false,code:'no_oocv',message:noAdmissibleMessage()};
    const c=containerByIndex(SELECTED_OOCV); if(!c) return {ok:false,code:'select_oocv',message:'Select OOCV data for model application or special preprocessing configuration.'};
    const r=readinessFor(SELECTED_ANALYSIS,SELECTED_OOCV);
    if(!r) return {ok:false,code:'readiness',message:'Analysis-specific OOCV readiness has not been resolved.'};
    if(!bool(r.ready)) return {ok:false,code:'readiness',message:r.message||'The selected OOCV/application dataset is not ready for this analysis.'};
    const total=Number(a.ix||0)*Number(a.jx||0);
    if(total>0&&selectedCount(effectiveGrid())<1) return {ok:false,code:'grid',message:'No selected trained CV2 partition is executable with the current OOCVdatamat coverage.'};
    const o=collectOptions();
    if(o.permutationTest&&!bool(r.labelsKnown)) return {ok:false,code:'labels',message:'Permutation analysis requires known OOCV labels.'};
    if(o.permutationTest&&(!Number.isFinite(o.nPerms)||o.nPerms<1)) return {ok:false,code:'permutations',message:'Enter a positive number of permutations.'};
    return {ok:true,code:'ready',message:'Ready to apply the selected trained analysis to the selected OOCV/application dataset.'};
  }

  function renderRunState(){
    const v=validateRunState(), running=RUNTIME_JOB_ACTIVE, editing=!!ACTIVE_APPLICATION_PREPROC;
    const run=el('runOOCV'), gen=el('generateRuntimeScript'), hint=el('runHint'), finish=el('finish');
    const selectionReady=hasSelectedAdmissibleOOCV();
    ['operationMode','manualArtifactMode','pickArtifactFile','overwriteExisting','saveParams','saveCV1','permutationTest','nPerms'].forEach(id=>{const x=el(id);if(x)x.disabled=running||!selectionReady;});
    const edit=el('editGrid'); if(edit) edit.disabled=running||!selectionReady;
    const select=el('selectOOCVDataset'); if(select) select.disabled=running||selectableContainers(SELECTED_ANALYSIS).length<1;
    if(run) run.disabled=!v.ok||running||editing;
    if(gen) gen.disabled=!v.ok||running||editing;
    if(finish) finish.disabled=running||editing;
    if(hint) hint.textContent=running?'OOCV model application is running in MATLAB. Closing the browser tab detaches from the viewer but does not cancel the MATLAB job.':'';
  }

  function injectPerformanceHost(){
    const panel=el('nmRuntimeProgressPanel');
    if(!panel) return null;
    let host=el('oocvRuntimePerformance');
    if(!host){
      host=document.createElement('section');
      host.id='oocvRuntimePerformance';
      host.className='nmRuntimeProgressSection oocvRuntimePerformance';
      host.innerHTML='<div class="nmRuntimeProgressLabel">OOCV performance evolution</div><div id="oocvRuntimePerformanceBody" class="oocvRuntimePerformanceBody"></div>';
      panel.appendChild(host);
    }
    return el('oocvRuntimePerformanceBody');
  }

  function renderOOCVPerformanceProgress(payload){
    const chart=payload&&payload.chart&&typeof payload.chart==='object'?payload.chart:null;
    if(!chart||String(chart.kind||'')!=='oocv_progress') return;
    const host=injectPerformanceHost(); if(!host) return;
    if(!bool(chart.performanceAvailable)){
      host.innerHTML=`<div class="oocvProgressEmpty">${esc(chart.performanceMessage||'Prediction-only OOCV dataset: performance traces are unavailable because labels are not supplied.')}</div>`;
      return;
    }
    const groups=arr(chart.groups);
    if(!groups.length){ host.innerHTML='<div class="oocvProgressEmpty">No OOCV performance series are available yet.</div>'; return; }
    host.innerHTML='<div class="oocvProgressLegend">Circle/solid = decision-score performance · diamond/dashed = hard-prediction performance · navy cross = multiclass performance · top = cumulative ensemble · bottom = current CV2 partition</div>'+
      `<div class="oocvProgressChartGrid">${groups.map((g,gi)=>progressGroupHtml(g,chart,gi)).join('')}</div>`;
  }

  function progressGroupHtml(group,chart,groupIndex){
    const name=esc(group.name||`Group ${groupIndex+1}`);
    return `<div class="oocvProgressGroup"><div class="oocvProgressGroupTitle">${name}</div>${progressAxisHtml(group.overall,chart,'Cumulative ensemble',false)}${progressAxisHtml(group.current,chart,'Current CV2',true)}</div>`;
  }

  function oocvSeriesAppearance(series,seriesIndex){
    const kind=String(series&&series.kind||'score').toLowerCase();
    if(kind==='multiclass') return {kind:'multiclass',color:'#153552'};
    const palette=['#316cec','#d46a2f','#25836f','#7b5bc7','#c44f68','#5b7189'];
    const classIndex=Math.max(1,Math.round(Number(series&&series.classIndex)||seriesIndex+1));
    return {kind:kind==='target'?'target':'score',color:palette[(classIndex-1)%palette.length]};
  }

  function progressAxisHtml(axis,chart,title,showXAxis){
    const series=arr(axis&&axis.series);
    const yLimits=arr(chart.yLimits).map(Number).filter(Number.isFinite);
    const valid=series.filter(s=>arr(s.values).some(v=>Number.isFinite(Number(v))));
    if(!valid.length) return `<div class="oocvProgressAxis"><div class="oocvProgressAxisTitle">${esc(title)}</div><div class="oocvProgressEmpty">Waiting for performance values.</div></div>`;
    const W=360,H=showXAxis?100:88,padL=52,padR=7,padT=6,padB=showXAxis?18:6,innerW=W-padL-padR,innerH=H-padT-padB;
    let all=[];
    valid.forEach(s=>arr(s.values).forEach(v=>{const n=Number(v);if(Number.isFinite(n))all.push(n);}));
    let ymin=yLimits.length>=2?yLimits[0]:Math.min(...all), ymax=yLimits.length>=2?yLimits[1]:Math.max(...all);
    if(!Number.isFinite(ymin)||!Number.isFinite(ymax)){ymin=0;ymax=1;}
    if(ymin===ymax){const d=Math.max(1,Math.abs(ymin)*0.1);ymin-=d;ymax+=d;}
    const maxN=Math.max(2,...valid.map(s=>arr(s.values).length));
    const x=(i)=>padL+(i/(maxN-1))*innerW;
    const y=(v)=>padT+(1-(v-ymin)/(ymax-ymin))*innerH;
    const ticks=Array.from({length:6},(_,i)=>{const t=i/5;return {v:ymin+t*(ymax-ymin),yy:padT+(1-t)*innerH};});
    const grid=ticks.map(t=>`<line x1="${padL}" y1="${t.yy}" x2="${W-padR}" y2="${t.yy}" class="oocvProgressGridLine"/><text x="${padL-4}" y="${t.yy+2.4}" text-anchor="end" class="oocvProgressTick">${esc(formatMetric(t.v))}</text>`).join('');
    const scorePaths=[];
    const targetPaths=[];
    const multiPaths=[];
    const scoreMarkers=[];
    const targetMarkers=[];
    const multiMarkers=[];
    valid.forEach((s,si)=>{
      const vals=arr(s.values);
      const appearance=oocvSeriesAppearance(s,si);
      let d='',open=false;
      vals.forEach((v,i)=>{
        const n=Number(v);
        if(!Number.isFinite(n)){open=false;return;}
        const px=x(i),py=y(n),cmd=open?'L':'M';
        d+=`${cmd}${px.toFixed(2)},${py.toFixed(2)} `;open=true;
        if(appearance.kind==='target'){
          targetMarkers.push(`<rect x="${(px-2.3).toFixed(2)}" y="${(py-2.3).toFixed(2)}" width="4.6" height="4.6" transform="rotate(45 ${px.toFixed(2)} ${py.toFixed(2)})" class="oocvProgressMarker target" style="--series-color:${appearance.color}"/>`);
        }else if(appearance.kind==='multiclass'){
          multiMarkers.push(`<path d="M${(px-2.1).toFixed(2)},${py.toFixed(2)} L${(px+2.1).toFixed(2)},${py.toFixed(2)} M${px.toFixed(2)},${(py-2.1).toFixed(2)} L${px.toFixed(2)},${(py+2.1).toFixed(2)}" class="oocvProgressMarker multiclass" style="--series-color:${appearance.color}"/>`);
        }else{
          scoreMarkers.push(`<circle cx="${px.toFixed(2)}" cy="${py.toFixed(2)}" r="1.45" class="oocvProgressMarker score" style="--series-color:${appearance.color}"/>`);
        }
      });
      const path=`<path d="${d.trim()}" class="oocvProgressSeries ${appearance.kind}" style="--series-color:${appearance.color}"/>`;
      if(appearance.kind==='target') targetPaths.push(path);
      else if(appearance.kind==='multiclass') multiPaths.push(path);
      else scorePaths.push(path);
    });
    const labels=valid.map((s,si)=>{
      const appearance=oocvSeriesAppearance(s,si);
      return `<span class="oocvProgressSeriesLabel ${appearance.kind}" style="--series-color:${appearance.color}"><span class="oocvProgressLegendSwatch ${appearance.kind}"></span>${esc(s.label||`Series ${si+1}`)}</span>`;
    }).join('');
    const yAxisLabel=String(chart.yLabel||'Performance');
    const yAxisX=9,yAxisY=padT+innerH/2;
    const yLabel=`<text x="${yAxisX}" y="${yAxisY}" text-anchor="middle" transform="rotate(-90 ${yAxisX} ${yAxisY})" class="oocvProgressYAxisLabel">${esc(yAxisLabel)}</text>`;
    const xLabel=showXAxis?`<text x="${padL+innerW/2}" y="${H-3}" text-anchor="middle" class="oocvProgressAxisLabel">Processed CV2 partitions</text>`:'';
    return `<div class="oocvProgressAxis"><div class="oocvProgressAxisTitle">${esc(title)}</div><svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(title)} OOCV performance chart; ${esc(yAxisLabel)}">${grid}${yLabel}<line x1="${padL}" y1="${padT+innerH}" x2="${W-padR}" y2="${padT+innerH}" class="oocvProgressAxisLine"/>${scorePaths.join('')}${multiPaths.join('')}${targetPaths.join('')}${targetMarkers.join('')}${multiMarkers.join('')}${scoreMarkers.join('')}${xLabel}</svg><div class="oocvProgressSeriesLabels">${labels}</div></div>`;
  }
  function formatMetric(v){ if(Math.abs(v)>=100||Math.abs(v)<0.01&&v!==0)return Number(v).toExponential(1);return Number(v).toFixed(2); }

  async function applyRunResult(out){
    if(out&&out.ok){
      if(out.state){
        const keepA=SELECTED_ANALYSIS, keepO=SELECTED_OOCV;
        STATE=out.state;
        SELECTED_ANALYSIS=analysisByIndex(keepA)?keepA:finiteIndex(STATE.selectedAnalysisIndex);
        SELECTED_OOCV=keepO;
        reconcileOOCVSelection(false);
        ANALYSIS_SELECTOR=null; GRID_PICKER=null; renderAll();
        await refresh().catch(e=>setMsg(`OOCV run completed, but artifact refresh failed: ${e.message}`,'warning'));
      }
      finishRuntimeProgress();
      return;
    }
    if(RUNTIME_PROGRESS_VIEWER) RUNTIME_PROGRESS_VIEWER.hide();
    throw new Error(serviceMessage(out,'Running OOCV model application failed.'));
  }

  async function runOOCV(){
    const v=validateRunState(); if(!v.ok){setMsg(v.message,'warning');return;}
    const client=runtimeJobClient(); if(!client){setMsg('The durable MATLAB runtime-job client is unavailable.','danger');return;}
    try{if(window.NMRunnerStateManager)await window.NMRunnerStateManager.syncNow();}
    catch(err){setMsg(`OOCV model application cannot start because its runner setup could not be saved: ${err.message||String(err)}`,'danger');return;}
    const progressTaskId=createRuntimeProgressTaskId('oocv');
    showRuntimeProgress(progressTaskId);
    RUNTIME_JOB_ACTIVE=true; renderRunState();
    try{
      const servicePayload={operation:'oocv_runner_run',plan:collectPlan(),progressTaskId,progressChartMinIntervalSeconds:RUNTIME_PROGRESS_WRITE_INTERVAL_SECONDS};
      const out=await client.run(servicePayload,{jobId:progressTaskId,progressTaskId});
      await applyRunResult(out);
    }catch(err){
      setMsg(`Running OOCV model application failed: ${err.message||String(err)}`,'danger');
    }finally{RUNTIME_JOB_ACTIVE=false;renderRunState();}
  }

  async function resumeRuntimeJobIfPresent(){
    const client=runtimeJobClient(); if(!client)return false;
    const pending=await client.find('oocv_runner_run');
    if(!pending||!pending.jobId)return false;
    const progressTaskId=String(pending.progressTaskId||''); if(progressTaskId)showRuntimeProgress(progressTaskId);
    RUNTIME_JOB_ACTIVE=true;renderRunState();
    try{const out=await client.wait(pending.jobId);await applyRunResult(out);}
    catch(err){setMsg(`Running OOCV model application failed: ${err.message||String(err)}`,'danger');}
    finally{RUNTIME_JOB_ACTIVE=false;renderRunState();}
    return true;
  }

  async function generateRuntimeScript(){
    const v=validateRunState(); if(!v.ok){setMsg(v.message,'warning');return;}
    const out=await matlabService({operation:'oocv_runner_generate_script',plan:collectPlan(),timeout:120});
    if(out&&out.ok)setMsg(out.message||'OOCV runtime script generated.','success');
    else setMsg(serviceMessage(out,'Generating the OOCV runtime script failed.'),serviceSeverity(out,'danger'));
  }

  async function refresh(light=false){
    const keepA=SELECTED_ANALYSIS,keepO=SELECTED_OOCV;
    const out=await matlabService({operation:light?'oocv_runner_refresh_light':'oocv_runner_refresh',plan:collectPlan()});
    if(out&&out.ok&&out.state){
      STATE=out.state;
      SELECTED_ANALYSIS=analysisByIndex(keepA)?keepA:finiteIndex(STATE.selectedAnalysisIndex);
      SELECTED_OOCV=keepO;
      reconcileOOCVSelection(false);
      ANALYSIS_SELECTOR=null;GRID_PICKER=null;renderAll();
      if(!light && SELECTED_OOCV && Number(keepO)!==Number(SELECTED_OOCV)) await refresh();
    }else throw new Error(serviceMessage(out,'OOCV runner refresh failed.'));
  }

  function workbenchReturnUrl(){
    const target=appContext().returnPage||'nm_workbench.html';
    const sep=target.includes('?')?'&':'?';
    return `${target}${sep}port=${encodeURIComponent(PORT)}&_nmcb=${Date.now()}`;
  }
  function isWorkbenchChild(){
    const ctx=appContext();
    return bool(ctx.returnToWorkbench)||String(ctx.caller||'').toLowerCase()==='workbench';
  }
  async function finish(){
    if(RUNTIME_JOB_ACTIVE){setMsg('The OOCV runtime job is still active. Leave this page open or close the browser tab to detach.','warning');return;}
    if(ACTIVE_APPLICATION_PREPROC){setMsg('Return from the application preprocessing configurator before closing the OOCV runner.','warning');return;}
    try{
      if(window.NMRunnerStateManager)await window.NMRunnerStateManager.syncNow();
      if(isWorkbenchChild()){
        const out=await matlabService({operation:'app_child_return',source:'oocv_runner',timeout:120});
        if(!out || out.ok!==true) throw new Error(serviceMessage(out,'Returning to the workbench failed.'));
        window.location.replace(window.NMBridgeNavigationURL?window.NMBridgeNavigationURL(workbenchReturnUrl()):workbenchReturnUrl());
        return;
      }
      window.close();
    }catch(err){setMsg(`ERROR while closing OOCV runner: ${err.message||String(err)}`,'danger');}
  }

  function updateFinishButton(){
    window.NMModuleNavigationRail.updateReturnButton(appContext(),'Finish / close');
  }

  function bind(){
    const f=el('finish');if(f)f.addEventListener('click',()=>finish().catch(e=>setMsg(e.message,'danger')));
    ['overwriteExisting','saveParams','saveCV1','permutationTest','nPerms'].forEach(id=>{
      const x=el(id); if(!x)return;
      x.addEventListener(id==='nPerms'?'input':'change',()=>{
        renderOptions();
        if(mode()==='precomputed' && (id==='permutationTest' || id==='nPerms')) refresh().catch(e=>setMsg(e.message,'danger'));
      });
    });
    ['operationMode','manualArtifactMode'].forEach(id=>el(id).addEventListener('change',()=>{
      renderSelectionDependent();refresh().catch(e=>setMsg(e.message,'danger'));window.NMRunnerStateManager.markChanged();
    }));
    el('pickArtifactFile').addEventListener('click',()=>pickArtifact().catch(e=>setMsg(e.message,'danger')));
    const run=el('runOOCV');if(run)run.addEventListener('click',()=>runOOCV().catch(e=>setMsg(e.message,'danger')));
    const gen=el('generateRuntimeScript');if(gen)gen.addEventListener('click',()=>generateRuntimeScript().catch(e=>setMsg(e.message,'danger')));
    const back=el('applicationPreprocBack');if(back)back.addEventListener('click',requestApplicationPreprocFinish);
    window.addEventListener('message',ev=>{if(ev&&ev.data&&ev.data.type==='nm-module-done'&&ACTIVE_APPLICATION_PREPROC){applyFinishedApplicationPreproc(ev.data).catch(e=>setMsg(`Configurator saved, but MATLAB state update failed: ${e.message||String(e)}`,'danger'));}});
  }

  function renderAll(){
    updateFinishButton();renderAnalyses();reconcileOOCVSelection(false);renderSelectionDependent();
    if(window.NMModuleNavigationRail&&typeof window.NMModuleNavigationRail.refresh==='function')window.NMModuleNavigationRail.refresh();
  }

  function installRunnerStateAdapter(){
    if(!window.NMRunnerStateManager)return;
    window.NMRunnerStateManager.registerAdapter({
      key:'oocv_runner',
      snapshot:()=>collectPlan(),
      restore:async(saved)=>{
        if(!saved||typeof saved!=='object')return;
        const analysisIndices=new Set(analyses().filter(a=>a.enabled!==false).map(a=>Number(a.index)));
        const requestedAnalysis=finiteIndex(saved.analysisIndex);
        SELECTED_ANALYSIS=analysisIndices.has(Number(requestedAnalysis))?requestedAnalysis:null;
        const containerIndices=new Set(containers().map(c=>Number(c.index)));
        const requestedOOCV=finiteIndex(saved.oocvIndex);
        SELECTED_OOCV=containerIndices.has(Number(requestedOOCV))?requestedOOCV:null;
        if(Array.isArray(saved.gridAction))GRID_ACT=saved.gridAction;
        const o=saved.options&&typeof saved.options==='object'?saved.options:{};
        if(o.operationMode)el('operationMode').value=o.operationMode;
        if(o.manualArtifactMode)el('manualArtifactMode').value=o.manualArtifactMode;
        MANUAL_FILES=fileSpec(arr(o.manualFiles && (o.manualFiles.oocvDataMasterFile || o.manualFiles.oocvDataFiles)));
        if(typeof o.overwrite==='boolean'&&el('overwriteExisting'))el('overwriteExisting').checked=o.overwrite;
        if(typeof o.saveparam==='boolean'&&el('saveParams'))el('saveParams').checked=o.saveparam;
        if(typeof o.saveCV1==='boolean'&&el('saveCV1'))el('saveCV1').checked=o.saveCV1;
        if(typeof o.permutationTest==='boolean'&&el('permutationTest'))el('permutationTest').checked=o.permutationTest;
        if(Number.isFinite(Number(o.nPerms))&&el('nPerms'))el('nPerms').value=String(Math.max(1,Math.round(Number(o.nPerms))));
        ANALYSIS_SELECTOR=null;GRID_PICKER=null;renderAll();
        if(SELECTED_ANALYSIS&&SELECTED_OOCV)await refresh();
      },
      report:(message)=>setMsg(message,'danger')
    });
  }
  installRunnerStateAdapter();
  document.addEventListener('DOMContentLoaded',()=>{
    bind();renderAll();
    (async()=>{
      if(STATE.loading)await refresh(true);
      await refresh();
      if(window.NMRunnerStateManager)await window.NMRunnerStateManager.markReady();
      await resumeRuntimeJobIfPresent();
    })().catch(e=>setMsg(`OOCV runner initialization failed: ${e.message||String(e)}`,'danger'));
  });
})();