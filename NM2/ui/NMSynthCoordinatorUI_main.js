(function(){
'use strict';
const S=window.NM_SYNTH_COORDINATOR_STATE;
const PORT=new URLSearchParams(window.location.search).get('port')||'4821';
const api=`http://127.0.0.1:${PORT}/api/matlabservice`;
const $=id=>document.getElementById(id);
$('synthBack').insertAdjacentHTML('afterbegin',window.NMModuleIconSet.svg('back'));
const jump=new URLSearchParams(window.location.search);
let experiments=S.experiments, running=false, renderedDefinition='', syntheticDefinition=null, definitionLoading=false;
let addMode=S.existingDataReady?'existing':'synthetic';
const progressViewer=new window.NMRuntimeProgressViewer({port:PORT,title:'SYNTH simulation progress',overallTitle:'Current analysis · CV2 progress',lowerTitle:'Optimization progress',stageUnit:'Hyperparameter combinations'});
function clientFor(item){return new window.NMRuntimeJobClient({port:PORT,storageKey:`nm2_synth_runtime_job_${PORT}_${item.id}`,pollMs:750});}
function openRunProgress(item,taskId,message,parallelEnabled){
 progressViewer.stageOnly=item.mode==='fully_synthetic'&&parallelEnabled;
 progressViewer.stageTotal=progressViewer.stageOnly?item.nCombinations:0;
 progressViewer.open(taskId,message);
}
function msg(text,error){window.NMUIMessageTools.setMessage(text,error?'danger':'info');}
function action(fn){return Promise.resolve().then(fn).catch(e=>msg(e.message,true));}
function setBusy(value){running=value;$('synthAdd').disabled=value;$('synthRefresh').disabled=value;$('synthReview').disabled=value;render();}
function locked(fn){
 if(running)return;
 setBusy(true);
 return action(fn).finally(()=>setBusy(false));
}
async function service(payload){
 const res=await fetch(api,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});
 const out=await res.json();if(!res.ok||out.ok===false)throw Error(out.message||out.error||'MATLAB service failed');return out;
}
function go(page){if(page==='existing'||page==='synthetic')addMode=page;document.querySelectorAll('.rvReportTabs button').forEach(b=>{const active=b.dataset.tab===page;b.classList.toggle('isActive',active);b.setAttribute('aria-selected',String(active));});document.querySelectorAll('.synthTab').forEach(p=>p.classList.toggle('hidden',p.id!=='synth-'+page));render();if(page==='synthetic')action(loadSyntheticDefinition);}
document.querySelectorAll('.rvReportTabs button').forEach(b=>b.addEventListener('click',()=>go(b.dataset.tab)));
function field(id){return $(id).value;}
function number(id){return Number(field(id));}
function generator(){
 const method=number('synthMethod');
 document.querySelectorAll('.gmmField').forEach(x=>x.style.display=method===4?'':'none');
}
$('synthMethod').onchange=generator;
function setGenerator(cfg){
 for(const id of ['synthMethod','synthStandardizeData','synthNComponentsText','synthMinMethod','synthUncertaintyScale'])$(id).value=cfg[id];
 generator();
}
setGenerator(S.synth);
$('sourceSummary').textContent=`${S.observedN} observed subjects · ${S.modeflag} · Persistent execution`;
$('synthSizes').value=[S.observedN+4,S.observedN+8,S.observedN+16].join(', ');
$('synthOutput').value=S.defaultOutputDir;
function spec(){
 const raw=field('synthSizes').trim();
 if(!/^\d+(\s*[,;]\s*\d+)*$/.test(raw))throw Error('Enter comma-separated integer cohort sizes.');
 const sampleSizes=raw.split(/[,;]/).map(s=>Number(s.trim()));
 if(sampleSizes.some((n,i)=>n<=S.observedN||(i>0&&n<=sampleSizes[i-1])))throw Error('Cohort sizes must increase and exceed observed N.');
 const shiftPermutations=number('synthPerms'),shiftBlockSize=number('synthBlock'),seed=number('synthSeed');
 if(![shiftPermutations,shiftBlockSize,seed].every(Number.isInteger)||shiftPermutations<1||shiftBlockSize<1||seed<0)throw Error('Permutations and block size must be positive integers; seed must be nonnegative.');
 if(!field('synthOutput').trim())throw Error('Select an output directory.');
 return {sampleSizes,shiftPermutations,shiftBlockSize,seed,outputDir:field('synthOutput').trim()};
}
function synthSpec(){return {synthMethod:number('synthMethod'),synthK:S.synth.synthK,synthDistanceMeasure:S.synth.synthDistanceMeasure,synthStandardizeData:number('synthStandardizeData'),synthNComponentsText:field('synthNComponentsText'),synthMinMethod:number('synthMinMethod'),synthUncertaintyScale:number('synthUncertaintyScale')};}
async function loadSyntheticDefinition(){
 if(!S.fullySyntheticReady||syntheticDefinition||definitionLoading)return;
 definitionLoading=true;
 try{
  const res=await service({operation:'synth_coordinator_definition'});
  syntheticDefinition=res.definition;
  render();
 }finally{definitionLoading=false;}
}
function update(res){
 experiments=res.state.experiments;
 S.fullySyntheticReady=res.state.fullySyntheticReady;
 syntheticDefinition=null;
 S.existingDataReady=res.state.existingDataReady;
 S.observedN=res.state.observedN;
 render();
}
function render(){
 const ready=S.fullySyntheticReady;
 $('synPlaceholderFields').style.display=ready?'none':'';
 $('synInit').style.display=ready?'none':'';
 $('synDefinitionIntro').textContent=ready
  ? 'Existing NM provides the learning task and modality count only. Specify synthetic feature counts and outcome classes below.'
  : 'Define modalities and learning task to initialize a configuration workspace through DataIO.';
 if(ready&&syntheticDefinition){
  const d=syntheticDefinition, key=JSON.stringify(d);
  if(key!==renderedDefinition){
   const M=d.modalityNames.length;
   $('synFeats').value=d.featureCounts.join(';');
   $('synClasses').value=d.classCount;
   $('synClasses').disabled=d.modeflag==='regression';
   $('synMarkers').value=Array(M).fill('0.2').join(';');
   $('synLow').value=Array(M).fill(d.modeflag==='regression'?'0.2':'0.65').join(';');
   $('synHigh').value=Array(M).fill(d.modeflag==='regression'?'0.6':'0.85').join(';');
   $('synEvent').value=d.modeflag==='classification'&&d.classCount===2?'0.5':'0';
   renderedDefinition=key;
  }
 }
 $('synInit').disabled=running||ready;
 $('synConfigure').disabled=!S.fullySyntheticReady;
 $('synthAdd').disabled=running||(addMode==='synthetic'?!syntheticDefinition:!S.existingDataReady);
 $('synthAdd').textContent=addMode==='synthetic'?'Add fully synthetic analysis':'Add existing-data analysis';
 $('synthReview').disabled=running||!S.existingDataReady;
 $('synthExistingTab').disabled=!S.existingDataReady;
 const list=$('synthExperiments');list.replaceChildren();
 for(const item of experiments){
  const panel=document.createElement('div');panel.className='panel rvPlotPanel';
  const title=document.createElement('h3');title.textContent=`${item.id} · ${item.mode==='existing_data'?'Existing Data':'Fully Synthetic Data'}`;panel.append(title);
  const details=document.createElement('p');details.className='muted';
  const completed=item.completed===item.total;
  const registered=item.status==='registered';
  const description=item.mode==='fully_synthetic'
   ? `${item.nCombinations} combinations × ${item.repetitions} repetitions`
   : `N=${item.sampleSizes.join(', ')} · ${item.shiftPermutations} permutations`;
  details.textContent=`${item.rootAvailable?(completed?'Completed':registered?'Registered':'Unfinished'):'Unavailable · experiment directory missing'} · ${item.completed}/${item.total} analyses · ${description}`;
  panel.append(details);
  if(!item.rootAvailable){const path=document.createElement('p');path.className='muted';path.textContent=`Stored directory: ${item.rootdir}`;panel.append(path);}
  const action=document.createElement('button');action.className='primary nmActionButton';action.textContent=completed?'Reconstruct':registered?'Start':'Resume';
  action.disabled=running||!item.rootAvailable;
  action.onclick=()=>completed?reconstruct(item.index):resume(item.index);
  panel.append(action);
  const relinkButton=document.createElement('button');relinkButton.textContent='Relink root';relinkButton.disabled=running;
  relinkButton.onclick=()=>relink(item.index,item.rootdir);panel.append(relinkButton);
  const del=document.createElement('button');del.textContent='Delete';del.disabled=running;
  del.onclick=()=>remove(item.index,item.id);panel.append(del);
  if(item.completed>0){const inspect=document.createElement('button');inspect.textContent='View results';inspect.disabled=running;inspect.onclick=()=>openViewer(item.index);panel.append(inspect);}
  list.append(panel);
 }
}
$('synthReview').onclick=()=>action(()=>{const p=spec();$('synthPlan').textContent=`New analysis: ${p.sampleSizes.join(' → ')} subjects · ${p.shiftPermutations} permutations · seed ${p.seed}`;msg('');go('execution');});
$('synthAdd').onclick=()=>locked(async()=>{
 if(addMode==='synthetic'){
 const M=syntheticDefinition.modalityNames.length;
 const F=groups('synFeats',M),K=groups('synMarkers',M),lo=groups('synLow',M),hi=groups('synHigh',M);
 const regression=syntheticDefinition.modeflag==='regression';
 const modalityFactors=Array.from({length:M},(_,m)=>regression
  ? {NFeats:F[m],NMarkers:K[m],Rmin:lo[m],Rmax:hi[m]}
  : {NFeats:F[m],NMarkers:K[m],AUCmin:lo[m],AUCmax:hi[m]});
 const plan={modalityFactors,NCases:numbers(field('synN')),
  EventProb:numbers(field('synEvent')),NBatches:numbers(field('synBatches')),
  BatchPerc:numbers(field('synBatchStrength')),
  NCasesMiss:numbers(field('synMissingCases')),NFeatsMiss:numbers(field('synMissingFeatures')),
  NReps:number('synReps'),seed:number('synSeed'),classCount:regression?1:number('synClasses'),
  outputDir:field('synOut').trim()};
 if(!plan.outputDir)throw Error('Choose an output directory.');
 update(await service({operation:'synth_coordinator_add_fully',plan}));
 go('execution');msg('Fully synthetic experiment registered.');
 }else{
 const p=spec();
 msg('Registering persistent SYNTH analysis.');
 const res=await service({operation:'synth_coordinator_add',spec:p,synth:synthSpec()});
 update(res);msg('Persistent SYNTH analysis registered. Use Start to execute it.');go('execution');
 }
});
$('synthRefresh').onclick=()=>locked(async()=>{
 msg('Reconciling SYNTH child membership from NM.analysis.');
 update(await service({operation:'synth_coordinator_refresh'}));
 msg('Completed SYNTH analyses reconciled.');
});
async function finishJob(client,jobId,progressTaskId){
 try{
  const res=await client.wait(jobId);
  if(res.ok===false)throw Error(res.message);
  update(res);msg(res.message);progressViewer.scheduleAutoClose(550);
 }catch(e){
  progressViewer.hide();
  throw e;
 }
}
function resume(index){return locked(async()=>{
 const item=experiments.find(x=>x.index===index);
 const client=clientFor(item);
 const stored=client.safeStorageGet();
 let jobId='',progressTaskId='';
 if(stored&&stored.jobId){
  openRunProgress(item,stored.progressTaskId,'Reattaching to SYNTH experiment.',stored.parallelEnabled===true);
  const status=await client.status(stored.jobId);
  if(status.httpStatus===404){progressViewer.hide();client.safeStorageClear(stored.jobId);}
  else{
   jobId=stored.jobId;
   progressTaskId=stored.progressTaskId;
  }
 }
 if(!jobId){
  progressTaskId=window.NMRuntimeProgressViewer.createTaskId('synth');
  const requestedId=window.NMRuntimeJobClient.createJobId(item.id);
  const parallelEnabled=item.mode==='fully_synthetic'&&$('synthParallel').checked;
  openRunProgress(item,progressTaskId,'Submitting SYNTH experiment.',parallelEnabled);
  let accepted;
  try{
   accepted=await client.submit(
    {operation:'synth_coordinator_resume',analysisIndex:index,progressTaskId,
     parallelEnabled},
    {progressTaskId,jobId:requestedId});
  }catch(e){progressViewer.hide();throw e;}
  // The bridge reports a busy job with the same operation when another
  // experiment is running. Such a job must never be adopted as ours.
  if(accepted.jobId!==requestedId){
   client.safeStorageClear(accepted.jobId);
   progressViewer.hide();
   throw Error('Another SYNTH experiment is executing. Resume this experiment after it finishes.');
  }
  client.safeStorageSet({...client.safeStorageGet(),parallelEnabled});
  jobId=requestedId;
 }
 await finishJob(client,jobId,progressTaskId);
});}
function reconstruct(index){return locked(async()=>{
 const item=experiments.find(x=>x.index===index);
 const client=clientFor(item);
 const progressTaskId=window.NMRuntimeProgressViewer.createTaskId('synth_reconstruct');
 const requestedId=window.NMRuntimeJobClient.createJobId(`synth_reconstruct_${item.id}`);
 progressViewer.stageOnly=false;
 progressViewer.open(progressTaskId,'Reconciling child analyses in NM.analysis.');
 let accepted;
 try{
  accepted=await client.submit(
   {operation:'synth_coordinator_reconstruct',analysisIndex:index,progressTaskId},
   {progressTaskId,jobId:requestedId});
 }catch(e){progressViewer.hide();throw e;}
 if(accepted.jobId!==requestedId){
  client.safeStorageClear(accepted.jobId);progressViewer.hide();
  throw Error('Another SYNTH runtime operation is active.');
 }
 const res=await client.wait(requestedId).catch(e=>{progressViewer.hide();throw e;});
 if(res.ok===false){
  progressViewer.hide();
  throw Error(res.message);
 }
 update(res);
 if(item.mode==='existing_data'){
  setGenerator(res.synth);
  $('synthSizes').value=res.configuration.sampleSizes.join(', ');
  $('synthPerms').value=res.configuration.shiftPermutations;
  $('synthBlock').value=res.configuration.shiftBlockSize;
  $('synthSeed').value=res.configuration.seed;
 }
 progressViewer.scheduleAutoClose(550);
 msg('SYNTH child membership restored from NM.analysis; missing children recovered from disk.');
});}
function relink(index,oldRoot){return locked(async()=>{
 const pickResponse=await fetch(`http://127.0.0.1:${PORT}/api/pickpath`,{
  method:'POST',headers:{'Content-Type':'application/json'},
  body:JSON.stringify({kind:'directory',multiple:false,initial:'',
   title:'Select relocated SYNTH experiment directory'})});
 const pick=await pickResponse.json();
 if(!pickResponse.ok)throw Error('Directory selection failed.');
 const paths=Array.isArray(pick.paths)?pick.paths:[pick.paths];
 if(!paths.length)return;
 update(await service({operation:'synth_coordinator_relink_root',
  analysisIndex:index,newRootDir:paths[0]}));
 msg(`SYNTH experiment directory relinked from ${oldRoot}.`);
});}
function remove(index,id){return locked(async()=>{
 if(!window.confirm(`Delete ${id} and its owned child analysis files? This cannot be undone.`))return;
 update(await service({operation:'synth_coordinator_delete',analysisIndex:index}));
 msg(`${id} deleted.`);
});}
async function openViewer(index){
 if(running)return;
 try{
  const res=await service({operation:'app_prepare_page',page:'results_alpha',moduleKey:'results_alpha',timeout:240});
  const target=res.entryHtml;
  if(!target)throw Error('Results Viewer page was not prepared.');
  const params=new URLSearchParams({port:String(PORT),_nmcb:String(Date.now()),synthReturn:'1'});
  if(index>0)params.set('synthExperiment',String(index));
  const route=`${target}?${params}`;
  window.location.replace(window.NMBridgeNavigationURL?window.NMBridgeNavigationURL(route):route);
 }catch(e){msg(e.message,true);}
}
function numbers(v){
 const fields=v.split(',').map(x=>x.trim());
 const a=fields.map(Number);
 if(fields.some(x=>!x)||a.some(x=>!Number.isFinite(x)))throw Error('Invalid numeric parameter axis.');
 return a;
}
function groups(id,n){
 const rows=field(id).split(';');
 if(rows.length!==n)throw Error(`Enter ${n} modality axes for ${id}.`);
 return rows.map(numbers);
}
$('synMode').onchange=()=>{
 const mode=field('synMode');
 if(mode==='multiclass')$('synClasses').value=3;
 if(mode==='binary')$('synClasses').value=2;
 $('synEvent').value=mode==='binary'?'0.5':'0';
 if(mode==='regression'){$('synLow').value='0.2;0.2';$('synHigh').value='0.6;0.6';}
};
$('synClasses').onchange=()=>{
 const mode=syntheticDefinition ? syntheticDefinition.modeflag : field('synMode');
 if(mode!=='regression')$('synEvent').value=number('synClasses')===2?'0.5':'0';
};
$('synInit').onclick=()=>locked(async()=>{
 const modalityNames=field('synNames').split(',').map(x=>x.trim());
 const featureCounts=numbers(field('synWidths'));
 if(modalityNames.some(x=>!x)||new Set(modalityNames).size!==modalityNames.length ||
    modalityNames.length!==featureCounts.length || featureCounts.some(x=>!Number.isInteger(x)||x<1))
  throw Error('Provide unique modality names and one positive feature count for each.');
 const mode=field('synMode');
 const definition={modalityNames,featureCounts,modeflag:mode==='regression'?'regression':'classification',
   classCount:mode==='regression'?1:mode==='binary'?2:number('synClasses')};
 const res=await service({operation:'synth_coordinator_initialize',definition});
 update(res);
 await loadSyntheticDefinition();
 msg('DataIO placeholders finalized. Configure the learning template.');
});
$('synConfigure').onclick=()=>action(async()=>{
 const res=await service({operation:'app_prepare_page',page:'template',moduleKey:'template',parentPage:'synth_coordinator',timeout:240});
 if(!res.entryHtml)throw Error('Training Template is unavailable.');
 const url=`${res.entryHtml}?port=${encodeURIComponent(PORT)}`;
 window.location.replace(window.NMBridgeNavigationURL?window.NMBridgeNavigationURL(url):url);
});
$('synOut').value=S.defaultOutputDir;
$('synthOpenViewer').onclick=()=>openViewer(0);
$('synthBack').onclick=()=>action(async()=>{
 if(running)return;
 await service({operation:'app_child_return',source:'synth_coordinator',timeout:120});
 window.location.replace(window.NMBridgeNavigationURL?window.NMBridgeNavigationURL(`nm_workbench.html?port=${encodeURIComponent(PORT)}`):`nm_workbench.html?port=${encodeURIComponent(PORT)}`);
});
render();
if(!S.existingDataReady)go('synthetic');
if(jump.get('synthTab')==='execution')go('execution');
async function reattach(){
 for(const item of experiments){
  const client=clientFor(item);
  const stored=client.safeStorageGet();
  if(!stored||!stored.jobId)continue;
  openRunProgress(item,stored.progressTaskId,'Reattaching to SYNTH experiment.',stored.parallelEnabled===true);
  const status=await client.status(stored.jobId);
  if(status.httpStatus===404){progressViewer.hide();client.safeStorageClear(stored.jobId);continue;}
  setBusy(true);go('execution');
  try{await finishJob(client,stored.jobId,stored.progressTaskId);}
  finally{setBusy(false);}
  return;
 }
}
action(reattach);
})();
