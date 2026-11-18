function out = nm_train_template_generate_api_reconstruction_code(NM, outDir, ctx)
% Emit a documented scientific configuration, not a snapshot of editor state.
if nargin < 2 || isempty(outDir)
    outDir = fullfile(pwd,'NM_train_template_exports',datestr(now,'yyyymmdd_HHMMSS'));
end
if nargin < 3 || isempty(ctx), ctx = struct(); end
ctx.modeflag = NM.modeflag;
if ~ismember('TrainParam',fieldnames(NM))
    error('P12A:missingTrainParam','Materialize the browser configuration before export.');
end
active = NM.TrainParam.ActiveModality;
orch = NMTrainTemplateOrchestrator.fromNM(NM,active,ctx);

raw = NM;
raw.TrainParam = struct();
base = NMTrainTemplateOrchestrator.fromNM(raw,active,ctx);
L = local_header(active,orch.MLI);
L = [L,local_alternative_label(orch,NM)];
L = [L,{sprintf('orch = NMTrainTemplateOrchestrator.fromNM(NM,%d,ctx);',active)}];
L = [L, local_fusion(orch,base,NM)];
L = [L, local_cv(orch,base,NM)];
L = [L, local_synth(orch)];
L = [L, local_preproc(orch,NM)];
L = [L, local_learner(orch,ctx)];
L = [L, local_advanced(orch,base,NM)];
L = [L, local_footer()];
if ~exist(outDir,'dir'), mkdir(outDir); end
apiFile = fullfile(outDir,'build_nm_train_template_from_api.m');
fid = fopen(apiFile,'w');
if fid < 0, error('P12A:writeFailed','Cannot open %s.',apiFile); end
cleaner = onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',strjoin(L,newline));
clear cleaner
out = struct('ok',true,'message','Scientific MATLAB configuration scaffold exported.', ...
    'exportDir',outDir,'apiFile',apiFile,'files',{{'build_nm_train_template_from_api.m'}}, ...
    'nPreprocSteps',local_count_steps(orch),'nMLBranches',1+numel(orch.MLStrat));
end

function L = local_header(active, mli)
L = { ...
'function [NM, report, orch] = build_nm_train_template_from_api(NM, varargin)'
'% Reconstruct exported settings on an imported NM, even if already configured.'
'% Returns new TrainParam settings; the caller''s NM variable is unchanged.'
'% Example: [NMconfigured, report] = build_nm_train_template_from_api(NM);'
'% Requires NM2 on path; does not train or save. Review before sharing.'
''
'if ~isstruct(NM) || ~isfield(NM,''Y'') || ~isfield(NM,''modeflag'')'
'    error(''NMTrainTemplateScaffold:input'',''Load an imported NM dataset with Y and modeflag before reconstructing the training settings.'');'
'end'
'NM.TrainParam = struct(); % Rebuild from defaults, not previous training settings.'
'p = inputParser;'
'addParameter(p,''RunScaffold'',false);'
'addParameter(p,''Mode'',''dryrun'');'
'addParameter(p,''Context'',struct());'
'parse(p,varargin{:});'
'opts = p.Results;'
'ctx = opts.Context;'
'ctx.modeflag = NM.modeflag;'
'checks = struct();'
''
'%% 1. Scientific task and selected modalities'
'% The participant data, labels and modality geometry come from NM.'
};
L=L(:).';
% Dataset-specific atlas/descriptor paths are runtime resources, not exported literals.
if mli.mliIsImaging && mli.mliAtlasFlag && ~isempty(mli.mliAtlasFile)
    ix = find(strcmp(L,'parse(p,varargin{:});'));
    L = [L(1:ix-1), {'% Pass ''MLIAtlasFile'' with the atlas path when calling this function.', ...
        'addParameter(p,''MLIAtlasFile'','''');'}, L(ix:end)];
end
if mli.mliIsImaging && ~isempty(mli.mliCsvFile)
    ix = find(strcmp(L,'parse(p,varargin{:});'));
    L = [L(1:ix-1), {'% Pass ''MLIDescriptorFile'' with the descriptor table path.', ...
        'addParameter(p,''MLIDescriptorFile'','''');'}, L(ix:end)];
end
end

function L = local_alternative_label(orch,NM)
L = {};
if orch.AlternativeLabel.flag ~= 1, return; end
source = NMAlternativeLabelTools.importedLabelSource(NM,orch.AlternativeLabel.newlabel);
keys = {'Enabled','SourceVar','Mode','Name'};
vals = {true,source,orch.AlternativeLabel.newmode,orch.AlternativeLabel.newlabelname};
if strcmp(orch.AlternativeLabel.newmode,'classification')
    keys{end+1} = 'GroupNames';
    vals{end+1} = orch.AlternativeLabel.newgroupnames;
