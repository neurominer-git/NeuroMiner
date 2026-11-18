(function(){
  /**
   * arr  Normalize a nullable scalar or array-like value to an array.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function arr(x){return Array.isArray(x)?x:(x===undefined||x===null?[]:[x]);}
  /**
   * byId  Resolve the by id identifier used to connect UI state with NeuroMiner payload metadata.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function byId(id){return document.getElementById(id);}
  /**
   * asNum  Convert the supplied value into the as num representation expected by the UI.
   * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
   */
  function asNum(v,d){v=Number(v);return Number.isFinite(v)?v:d;}
  /**
   * bool  Provide the bool helper used by recursive feature-elimination subconfiguration UI panel.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function bool(v){return !!v && Number(v)!==0;}
  /**
   * setHidden  Provide the set hidden helper used by recursive feature-elimination subconfiguration UI panel.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function setHidden(id,flag){let e=byId(id); if(e)e.classList.toggle('hidden',!!flag);}
  /**
   * setClosestHidden  Provide the set closest hidden helper used by recursive feature-elimination subconfiguration UI panel.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function setClosestHidden(id,flag){let e=byId(id); if(!e)return; let p=e.closest('.field'); if(p)p.classList.toggle('hidden',!!flag);}
  /**
   * setVal  Provide the set val helper used by recursive feature-elimination subconfiguration UI panel.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setVal(id,v){let e=byId(id); if(e)e.value=(v===undefined||v===null?'':String(v));}
  /**
   * setChk  Provide the set chk helper used by recursive feature-elimination subconfiguration UI panel.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setChk(id,v){let e=byId(id); if(e)e.checked=!!v;}
  /**
   * getPath  Provide the get path helper used by recursive feature-elimination subconfiguration UI panel.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function getPath(o,path,d){let p=path.split('.'),x=o;for(let k of p){if(!x||typeof x!=='object'||!(k in x))return d;x=x[k];}return x===undefined||x===null?d:x;}
  /**
   * setPath  Provide the set path helper used by recursive feature-elimination subconfiguration UI panel.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setPath(o,path,v){let p=path.split('.'),x=o;for(let i=0;i<p.length-1;i++){let k=p[i];if(!x[k]||typeof x[k]!=='object')x[k]={};x=x[k];}x[p[p.length-1]]=v;}
  /**
   * firstImrelief  Provide the first imrelief helper used by recursive feature-elimination subconfiguration UI panel.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function firstImrelief(r){let im=getPath(r,'Filter.imrelief',null);if(Array.isArray(im)){if(!im[0])im[0]={};return im[0];}if(im&&typeof im==='object')return im;if(!r.Filter)r.Filter={};r.Filter.imrelief=[{}];return r.Filter.imrelief[0];}
  /**
   * numVec  Provide the num vec helper used by recursive feature-elimination subconfiguration UI panel.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function numVec(s,d){if(Array.isArray(s))return s;let a=String(s||'').trim().split(/[\s,;]+/).filter(Boolean).map(Number).filter(Number.isFinite);return a.length?a:d;}
  /**
   * escapeHtml  Build the escape html inserted into the browser UI.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function escapeHtml(s){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}

  /**
   * ensureBoosting  Ensure the boosting prerequisite exists before downstream rendering or requests.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function ensureBoosting(E){
    if(!E||typeof E!=='object')E={};
    if(!E.Boosting||typeof E.Boosting!=='object')E.Boosting={};
    let b=E.Boosting;
    if(!b.mode)b.mode='ridge';
    if(b.lambda===undefined)b.lambda=1e-3;
    if(b.alpha===undefined)b.alpha=0;
    if(b.useLogits===undefined)b.useLogits=false;
    if(b.wThreshold===undefined)b.wThreshold=0;
    if(b.clip===undefined)b.clip=1e-7;
    if(b.eta===undefined)b.eta=0.3;
    if(b.T===undefined)b.T=200;
    if(b.shareWeights===undefined)b.shareWeights=false;
    if(!b.Kernel||typeof b.Kernel!=='object')b.Kernel={};
    let k=b.Kernel;
    if(!k.regMode)k.regMode='residual-cov';
    if(!k.diagMode)k.diagMode='one';
    if(!k.scaleTo)k.scaleTo='HHT';
    if(k.autoAlpha===undefined)k.autoAlpha=false;
    if(k.tau===undefined)k.tau=0.10;
    return E;
  }

  /**
   * ensure  Ensure the ensure prerequisite exists before downstream rendering or requests.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function ensure(r){
    if(!r||typeof r!=='object')r={};
    if(!r.Filter)r.Filter={}; if(!r.Wrapper)r.Wrapper={}; if(!r.CV2Class)r.CV2Class={};
    if(r.Filter.flag===undefined)r.Filter.flag=0; if(r.Wrapper.flag===undefined)r.Wrapper.flag=0;
    if(r.Filter.SubSpaceFlag===undefined)r.Filter.SubSpaceFlag=1; if(r.Wrapper.SubSpaceFlag===undefined)r.Wrapper.SubSpaceFlag=0;
    if(r.Filter.SubSpaceStrategy===undefined)r.Filter.SubSpaceStrategy=1; if(r.Filter.SubSpaceCrit===undefined)r.Filter.SubSpaceCrit=0;
    if(r.Wrapper.SubSpaceStrategy===undefined)r.Wrapper.SubSpaceStrategy=1; if(r.Wrapper.SubSpaceCrit===undefined)r.Wrapper.SubSpaceCrit=0;
    if(!r.Filter.EnsembleStrategy)r.Filter.EnsembleStrategy={}; if(!r.Wrapper.EnsembleStrategy)r.Wrapper.EnsembleStrategy={};
    if(!r.CV2Class.EnsembleStrategy)r.CV2Class.EnsembleStrategy={};
    r.Filter.EnsembleStrategy=ensureBoosting(r.Filter.EnsembleStrategy);
    r.Wrapper.EnsembleStrategy=ensureBoosting(r.Wrapper.EnsembleStrategy);
    r.CV2Class.EnsembleStrategy=ensureBoosting(r.CV2Class.EnsembleStrategy);
    if(!r.Filter.PFE)r.Filter.PFE={}; if(!r.Wrapper.PFE)r.Wrapper.PFE={};
    if(!r.Wrapper.GreedySearch)r.Wrapper.GreedySearch={}; if(!r.Wrapper.GreedySearch.EarlyStop)r.Wrapper.GreedySearch.EarlyStop={};
    if(!r.Wrapper.GreedySearch.CritGap)r.Wrapper.GreedySearch.CritGap={}; if(!r.Wrapper.GreedySearch.PERM)r.Wrapper.GreedySearch.PERM={};
    if(!r.Wrapper.GreedySearch.AdRef)r.Wrapper.GreedySearch.AdRef={}; if(!r.Wrapper.GreedySearch.AdRef.Auto)r.Wrapper.GreedySearch.AdRef.Auto={};
    if(!r.Wrapper.GreedySearch.AdRef.Stop)r.Wrapper.GreedySearch.AdRef.Stop={};
    if(!r.Wrapper.SA)r.Wrapper.SA={}; if(!r.Wrapper.GA)r.Wrapper.GA={}; if(!r.Wrapper.PSO)r.Wrapper.PSO={}; if(!r.Wrapper.PFA)r.Wrapper.PFA={};
    if(!r.Filter.FEAST)r.Filter.FEAST={}; if(!r.Filter.MRMR)r.Filter.MRMR={};
    if(!r.Filter.simba)r.Filter.simba={}; if(!r.Filter.simba.extra_param)r.Filter.simba.extra_param={};
    if(!r.Filter.gflip)r.Filter.gflip={}; if(!r.Filter.gflip.extra_param)r.Filter.gflip.extra_param={};
    if(!r.Filter.RGS)r.Filter.RGS={}; if(!r.Filter.RGS.extra_param)r.Filter.RGS.extra_param={};
    if(!r.Filter.RSS)r.Filter.RSS={}; if(!r.Filter.Relief)r.Filter.Relief={};
    if(r.Filter.imrelief===undefined)r.Filter.imrelief=[{distance:'block',sigma:2,lambda:0.1,maxiter:10,plotfigure:false,desc:'IMRelief'}];
    return r;
  }

  let ctx=null, activeTab='overview';
  /**
   * state  Provide the state helper used by recursive feature-elimination subconfiguration UI panel.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function state(){return ctx.getState();}
  /**
   * RFE  Provide the rfe helper used by recursive feature-elimination subconfiguration UI panel.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function RFE(){let s=state(); if(!s.rfe||typeof s.rfe!=='object')s.rfe={}; s.rfe=ensure(s.rfe); return s.rfe;}
  /**
   * mark  Provide the mark helper used by recursive feature-elimination subconfiguration UI panel.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function mark(){let r=RFE(); r.rfeDirty=true; normalize(r); ctx.sync();}

  /**
   * normalizeEnsemble  Normalize ensemble payloads into the browser-side model used by the UI.
   * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
   */
  function normalizeEnsemble(E,mode){
    E=ensureBoosting(E);
    let cm=Number(E.ConstructMode||0); if(![0,1,2,4,5].includes(cm))cm=0; E.ConstructMode=cm;
    if(E.DivCrit===undefined||E.DivCrit===null||E.DivCrit==='')E.DivCrit=2;
    E.DivCrit=Number(E.DivCrit);
    if(!E.DiversitySource)E.DiversitySource=String(mode||'classification').toLowerCase()==='regression'?'regvar':'entropy';
    if(E.DiversityEps===undefined)E.DiversityEps=0.02;
    if(E.PerfSlackPct===undefined)E.PerfSlackPct=0;
    if(E.EntropyWeight===undefined)E.EntropyWeight=2;
    if(E.SizePenalty===undefined)E.SizePenalty=0;
    if(E.Patience===undefined)E.Patience=0;
    if(E.Weighting===undefined)E.Weighting=0;
    if(E.MinNum===undefined)E.MinNum=1;
    if(E.Perc===undefined)E.Perc=75;
    if(String(mode||'classification').toLowerCase()==='regression'){
      if(!(E.DivCrit===2||E.DivCrit===5))E.DivCrit=2;
      E.DiversitySource='regvar';
    }
    E.OptFunc=(E.DivCrit===2)?'CVMax':'DiversityMax';
    switch(cm){
      case 0: E.type=0; break;
      case 1: E.type=(E.OptFunc==='CVMax')?2:1; break;
      case 2: E.type=(E.OptFunc==='CVMax')?6:5; break;
      case 4: E.type=9; E.Mode=4; E.Weighting=0; break;
      case 5: E.type=10; break;
    }
    if(String(mode||'classification').toLowerCase()==='regression'){
      if(cm===5){E.Boosting.mode='ridge';E.Boosting.useLogits=false;}
      if(E.type!==9)E.Metric=1;
    }
    return E;
  }
  /**
   * normalize  Normalize normalize payloads into the browser-side model used by the UI.
   * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
   */
  function normalize(r){
    r=ensure(r);
    if(!bool(r.Filter.flag))r.Filter.PFE.flag=0;
    if(!bool(r.Wrapper.flag))r.Wrapper.PFE.flag=0;
    if(r.rfePFEEligibility && !r.rfePFEEligibility.eligible){r.Filter.PFE.flag=0;r.Wrapper.PFE.flag=0;}
    const filterEnsembleActive=bool(r.Filter.flag)&&bool(r.Filter.SubSpaceFlag);
    if(!filterEnsembleActive)r.Wrapper.SubSpaceFlag=0;
    r.Filter.EnsembleStrategy=normalizeEnsemble(r.Filter.EnsembleStrategy,r.rfeModeFlag);
    r.Wrapper.EnsembleStrategy=normalizeEnsemble(r.Wrapper.EnsembleStrategy,r.rfeModeFlag);
    if(!filterEnsembleActive)r.Filter.EnsembleStrategy.type=0;
    const wrapperEnsembleActive=filterEnsembleActive&&bool(r.Wrapper.flag)&&bool(r.Wrapper.SubSpaceFlag);
    if(!wrapperEnsembleActive)r.Wrapper.EnsembleStrategy.type=0;
    if(!(bool(r.rfeCanRetrainImmediate)))r.RetrainImmediate=0;
    r.CV2Class.type=2; r.CV2Class.EnsembleStrategy.type=0; r.CV2Class.EnsembleStrategy.DataType=0;
    if(String(r.rfeModeFlag||'classification').toLowerCase()==='regression')r.CV2Class.EnsembleStrategy.Metric=2;
  }

  /**
   * labelFilter  Provide the label filter helper used by recursive feature-elimination subconfiguration UI panel.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function labelFilter(r){let m={1:'FEAST',2:'MRMR',3:'Pearson/Spearman',4:'Simba',5:'Gflip',7:'IMRelief',9:'Increasing subspace cardinality',10:'RGS',11:'Random subspace sampling',12:'Relief',13:'FScore'};return m[Number(getPath(r,'Filter.type',3))]||'method '+getPath(r,'Filter.type',3);}
  /**
   * labelWrapper  Provide the label wrapper helper used by recursive feature-elimination subconfiguration UI panel.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function labelWrapper(r){let a=['Greedy search','Simulated annealing','Genetic algorithm','Particle swarm optimization','Path finder algorithm'];return a[Number(getPath(r,'Wrapper.type',1))-1]||'Wrapper method';}
  /**
   * summaryText  Build the summary text shown to users in the browser UI.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function summaryText(r){r=ensure(r||{});let f=bool(getPath(r,'Filter.flag',0)),w=bool(getPath(r,'Wrapper.flag',0));if(!f&&!w)return 'Filter- and wrapper-based ensemble learning disabled.';let p=[];if(f)p.push('Filter: '+labelFilter(r));if(w)p.push('Wrapper: '+labelWrapper(r));return p.join('; ');}
  /**
   * renderSummary  Render the summary UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderSummary(s){let e=byId('rfeSummary');if(e)e.textContent=summaryText((s||{}).rfe||{});}
  /**
   * methodOptions  Provide the method options helper used by recursive feature-elimination subconfiguration UI panel.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function methodOptions(r){let mode=String(r.rfeModeFlag||'classification').toLowerCase();return mode==='regression'?[[1,'FEAST'],[2,'MRMR'],[3,'Pearson/Spearman'],[10,'RGS'],[9,'Increasing feature subspace cardinality'],[11,'Random subspace sampling'],[12,'Relief']]:[[1,'FEAST'],[2,'MRMR'],[3,'Pearson/Spearman'],[4,'Simba'],[5,'Gflip'],[7,'IMRelief'],[9,'Increasing feature subspace cardinality'],[11,'Random subspace sampling'],[12,'Relief'],[13,'FScore']];}
  /**
   * fillOptions  Provide the fill options helper used by recursive feature-elimination subconfiguration UI panel.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * opts.forEach: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function fillOptions(id,opts,val){let e=byId(id);if(!e)return;e.innerHTML='';opts.forEach(o=>{let opt=document.createElement('option');opt.value=o[0];opt.textContent=o[1];if(String(o[0])===String(val))opt.selected=true;e.appendChild(opt);});}

  /**
   * gateSideTabs  Provide the gate side tabs helper used by recursive feature-elimination subconfiguration UI panel.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function gateSideTabs(r){
    let f=bool(getPath(r,'Filter.flag',0)), w=bool(getPath(r,'Wrapper.flag',0));
    let fb=document.querySelector('.rfeTab[data-tab="filter"]'), wb=document.querySelector('.rfeTab[data-tab="wrapper"]');
    if(fb)fb.classList.toggle('hidden',!f);
    if(wb)wb.classList.toggle('hidden',!w);
    if((activeTab==='filter'&&!f)||(activeTab==='wrapper'&&!w))activeTab='overview';
  }
  /**
   * setTab  Provide the set tab helper used by recursive feature-elimination subconfiguration UI panel.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function setTab(tab){activeTab=tab;document.querySelectorAll('.rfeTab').forEach(b=>b.classList.toggle('active',b.dataset.tab===tab));document.querySelectorAll('.rfePane').forEach(p=>p.classList.toggle('hidden',p.id!=='rfePane_'+tab));}

  /**
   * classOptValue  Provide the class opt value helper used by recursive feature-elimination subconfiguration UI panel.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function classOptValue(E,mode){
    if(String(mode||'classification').toLowerCase()==='regression')return Number(E.DivCrit)===5?'regvar':'combine';
    if(Number(E.DivCrit)===2)return 'combine';
    if(Number(E.DivCrit)===1)return 'entropy';
    if(Number(E.DivCrit)===4)return 'lobag';
    let obj=String(E.DiversityObjective||'').toUpperCase();
    if(obj==='A')return 'kappaa'; if(obj==='K')return 'kappaf'; if(obj==='Q')return 'kappaq';
    return String(E.DiversitySource||'entropy');
  }
  /**
   * applyOptValue  Apply the opt value change to local browser state or visible controls.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function applyOptValue(E,val,mode){
    if(String(mode||'classification').toLowerCase()==='regression'){
      E.DivCrit=(val==='regvar')?5:2; E.DiversitySource='regvar'; E.DiversityObjective=(val==='regvar')?'R':[]; return;
    }
    if(val==='combine'){E.DivCrit=2; E.DiversityObjective=[]; if(!E.DiversitySource||E.DiversitySource==='regvar')E.DiversitySource='entropy'; return;}
    if(val==='entropy'){E.DivCrit=1; E.DiversitySource='entropy'; E.DiversityObjective='H'; return;}
    if(val==='lobag'){E.DivCrit=4; E.DiversitySource='lobag'; E.DiversityObjective='L'; return;}
    E.DivCrit=3; E.DiversitySource=val; E.DiversityObjective=(val==='kappaa')?'A':(val==='kappaf')?'K':'Q';
  }

  /**
   * boostHtml  Build the boost html inserted into the browser UI.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function boostHtml(prefix){
    return '<div id="'+prefix+'BoostBlock" class="rfeMini hidden"><h3>Boosting configuration</h3>'+ 
      '<div class="twocol"><div class="field" id="'+prefix+'BoostClassModeField"><label for="'+prefix+'BoostMode">Boosting mode</label><select id="'+prefix+'BoostMode"><option value="ridge">Ridge / MSE stacking</option><option value="logloss">Log-loss / cross-entropy</option><option value="expgrad">Exponentiated-gradient weighting</option></select></div><div class="field"><label for="'+prefix+'BoostLambda">Lambda / L2 penalty</label><input id="'+prefix+'BoostLambda" class="textInput" type="number" step="0.0001" min="0"></div></div>'+ 
      '<div class="twocol"><div class="field"><label for="'+prefix+'BoostAlpha">Diversity weight alpha</label><input id="'+prefix+'BoostAlpha" class="textInput" type="number" step="0.001" min="0"></div><div class="field"><label for="'+prefix+'BoostWThreshold">Low-weight threshold</label><input id="'+prefix+'BoostWThreshold" class="textInput" type="number" step="0.001" min="0"></div></div>'+ 
      '<div class="twocol"><div class="field" id="'+prefix+'BoostUseLogitsField"><label><input id="'+prefix+'BoostUseLogits" type="checkbox"> Use logits for score transformation</label></div><div class="field" id="'+prefix+'BoostClipField"><label for="'+prefix+'BoostClip">Probability clipping for log-loss</label><input id="'+prefix+'BoostClip" class="textInput" type="number" step="0.0000001" min="0" max="0.5"></div></div>'+ 
      '<div id="'+prefix+'BoostExpgradBlock"><div class="twocol"><div class="field"><label for="'+prefix+'BoostEta">Exponentiated-gradient eta</label><input id="'+prefix+'BoostEta" class="textInput" type="number" step="0.001" min="0"></div><div class="field"><label for="'+prefix+'BoostT">Exponentiated-gradient iterations</label><input id="'+prefix+'BoostT" class="textInput" type="number" step="1" min="1"></div></div><div class="field"><label><input id="'+prefix+'BoostShareWeights" type="checkbox"> Share weights across dichotomizers/classes</label></div></div>'+ 
      '<div class="field" id="'+prefix+'BoostDivSourceField"><label for="'+prefix+'BoostDiversitySource">Boosting diversity metric</label><select id="'+prefix+'BoostDiversitySource"><option value="entropy">Vote entropy</option><option value="kappaa">1 - double-fault A</option><option value="kappaq">-Q statistic</option><option value="kappaf">1 - Fleiss kappa / 2</option><option value="lobag">-LoBag ED</option></select></div>'+ 
      '<div id="'+prefix+'BoostRegKernelBlock"><div class="twocol"><div class="field"><label for="'+prefix+'BoostKernelRegMode">Regression diversity kernel</label><select id="'+prefix+'BoostKernelRegMode"><option value="residual-cov">Residual covariance</option><option value="residual-corr">Residual correlation</option><option value="residual-lapl">Residual Laplacian</option></select></div><div class="field"><label for="'+prefix+'BoostKernelDiagMode">Kernel diagonal</label><select id="'+prefix+'BoostKernelDiagMode"><option value="one">One</option><option value="zero">Zero</option><option value="keep">Keep</option></select></div></div><div class="twocol"><div class="field"><label for="'+prefix+'BoostKernelScaleTo">Kernel scaling</label><select id="'+prefix+'BoostKernelScaleTo"><option value="HHT">Match HHT norm</option><option value="unit">Unit norm</option></select></div><div class="field"><label for="'+prefix+'BoostKernelTau">Auto-alpha tau</label><input id="'+prefix+'BoostKernelTau" class="textInput" type="number" step="0.01" min="0" max="0.5"></div></div><div class="field"><label><input id="'+prefix+'BoostKernelAutoAlpha" type="checkbox"> Use auto-alpha for regression diversity kernel</label></div></div></div>';
  }
  /**
   * advancedHtml  Build the advanced html inserted into the browser UI.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function advancedHtml(prefix, includeCore){
    let p=escapeHtml(prefix);
    return '<div id="'+p+'EnsAdvancedBlock" class="rfeMini hidden"><h3>Subspace ensemble optimization</h3>'+ 
      (includeCore?'<div class="twocol"><div class="field"><label for="'+p+'EnsSubSpaceStrategy">Subspace selection strategy</label><select id="'+p+'EnsSubSpaceStrategy"><option value="1">Winner takes all</option><option value="2">Within range of optimum</option><option value="3">Percentile cutoff</option><option value="4">All subspaces</option></select></div><div class="field"><label for="'+p+'EnsSubSpaceCrit">Subspace range / percentile</label><input id="'+p+'EnsSubSpaceCrit" class="textInput" type="number" step="0.1"></div></div><div class="twocol"><div class="field"><label for="'+p+'EnsMinNum">Minimum selected classifiers/features</label><input id="'+p+'EnsMinNum" class="textInput" type="number" step="1" min="1"></div><div class="field"><label for="'+p+'EnsPerc">Feature-agreement percentage</label><input id="'+p+'EnsPerc" class="textInput" type="number" step="1" min="0" max="100"></div></div>':'')+
      '<div id="'+p+'EnsOptimizationBlock"><div class="twocol"><div class="field"><label for="'+p+'EnsOptMethod">Optimization function</label><select id="'+p+'EnsOptMethod"></select></div><div class="field" id="'+p+'EnsDiversitySourceField"><label for="'+p+'EnsDiversitySource">Diversity metric combined with performance</label><select id="'+p+'EnsDiversitySource"><option value="entropy">Vote entropy</option><option value="kappaa">1 - double-fault A</option><option value="kappaq">-Q statistic</option><option value="kappaf">1 - Fleiss kappa / 2</option><option value="lobag">-LoBag ED</option></select></div></div>'+ 
      '<div class="twocol" id="'+p+'EnsSelectedLearnerBlock"><div class="field" id="'+p+'EnsMetricField"><label for="'+p+'EnsMetric">Decision source</label><select id="'+p+'EnsMetric"><option value="1">Predicted labels / hard decisions</option><option value="2">Algorithm scores / soft decisions</option></select></div><div class="field"><label for="'+p+'EnsWeighting">Base-learner weighting</label><select id="'+p+'EnsWeighting"><option value="0">No weighting</option><option value="1">Weight = 1 / resubstitution error</option></select></div></div>'+ 
      '<div id="'+p+'EnsRegularizerBlock"><div class="twocol"><div class="field"><label for="'+p+'EnsPerfSlackPct">Performance slack [% of criterion range]</label><input id="'+p+'EnsPerfSlackPct" class="textInput" type="number" step="0.01" min="0"></div><div class="field"><label for="'+p+'EnsEntropyWeight">Diversity rank-blend weight</label><input id="'+p+'EnsEntropyWeight" class="textInput" type="number" step="0.01" min="0"></div></div><div class="twocol"><div class="field"><label for="'+p+'EnsSizePenalty">Size penalty</label><input id="'+p+'EnsSizePenalty" class="textInput" type="number" step="0.001" min="0"></div><div class="field"><label for="'+p+'EnsPatience">Early-stop patience</label><input id="'+p+'EnsPatience" class="textInput" type="number" step="1" min="0"></div></div></div>'+ 
      '<div id="'+p+'EnsDiversityOnlyBlock"><div class="twocol"><div class="field"><label for="'+p+'EnsDiversityEps">Diversity epsilon</label><input id="'+p+'EnsDiversityEps" class="textInput" type="number" step="0.001" min="0"></div><div class="field"><label for="'+p+'EnsSizePenalty2">Size penalty</label><input id="'+p+'EnsSizePenalty2" class="textInput" type="number" step="0.001" min="0"></div></div></div></div></div>';
  }
  /**
   * ensureAdvancedDom  Ensure the advanced dom prerequisite exists before downstream rendering or requests.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function ensureAdvancedDom(){
    if(byId('rfeFilterEnsAdvancedBlock'))return;
    let fb=byId('rfeFilterBoostBlock');
    if(fb)fb.insertAdjacentHTML('beforebegin',advancedHtml('rfeFilter',false));
    let wrap=byId('rfeWrapperSubspaceBlock');
    if(wrap){
      wrap.insertAdjacentHTML('beforeend',advancedHtml('rfeWrapper',true)+boostHtml('rfeWrapper'));
    }
  }

  function renderPFE(prefix, PFE){
    const mode=Number(PFE.Mode), input=byId(prefix+'PFEPerc');
    setChk(prefix+'PFEFlag',bool(PFE.flag)); setHidden(prefix+'PFEOptions',!bool(PFE.flag));
    setVal(prefix+'PFEMode',mode); setVal(prefix+'PFEPerc',PFE.Perc);
    setVal(prefix+'PFETolWin',PFE.TolWin); setVal(prefix+'PFEMinNum',PFE.MinNum);
    setChk(prefix+'PFEPrune',bool(PFE.PruneFlag));
    setClosestHidden(prefix+'PFETolWin',mode!==1); setClosestHidden(prefix+'PFEMinNum',mode!==1);
    input.min=1; input.max=mode===2?'':100;
    input.closest('.field').querySelector('label').firstChild.nodeValue={1:'Minimum CV1 agreement [%]',2:'Number of most consistent features',3:'Percentage of most consistent features [%]'}[mode];
  }

  /**
   * render  Render the render UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function render(){
    ensureAdvancedDom();
    let r=RFE(); normalize(r); renderSummary(state()); gateSideTabs(r);
    setChk('rfeFilterEnabled',bool(getPath(r,'Filter.flag',0))); setChk('rfeWrapperEnabled',bool(getPath(r,'Wrapper.flag',0)));
    setChk('rfeRetrainImmediate',bool(r.RetrainImmediate)); setHidden('rfeRetrainImmediateField',!bool(r.rfeCanRetrainImmediate));

    setVal('rfeFilterMinNum',getPath(r,'Filter.MinNum',1)); setChk('rfeFilterSubspace',bool(getPath(r,'Filter.SubSpaceFlag',1))); setVal('rfeFilterRankThresh',getPath(r,'Filter.RankThresh',95));
    fillOptions('rfeFilterType',methodOptions(r),getPath(r,'Filter.type',3));
    setVal('rfeFilterPearson',getPath(r,'Filter.Pearson',1)); setVal('rfeFilterMetric',getPath(r,'Filter.EnsembleStrategy.Metric',2));
    setVal('rfeFilterBinmode',getPath(r,'Filter.binmode',1)); setHidden('rfeFilterBinmodeField',!(String(r.rfeModeFlag||'classification')==='classification'&&bool(r.rfeIsMulticlass)));
    setHidden('rfeFilterOptions',!bool(getPath(r,'Filter.flag',0))); setHidden('rfeFilterRankModeBlock',bool(getPath(r,'Filter.SubSpaceFlag',1)));
    setHidden('rfeFilterSubspaceBlock',!bool(getPath(r,'Filter.SubSpaceFlag',1))); setHidden('rfeFilterMetricField',String(r.rfeModeFlag||'classification')==='regression');
    setVal('rfeFilterCostFun',getPath(r,'Filter.CostFun',2)); setVal('rfeFilterSubSpaceStrategy',getPath(r,'Filter.SubSpaceStrategy',1)); setVal('rfeFilterSubSpaceCrit',getPath(r,'Filter.SubSpaceCrit',0)); setVal('rfeFilterSubSpaceStepping',getPath(r,'Filter.SubSpaceStepping',0));
    setVal('rfeFilterEnsConstructMode',getPath(r,'Filter.EnsembleStrategy.ConstructMode',0)); setVal('rfeFilterEnsMinNum',getPath(r,'Filter.EnsembleStrategy.MinNum',1)); setVal('rfeFilterEnsPerc',getPath(r,'Filter.EnsembleStrategy.Perc',75));
    renderEnsemble('rfeFilter','Filter',bool(getPath(r,'Filter.flag',0))&&bool(getPath(r,'Filter.SubSpaceFlag',1)),false,r);
    renderBoosting('rfeFilter','Filter',r);
    let pfeAllowed=r.rfePFEEligibility && r.rfePFEEligibility.eligible;
    let pfeReason='Checking preprocessing compatibility...';
    if(r.rfePFEEligibility)pfeReason=r.rfePFEEligibility.reason;
    let pfeTab=document.querySelector('.rfeTab[data-tab="pfe"]');
    if(pfeTab){pfeTab.disabled=!(pfeAllowed && (bool(getPath(r,'Filter.flag',0)) || bool(getPath(r,'Wrapper.flag',0))));pfeTab.title=pfeAllowed?'Enable Filter or Wrapper to configure feature stability.':pfeReason;}
    setHidden('rfePFEFilterPanel',!bool(getPath(r,'Filter.flag',0)));
    setHidden('rfePFEWrapperPanel',!bool(getPath(r,'Wrapper.flag',0)));
    let pfeMsg=byId('rfePFEEligibilityMessage');if(pfeMsg)pfeMsg.textContent=pfeAllowed?'':pfeReason;
    let pfeDisabledMsg=byId('rfePFEUnavailableMessage');
    if(pfeDisabledMsg){pfeDisabledMsg.textContent=pfeAllowed?'':pfeReason;pfeDisabledMsg.classList.toggle('hidden',!!pfeAllowed);}
    if(activeTab==='pfe' && pfeTab && pfeTab.disabled) activeTab='overview';
    renderPFE('rfeFilter',r.Filter.PFE);
    renderFilterMethod(r);

    setHidden('rfeWrapperOptions',!bool(getPath(r,'Wrapper.flag',0))); setVal('rfeWrapperType',getPath(r,'Wrapper.type',1)); setVal('rfeWrapperDatamode',getPath(r,'Wrapper.datamode',2));
    let wrapperSubspaceAvailable=bool(getPath(r,'Filter.flag',0))&&bool(getPath(r,'Filter.SubSpaceFlag',1));
    setHidden('rfeWrapperSubspaceBlock',!wrapperSubspaceAvailable); setChk('rfeWrapperSubspace',bool(getPath(r,'Wrapper.SubSpaceFlag',0))); setVal('rfeWrapperSubSpaceStepping',getPath(r,'Wrapper.SubSpaceStepping',0)); setVal('rfeWrapperEnsConstructMode',getPath(r,'Wrapper.EnsembleStrategy.ConstructMode',0));
    setHidden('rfeWrapperOptField',!bool(r.rfeCanWrapperOpt)); setVal('rfeWrapperOptflag',getPath(r,'Wrapper.optflag',2));
    renderEnsemble('rfeWrapper','Wrapper',bool(getPath(r,'Wrapper.flag',0))&&wrapperSubspaceAvailable&&bool(getPath(r,'Wrapper.SubSpaceFlag',0)),true,r);
    renderBoosting('rfeWrapper','Wrapper',r);
    renderWrapperMethod(r);
    renderPFE('rfeWrapper',r.Wrapper.PFE);
    setChk('rfeClassRetrain',bool(r.ClassRetrain)); setVal('rfeCV2Metric',r.CV2Class.EnsembleStrategy.Metric); setHidden('rfeCV2MetricField',r.rfeModeFlag==='regression'); setVal('rfeAggregationLevel',r.CV2Class.EnsembleStrategy.AggregationLevel);
    drawAdaptivePlot(r); setTab(activeTab);
  }

  /**
   * renderEnsemble  Render the ensemble UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderEnsemble(prefix,branch,active,includeCore,r){
    let mode=String(r.rfeModeFlag||'classification').toLowerCase(), E=getPath(r,branch+'.EnsembleStrategy',{}), cm=Number(E.ConstructMode||0);
    let subStr=Number(getPath(r,branch+'.SubSpaceStrategy',1));
    let show=active && subStr>1 && cm>0;
    let blockVisible=includeCore ? active : show;
    setHidden(prefix+'EnsAdvancedBlock',!blockVisible);
    setClosestHidden(prefix+'EnsConstructMode',!active || subStr<=1);
    setClosestHidden(prefix+'EnsMinNum',!(show && (cm===1||cm===2||cm===4)));
    setClosestHidden(prefix+'EnsPerc',!(show && cm===4));
    if(includeCore){setVal(prefix+'EnsSubSpaceStrategy',subStr); setVal(prefix+'EnsSubSpaceCrit',getPath(r,branch+'.SubSpaceCrit',0)); setVal(prefix+'EnsMinNum',E.MinNum===undefined?1:E.MinNum); setVal(prefix+'EnsPerc',E.Perc===undefined?75:E.Perc);}
    let optOpts=mode==='regression'?[["combine","Combine performance with regression ambiguity"],["regvar","Regression ambiguity only"]]:[["combine","Combine performance with a diversity metric"],["entropy","Vote entropy only"],["kappaa","1 - double-fault A only"],["kappaq","-Q statistic only"],["kappaf","1 - Fleiss kappa / 2 only"],["lobag","-LoBag ED only"]];
    fillOptions(prefix+'EnsOptMethod',optOpts,classOptValue(E,mode));
    setVal(prefix+'EnsDiversitySource',E.DiversitySource||'entropy');
    setVal(prefix+'EnsMetric',E.Metric===undefined?2:E.Metric); setVal(prefix+'EnsWeighting',E.Weighting===undefined?0:E.Weighting);
    setVal(prefix+'EnsPerfSlackPct',100*asNum(E.PerfSlackPct,0)); setVal(prefix+'EnsEntropyWeight',E.EntropyWeight===undefined?2:E.EntropyWeight); setVal(prefix+'EnsSizePenalty',E.SizePenalty===undefined?0:E.SizePenalty); setVal(prefix+'EnsPatience',E.Patience===undefined?0:E.Patience);
    setVal(prefix+'EnsDiversityEps',E.DiversityEps===undefined?0.02:E.DiversityEps); setVal(prefix+'EnsSizePenalty2',E.SizePenalty===undefined?0:E.SizePenalty);
    setHidden(prefix+'EnsOptimizationBlock',!(show && (cm===1||cm===2)));
    setHidden(prefix+'EnsDiversitySourceField',!(show && (cm===1||cm===2) && mode==='classification' && Number(E.DivCrit)===2));
    setHidden(prefix+'EnsSelectedLearnerBlock',!(show && (cm===1||cm===2)));
    setHidden(prefix+'EnsMetricField',mode==='regression');
    setHidden(prefix+'EnsRegularizerBlock',!(show && (cm===1||cm===2) && Number(E.DivCrit)===2));
    setHidden(prefix+'EnsDiversityOnlyBlock',!(show && (cm===1||cm===2) && Number(E.DivCrit)!==2));
  }
  /**
   * renderBoosting  Render the boosting UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderBoosting(prefix,branch,r){
    let mode=String(r.rfeModeFlag||'classification').toLowerCase(), E=getPath(r,branch+'.EnsembleStrategy',{}), b=getPath(r,branch+'.EnsembleStrategy.Boosting',{}), bm=String(b.mode||'ridge').toLowerCase(), alpha=asNum(b.alpha,0);
    let active=(branch==='Filter')?bool(getPath(r,'Filter.flag',0))&&bool(getPath(r,'Filter.SubSpaceFlag',1)):bool(getPath(r,'Wrapper.flag',0))&&bool(getPath(r,'Wrapper.SubSpaceFlag',0));
    let subStr=Number(getPath(r,branch+'.SubSpaceStrategy',1));
    let show=active && subStr>1 && Number(E.ConstructMode||0)===5;
    setHidden(prefix+'BoostBlock',!show);
    setHidden(prefix+'BoostClassModeField',mode!=='classification');
    setHidden(prefix+'BoostClipField',!(mode==='classification'&&bm==='logloss'));
    setHidden(prefix+'BoostExpgradBlock',!(mode==='classification'&&bm==='expgrad'));
    setHidden(prefix+'BoostUseLogitsField',mode!=='classification');
    setHidden(prefix+'BoostDivSourceField',!(mode==='classification'&&alpha>0));
    setHidden(prefix+'BoostRegKernelBlock',!(mode==='regression'&&alpha>0));
    setVal(prefix+'BoostMode',mode==='regression'?'ridge':bm); setVal(prefix+'BoostLambda',b.lambda===undefined?1e-3:b.lambda); setVal(prefix+'BoostAlpha',alpha); setChk(prefix+'BoostUseLogits',bool(b.useLogits)); setVal(prefix+'BoostWThreshold',b.wThreshold===undefined?0:b.wThreshold); setVal(prefix+'BoostClip',b.clip===undefined?1e-7:b.clip); setVal(prefix+'BoostEta',b.eta===undefined?0.3:b.eta); setVal(prefix+'BoostT',b.T===undefined?200:b.T); setChk(prefix+'BoostShareWeights',bool(b.shareWeights)); setVal(prefix+'BoostDiversitySource',E.DiversitySource||'entropy');
    setVal(prefix+'BoostKernelRegMode',getPath(r,branch+'.EnsembleStrategy.Boosting.Kernel.regMode','residual-cov')); setVal(prefix+'BoostKernelDiagMode',getPath(r,branch+'.EnsembleStrategy.Boosting.Kernel.diagMode','one')); setVal(prefix+'BoostKernelScaleTo',getPath(r,branch+'.EnsembleStrategy.Boosting.Kernel.scaleTo','HHT')); setChk(prefix+'BoostKernelAutoAlpha',bool(getPath(r,branch+'.EnsembleStrategy.Boosting.Kernel.autoAlpha',false))); setVal(prefix+'BoostKernelTau',getPath(r,branch+'.EnsembleStrategy.Boosting.Kernel.tau',0.10));
  }

  /**
   * renderFilterMethod  Render the filter method UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderFilterMethod(r){
    let t=Number(getPath(r,'Filter.type',3));['Pearson','FEAST','MRMR','Simba','Gflip','IMRelief','RGS','RSS','Relief','None'].forEach(x=>setHidden('rfeFilterMethod'+x,true));let block='None'; if(t===3)block='Pearson'; else if(t===1)block='FEAST'; else if(t===2)block='MRMR'; else if(t===4)block='Simba'; else if(t===5)block='Gflip'; else if(t===7)block='IMRelief'; else if(t===10)block='RGS'; else if(t===11)block='RSS'; else if(t===12)block='Relief'; setHidden('rfeFilterMethod'+block,false);
    setVal('rfeFEASTMethod',getPath(r,'Filter.FEAST.Method',1)); setVal('rfeFEASTNumFeat',arr(getPath(r,'Filter.FEAST.NumFeat',10)).join(' ')); setVal('rfeMRMRScheme',getPath(r,'Filter.MRMR.mRMRscheme',1)); setVal('rfeMRMRNumFeat',arr(getPath(r,'Filter.MRMR.NumFeat',10)).join(' '));
    setVal('rfeSimbaStart',getPath(r,'Filter.simba.extra_param.start_points',1)); setVal('rfeSimbaMaxIter',getPath(r,'Filter.simba.extra_param.max_iter',5)); setVal('rfeSimbaAbort',getPath(r,'Filter.simba.extra_param.iter_abort_crit',100)); setVal('rfeSimbaBlock',getPath(r,'Filter.simba.extra_param.block_size',1)); setVal('rfeSimbaUtility',getPath(r,'Filter.simba.utilfunc',1)); setVal('rfeSimbaBeta',getPath(r,'Filter.simba.extra_param.beta','auto'));
    setVal('rfeGflipStart',getPath(r,'Filter.gflip.extra_param.start_points',1)); setVal('rfeGflipMaxIter',getPath(r,'Filter.gflip.extra_param.max_iter',5)); setVal('rfeGflipBlock',getPath(r,'Filter.gflip.extra_param.block_size',1)); setVal('rfeGflipUtility',getPath(r,'Filter.gflip.utilfunc',2)); setVal('rfeGflipBeta',getPath(r,'Filter.gflip.extra_param.beta','auto')); setChk('rfeGflipLimFeat',bool(getPath(r,'Filter.gflip.limfeat',0)));
    let im=firstImrelief(r); setVal('rfeIMReliefDistance',im.distance||'block'); setVal('rfeIMReliefSigma',arr(im.sigma||2).join(' ')); setVal('rfeIMReliefLambda',arr(im.lambda||0.1).join(' ')); setVal('rfeIMReliefMaxiter',im.maxiter||10); setChk('rfeIMReliefPlot',bool(im.plotfigure));
    setVal('rfeRGSStarts',getPath(r,'Filter.RGS.extra_param.num_starts',2)); setVal('rfeRGSEpochs',getPath(r,'Filter.RGS.extra_param.epochs',1)); setVal('rfeRGSK',arr(getPath(r,'Filter.RGS.extra_param.k','')).join(' ')); setVal('rfeRGSBeta',arr(getPath(r,'Filter.RGS.extra_param.beta','')).join(' ')); setChk('rfeRGSVerbose',bool(getPath(r,'Filter.RGS.extra_param.verbose',true)));
    setVal('rfeRSSPerms',getPath(r,'Filter.RSS.nperms',50)); setVal('rfeRSSMin',getPath(r,'Filter.RSS.nMinFeatsPerc',10)); setVal('rfeRSSMax',getPath(r,'Filter.RSS.nMaxFeatsPerc',90)); setVal('rfeReliefK',getPath(r,'Filter.Relief.k',10));
  }
  /**
   * renderWrapperMethod  Render the wrapper method UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderWrapperMethod(r){
    let t=Number(getPath(r,'Wrapper.type',1));['Greedy','SA','GA','PSO','PFA'].forEach((x,i)=>setHidden('rfeWrapperMethod'+x,t!==i+1));
    let g=getPath(r,'Wrapper.GreedySearch',{}); setVal('rfeGreedyDirection',g.Direction||1); setVal('rfeGreedyEarlyThresh',getPath(r,'Wrapper.GreedySearch.EarlyStop.Thresh',50)); setVal('rfeGreedyEarlyPerc',getPath(r,'Wrapper.GreedySearch.EarlyStop.Perc',1)); setVal('rfeGreedyFeatStep',g.FeatStepPerc||0); setVal('rfeGreedyFeatRand',g.FeatRandPerc||0); setVal('rfeGreedyKnee',g.KneePointDetection||2); setVal('rfeGreedyWeightSort',g.WeightSort||1); setChk('rfeGreedyCritGapFlag',Number(getPath(r,'Wrapper.GreedySearch.CritGap.flag',2))===1); setVal('rfeGreedyCritGapCrit',getPath(r,'Wrapper.GreedySearch.CritGap.crit',10)); setHidden('rfeGreedyCritGapCritField',Number(getPath(r,'Wrapper.GreedySearch.CritGap.flag',2))!==1); setHidden('rfeGreedyCritGapBlock',Number(getPath(r,'Wrapper.datamode',2))!==4);
    let ad=getPath(r,'Wrapper.GreedySearch.AdRef',{}); setHidden('rfeAdaptiveBlock',asNum(getPath(r,'Wrapper.GreedySearch.EarlyStop.Thresh',50),50)!==0); setChk('rfeAdEnable',bool(ad.Enable)); setHidden('rfeAdOptions',!bool(ad.Enable)); setChk('rfeAdAuto',bool(getPath(r,'Wrapper.GreedySearch.AdRef.Auto.Enable',false))); setVal('rfeAdLambda',ad.lambda||0.5); setVal('rfeAdKNN',ad.kNN||20); setVal('rfeAdGamma',ad.gamma||0.98); setVal('rfeAdEta0',ad.eta0||0.001); setVal('rfeAdEta1',ad.eta1||0.005); setVal('rfeAdRmax',ad.rmax||10); setVal('rfeAdC',ad.c||0.55); setVal('rfeAdW',ad.w||0.15); setVal('rfeAdBetaWell',ad.beta_well||1); setVal('rfeAdBetaHi',ad.beta_hi||1); setVal('rfeAdSigmaLo',ad.sigma_lo||0.05); setVal('rfeAdSigmaHi',ad.sigma_hi||0.06);
    ['SA.c','SA.T','SA.T_stop','SA.alpha','SA.itt_max','SA.Rep_T_max','SA.Rep_accept_max','SA.kc'].forEach(p=>setVal('rfe'+p.replace('.',''),getPath(r,'Wrapper.'+p,'')));
    ['GA.N','GA.max_Iter','GA.CR','GA.MR','PSO.N','PSO.max_Iter','PSO.c1','PSO.c2','PSO.w','PSO.lb','PSO.ub','PSO.thres','PFA.N','PFA.max_Iter','PFA.lb','PFA.ub','PFA.thres'].forEach(p=>setVal('rfe'+p.replace('.',''),getPath(r,'Wrapper.'+p,'')));
  }

  /**
   * bind  Register event handlers for the bind controls.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function bind(id,path,type){let e=byId(id);if(!e)return;let h=function(){if(path.includes('.PFE.') && !(RFE().rfePFEEligibility && RFE().rfePFEEligibility.eligible))return;let v;if(type==='check')v=e.checked?1:0;else if(type==='two12')v=e.checked?1:2;else if(type==='bool')v=!!e.checked;else if(type==='num')v=asNum(e.value,0);else if(type==='vec')v=numVec(e.value,[]);else v=e.value;let r=RFE();setPath(r,path,v);if(path.endsWith('.PFE.Mode'))setPath(r,path.slice(0,-4)+'Perc',v===1?90:10);mark();render();};e.onchange=h;e.oninput=(type==='text'||type==='num'||type==='vec')?h:null;}
  /**
   * bindOpt  Register event handlers for the opt controls.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function bindOpt(prefix,branch){let e=byId(prefix+'EnsOptMethod');if(!e)return;e.onchange=()=>{let r=RFE(),E=getPath(r,branch+'.EnsembleStrategy',{});applyOptValue(E,e.value,r.rfeModeFlag);setPath(r,branch+'.EnsembleStrategy',E);mark();render();};}
  /**
   * bindPct  Register event handlers for the pct controls.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function bindPct(id,path){let e=byId(id);if(!e)return;let h=()=>{setPath(RFE(),path,Math.max(0,asNum(e.value,0))/100);mark();render();};e.onchange=h;e.oninput=h;}
  /**
   * bindSizePenaltyMirror  Register event handlers for the size penalty mirror controls.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function bindSizePenaltyMirror(prefix,branch){let e=byId(prefix+'EnsSizePenalty2');if(!e)return;let h=()=>{setPath(RFE(),branch+'.EnsembleStrategy.SizePenalty',asNum(e.value,0));mark();render();};e.onchange=h;e.oninput=h;}

  /**
   * refresh  Refresh preprocessing-derived RFE metadata from MATLAB on configurator entry.
   */
  async function refresh(){let S=state(),changedPaths=ctx.changedPathsFor('');try{await fetch(ctx.API('/api/current'),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(S)});let res=await fetch(ctx.API('/api/matlabservice'),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({operation:'train_template_refresh_rfe',state:S,changedPaths:changedPaths,includeCanvas:!(ctx.deferCanvas&&ctx.deferCanvas()),timeout:60})}).then(r=>r.json());if(res&&res.error)throw new Error(res.error);if(!res||res.ok===false)throw new Error((res&&res.message)||'Ensemble-learning refresh failed.');if(res.state&&typeof res.state==='object')ctx.setState(res.state);else if(res.rfe&&typeof res.rfe==='object')state().rfe=res.rfe;ctx.clearChangedPaths(changedPaths);render();return true;}catch(e){localStatus('Ensemble-learning settings could not be refreshed: '+e.message,'danger');return false;}}

  /**
   * apply  Apply the apply change to local browser state or visible controls.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function apply(){let r=RFE(); if(!r.rfeDirty)return true;let changedPaths=ctx.changedPathsFor('rfe');try{await fetch(ctx.API('/api/current'),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(state())});let res=await fetch(ctx.API('/api/matlabservice'),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({operation:'train_template_apply_rfe',state:state(),changedPaths:changedPaths,includeCanvas:!(ctx.deferCanvas&&ctx.deferCanvas()),timeout:120})}).then(r=>r.json());if(res&&res.error)throw new Error(res.error);if(!res||res.ok===false)throw new Error((res&&res.message)||'Ensemble-learning request failed.');if(res.state&&typeof res.state==='object')ctx.setState(res.state);else if(res.rfe&&typeof res.rfe==='object')state().rfe=res.rfe;ctx.clearChangedPaths(changedPaths);if((res.canvasDirty||(res.state&&res.state.canvasDirty))&&ctx.markCanvasDirty){ctx.markCanvasDirty(res.canvasDirtyReason||(res.state&&res.state.canvasDirtyReason)||'Canvas refresh pending.');if(ctx.scheduleCanvasRefresh)ctx.scheduleCanvasRefresh(150);}render();return true;}catch(e){localStatus('Ensemble-learning settings could not be applied: '+e.message,'danger');return false;}}
  /**
   * localStatus  Provide the local status helper used by recursive feature-elimination subconfiguration UI panel.
   * It supports recursive feature-elimination subconfiguration UI panel at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function localStatus(s,cls){if(ctx&&ctx.status)ctx.status(s,cls||'info');else window.NMUIMessageTools.setMessage(s,cls||'info');}
  /**
   * drawAdaptivePlot  Draw the adaptive plot visualization for the active NeuroMiner payload.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function drawAdaptivePlot(r){let cv=byId('rfeAdaptiveCanvas');if(!cv||!cv.getContext)return;let ad=getPath(r,'Wrapper.GreedySearch.AdRef',{}),c=asNum(ad.c,0.55),w=asNum(ad.w,0.15),bw=asNum(ad.beta_well,1),bh=asNum(ad.beta_hi,1),sl=Math.max(1e-4,asNum(ad.sigma_lo,w/3)),sh=Math.max(1e-4,asNum(ad.sigma_hi,0.06));let ctx2=cv.getContext('2d'),W=cv.width,H=cv.height;ctx2.clearRect(0,0,W,H);let vals=[];for(let i=0;i<=120;i++){let s=i/120;let left=1/(1+Math.exp(-(s-(c-w))/sl));let right=1/(1+Math.exp((s-(c+w))/sl));let well=-bw*left*right;let high=bh/(1+Math.exp(-(s-(c+w))/sh));let y=well+high;vals.push([s,y]);}let ys=vals.map(v=>v[1]),mn=Math.min(-1,...ys),mx=Math.max(1,...ys);function X(s){return 36+s*(W-48);}function Y(y){return 12+(mx-y)/(mx-mn)*(H-34);}ctx2.strokeStyle='#d0d7de';ctx2.lineWidth=1;ctx2.beginPath();ctx2.moveTo(36,Y(0));ctx2.lineTo(W-12,Y(0));ctx2.stroke();ctx2.strokeStyle='#1f6feb';ctx2.lineWidth=2;ctx2.beginPath();vals.forEach((v,i)=>{let x=X(v[0]),y=Y(v[1]);if(i===0)ctx2.moveTo(x,y);else ctx2.lineTo(x,y);});ctx2.stroke();ctx2.fillStyle='#667085';ctx2.font='11px system-ui';ctx2.fillText('similarity s',W-84,H-6);ctx2.fillText('φ(s)',6,14);}

  /**
   * attach  Provide the attach helper used by recursive feature-elimination subconfiguration UI panel.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */

  // Context-help navigation changes presentation only; RFE state and write-back remain unchanged.
  const helpTopics = {
      rfeRetrainImmediate: "retrain-immediate",
      rfeFilterType: "filter-method",
      rfeFilterPearson: "filter-correlation-correlation",
      rfeFEASTMethod: "filter-feast-algorithm",
      rfeFEASTNumFeat: "filter-feast-count",
      rfeMRMRScheme: "filter-mrmr-scheme",
      rfeMRMRNumFeat: "filter-mrmr-count",
      rfeSimbaStart: "filter-simba-starts",
      rfeSimbaMaxIter: "filter-simba-iterations",
      rfeSimbaAbort: "filter-simba-stability",
      rfeSimbaBlock: "filter-simba-block",
      rfeSimbaUtility: "filter-simba-utility",
      rfeSimbaBeta: "filter-simba-beta",
      rfeGflipStart: "filter-gflip-starts",
      rfeGflipMaxIter: "filter-gflip-iterations",
      rfeGflipBlock: "filter-gflip-block",
      rfeGflipUtility: "filter-gflip-utility",
      rfeGflipBeta: "filter-gflip-beta",
      rfeGflipLimFeat: "filter-gflip-limit",
      rfeIMReliefDistance: "filter-imrelief-distance",
      rfeIMReliefSigma: "filter-imrelief-sigma",
      rfeIMReliefLambda: "filter-imrelief-lambda",
      rfeIMReliefMaxiter: "filter-imrelief-iterations",
      rfeIMReliefPlot: "filter-imrelief-plot",
      rfeRGSStarts: "filter-rgs-starts",
      rfeRGSEpochs: "filter-rgs-epochs",
      rfeRGSK: "filter-rgs-k",
      rfeRGSBeta: "filter-rgs-beta",
      rfeRGSVerbose: "filter-rgs-verbose",
      rfeRSSPerms: "filter-rss-repeats",
      rfeRSSMin: "filter-rss-min",
      rfeRSSMax: "filter-rss-max",
      rfeReliefK: "filter-relief-neighbors",
      rfeWrapperType: "wrapper-method",
      rfeAdAuto: "wrapper-adaptive-auto",
      rfeAdLambda: "wrapper-adaptive-lambda",
      rfeAdKNN: "wrapper-adaptive-knn",
      rfeAdGamma: "wrapper-adaptive-gamma",
      rfeAdRmax: "wrapper-adaptive-rmax",
      rfeAdEta0: "wrapper-adaptive-eta0",
      rfeAdEta1: "wrapper-adaptive-eta1",
      rfeAdC: "wrapper-adaptive-center",
      rfeAdW: "wrapper-adaptive-width",
      rfeAdBetaWell: "wrapper-adaptive-beta-well",
      rfeAdBetaHi: "wrapper-adaptive-beta-high",
      rfeAdSigmaLo: "wrapper-adaptive-sigma-low",
      rfeAdSigmaHi: "wrapper-adaptive-sigma-high",
      rfeClassRetrain: "cv2-retrain",
      rfeCV2Metric: "cv2-metric",
      rfeAggregationLevel: "cv2-aggregation",
      rfeSAc: "wrapper-sa-c",
      rfeSAT: "wrapper-sa-T",
      rfeSAT_stop: "wrapper-sa-T_stop",
      rfeSAalpha: "wrapper-sa-alpha",
      rfeSAitt_max: "wrapper-sa-itt_max",
      rfeSARep_T_max: "wrapper-sa-Rep_T_max",
      rfeSARep_accept_max: "wrapper-sa-Rep_accept_max",
      rfeSAkc: "wrapper-sa-kc",
      rfeGAN: "wrapper-ga-N",
      rfeGAmax_Iter: "wrapper-ga-iter",
      rfeGACR: "wrapper-ga-cr",
      rfeGAMR: "wrapper-ga-mr",
      rfePSON: "wrapper-pso-N",
      rfePSOmax_Iter: "wrapper-pso-iter",
      rfePSOc1: "wrapper-pso-c1",
      rfePSOc2: "wrapper-pso-c2",
      rfePSOw: "wrapper-pso-w",
      rfePSOthres: "wrapper-pso-threshold",
      rfePSOlb: "wrapper-pso-lb",
      rfePSOub: "wrapper-pso-ub",
      rfePFAN: "wrapper-pfa-N",
      rfePFAmax_Iter: "wrapper-pfa-iter",
      rfePFAlb: "wrapper-pfa-lb",
      rfePFAub: "wrapper-pfa-ub",
      rfePFAthres: "wrapper-pfa-threshold"
  };
  const filterMethodHelp={1:'filter-feast',2:'filter-mrmr',3:'filter-correlation',4:'filter-simba',5:'filter-gflip',7:'filter-imrelief',9:'filter-increasing',10:'filter-rgs',11:'filter-rss',12:'filter-relief',13:'filter-fscore'};
  const wrapperMethodHelp={1:'wrapper-greedy',2:'wrapper-sa',3:'wrapper-ga',4:'wrapper-pso',5:'wrapper-pfa'};
  let contextHelp;
  function attachHelp(){
    const modal=byId('rfeConfigModal');
    contextHelp=NMContextHelp.attach(modal,modal.querySelector('.rfeLayout'),'RFE_Context_Help.html','Ensemble learning help');
    modal.querySelectorAll('.rfePane h2').forEach(heading=>{
      contextHelp.button(heading,heading.parentElement.id.slice('rfePane_'.length),heading.textContent);
    });
    modal.querySelectorAll('.rfePane .field > label').forEach(label=>{
      const input=label.control || label.querySelector('[id]');
      if(input && (input.id==='rfeFilterEnabled' || input.id==='rfeWrapperEnabled'))return;
      const pane=label.closest('.rfePane');
      const topic=helpTopics[input && input.id] || (input && input.id) || pane.id.slice('rfePane_'.length);
      contextHelp.button(label,topic==='filter-method' ? ()=>filterMethodHelp[byId('rfeFilterType').value] : topic==='wrapper-method' ? ()=>wrapperMethodHelp[byId('rfeWrapperType').value] : topic,label.textContent);
    });
    const blocks={rfeFilterMethodFEAST:'filter-feast',rfeFilterMethodMRMR:'filter-mrmr',rfeFilterMethodPearson:'filter-correlation',rfeFilterMethodSimba:'filter-simba',rfeFilterMethodGflip:'filter-gflip',rfeFilterMethodIMRelief:'filter-imrelief',rfeFilterMethodRGS:'filter-rgs',rfeFilterMethodRSS:'filter-rss',rfeFilterMethodRelief:'filter-relief',rfeWrapperMethodGreedy:'wrapper-greedy',rfeAdaptiveBlock:'wrapper-adaptive',rfeWrapperMethodSA:'wrapper-sa',rfeWrapperMethodGA:'wrapper-ga',rfeWrapperMethodPSO:'wrapper-pso',rfeWrapperMethodPFA:'wrapper-pfa'};
    Object.entries(blocks).forEach(([id,topic])=>{
      const block=byId(id);
      if(block){
        let heading=block.querySelector('h3');
        if(!heading){heading=document.createElement('h3');heading.textContent=topic.replace('filter-','').toUpperCase();block.prepend(heading);}
        contextHelp.button(heading,topic,heading.textContent);
      }
    });
  }

  function attach(c){
    ctx=c;
    ensureAdvancedDom();
    attachHelp();
    let open=byId('openRFEConfig');if(open)open.onclick=async()=>{if(ctx.getState().seqoptStacking)return;if(ctx.getActiveEditor()){ctx.status('Another configuration window is already open. Return to the main configuration menu first.','warn');return;}ctx.setActiveEditor('rfe');byId('rfeConfigModal').classList.add('open');render();await refresh();};
    let close=byId('closeRFEConfig');if(close)close.onclick=async()=>{if(!(await apply()))return;byId('rfeConfigModal').classList.remove('open');contextHelp.close();ctx.setActiveEditor(null);ctx.render();ctx.sync();};
    document.querySelectorAll('.rfeTab').forEach(b=>b.onclick=()=>setTab(b.dataset.tab));
    [
      'rfeFilterEnabled:Filter.flag:check','rfeWrapperEnabled:Wrapper.flag:check','rfeRetrainImmediate:RetrainImmediate:check',
      'rfeFilterSubspace:Filter.SubSpaceFlag:check','rfeFilterType:Filter.type:num','rfeFilterMinNum:Filter.MinNum:num','rfeFilterRankThresh:Filter.RankThresh:num','rfeFilterPearson:Filter.Pearson:num','rfeFilterMetric:Filter.EnsembleStrategy.Metric:num','rfeFilterBinmode:Filter.binmode:num','rfeFilterCostFun:Filter.CostFun:num','rfeFilterSubSpaceStrategy:Filter.SubSpaceStrategy:num','rfeFilterSubSpaceCrit:Filter.SubSpaceCrit:num','rfeFilterSubSpaceStepping:Filter.SubSpaceStepping:num','rfeFilterEnsConstructMode:Filter.EnsembleStrategy.ConstructMode:num','rfeFilterEnsMinNum:Filter.EnsembleStrategy.MinNum:num','rfeFilterEnsPerc:Filter.EnsembleStrategy.Perc:num',
      'rfeFilterEnsDiversitySource:Filter.EnsembleStrategy.DiversitySource:text','rfeFilterEnsMetric:Filter.EnsembleStrategy.Metric:num','rfeFilterEnsWeighting:Filter.EnsembleStrategy.Weighting:num','rfeFilterEnsEntropyWeight:Filter.EnsembleStrategy.EntropyWeight:num','rfeFilterEnsSizePenalty:Filter.EnsembleStrategy.SizePenalty:num','rfeFilterEnsPatience:Filter.EnsembleStrategy.Patience:num','rfeFilterEnsDiversityEps:Filter.EnsembleStrategy.DiversityEps:num',
      'rfeFilterBoostMode:Filter.EnsembleStrategy.Boosting.mode:text','rfeFilterBoostLambda:Filter.EnsembleStrategy.Boosting.lambda:num','rfeFilterBoostAlpha:Filter.EnsembleStrategy.Boosting.alpha:num','rfeFilterBoostUseLogits:Filter.EnsembleStrategy.Boosting.useLogits:bool','rfeFilterBoostWThreshold:Filter.EnsembleStrategy.Boosting.wThreshold:num','rfeFilterBoostClip:Filter.EnsembleStrategy.Boosting.clip:num','rfeFilterBoostEta:Filter.EnsembleStrategy.Boosting.eta:num','rfeFilterBoostT:Filter.EnsembleStrategy.Boosting.T:num','rfeFilterBoostShareWeights:Filter.EnsembleStrategy.Boosting.shareWeights:bool','rfeFilterBoostDiversitySource:Filter.EnsembleStrategy.DiversitySource:text','rfeFilterBoostKernelRegMode:Filter.EnsembleStrategy.Boosting.Kernel.regMode:text','rfeFilterBoostKernelDiagMode:Filter.EnsembleStrategy.Boosting.Kernel.diagMode:text','rfeFilterBoostKernelScaleTo:Filter.EnsembleStrategy.Boosting.Kernel.scaleTo:text','rfeFilterBoostKernelAutoAlpha:Filter.EnsembleStrategy.Boosting.Kernel.autoAlpha:bool','rfeFilterBoostKernelTau:Filter.EnsembleStrategy.Boosting.Kernel.tau:num',
      'rfeFilterPFEFlag:Filter.PFE.flag:check','rfeFilterPFEMode:Filter.PFE.Mode:num','rfeFilterPFEPerc:Filter.PFE.Perc:num','rfeFilterPFETolWin:Filter.PFE.TolWin:num','rfeFilterPFEMinNum:Filter.PFE.MinNum:num','rfeFilterPFEPrune:Filter.PFE.PruneFlag:bool',
      'rfeFEASTMethod:Filter.FEAST.Method:num','rfeFEASTNumFeat:Filter.FEAST.NumFeat:vec','rfeMRMRScheme:Filter.MRMR.mRMRscheme:num','rfeMRMRNumFeat:Filter.MRMR.NumFeat:vec','rfeSimbaStart:Filter.simba.extra_param.start_points:num','rfeSimbaMaxIter:Filter.simba.extra_param.max_iter:num','rfeSimbaAbort:Filter.simba.extra_param.iter_abort_crit:num','rfeSimbaBlock:Filter.simba.extra_param.block_size:num','rfeSimbaUtility:Filter.simba.utilfunc:num','rfeSimbaBeta:Filter.simba.extra_param.beta:text','rfeGflipStart:Filter.gflip.extra_param.start_points:num','rfeGflipMaxIter:Filter.gflip.extra_param.max_iter:num','rfeGflipBlock:Filter.gflip.extra_param.block_size:num','rfeGflipUtility:Filter.gflip.utilfunc:num','rfeGflipBeta:Filter.gflip.extra_param.beta:text','rfeGflipLimFeat:Filter.gflip.limfeat:check','rfeRGSStarts:Filter.RGS.extra_param.num_starts:num','rfeRGSEpochs:Filter.RGS.extra_param.epochs:num','rfeRGSK:Filter.RGS.extra_param.k:vec','rfeRGSBeta:Filter.RGS.extra_param.beta:vec','rfeRGSVerbose:Filter.RGS.extra_param.verbose:bool','rfeRSSPerms:Filter.RSS.nperms:num','rfeRSSMin:Filter.RSS.nMinFeatsPerc:num','rfeRSSMax:Filter.RSS.nMaxFeatsPerc:num','rfeReliefK:Filter.Relief.k:num',
      'rfeWrapperSubspace:Wrapper.SubSpaceFlag:check','rfeWrapperSubSpaceStepping:Wrapper.SubSpaceStepping:num','rfeWrapperEnsConstructMode:Wrapper.EnsembleStrategy.ConstructMode:num','rfeWrapperEnsSubSpaceStrategy:Wrapper.SubSpaceStrategy:num','rfeWrapperEnsSubSpaceCrit:Wrapper.SubSpaceCrit:num','rfeWrapperEnsMinNum:Wrapper.EnsembleStrategy.MinNum:num','rfeWrapperEnsPerc:Wrapper.EnsembleStrategy.Perc:num','rfeWrapperEnsDiversitySource:Wrapper.EnsembleStrategy.DiversitySource:text','rfeWrapperEnsMetric:Wrapper.EnsembleStrategy.Metric:num','rfeWrapperEnsWeighting:Wrapper.EnsembleStrategy.Weighting:num','rfeWrapperEnsEntropyWeight:Wrapper.EnsembleStrategy.EntropyWeight:num','rfeWrapperEnsSizePenalty:Wrapper.EnsembleStrategy.SizePenalty:num','rfeWrapperEnsPatience:Wrapper.EnsembleStrategy.Patience:num','rfeWrapperEnsDiversityEps:Wrapper.EnsembleStrategy.DiversityEps:num',
      'rfeWrapperBoostMode:Wrapper.EnsembleStrategy.Boosting.mode:text','rfeWrapperBoostLambda:Wrapper.EnsembleStrategy.Boosting.lambda:num','rfeWrapperBoostAlpha:Wrapper.EnsembleStrategy.Boosting.alpha:num','rfeWrapperBoostUseLogits:Wrapper.EnsembleStrategy.Boosting.useLogits:bool','rfeWrapperBoostWThreshold:Wrapper.EnsembleStrategy.Boosting.wThreshold:num','rfeWrapperBoostClip:Wrapper.EnsembleStrategy.Boosting.clip:num','rfeWrapperBoostEta:Wrapper.EnsembleStrategy.Boosting.eta:num','rfeWrapperBoostT:Wrapper.EnsembleStrategy.Boosting.T:num','rfeWrapperBoostShareWeights:Wrapper.EnsembleStrategy.Boosting.shareWeights:bool','rfeWrapperBoostDiversitySource:Wrapper.EnsembleStrategy.DiversitySource:text','rfeWrapperBoostKernelRegMode:Wrapper.EnsembleStrategy.Boosting.Kernel.regMode:text','rfeWrapperBoostKernelDiagMode:Wrapper.EnsembleStrategy.Boosting.Kernel.diagMode:text','rfeWrapperBoostKernelScaleTo:Wrapper.EnsembleStrategy.Boosting.Kernel.scaleTo:text','rfeWrapperBoostKernelAutoAlpha:Wrapper.EnsembleStrategy.Boosting.Kernel.autoAlpha:bool','rfeWrapperBoostKernelTau:Wrapper.EnsembleStrategy.Boosting.Kernel.tau:num',
      'rfeWrapperOptflag:Wrapper.optflag:num','rfeWrapperType:Wrapper.type:num','rfeWrapperDatamode:Wrapper.datamode:num','rfeWrapperPFEFlag:Wrapper.PFE.flag:check','rfeWrapperPFEMode:Wrapper.PFE.Mode:num','rfeWrapperPFEPerc:Wrapper.PFE.Perc:num','rfeWrapperPFETolWin:Wrapper.PFE.TolWin:num','rfeWrapperPFEMinNum:Wrapper.PFE.MinNum:num','rfeWrapperPFEPrune:Wrapper.PFE.PruneFlag:bool',
      'rfeGreedyDirection:Wrapper.GreedySearch.Direction:num','rfeGreedyEarlyThresh:Wrapper.GreedySearch.EarlyStop.Thresh:num','rfeGreedyEarlyPerc:Wrapper.GreedySearch.EarlyStop.Perc:num','rfeGreedyFeatStep:Wrapper.GreedySearch.FeatStepPerc:num','rfeGreedyFeatRand:Wrapper.GreedySearch.FeatRandPerc:num','rfeGreedyKnee:Wrapper.GreedySearch.KneePointDetection:num','rfeGreedyWeightSort:Wrapper.GreedySearch.WeightSort:num','rfeGreedyCritGapFlag:Wrapper.GreedySearch.CritGap.flag:two12','rfeGreedyCritGapCrit:Wrapper.GreedySearch.CritGap.crit:num','rfeAdEnable:Wrapper.GreedySearch.AdRef.Enable:bool','rfeAdAuto:Wrapper.GreedySearch.AdRef.Auto.Enable:bool','rfeAdLambda:Wrapper.GreedySearch.AdRef.lambda:num','rfeAdKNN:Wrapper.GreedySearch.AdRef.kNN:num','rfeAdGamma:Wrapper.GreedySearch.AdRef.gamma:num','rfeAdEta0:Wrapper.GreedySearch.AdRef.eta0:num','rfeAdEta1:Wrapper.GreedySearch.AdRef.eta1:num','rfeAdRmax:Wrapper.GreedySearch.AdRef.rmax:num','rfeAdC:Wrapper.GreedySearch.AdRef.c:num','rfeAdW:Wrapper.GreedySearch.AdRef.w:num','rfeAdBetaWell:Wrapper.GreedySearch.AdRef.beta_well:num','rfeAdBetaHi:Wrapper.GreedySearch.AdRef.beta_hi:num','rfeAdSigmaLo:Wrapper.GreedySearch.AdRef.sigma_lo:num','rfeAdSigmaHi:Wrapper.GreedySearch.AdRef.sigma_hi:num',
      'rfeSAc:Wrapper.SA.c:num','rfeSAT:Wrapper.SA.T:num','rfeSAT_stop:Wrapper.SA.T_stop:num','rfeSAalpha:Wrapper.SA.alpha:num','rfeSAitt_max:Wrapper.SA.itt_max:num','rfeSARep_T_max:Wrapper.SA.Rep_T_max:num','rfeSARep_accept_max:Wrapper.SA.Rep_accept_max:num','rfeSAkc:Wrapper.SA.kc:num','rfeGAN:Wrapper.GA.N:num','rfeGAmax_Iter:Wrapper.GA.max_Iter:num','rfeGACR:Wrapper.GA.CR:num','rfeGAMR:Wrapper.GA.MR:num','rfePSON:Wrapper.PSO.N:num','rfePSOmax_Iter:Wrapper.PSO.max_Iter:num','rfePSOc1:Wrapper.PSO.c1:num','rfePSOc2:Wrapper.PSO.c2:num','rfePSOw:Wrapper.PSO.w:num','rfePSOlb:Wrapper.PSO.lb:num','rfePSOub:Wrapper.PSO.ub:num','rfePSOthres:Wrapper.PSO.thres:num','rfePFAN:Wrapper.PFA.N:num','rfePFAmax_Iter:Wrapper.PFA.max_Iter:num','rfePFAlb:Wrapper.PFA.lb:num','rfePFAub:Wrapper.PFA.ub:num','rfePFAthres:Wrapper.PFA.thres:num',
      'rfeClassRetrain:ClassRetrain:check','rfeCV2Metric:CV2Class.EnsembleStrategy.Metric:num','rfeAggregationLevel:CV2Class.EnsembleStrategy.AggregationLevel:num'
    ].forEach(s=>{let p=s.split(':');bind(p[0],p[1],p[2]);});
    ['rfeFilter','rfeWrapper'].forEach(p=>{let branch=p==='rfeFilter'?'Filter':'Wrapper';bindOpt(p,branch);bindPct(p+'EnsPerfSlackPct',branch+'.EnsembleStrategy.PerfSlackPct');bindSizePenaltyMirror(p,branch);});
    ['rfeIMReliefDistance','rfeIMReliefSigma','rfeIMReliefLambda','rfeIMReliefMaxiter','rfeIMReliefPlot'].forEach(id=>{let e=byId(id);if(!e)return;let h=()=>{let im=firstImrelief(RFE());if(id==='rfeIMReliefDistance')im.distance=e.value;else if(id==='rfeIMReliefSigma')im.sigma=numVec(e.value,[2]);else if(id==='rfeIMReliefLambda')im.lambda=numVec(e.value,[0.1]);else if(id==='rfeIMReliefMaxiter')im.maxiter=asNum(e.value,10);else if(id==='rfeIMReliefPlot')im.plotfigure=!!e.checked;mark();render();};e.onchange=h;e.oninput=id==='rfeIMReliefSigma'||id==='rfeIMReliefLambda'||id==='rfeIMReliefMaxiter'?h:null;});
    render();
  }
  window.NMRFEUI={attach:attach,render:render,renderSummary:renderSummary,apply:apply};
})();