end
L = {'','%% Alternative target','% Select target values by imported NM identity, not subject vectors.'};
L = [L,local_call('[NM,~,~,checks.target] = NMAlternativeLabelTools.cli_configure(NM, ...', ...
    keys,vals,'general',[])];
L{end+1} = 'ctx.modeflag = NMAlternativeLabelTools.effectiveMode(NM);';
end

function L = local_fusion(orch,base,NM)
L = {};
if orch.Stacking.flag == 1
    selected = orch.Stacking.sel_anal;
    settings = struct('flag','enabled','sel_anal',selected, ...
        'featname_mode',orch.Stacking.featname_mode, ...
        'featname_edit',orch.Stacking.featname_edit,'mode',orch.Stacking.mode);
    catalogue = NMAnalysisManagerTools.listAnalyses(NM);
    L = {'','%% Stacking: reuse the completed first-level analyses in NM', ...
        'catalogue = NMAnalysisManagerTools.listAnalyses(NM);', ...
        sprintf('assert(isequal(catalogue.ids(%s),%s),''P12A:stackingSources'', ...', ...
            mat2str(selected),local_literal(catalogue.ids(selected),0)), ...
        '    ''The selected first-level analyses do not match the source NM.'');', ...
        ['[orch,checks.stacking] = orch.cli_configure(''Stacking'', ' local_literal(settings,0) ');'], ...
        'assert(orch.isStackingEnabled(),''P12A:stackingSources'',''First-level analyses are ineligible for stacking.'');'};
elseif ~isequaln(orch.FusionFlag,base.FusionFlag) || ...
        ~isequaln(orch.FusionModalities,base.FusionModalities)
    h = orch.cli_configureHelp();
    symbol = local_symbol(orch.FusionFlag,h.choices.FusionFlag,'fusion');
    L = [L,{'% Combine imported modalities using the fusion strategy.'}, ...
        local_call('[orch,checks.fusion] = orch.cli_configure(', ...
        {'FusionFlag','FusionModalities'}, {symbol,orch.FusionModalities},'general',[])];
end
end

function L = local_cv(orch,base,NM)
L = {'','%% 2. Cross-validation','% Nested CV defines unbiased outer-fold evaluation and inner-fold model selection.'};
keys = {'cvFramework','cvOuterMode','cvOuterPerm','cvOuterFold', ...
        'cvInnerMode','cvInnerPerm','cvInnerFold','cvDecompose'};
if orch.CVPartition.cvEqEnabled
    keys=[keys,{'cvEqEnabled','cvEqAddRemoved2Test','cvEqMinCount', ...
        'cvEqMaxCount','cvEqBinCount','cvEqPosNegRatio','cvEqTarget'}];
elseif ~isequaln(orch.CVPartition.cvEqEnabled,base.CVPartition.cvEqEnabled)
    keys=[keys,{'cvEqEnabled'}];
end
if ~isequaln(orch.CVPartition.cvConstrainedCV,base.CVPartition.cvConstrainedCV)
    keys=[keys,{'cvConstrainedCV'}];
end
if ~isequaln(orch.CVPartition.cvOnlyGroupFlag,base.CVPartition.cvOnlyGroupFlag)
    keys=[keys,{'cvOnlyGroupFlag','cvOnlyGroupLevel'}];
end
if orch.CVPartition.cvEqEnabled && strcmp(orch.CVPartition.cvEqTarget,'covariate')
    keys{end+1} = 'cvEqCovarName';
end
indexKeys = {'cvOuterGroupIndex','cvInnerGroupIndex', ...
    'cvConstrainedGroupIndex','cvOnlyGroupIndex'};
activeGroups = [orch.CVPartition.cvFramework ~= 1, ...
    any(orch.CVPartition.cvFramework == [3 4]), ...
    orch.CVPartition.cvConstrainedCV == 1 && orch.CVPartition.cvFramework == 1, ...
    orch.CVPartition.cvOnlyGroupFlag == 1];
keys = [keys,indexKeys(activeGroups)];
used = any(cellfun(@(key) any(strcmp(key,indexKeys)) || ...
    ~isequaln(orch.CVPartition.(key),base.CVPartition.(key)),keys));
if used
    values = cell(size(keys));
    choices = NMCVPartitionTools.apiChoices();
    for i=1:numel(keys)
        value = orch.CVPartition.(keys{i});
        if ismember(keys{i},fieldnames(choices))
            value = local_symbol(value,choices.(keys{i}),keys{i});
        end
        if any(strcmp(keys{i},indexKeys))
            value = NMCVPartitionTools.importedGroupSource(NM,value);
        end
        values{i} = value;
    end
    L = [L,{'% Configure one complete CV design using the public CV API.'}, ...
        local_call('[~,cvState,checks.cv] = NMCVPartitionTools.cli_configure(NM, NMCVPartitionTools.stateFromNM(NM), ...',keys,values,'cv',[])];
else
    L{end+1} = 'cvState = NMCVPartitionTools.stateFromNM(NM);';
end
L = [L,{'[orch,checks.cvBind] = orch.cli_configure(''CVPartition'',cvState);'}];
end

function L = local_synth(orch)
L = {};
if ~orch.Synth.synthEnabled, return; end
L = {'','%% 3. Optional synthetic-data augmentation','% Synthetic cases are generated inside training partitions, never embedded here.'};
keys = {'synthEnabled','synthMethod','synthK','synthDistanceMeasure', ...
    'synthStandardizeData','synthNumSyntheticObservations','synthWrite2Disk', ...
    'synthBeta','synthKDensity','synthKSMOTE','synthNComponents','synthMinMethod'};
values = cellfun(@(key)orch.Synth.(key),keys,'UniformOutput',false);
L = [L, local_call('[~,synthState,checks.synth] = NMSynthTools.cli_configure(NM, NMSynthTools.stateFromNM(NM), ...',keys,values,'general',[]), ...
    {'[orch,checks.synthBind] = orch.cli_configure(''Synth'',synthState);'}];
end

function L = local_preproc(orch,NM)
L = {'','%% 4. Ordered preprocessing', ...
    '% Operations preserve their stage and execute inside the established preprocessing authority.'};
stacking = orch.Stacking.flag == 1;
if orch.FusionFlag==0
    relevant = orch.VarIndex;
elseif orch.FusionFlag==3
    relevant = 1:orch.NumModalities;
else
    relevant = orch.FusionModalities;
end
if ~stacking, L{end+1} = 'preprocBranches = cell(1,numel(NM.Y));'; end
n = 0;
for i=relevant
    if stacking, pp = orch.materializePreprocBranch(1,true);
    else, pp = orch.Preproc{i}; end
    if isempty(pp), continue; end
    local_verify_preserved_px(pp);
    globalKeys = {'binmod','enableTargetTransform','targetScale','usePolynomial', ...
        'polynomial','enableLabelImpute','labelImputeMethod','labelImputeK'};
    globalChanged = stacking;
    if ~stacking
        raw = NM;
        raw.TrainParam = struct();
        defaultPP = NMPreprocOrchestrator.fromNM(raw,i,[]);
        globalChanged = any(cellfun(@(key) ~isequaln(pp.GlobalOptions.(key), ...
            defaultPP.GlobalOptions.(key)),globalKeys));
    end
    steps = [pp.SubjectSequence.Steps pp.CVSequence.Steps];
    if isempty(steps) && ~globalChanged, continue; end
    n = n + 1;
    source = sprintf('pp = NMPreprocOrchestrator.fromNM(NM,%d,[]);',i);
    target = sprintf('preprocBranches{%d} = pp;',i);
    if stacking
        source = 'pp = orch.materializePreprocBranch(1,true);';
        target = '[orch,checks.preproc] = orch.cli_configure(''StackingPreproc'',pp);';
    end
    L = [L,{''; sprintf('%% Preprocessing branch %d: preserve operation order.',i); ...
        source; 'pp.SubjectSequence.Steps = {};';'pp.CVSequence.Steps = {};'; ...
        'pp.refreshStageContexts();'}'];
    if globalChanged
        options = rmfield(pp.GlobalOptions,'legacyLABELMOD');
        binmodChoices = NMPreprocGlobalOptions.binmodChoices();
        options.binmod = local_symbol(options.binmod,[binmodChoices{:}],'binmod');
        L = [L,{'% Configure target transformation, label handling and group processing.'}, ...
            {['[pp,~,globalReport] = pp.cli_configure(''GlobalOptions'', ' local_literal(options,0) ');']}, ...
            {'if ~globalReport.ok, error(''P12A:globalOptions'',''%s'',strjoin(globalReport.errors,''; '')); end'}];
    end
    L = [L,local_preproc_stage(pp,'subject',pp.SubjectSequence.Steps,NM), ...
        local_preproc_stage(pp,'cv',pp.CVSequence.Steps,NM), ...
        {'validation = pp.validate();', ...
        'if ~validation.ok, error(''P12A:preproc'',''%s'',strjoin(validation.errors,newline)); end',target}];
end
if n>0 && ~stacking
    L = [L,{'[orch,checks.preproc] = orch.cli_configure(''Preproc'',preprocBranches);'}];
end
end

function L = local_preproc_stage(pp,stage,steps,NM)
L = {};
if strcmp(stage,'subject'), ctx = pp.SubjectSequence.Context;
else, ctx = pp.CVSequence.Context; end
k=1;
while k<=numel(steps)
    st=steps{k};
    mid=st.moduleId;
    % The ruleset, not the generator, owns automatic parent-child blocks.
    rule = NMPreprocRuleSet.default().getRule(mid);
    child = rule.sequence.autoAddChild;
    paired=false;
    if k<numel(steps)
        paired=strcmp(steps{k+1}.moduleId,child);
    end
    L = [L, local_preproc_step(pp.Registry.get(mid),st,stage,k,ctx,NM)];
    if paired
        L = [L,local_preproc_step(pp.Registry.get(child),steps{k+1},stage,k+1,ctx,NM), ...
            {sprintf('pp.addBlockAtStage(''%s'',''%s'',cfg%d,''%s'',cfg%d);', ...
            stage,mid,k,child,k+1)}];
    else
        L{end+1}=sprintf('pp.addStepAtStage(''%s'',''%s'',cfg%d);',stage,mid,k);
    end
    k=k+1+paired;
end
end

function L = local_preproc_step(module,step,stage,idx,ctx,NM)
% Build a single module API call rather than emitting setting-by-setting edits.
spec = module.configSpec(ctx);
base = module.defaultConfig(ctx);
keys = {};
vals = {};
docs = {};
for j=1:numel(spec.fields)
    f=spec.fields{j};
    if NMConfigTools.getField(f,'uiHidden',false) || strcmp(f.type,'readonly'), continue; end
    key=f.name;
    val=step.config.(key);
    if strcmp(f.type,'subconfig')
        if isequaln(val,base.(key)),continue;end
        if strcmp(key,'methodConfig')
            nestedSpec=NMNuisanceSubconfigLibrary.byMethod(step.config.method,ctx);
            docs{end+1}=local_description(nestedSpec.description); %#ok<AGROW>
        end
        val=local_subconfig(val,step.config,key,ctx);
    elseif isequaln(val,base.(key))
        continue;
    end
    if ismember('help',fieldnames(f)) && ~isempty(f.help)
        % The owning schema supplies the explanation of this selected option.
        docs{end+1}=local_description(f.help); %#ok<AGROW>
    end
    keys{end+1}=key; %#ok<AGROW>
    vals{end+1}=val; %#ok<AGROW>
end
L = {sprintf('%% %s: %s (step %d).',stage,spec.title,idx)};
if ismember('method',fieldnames(step.config))
    L{end+1}=sprintf('%% Selected method: %s.',local_literal(step.config.method,0));
end
if ~isempty(spec.description)
    L{end+1}=['% ' local_description(spec.description)];
end
for j=1:numel(docs)
    L{end+1}=['% ' docs{j}]; %#ok<AGROW>
end
var=sprintf('cfg%d',idx);
% The module owns both the default schema and normalization.
L = [L,{sprintf('module = pp.Registry.get(''%s'');',step.moduleId)}];
callPrefix=sprintf('%s = module.parseConfig(struct(''nm2PreprocContext'',pp.%sSequence.Context), ...', ...
    var,local_stage_title(stage));
L=[L,local_call(callPrefix,keys,vals,'preproc',NM)];
end

function sub = local_subconfig(configured,parent,key,ctx)
switch key
    case 'methodConfig'
        spec=NMNuisanceSubconfigLibrary.byMethod(parent.method,ctx);
    case 'algorithmParams'
        spec=NMRankSubconfigLibrary.spec(parent.algorithm,ctx);
    case 'methodParams'
        spec=NMDimRedSubconfigLibrary.spec(parent.method,ctx);
    otherwise
        error('P12A:missingSubconfigAPI','No scientific subconfiguration schema for %s.',key);
end
base=NMConfigTools.defaultsFromSpec(spec);
sub=struct();
fn=fieldnames(configured);
for i=1:numel(fn)
    f=fn{i};
    if strcmp(f,'covariateDetails'),continue;end
    if any(strcmp(f,{'subgroupVector','externalBetaMatrix'})) && ~isempty(configured.(f))
        error('P12A:unboundData','%s requires a named data-source API.',f);
    end
    if ~ismember(f,fieldnames(base))
        error('P12A:missingSubconfigAPI', ...
            'The owning schema does not describe nested setting %s.',f);
    end
    if isequaln(configured.(f),base.(f)),continue;end
    sub.(f)=configured.(f);
end
end

function L = local_learner(orch,ctx)
L = {'','%% 5. Learner, objective and hyperparameter search','% The active learner schema supplies defaults and owns the legacy SVM/GRD writer.'};
if orch.FusionFlag==3
    mods=1:orch.NumModalities;
else
    mods=0;
end
for idx=mods
    if idx==0, mlorch=orch.MLGlobal;branch='MLGlobal';
    else, mlorch=orch.MLStrat{idx};branch=sprintf('MLStrat{%d}',idx); end
    if isempty(mlorch),continue;end
    cfg=mlorch.MLConfig;
    baseline=mlorch.ML.defaultConfig(ctx,cfg.algorithm);
    % The entire *active* learner is emitted as one canonical API request.
    choice=struct('algorithm',cfg.algorithm);
    criterionChoices=NMLearnerLibrary.evalCriterionValues(NMLearnerLibrary.taskMode(ctx));
    choice.performanceCriterion=local_symbol(cfg.performanceCriterion, ...
        [criterionChoices{:}],'performance criterion');
    fixed=cfg.fixedSettings;
    fixedChoices=NMLearnerLibrary.learnerFixedChoices(cfg.algorithm,NMLearnerLibrary.taskMode(ctx));
    fields=fieldnames(fixedChoices);
    for k=1:numel(fields)
        field=fields{k};
        values=fixedChoices.(field);
        fixed.(field)=local_symbol(fixed.(field),[values{:}],field);
    end
    choice.fixedSettings=fixed;
    if ~isequaln(cfg.kernelSettings,baseline.kernelSettings)
        choice.kernelSettings=cfg.kernelSettings;
        choice.kernelSettings.kernstr = NMLearnerLibrary.kernelSymbol( ...
            cfg.algorithm,cfg.kernelSettings.kernstr);
    end
    % Preserve exactly the chosen learner parameter rows and their ranges.
    choice.hyperparameters=struct();
    if ~isequaln(cfg.hyperparameters.learnerParams,baseline.hyperparameters.learnerParams)
        choice.hyperparameters=struct('learnerParams',cfg.hyperparameters.learnerParams);
    end
    if ~isequaln(cfg.hyperparameters.learnerOptions,baseline.hyperparameters.learnerOptions)
        choice.hyperparameters.learnerOptions=cfg.hyperparameters.learnerOptions;
    end
    if isempty(fieldnames(choice.hyperparameters))
        choice=rmfield(choice,'hyperparameters');
    end
    choice.optimizationSettings=struct('type',cfg.optimizationSettings.type);
    if strcmp(cfg.optimizationSettings.type,'bayesopt')
        choice.optimizationSettings.Bayes=cfg.optimizationSettings.Bayes;
    elseif strcmp(cfg.optimizationSettings.type,'simanneal')
        choice.optimizationSettings.SimAneal=cfg.optimizationSettings.SimAneal;
    end
    model=struct('NodeSelect',cfg.modelSelectionSettings.NodeSelect);
    selectionChoices=NMLearnerLibrary.nodeSelectionValues();
    model.NodeSelect.mode=local_symbol(model.NodeSelect.mode,[selectionChoices{:}],'model selection');
    choice.modelSelectionSettings=model;
    if ~isequaln(cfg.postProcessingSettings,baseline.postProcessingSettings)
        choice.postProcessingSettings=cfg.postProcessingSettings;
    end
    L=[L,{sprintf('%% %s: %s; criterion %s; optimize via %s.', ...
        branch,cfg.algorithm,char(choice.performanceCriterion),cfg.optimizationSettings.type)}];
    if idx==0
        L=[L,{'ml = NMTrainConfigOrchestrator.fromNM(NM,[],ctx);'}];
    else
        L=[L,{sprintf('ml = NMTrainConfigOrchestrator.fromNM(NM,%d,ctx);',idx)}];
    end
    L=[L,local_ml_config_block(choice), ...
        {'[ml.MLConfig,~] = ml.ML.cli_configure(scientificLearner,ctx);'}];
    if idx==0
        L=[L,{'[orch,checks.learner] = orch.cli_configure(''MLGlobal'',ml);'}];
    else
        L=[L,{sprintf('mlBranches{%d} = ml;',idx)}];
    end
end
if orch.FusionFlag==3
    L=[L(1:3),{'mlBranches = cell(1,numel(NM.Y));'},L(4:end)];
    L=[L,{'[orch,checks.learner] = orch.cli_configure(''MLStrat'',mlBranches);'}];
end
end

function L = local_advanced(orch,base,NM)
L = {'','%% 6. Optional scientific analysis options'};
blocks={ ...
    struct('name','RFE','state',orch.RFE,'base',base.RFE,'owner','NMRFETools', ...
        'keys',{{'Filter','Wrapper','ClassRetrain','RetrainImmediate'}}), ...
    struct('name','Multi','state',orch.Multi,'base',base.Multi,'owner','NMMULTITools', ...
        'keys',{{'multiFlag','multiTrain','multiMethod','multiCoding','multiDecoding','multiBinBind','multiDecisionType'}}), ...
    struct('name','Vis','state',orch.Vis,'base',base.Vis,'owner','NMVISTools', ...
        'keys',{{}}), ...
    struct('name','MLI','state',orch.MLI,'base',base.MLI,'owner','NMMLITools', ...
        'keys',{{}}), ...
    struct('name','SAV','state',orch.SAV,'base',base.SAV,'owner','NMSAVTools', ...
        'keys',{{'savSaveModel','savMatName','verbosity','verbosityValue'}}) ...
};
for b=1:numel(blocks)
    x=blocks{b};
    % RFE's owner supplies the effective filter/wrapper block and symbols.
    if strcmp(x.name,'RFE')
        rfeDescription = NMRFETools.summary(x.state);
        effective = NMRFETools.scientificConfig(NM,x.state,orch.VarIndex,orch.FusionFlag);
        if isempty(fieldnames(effective)),continue;end
        x.keys = fieldnames(effective);
        x.state = effective;
        x.base = struct();
    end
    if strcmp(x.name,'Vis')
        effective = NMVISTools.scientificConfig(NM,x.state,orch.VarIndex,orch.FusionFlag);
        if isempty(fieldnames(effective)),continue;end
        x.keys = fieldnames(effective);
        x.state = effective;
    elseif strcmp(x.name,'MLI')
        effective = NMMLITools.scientificConfig(NM,x.state,orch.VarIndex,orch.FusionFlag);
        if isempty(fieldnames(effective)),continue;end
        x.keys = fieldnames(effective);
        x.state = effective;
    end
    if strcmp(x.name,'Multi') && ~x.state.multiFlag && ~x.state.multiTrain,continue;end
    diff=any(strcmp(x.name,{'RFE','Vis','MLI'}));
    if ~diff
        for j=1:numel(x.keys)
            key=x.keys{j};
            diff=diff || ~isequaln(x.state.(key),x.base.(key));
        end
    end
    if ~diff,continue;end
    names=x.keys(:).';
    values=cell(1,numel(names));
    for j=1:numel(names)
        value=x.state.(names{j});
        if strcmp(x.name,'Multi')
            choices=NMMULTITools.apiChoices();
            if ismember(names{j},fieldnames(choices))
                value=local_symbol(value,choices.(names{j}),names{j});
            end
        end
        values{j}=value;
    end
    if any(strcmp(x.name,{'Vis','MLI'}))
        names = [{'VarIndex','FusionFlag'}, names];
        values = [{orch.VarIndex,orch.FusionFlag}, values];
    end
    if strcmp(x.name,'SAV')
        prefix='[~,configured,checks.sav] = NMSAVTools.cli_configure(NM, NMSAVTools.stateFromNM(NM), ...';
    else
        prefix=sprintf('[~,configured,checks.%s] = %s.cli_configure(NM, %s.stateFromNM(NM,orch.VarIndex,orch.FusionFlag), ...', ...
            lower(x.name),x.owner,x.owner);
    end
    if ~any(strcmp(L,'NM = orch.toNM(NM,ctx);'))
        L=[L,{'% Materialize preprocessing and learner dependencies before advanced editors.', ...
            'NM = orch.toNM(NM,ctx);'}];
    end
    if strcmp(x.name,'RFE')
        L=[L,{['% ' rfeDescription]}];
    elseif strcmp(x.name,'Vis')
        L=[L,{'% VIS: normalization and enabled permutation tests, with covariate names bound to NM.'}];
    elseif strcmp(x.name,'MLI')
        L=[L,{'% MLI: interpretation method, active iteration/threshold options and optional mapping.'}];
    else
        L=[L,{sprintf('%% %s: apply the selected scientific settings as one block.',x.name)}];
    end
    mode='general';
    if strcmp(x.name,'Vis'), mode='vis'; end
    if strcmp(x.name,'MLI'), mode='mli'; end
    L=[L,local_call(prefix,names,values,mode,NM), ...
        {sprintf('[orch,checks.bind%s] = orch.cli_configure(''%s'',configured);',x.name,x.name)}];
    if strcmp(x.name,'MLI') && ...
            (any(strcmp(names,'mliAtlasFile')) || any(strcmp(names,'mliCsvFile')))
        L=[L,{'% Materialize MLI before importing external scientific resources.', ...
            'NM = orch.toNM(NM,ctx);'}];
        if any(strcmp(names,'mliAtlasFile'))
            L=[L,{'% Import the atlas from the file supplied at execution time.', ...
                '[configured,atlasMLI] = NMMLITools.importAtlasFile(NM,configured,orch.VarIndex,orch.FusionFlag,opts.MLIAtlasFile);', ...
                'NM = NMMLITools.applyLegacyToNM(NM,atlasMLI,orch.VarIndex,orch.FusionFlag);'}];
        end
        if any(strcmp(names,'mliCsvFile'))
            L=[L,{'% Import the descriptor table; the table data are not embedded in the script.', ...
                '[configured,descriptorMLI] = NMMLITools.importDescriptorFile(NM,configured,orch.VarIndex,orch.FusionFlag,opts.MLIDescriptorFile);', ...
                'NM = NMMLITools.applyLegacyToNM(NM,descriptorMLI,orch.VarIndex,orch.FusionFlag);'}];
        end
    end
end
end

function L = local_footer()
L = {'','%% 7. Materialization and validation', ...
'% Existing analysis snapshots are not modified; this configures training only.', ...
'NM = orch.toNM(NM,ctx);', ...
'items = fieldnames(checks);', ...
'for k=1:numel(items)', ...
'    c=checks.(items{k});', ...
'    if ~c.ok, error(''P12A:rejected'',''API %s rejected: %s'',items{k},strjoin(c.errors,''; '')); end', ...
'end', ...
'report = struct(''ok'',true,''api'',checks);', ...
'if opts.RunScaffold', ...
'    [~,audit,NM] = run_nm_train_template_scaffold(NM,''Mode'',opts.Mode, ...', ...
'        ''Context'',ctx,''VarIndex'',NM.TrainParam.ActiveModality);', ...
'    report = audit;', ...
'    report.api = checks;', ...
'end', ...
'end', ...
'', ...
'function idx = local_covariate_index(NM,idx,name)', ...
'assert(idx<=size(NM.covars,2) && strcmp(NM.covnames{idx},name), ...', ...
'    ''P12A:covariateName'',''Covariate %s no longer matches imported column %d.'',name,idx);', ...
'end'};
end

function L=local_call(prefix,names,values,mode,NM)
% One atomic API call for the complete scientific configuration block.
L={prefix};
if endsWith(prefix,'('),L{1}=[prefix ' ...'];end
for k=1:numel(names)
    if strcmp(mode,'preproc')
        expr=local_preproc_literal(values{k},names{k},NM);
    elseif strcmp(mode,'cv') && any(strcmp(names{k}, ...
            {'cvOuterGroupIndex','cvInnerGroupIndex', ...
             'cvConstrainedGroupIndex','cvOnlyGroupIndex'}))
        expr=['NMCVPartitionTools.importedGroupColumn(NM,' ...
            local_literal(values{k},0) ')'];
    elseif strcmp(mode,'vis') && strcmp(names{k},'visCovariateIndices')
        expr=local_named_covariates(values{k},NM);
    elseif strcmp(mode,'mli') && strcmp(names{k},'mliAtlasFile')
        expr='opts.MLIAtlasFile';
    elseif strcmp(mode,'mli') && strcmp(names{k},'mliCsvFile')
        expr='opts.MLIDescriptorFile';
    else
        expr=local_literal(values{k},0);
    end
    if k<numel(names)
        L{end+1}=sprintf('    ''%s'', %s, ...',names{k},expr); %#ok<AGROW>
    else
        L{end+1}=sprintf('    ''%s'', %s);',names{k},expr); %#ok<AGROW>
    end
end
if isempty(names)
    L{end}=regexprep(L{end},', \.\.\.$',');');
end
end

function L=local_ml_config_block(cfg)
% One coherent canonical MLConfig request, not detached field mutations.
fields=fieldnames(cfg);
L={'scientificLearner = struct( ...'};
for k=1:numel(fields)
    v=local_literal(cfg.(fields{k}),4);
    if k<numel(fields)
        L{end+1}=sprintf('    ''%s'', {%s}, ...',fields{k},v); %#ok<AGROW>
    else
        L{end+1}=sprintf('    ''%s'', {%s});',fields{k},v); %#ok<AGROW>
    end
end
end

function expr=local_preproc_literal(value,name,NM)
if ~strcmp(name,'methodConfig')
    expr=local_literal(value,0);return
end
fs=fieldnames(value);
args=cell(1,2*numel(fs));
for k=1:numel(fs)
    key=fs{k};
    v=value.(key);
    args{2*k-1}=local_literal(key,0);
    if any(strcmp(key,{'batchCovariate','covariates','categoricalCovariates'}))
        raw=local_named_covariates(v,NM);
    else
        raw=local_literal(v,0);
    end
    args{2*k}=['{' raw '}'];
end
expr=['struct(' strjoin(args,', ') ')'];
end

function expr=local_named_covariates(indices,NM)
if isempty(indices),expr='[]';return;end
names=NM.covnames;
assert(all(indices==fix(indices) & indices>=1 & indices<=numel(names)), ...
    'P12A:covariateBinding','Selected covariate indices are invalid.');
v=arrayfun(@(idx)sprintf('local_covariate_index(NM,%d,%s)',idx, ...
    local_literal(names{idx},0)),indices,'UniformOutput',false);
expr=['[' strjoin(v,' ') ']'];
end

function symbol=local_symbol(value,choices,field)
% Numeric-to-symbol translation reads only the owning API's choice records.
if ismember('code',fieldnames(choices))
    nums={choices.code};
else
    nums={choices.value};
end
idx=find(cellfun(@(x)isequaln(x,value),nums));
if numel(idx)~=1
    error('P12A:missingSymbols','No unique symbolic expression for %s.',field);
end
symbol=choices(idx).symbol;
end

function s=local_literal(x,indent)
% Human-readable MATLAB literals; structs remain API argument blocks.
switch class(x)
    case 'logical'
        if isscalar(x)
            if x,s='true';else,s='false';end
        else
            s=['logical(' mat2str(double(x)) ')'];
        end
    case 'char'
        s=['''' strrep(x,'''','''''') ''''];
    case 'string'
        s=['string(' local_literal(char(x),indent+4) ')'];
    case {'double','single'}
        if numel(x)>10000
            error('P12A:participantData','A block contains an array too large for scientific source.');
        end
        if isempty(x),s='[]';else,s=mat2str(x,17);end
        if strcmp(class(x),'single'),s=['single(' s ')'];end
    case 'cell'
        if numel(x)>1000,error('P12A:participantData','Large cell arrays cannot be emitted.');end
        parts=cellfun(@(v)local_literal(v,indent+4),x(:)','UniformOutput',false);
        s=['{' strjoin(parts,', ') '}'];
    case 'struct'
        if numel(x)>1000,error('P12A:participantData','Large structures cannot be emitted.');end
        if isempty(x),s='struct()';return;end
        if ~isscalar(x)
            vals=arrayfun(@(v)local_literal(v,indent+4),x,'UniformOutput',false);
            s=['[' strjoin(vals,', ') ']'];return;
        end
        fs=fieldnames(x);
        if isempty(fs),s='struct()';return;end
        parts=cell(1,numel(fs));
        for i=1:numel(fs)
            name=local_literal(fs{i},indent+4);
            value=local_literal(x.(fs{i}),indent+4);
            parts{i}=[name ', {' value '}'];
        end
        if numel(parts)<3
            s=['struct(' strjoin(parts,', ') ')'];
        else
            pad=repmat(' ',1,indent+4);
            s=['struct( ...' newline pad ...
               strjoin(parts,[', ...' newline pad]) ')'];
        end
    otherwise
        error('P12A:unsupportedValue', ...
            'The scientific API block contains unsupported type %s.',class(x));
end
end

function text=local_description(s)
text=strtrim(regexprep(char(s),'\s+',' '));
if numel(text)>150,text=[text(1:147) '...'];end
end

function s=local_stage_title(stage)
if strcmp(stage,'cv'),s='CV';else,s='Subject';end
end

function local_verify_preserved_px(pp)
% Reject inherited hyperparameter shelves that canonical writers cannot reproduce.
seqs={pp.SubjectSequence,pp.CVSequence};
for s=1:numel(seqs)
    seq=seqs{s};
    for k=1:numel(seq.Steps)
        step=seq.Steps{k};
        if ~ismember('legacyPX',fieldnames(step.config)) || isempty(fieldnames(step.config.legacyPX))
            continue
        end
        writer=seq.Registry.get(step.moduleId);
        cfg=step.config;
        if strcmp(step.moduleId,'standardize'),cfg=rmfield(cfg,'legacyPX');end
        if strcmp(seq.ExecutionStage,'subject') && ismethod(writer,'toLegacySubject')
            rebuilt=writer.toLegacySubject(cfg,seq.Context);
        else
            rebuilt=writer.toLegacy(cfg,seq.Context);
        end
        if ~ismember('PX',fieldnames(rebuilt)) || ~isequaln(step.config.legacyPX,rebuilt.PX)
            error('nm_train_template_generate_api_reconstruction_code:hyperparameterMismatch', ...
                '%s.PX cannot be reconstructed at %s step %d.', ...
                step.moduleId,seq.ExecutionStage,k);
        end
    end
end
end

function n=local_count_steps(orch)
if orch.Stacking.flag==1, branches={orch.StackingPreproc};
else, branches=orch.Preproc; end
branches=branches(~cellfun('isempty',branches));
n=sum(cellfun(@(p) numel(p.SubjectSequence.Steps)+numel(p.CVSequence.Steps),branches));
end
