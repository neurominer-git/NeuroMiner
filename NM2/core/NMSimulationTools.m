classdef NMSimulationTools
% SYNTH simulation using standard DataIO and ML lifecycle authorities.
% The coordinator owns cumulative cohort growth and AltY shift assignments;
% CV indices, analysis snapshots and training remain with their existing owners.

    methods (Static)
        function NM = createSyntheticTemplate(definition)
            % DataIO creates ordinary, finalized modality metadata for the
            % normal CV/PREPROC/ML/(MULTI) configurators.
            K=definition.classCount;
            n=max(60,20*K);
            if strcmp(definition.modeflag,'regression')
                labels=(1:n)'; groups={};
            else
                labels=mod((0:n-1)',K)+1;
                groups=arrayfun(@(k)sprintf('Group %d',k), ...
                    1:K,'UniformOutput',false);
            end
            cases=arrayfun(@(k)sprintf('SYNTH_CFG_%06d',k), ...
                1:n,'UniformOutput',false)';
            names=cell(1,numel(definition.modalityNames));
            X=cell(size(names));
            stream = RandStream('mt19937ar', 'Seed', 1047);
            for m=1:numel(names)
                X{m} = randn(stream, n, definition.featureCounts(m));
                names{m}=arrayfun(@(j)sprintf('Feature_%06d',j), ...
                    1:definition.featureCounts(m),'UniformOutput',false);
            end
            data=struct('Y',{X},'label',labels,'cases',{cases}, ...
                'featnames',{names},'groupnames',{groups});
            NM=NMSimulationTools.importSyntheticMatrices( ...
                NMDataIOAPITools.emptyNM(),data,definition,false);
            if numel(X)>1
                % Multi-modal synthetic experiments use the normal early-fusion authority.
                orch=NMTrainTemplateOrchestrator.fromNM(NM,1,struct());
                [orch,fusionReport]=orch.configure('FusionFlag',1, ...
                    'FusionModalities',1:numel(X));
                assert(fusionReport.ok,'NMSimulationTools:syntheticFusion', ...
                    'Default multi-modal early-fusion configuration failed.');
                NM=orch.toNM(NM,struct());
            end
            NM.TrainParam.SYNTH=NMSynthTools.defaultSetting(NM);
            NM.SYNTH=struct('analysis',{{}},'fullySyntheticDefinition',definition);
            NM.analysis={};
        end

        function definition = syntheticDefinition(NM)
            % Existing NM only establishes the native task and modality count.
            % Numerical widths and synthetic group counts belong to the SYNTH plan.
            % nm2-allow: Only DataIO SYNTH placeholders persist this optional definition.
            if isfield(NM,'SYNTH') && isfield(NM.SYNTH,'fullySyntheticDefinition')
                definition=NM.SYNTH.fullySyntheticDefinition;
                return;
            end
            M=numel(NM.Y);
            assert(NM.defs.import_finished && M>0, ...
                'NMSimulationTools:syntheticInput', ...
                'Finalize training data before configuring fully synthetic experiments.');
            mode=NM.modeflag;
            assert(strcmp(mode,'classification') || strcmp(mode,'regression'), ...
                'NMSimulationTools:syntheticTask', ...
                'Fully synthetic experiments require classification or regression.');
            definition=struct('modalityNames',{arrayfun(@(m)sprintf('Modality %d',m), ...
                1:M,'UniformOutput',false)},'featureCounts',10*ones(1,M), ...
                'modeflag',mode,'classCount',2);
            if strcmp(mode,'regression'),definition.classCount=1;end
        end

        function work = applySyntheticPopulation(template,data,definition)
            % DataIO is the only mutation authority; the unlocked copy
            % cannot affect the finalised configuration workspace.
            configured=template.TrainParam;
            assert(~NMSynthTools.stateFromNM(template).synthEnabled, ...
                'NMSimulationTools:doubleSynthesis', ...
                'Disable ordinary training-time SYNTH augmentation.');
            work=template;
            work.defs.import_finished=false;
            work.defs.analyses_locked=false;
            work.analysis={};
            work.cv=[];
            work=rmfield(work,'SYNTH');
            work=NMSimulationTools.importSyntheticMatrices(work,data,definition,true);
            work.TrainParam=configured;
        end

        function NM = importSyntheticMatrices(NM,data,definition,replacing)
            % The public DataIO matrix API accepts workspace variable names.
            % The isolated temporary variables are removed on every exit.
            token=regexprep(char(java.util.UUID.randomUUID()),'-','');
            vars=strcat('nm2syn_',token,{'_X','_ID','_F','_L'});
            cleanup=onCleanup(@()evalin('base',['clear ' strjoin(vars,' ')])); %#ok<NASGU>
            assignin('base',vars{2},data.cases);
            assignin('base',vars{4},data.label);
            for m=1:numel(data.Y)
                assignin('base',vars{1},data.Y{m});
                assignin('base',vars{3},data.featnames{m});
                targetMode='add';
                % Replacing modality 1 with a new case axis drops dependent slots.
                if replacing && m==1, targetMode='replace'; end
                spec=struct('varind',m,'sourceType','workspace', ...
                    'Y',vars{1},'cases',vars{2},'features',vars{3}, ...
                    'label',vars{4},'description',definition.modalityNames{m}, ...
                    'modeflag',definition.modeflag, ...
                    'groupnames',{data.groupnames}, ...
                    'targetMode',targetMode, ...
                    'finalizeTrainingImport',m==numel(data.Y));
                [NM,~]=NMDataIOAPITools.importTrainingMatrix(NM,spec);
            end
        end


        function [NM,parentIndex] = registerFullySynthetic(NM,plan)
            % Same parent manifest and analysis registry as existing-data SYNTH.
            assert(NM.defs.import_finished && numel(NM.Y)==numel(plan.definition.modalityNames) && ...
                strcmp(NM.modeflag,plan.definition.modeflag), ...
                'NMSimulationTools:syntheticTemplate', ...
                'The SYNTH plan task or modality count differs from the configured NM.');
            assert(~NMSynthTools.stateFromNM(NM).synthEnabled, ...
                'NMSimulationTools:doubleSynthesis','Disable ordinary SYNTH augmentation.');
            LABEL=NMAlternativeLabelTools.extractLabel(NM);
            assert(LABEL.flag~=1,'NMSimulationTools:syntheticAlternativeTarget', ...
                'Fully synthetic generation requires the native task target, not a saved alternative target.');
            combinations=NMSynthPopulationGenerator.grid(plan);
            token=regexprep(char(java.util.UUID.randomUUID()),'-','');
            parent=struct('id',['SYNTH_' token],'mode','fully_synthetic', ...
                'configuration',struct('plan',plan,'combinations',combinations), ...
                'analysisIndices',[],'status','registered','performanceSummary',[], ...
                'rootdir',fullfile(plan.outputDir,['SYNTH_' token(1:12)]), ...
                'logfile',fullfile(plan.outputDir,['SYNTH_' token(1:12)],'synth_execution.log'));
            [made,msg]=mkdir(parent.rootdir);
            assert(made,'NMSimulationTools:syntheticOutput', ...
                'Cannot create SYNTH experiment directory: %s.',msg);
            % nm2-allow: NMDataIOAPITools training imports do not create the optional SYNTH registry.
            if ~isfield(NM,'SYNTH'), NM.SYNTH=struct('analysis',{{}}); end
            template=NM; %#ok<NASGU>
            template.SYNTH.analysis={};
            save(fullfile(parent.rootdir,'synth_training_template.mat'),'template','-v7.3');
            save(fullfile(parent.rootdir,'synth_experiment.mat'),'parent','-v7.3');
            parentIndex=numel(NM.SYNTH.analysis)+1;
            NM.SYNTH.analysis{parentIndex}=parent;
        end

        function session = runFullySynthetic(NM,parentIndex,runtimeUI,commit,useParallel)
            % One reconciliation authority provides ordered child coordinates;
            % the worker operation is identical under for and parfor.
            NM=NMSimulationTools.reconstructExistingData(NM,parentIndex);
            parent=NM.SYNTH.analysis{parentIndex};
            plan=parent.configuration.plan;
            combinations=parent.configuration.combinations;
            saved=load(fullfile(parent.rootdir,'synth_training_template.mat'),'template');
            template=saved.template;
            assert(numel(template.Y)==numel(plan.definition.modalityNames) && ...
                strcmp(template.modeflag,plan.definition.modeflag), ...
                'NMSimulationTools:templateIdentity', ...
                'The saved SYNTH training template has a different task or modality count.');
            total=size(combinations,1)*plan.NReps;
            missing=true(1,total);
            for idx=parent.analysisIndices
                sim=NM.analysis{idx}.simulation;
                coordinate=(sim.combinationIndex-1)*plan.NReps+sim.repetitionIndex;
                assert(missing(coordinate),'NMSimulationTools:duplicateChild', ...
                    'Duplicate fully synthetic child coordinate.');
                missing(coordinate)=false;
            end
            pending=find(missing);
            if useParallel
                remainingPerCombination=sum(reshape(missing,plan.NReps,[]),1);
                completedCombinations=nnz(remainingPerCombination==0);
            end
            originalRng=rng;
            cleanupRng=onCleanup(@()rng(originalRng)); %#ok<NASGU>
            cleanupNM=onCleanup(@()NMSimulationTools.restoreLegacyObservedNM(NM)); %#ok<NASGU>
            if useParallel && ~isempty(pending)
                pool=gcp('nocreate');
                if isempty(pool),pool=parpool('Processes');end
                assert(isa(pool,'parallel.ProcessPool'), ...
                    'NMSimulationTools:processPoolRequired', ...
                    'Thread workers cannot execute the current MAT v7.3/legacy ML child lifecycle.');
                % Each worker task owns a combination and its remaining repetitions.
                batches=cell(1,size(combinations,1));
                for c=1:numel(batches)
                    coordinates=(c-1)*plan.NReps+(1:plan.NReps);
                    batches{c}=coordinates(missing(coordinates));
                end
                batches=batches(~cellfun(@isempty,batches));
                workerTemplate=parallel.pool.Constant(template);
                cleanupTemplate=onCleanup(@()delete(workerTemplate)); %#ok<NASGU>
                futures=parallel.FevalFuture.empty;
                nActive=min(pool.NumWorkers,numel(batches));
                for j=1:nActive
                    futures(j)=parfeval(pool,@NMSimulationTools.trainSyntheticBatch,1, ...
                        workerTemplate,parent,plan,combinations,batches{j});
                end
                nextBatch=nActive+1;
            else
                batches=num2cell(pending);
            end
            % Buffer only artifact paths until earlier coordinates can commit.
            % Completion order must not determine the NM.analysis coordinate order.
            ready=cell(1,total);
            nextPending=1;
            NMRuntimeProgressTools.start(runtimeUI,'Fully synthetic SYNTH', ...
                sprintf('%d generated populations and normal ML analyses.',total));
            if useParallel
                runtimeUI=NMRuntimeProgressTools.setStage(runtimeUI, ...
                    'Hyperparameter combinations',max(1,completedCombinations), ...
                    size(combinations,1),completedCombinations>0);
            end
            try
                for b=1:numel(batches)
                    if useParallel
                        [slot,completed]=fetchNext(futures);
                        if nextBatch<=numel(batches)
                            futures(slot)=parfeval(pool,@NMSimulationTools.trainSyntheticBatch,1, ...
                                workerTemplate,parent,plan,combinations,batches{nextBatch});
                            nextBatch=nextBatch+1;
                        end
                    else
                        completed=struct('coordinates',batches{b}, ...
                            'artifacts',{{NMSimulationTools.trainSyntheticChild( ...
                                template,parent,plan,combinations,batches{b},runtimeUI)}});
                    end
                    for j=1:numel(completed.coordinates)
                        coordinate=completed.coordinates(j);
                        assert(missing(coordinate) && isempty(ready{coordinate}), ...
                            'NMSimulationTools:duplicateChild', ...
                            'SYNTH worker returned an already resolved coordinate.');
                        ready{coordinate}=completed.artifacts{j};
                    end
                    % nm2-allow: The pending cursor bounds the ordered artifact queue before checking whether its next child is ready.
                    while nextPending<=numel(pending) && ~isempty(ready{pending(nextPending)})
                        coordinate=pending(nextPending);
                        if useParallel
                            savedChild=load(ready{coordinate},'analysis');
                            A=savedChild.analysis;
                        else
                            A=ready{coordinate};
                        end
                        actual=(A.simulation.combinationIndex-1)*plan.NReps+ ...
                            A.simulation.repetitionIndex;
                        assert(actual==coordinate,'NMSimulationTools:childIdentity', ...
                            'SYNTH worker returned the wrong child coordinate.');
                        NM.analysis{end+1}=A;
                        NM.SYNTH.analysis{parentIndex}.analysisIndices(end+1)=numel(NM.analysis);
                        NM.SYNTH.analysis{parentIndex}.status='running';
                        commit(NM);
                        ready{coordinate}=[];
                        nextPending=nextPending+1;
                        if useParallel
                            c=A.simulation.combinationIndex;
                            remainingPerCombination(c)=remainingPerCombination(c)-1;
                            if remainingPerCombination(c)==0
                                completedCombinations=completedCombinations+1;
                            end
                        else
                            runtimeUI=NMRuntimeProgressTools.setStage(runtimeUI, ...
                                sprintf('Completed child %d/%d',coordinate,total), ...
                                numel(NM.SYNTH.analysis{parentIndex}.analysisIndices),total,true);
                        end
                    end
                    if useParallel
                        runtimeUI=NMRuntimeProgressTools.setStage(runtimeUI, ...
                            'Hyperparameter combinations',max(1,completedCombinations), ...
                            size(combinations,1),completedCombinations>0);
                    end
                end
            catch ME
                if useParallel && ~isempty(pending)
                    cancel(futures);
                end
                rethrow(ME);
            end
            % The same reconciliation used by existing-data SYNTH is the
            % authority for child ordering and completed status.
            NM=NMSimulationTools.reconstructExistingData(NM,parentIndex);
            indices=NM.SYNTH.analysis{parentIndex}.analysisIndices;
            assert(numel(indices)==total,'NMSimulationTools:childCount', ...
                'Not all synthetic child coordinates have been completed.');
            NM.SYNTH.analysis{parentIndex}.performanceSummary= ...
                NMSynthPerformanceTools.buildSummary(NM,parentIndex);
            runs=repmat(struct('analysisIndex',0,'sampleSize',0, ...
                'combinationIndex',0,'repetitionIndex',0,'rootdir',''),1,total);
            for k=1:total
                idx=indices(k);
                A=NM.analysis{idx};
                runs(k)=struct('analysisIndex',idx,'sampleSize',A.simulation.sampleSize, ...
                    'combinationIndex',A.simulation.combinationIndex, ...
                    'repetitionIndex',A.simulation.repetitionIndex,'rootdir',A.rootdir);
            end
            commit(NM);
            NMRuntimeProgressTools.finish(runtimeUI,'Fully synthetic SYNTH completed.');
            session=struct('ok',true,'NM',NM,'runs',runs);
        end

        function completed = trainSyntheticBatch(workerTemplate,parent,plan,combinations,coordinates)
            % One task per combination; return child coordinates with paths.
            template=workerTemplate.Value;
            artifacts=cell(1,numel(coordinates));
            for j=1:numel(coordinates)
                A=NMSimulationTools.trainSyntheticChild( ...
                    template,parent,plan,combinations,coordinates(j), ...
                    NMRuntimeProgressTools.emptyUI());
                artifacts{j}=fullfile(A.rootdir,'synth_analysis.mat');
            end
            completed=struct('coordinates',coordinates,'artifacts',{artifacts});
        end

        function analysis = trainSyntheticChild(template,parent,plan,combinations,k,runtimeUI)
            % Worker-safe data preparation. The shared child lifecycle owns
            % analysis creation, training and atomic artifact completion.
            originalRng=rng;
            cleanupRng=onCleanup(@()rng(originalRng)); %#ok<NASGU>
            cleanupNM=onCleanup(@()NMSimulationTools.restoreLegacyObservedNM(template)); %#ok<NASGU>
            c=ceil(k/plan.NReps);
            r=mod(k-1,plan.NReps)+1;
            data=NMSynthPopulationGenerator.generate(plan,combinations(c,:),c,r);
            work=NMSimulationTools.applySyntheticPopulation(template,data,plan.definition);
            for m=1:numel(work.Y)
                if ~any(isnan(work.Y{m}(:))),continue;end
                configured=work.TrainParam.PREPROC{m};
                commands=cellfun(@(a)a.cmd,configured.ACTPARAM,'UniformOutput',false);
                assert(any(strcmp(commands,'impute')), ...
                    'NMSimulationTools:missingImputer', ...
                    'Generated modality %d contains NaNs; configure imputation in PREPROC.',m);
            end
            rng(data.seed+100000,'twister');
            work=NMCVPartitionTools.buildCV(work,0);
            childId=sprintf('SYN_%s_C%d_R%d',parent.id(7:14),c,r);
            manifest=struct('mode','fully_synthetic', ...
                'synthAnalysisId',parent.id,'combinationIndex',c, ...
                'repetitionIndex',r,'sampleSize',numel(data.label),'observedN',0, ...
                'seed',data.seed,'factors',data.factors);
            [work,idx]=NMSimulationTools.trainAndPersistChild( ...
                work,childId,sprintf('SYNTH grid %d, repetition %d',c,r), ...
                parent.rootdir,data,manifest,runtimeUI,data.seed+200000);
            analysis=work.analysis{idx};
        end

        function [work,idx] = trainAndPersistChild(work,childId,description, ...
                rootdir,synthData,manifest,runtimeUI,trainSeed)
            % Shared for both SYNTH modes: one standard NM2 analysis and
            % one atomic completion artifact per independently trained child.
            currentIds=cellfun(@(A)A.id,work.analysis,'UniformOutput',false);
            existing=find(strcmp(currentIds,childId));
            assert(numel(existing)<=1,'NMSimulationTools:duplicateChild', ...
                'The SYNTH child ID appears more than once.');
            stale=dir(fullfile(rootdir,['NM_*_' childId]));
            for d=find([stale.isdir])
                folder=fullfile(stale(d).folder,stale(d).name);
                assert(~isfile(fullfile(folder,'synth_analysis.mat')), ...
                    'NMSimulationTools:orphanIdentity', ...
                    'A committed SYNTH child was omitted from reconciliation: %s',folder);
                rmdir(folder,'s');
            end
            [work,created]=NMAnalysisManagerTools.createAnalysis(work,struct( ...
                'id',childId,'description',{{description}}, ...
                'parentdir',rootdir,'analdim',existing));
            idx=created.analysisIndex;
            folder=work.analysis{idx}.rootdir;
            save(fullfile(folder,'synth_data.mat'),'synthData','-v7.3');
            rng(trainSeed,'twister');
            [work,trained]=NMRunTools.trainAnalysis(work,idx,struct( ...
                'gridAction','all','overwrite',true,'hideGrid',true,'UI',runtimeUI));
            assert(trained.hasGDdims,'NMSimulationTools:runner', ...
                'The standard CV runner did not retain model results.');
            work.analysis{idx}.simulation=manifest;
            analysis=work.analysis{idx}; %#ok<NASGU>
            partial=fullfile(folder,'synth_analysis.partial.mat');
            save(partial,'analysis','-v7.3');
            [ok,msg]=movefile(partial,fullfile(folder,'synth_analysis.mat'),'f');
            assert(ok,'NMSimulationTools:commitArtifact', ...
                'Cannot finalize completed SYNTH child: %s',msg);
        end

        function preflight = preflightExistingData(NM, analysisIndex)
            % One label-blind shift estimate from the selected analysis's real CV2 folds.
            A = NM.analysis{analysisIndex};
            TP = A.params.TrainParam;
            assert(TP.STACKING.flag ~= 1, 'NMSimulationTools:stacking', ...
                'Existing-data simulation does not yet support analysis-dependent stacking.');
            assert(A.params.label.altlabelflag == 0 && size(NM.label,2) == 1, ...
                'NMSimulationTools:label', ...
                'The first simulation path requires one native outcome; alternative-label analyses are excluded.');
            % An already active alternative-CV2 experiment has a distinct
            % observed test contract and cannot be silently replaced.
            % nm2-allow: AltY is optional in inherited analysis templates.
            if isfield(TP,'AltY') && TP.AltY.flag==1
                error('NMSimulationTools:existingAltY', ...
                    'The selected analysis already uses alternative CV2 predictors.');
            end
            mode = NMAlternativeLabelTools.effectiveMode(NM);
            assert(strcmp(mode,A.params.label.modeflag), ...
                'NMSimulationTools:mode', 'The selected analysis and NM learning modes differ.');
            assert(numel(NM.cases) == size(NM.label,1), ...
                'NMSimulationTools:cases', 'The committed case axis and outcome rows differ.');
            cv = A.params.cv;
            assert(numel(cv.TrainInd) >= 2, 'NMSimulationTools:cv', ...
                'At least two observed CV2 folds are required to characterize shifts.');
            rows = double(cv.TrainInd{1,1}(:));
            assert(numel(rows)>=20,'NMSimulationTools:minTraining', ...
                'The original CV2 training calibration partition must contain at least 20 subjects.');
            activeModalities = TP.FUSION.M;
            directions = cell(1,numel(NM.Y));
            for m = activeModalities(:)' 
                X = NM.Y{m};
                assert(size(X,1)==size(NM.label,1),'NMSimulationTools:modalityAxis', ...
                    'Committed modality %d does not share the outcome case axis.',m);
                D = zeros(numel(cv.TrainInd),size(X,2));
                for f = 1:numel(cv.TrainInd)
                    tr = double(cv.TrainInd{f});
                    ts = double(cv.TestInd{f});
                    assert(~isempty(tr) && ~isempty(ts),'NMSimulationTools:emptyFold', ...
                        'Original CV2 partition %d is empty.',f);
                    D(f,:) = mean(X(ts,:),1,'omitnan') - mean(X(tr,:),1,'omitnan');
                end
                assert(all(isfinite(D(:))),'NMSimulationTools:nonfiniteShift', ...
                    'Modality %d contains features with unestimable CV2 predictor shifts.',m);
                directions{m}=D;
            end
            preflight = struct('sourceAnalysisIndex',analysisIndex, ...
                'calibrationRows',rows,'observedN',size(NM.label,1), ...
                'directions',{directions},'activeModalities',activeModalities, ...
                'modeflag',mode,'nDirections',numel(cv.TrainInd));
        end

        function [NM,parentIndex] = registerExistingData(NM,spec)
            % Persist one SYNTH plan before execution. The caller's observed
            % matrices and training template are not replaced.
            validateattributes(spec.sampleSizes,{'numeric'}, ...
                {'vector','integer','positive','<=',65535},mfilename,'sampleSizes');
            validateattributes(spec.shiftPermutations,{'numeric'}, ...
                {'scalar','integer','positive'},mfilename,'shiftPermutations');
            validateattributes(spec.seed,{'numeric'}, ...
                {'scalar','integer','nonnegative'},mfilename,'seed');
            validateattributes(spec.shiftBlockSize,{'numeric'}, ...
                {'scalar','integer','positive'},mfilename,'shiftBlockSize');
            % Validate the proposed plan before linked-data loading and writes.
            observedN=size(NM.label,1);
            assert(all(diff(double(spec.sampleSizes(:)))>0) && ...
                all(spec.sampleSizes>observedN),'NMSimulationTools:sampleSizes', ...
                'Sample sizes must be strictly increasing beyond the observed cohort.');
            % nm2-allow: Inherited NM workspaces may omit the optional TrainParam.SYNTH branch.
            if isfield(NM.TrainParam,'SYNTH')
                syn=NMSynthTools.completeDefaults(NM.TrainParam.SYNTH,NM);
            else
                syn=NMSynthTools.defaultSetting(NM);
            end
            assert(syn.flag==1,'NMSimulationTools:inactiveSYNTH', ...
                'Configure and enable SYNTH before registering an experiment.');
            assert(syn.method~=2,'NMSimulationTools:ADASYN', ...
                'ADASYN does not generate the exact requested sample count.');
            assert(syn.method~=1,'NMSimulationTools:kNNLearningCurve', ...
                'Cumulative SYNTH learning curves require PCA Gaussian, GMM or Gaussian copula generation.');
            assert(spec.shiftPermutations<=factorial(numel(NM.cv.TrainInd)), ...
                'NMSimulationTools:permutations', ...
                'Requested more distinct shifts than the observed CV2 directions permit.');
            sessionId=regexprep(char(java.util.UUID.randomUUID()),'-','');
            source=nk_LoadLinkedData(NM,1:numel(NM.Y));
            [source,~,storageReport]=NMSynthTools.configure(source,'synthWrite2Disk',1);
            assert(storageReport.ok,'NMSimulationTools:storage', ...
                'Persistent SYNTH storage was rejected by the configurator.');
            % The configurator's persisted write2disk=1 value is authoritative.
            syn=source.TrainParam.SYNTH;
            [source,base]=NMAnalysisManagerTools.createAnalysis(source,struct( ...
                'id',['SYN_SOURCE_' sessionId(1:8)], ...
                'description',{{'SYNTH simulation template snapshot'}}, ...
                'parentdir',tempdir));
            sourceAnalysis=source.analysis{base.analysisIndex};
            % The temporary template is never a persistent experiment resource.
            removeSource=onCleanup(@()rmdir(sourceAnalysis.rootdir,'s')); %#ok<NASGU>
            pf=NMSimulationTools.preflightExistingData(source,base.analysisIndex);
            assert(pf.observedN==observedN && ...
                pf.nDirections==numel(NM.cv.TrainInd), ...
                'NMSimulationTools:sourceIdentity', ...
                'Observed axis or CV2 partition count changed during registration.');
            observedDataHash=NMSimulationTools.observedDataFingerprint(source,pf);
            if ~exist(spec.outputDir,'dir'),mkdir(spec.outputDir);end
            experimentDir=fullfile(spec.outputDir,['SYNTH_' sessionId(1:12)]);
            [created,msg]=mkdir(experimentDir);
            assert(created,'NMSimulationTools:experimentDir', ...
                'Cannot create SYNTH experiment directory: %s',msg);
            % nm2-allow: First-use creation of the optional NM2 SYNTH domain.
            if ~isfield(NM,'SYNTH')
                NM.SYNTH=struct('analysis',{{}});
            end
            parentIndex=numel(NM.SYNTH.analysis)+1;
            parent=struct('id',['SYNTH_' sessionId], 'mode','existing_data', ...
                'sourceAnalysisIndex',0,'observedN',pf.observedN, ...
                'configuration',struct('synth',syn,'sampleSizes',spec.sampleSizes, ...
                    'shiftPermutations',spec.shiftPermutations, ...
                    'shiftBlockSize',spec.shiftBlockSize,'seed',spec.seed, ...
                    'activeModalities',pf.activeModalities, ...
                    'observedDataHash',observedDataHash), ...
                'analysisIndices',[],'status','registered','performanceSummary',[], ...
                'rootdir',experimentDir, ...
                'logfile',fullfile(experimentDir,'synth_execution.log'));
            NM.SYNTH.analysis{parentIndex}=parent;
            % The immutable template snapshot must also survive loss of the
            % MATLAB session. The parent manifest remains the plan authority.
            save(fullfile(experimentDir,'synth_source_analysis.mat'), ...
                'sourceAnalysis','-v7.3');
            % The analysis-manager snapshot is an execution template, not a
            % persisted NM analysis or a separate Results Viewer resource.
            % Parent manifest describes the registered plan; completed child
            % directories, not a checkpoint counter, determine resume state.
            save(fullfile(experimentDir,'synth_experiment.mat'),'parent','-v7.3');
            NMSimulationTools.appendLog(parent.logfile,sprintf( ...
                'Registered SYNTH: sampleSizes=%s, permutations=%d, seed=%d', ...
                mat2str(spec.sampleSizes),spec.shiftPermutations,spec.seed));
        end

        function NM = reconstructExperiments(NM)
            % One persisted-artifact reconciliation for catalogue, refresh
            % and deletion. Older observed NM workspaces have no SYNTH domain.
            % nm2-allow: Pre-SYNTH NM producers did not create NM.SYNTH.
            if ~isfield(NM,'SYNTH'),return;end
            for x=1:numel(NM.SYNTH.analysis)
                % A moved/unmounted directory is an external-resource state,
                % not an invalid SYNTH analysis. The catalogue exposes it.
                NM=NMSimulationTools.reconstructExistingData(NM,x);
            end
        end

        function NM = reconstructExistingData(NM,parentIndex,relinkRequested,runtimeUI)
            % In-memory child analyses are authoritative for normal reconstruction.
            % Disk is consulted only for absent child IDs or explicit root relinking.
            % nm2-allow: reconstructExperiments and runExistingData omit the third argument; relinkExperimentRoot supplies true.
            if nargin<3, relinkRequested=false; end
            % nm2-allow: reconstructExperiments and runExistingData omit the fourth argument; Coordinator supplies progress.
            if nargin<4, runtimeUI=NMRuntimeProgressTools.emptyUI();end
            parent=NM.SYNTH.analysis{parentIndex};
            cfg=parent.configuration;
            prefix=parent.id(7:14);
            indices=[];
            analysisIds=cellfun(@(A)A.id,NM.analysis,'UniformOutput',false);
            fullMode=strcmp(parent.mode,'fully_synthetic');
            if fullMode
                coordinates=1:size(cfg.combinations,1);
                repetitions=cfg.plan.NReps;
            else
                coordinates=cfg.sampleSizes;
                repetitions=cfg.shiftPermutations;
            end
            % Enumerate child directories only when a child is missing or
            % Relink explicitly requests a new physical root.
            folders=struct('name',{},'folder',{});
            directoriesScanned=false;
            taskTotal=numel(coordinates)*repetitions;
            NMRuntimeProgressTools.start(runtimeUI,'SYNTH reconstruction', ...
                sprintf('Resolving %d child analyses from NM.analysis first.',taskTotal));
            resolvedCount=0;
            for sizeIndex=1:numel(coordinates)
                n=coordinates(sizeIndex);
                for permutation=1:repetitions
                    if fullMode
                        childId=sprintf('SYN_%s_C%d_R%d',prefix,n,permutation);
                    else
                        childId=sprintf('SYN_%s_N%d_P%d',prefix,n,permutation);
                    end
                    matches=find(strcmp(analysisIds,childId));
                    resolvedCount=resolvedCount+1;
                    origin='NM.analysis';
                    if isempty(matches)||relinkRequested,origin='child directory';end
                    progressLabel=sprintf('Child %s: %s',childId,origin);
                    % The progress channel is file-backed; cap writes on
                    % large experiments while still showing both lookup sources.
                    updateProgress=runtimeUI.enabled && (taskTotal<=20 || ...
                        resolvedCount==1 || resolvedCount==taskTotal || ...
                        mod(resolvedCount,ceil(taskTotal/20))==0);
                    if updateProgress
                        runtimeUI=NMRuntimeProgressTools.setStage( ...
                            runtimeUI,progressLabel,resolvedCount,taskTotal,false);
                    end
                    assert(numel(matches)<=1,'NMSimulationTools:duplicateChild', ...
                        'SYNTH analysis ID %s appears more than once in NM.',childId);
                    if ~isempty(matches) && ~relinkRequested
                        A=NM.analysis{matches};
                        if fullMode
                            coordinateOK=A.simulation.combinationIndex==n && ...
                                A.simulation.repetitionIndex==permutation;
                        else
                            coordinateOK=A.simulation.sampleSize==n && ...
                                A.simulation.permutation==permutation;
                        end
                        assert(strcmp(A.simulation.synthAnalysisId,parent.id) && coordinateOK, ...
                            'NMSimulationTools:childIdentity', ...
                            'Resident SYNTH child has inconsistent experiment coordinates.');
                        indices(end+1)=matches; %#ok<AGROW>
                        if updateProgress
                            runtimeUI=NMRuntimeProgressTools.setStage( ...
                                runtimeUI,progressLabel,resolvedCount,taskTotal,true);
                        end
                        continue;
                    end
                    if ~directoriesScanned
                        directoriesScanned=true;
                        if ~isfolder(parent.rootdir)
                            % Offline experiment: retain resident children.
                            % Root validation belongs to the explicit Relink operation.
                            continue;
                        end
                        folders=dir(fullfile(parent.rootdir,'NM_*'));
                        folders=folders([folders.isdir]);
                    end
                    hit=find(endsWith({folders.name},['_' childId]));
                    completed=[];folder='';
                    for d=hit
                        candidate=fullfile(folders(d).folder,folders(d).name);
                        result=fullfile(candidate,'synth_analysis.mat');
                        if ~isfile(result),continue;end
                        assert(isfile(fullfile(candidate,'synth_data.mat')), ...
                            'NMSimulationTools:missingData', ...
                            'Completed SYNTH child has no corresponding data artifact: %s',candidate);
                        assert(isempty(completed),'NMSimulationTools:duplicateChild', ...
                            'Multiple completed directories have ID %s.',childId);
                        completed=load(result,'analysis');folder=candidate;
                    end
                    if isempty(completed)
                        assert(isempty(matches),'NMSimulationTools:relinkMissing', ...
                            'Cannot locate completed child %s in the selected experiment root.',childId);
                        continue;
                    end
                    A=completed.analysis;
                    if fullMode
                        coordinateOK=A.simulation.combinationIndex==n && ...
                            A.simulation.repetitionIndex==permutation;
                    else
                        coordinateOK=A.simulation.sampleSize==n && ...
                            A.simulation.permutation==permutation;
                    end
                    assert(strcmp(A.id,childId) && ...
                        strcmp(A.simulation.synthAnalysisId,parent.id) && coordinateOK, ...
                        'NMSimulationTools:childIdentity', ...
                        'Completed SYNTH child has inconsistent experiment identity.');
                    if isempty(matches)
                        idx=numel(analysisIds)+1;
                        analysisIds{idx}=A.id;
                        NM.analysis{idx}=A;
                    else
                        idx=matches;
                        % Explicit Relink changes only the physical root;
                        % never overwrite scientific results held in-session.
                    end
                    if ~strcmp(NM.analysis{idx}.rootdir,folder)
                        [NM,~]=NMAnalysisManagerTools.relinkAnalysisRoot(NM,idx, ...
                            struct('newRootDir',folder,'selectionKind','root'));
                    end
                    indices(end+1)=idx; %#ok<AGROW>
                    if updateProgress
                        runtimeUI=NMRuntimeProgressTools.setStage( ...
                            runtimeUI,progressLabel,resolvedCount,taskTotal,true);
                    end
                end
            end
            NM.SYNTH.analysis{parentIndex}.analysisIndices=indices;
            total=numel(coordinates)*repetitions;
            if numel(indices)==total
                NM.SYNTH.analysis{parentIndex}.status='completed';
            elseif isempty(indices) && strcmp(parent.status,'registered')
                NM.SYNTH.analysis{parentIndex}.status='registered';
            else
                NM.SYNTH.analysis{parentIndex}.status='unfinished';
            end
            NMRuntimeProgressTools.finish(runtimeUI, ...
                sprintf('Resolved %d/%d completed SYNTH children.',numel(indices),taskTotal), ...
                'SYNTH reconstruction');
        end

        function NM = relinkExperimentRoot(NM,parentIndex,newRootDir)
            % A selected directory is an exact relocated SYNTH experiment root.
            % The stored parent ID, not the directory name, establishes identity.
            assert(isfolder(newRootDir),'NMSimulationTools:relinkDirectory', ...
                'Selected SYNTH experiment directory does not exist: %s',newRootDir);
            manifestFile=fullfile(newRootDir,'synth_experiment.mat');
            assert(isfile(manifestFile),'NMSimulationTools:relinkManifest', ...
                'Selected directory has no SYNTH experiment manifest: %s',newRootDir);
            saved=load(manifestFile,'parent');
            assert(strcmp(saved.parent.id,NM.SYNTH.analysis{parentIndex}.id), ...
                'NMSimulationTools:relinkIdentity', ...
                'Selected directory belongs to a different SYNTH experiment.');
            NM.SYNTH.analysis{parentIndex}.rootdir=newRootDir;
            NM.SYNTH.analysis{parentIndex}.logfile=fullfile(newRootDir,'synth_execution.log');
            NM=NMSimulationTools.reconstructExistingData(NM,parentIndex,true);
            parent=NM.SYNTH.analysis{parentIndex}; %#ok<NASGU>
            for idx=parent.analysisIndices
                analysis=NM.analysis{idx}; %#ok<NASGU>
                save(fullfile(analysis.rootdir,'synth_analysis.mat'), ...
                    'analysis','-v7.3');
            end
            save(manifestFile,'parent','-v7.3');
        end

        function [NM,temporaryIndex] = sourceTemplate(NM,parentIndex)
            % Restore a snapshot only within a local execution/configuration NM.
            parent=NM.SYNTH.analysis{parentIndex};
            saved=load(fullfile(parent.rootdir,'synth_source_analysis.mat'), ...
                'sourceAnalysis');
            assert(strcmp(saved.sourceAnalysis.id,['SYN_SOURCE_' parent.id(7:14)]), ...
                'NMSimulationTools:sourceIdentity', ...
                'Persisted SYNTH source belongs to a different experiment.');
            temporaryIndex=numel(NM.analysis)+1;
            NM.analysis{temporaryIndex}=saved.sourceAnalysis;
            [NM,~]=NMAnalysisManagerTools.restoreTemplateFromAnalysis(NM,temporaryIndex);
        end

        function session = runExistingData(NM,parentIndex,runtimeUI,commit)
            % Existing child analyses own CV, configuration and results. Only
            % genuinely missing coordinates require cohort materialisation.
            NM=NMSimulationTools.reconstructExistingData(NM,parentIndex);
            parent=NM.SYNTH.analysis{parentIndex};
            assert(size(NM.label,1)==parent.observedN, ...
                'NMSimulationTools:observedAxisChanged', ...
                'SYNTH requires %d observed subjects; loaded NM contains %d.', ...
                parent.observedN,size(NM.label,1));
            restoreObservedGlobal=onCleanup(@() ...
                NMSimulationTools.restoreLegacyObservedNM(NM)); %#ok<NASGU>
            spec=parent.configuration;
            completedIndices=parent.analysisIndices;
            nPlanned=numel(spec.sampleSizes)*spec.shiftPermutations;
            runs=repmat(struct('analysisIndex',0,'sampleSize',0,'permutation',0, ...
                'shiftOrder',[],'rootdir',''),nPlanned,1);
            if numel(completedIndices)==nPlanned
                % Explicit Resume refreshes derived metrics from completed
                % child results without re-running training or preprocessing.
                NM.SYNTH.analysis{parentIndex}.performanceSummary= ...
                    NMSynthPerformanceTools.buildSummary(NM,parentIndex);
                NM.SYNTH.analysis{parentIndex}.status='completed';
                for j=1:nPlanned
                    idx=completedIndices(j);
                    A=NM.analysis{idx};
                    runs(j)=struct('analysisIndex',idx, ...
                        'sampleSize',A.simulation.sampleSize, ...
                        'permutation',A.simulation.permutation, ...
                        'shiftOrder',A.simulation.shiftOrder, ...
                        'rootdir',A.rootdir);
                end
                commit(NM);
                NMRuntimeProgressTools.finish(runtimeUI, ...
                    'All SYNTH analyses already completed.');
                session=struct('ok',true,'NM',NM,'preflight',[], ...
                    'runs',runs,'originalAnalysisIndex',0);
                return;
            end

            % Completed historical experiments remain inspectable, but an
            % incomplete kNN experiment must not generate further cohorts.
            assert(parent.configuration.synth.method~=1,'NMSimulationTools:kNNLearningCurve', ...
                'Incomplete historical kNN SYNTH experiments cannot generate additional cohorts.');
            NM.SYNTH.analysis{parentIndex}.status='running';
            NM.SYNTH.analysis{parentIndex}.performanceSummary=[];
            sessionId=parent.id(7:end);
            experimentDir=parent.rootdir;
            logFile=parent.logfile;
            % Missing children still require real observed predictors for
            % training. Load them only once for this incomplete execution.
            NMRuntimeProgressTools.start(runtimeUI,'SYNTH simulation', ...
                sprintf('Loading observed data for %d missing children.', ...
                nPlanned-numel(completedIndices)));
            source=nk_LoadLinkedData(NM,1:numel(NM.Y));
            [source,temporaryIndex]=NMSimulationTools.sourceTemplate(source,parentIndex);
            pf=NMSimulationTools.preflightExistingData(source,temporaryIndex);
            % 5.0088d plans have no signed observed-input identity and cannot
            % be safely resumed after their source data may have changed.
            % nm2-allow: Older SYNTH experiment manifests were written without observedDataHash.
            assert(isfield(spec,'observedDataHash'), ...
                'NMSimulationTools:missingObservedIdentity', ...
                'This SYNTH plan predates observed-input integrity protection; register a new experiment.');
            assert(strcmp(NMSimulationTools.observedDataFingerprint(source,pf), ...
                spec.observedDataHash), 'NMSimulationTools:observedDataChanged', ...
                ['Observed predictors, outcomes, case IDs, covariates, feature identity, ' ...
                'or source CV2 partitions differ from registration; refusing SYNTH Resume.']);
            source.analysis(temporaryIndex)=[];
            syn=spec.synth;
            commit(NM);
            work=source;
            [work,~,synthReport]=NMSynthTools.configure(work,'synthEnabled',false);
            assert(synthReport.ok,'NMSimulationTools:template', ...
                'The SYNTH configurator rejected disabling repeated augmentation.');
            [work,~,savReport]=NMSAVTools.configure(work,'savSaveModel',false);
            assert(savReport.ok,'NMSimulationTools:saving', ...
                'The saving configurator rejected disabling model export.');
            work.TrainParam.AltY.flag=1;
            oldRng=rng;
            rngCleanup=onCleanup(@()rng(oldRng)); %#ok<NASGU>
            rng(spec.seed,'twister');
            generationRng=rng;
            assert(spec.shiftPermutations<=factorial(pf.nDirections), ...
                'NMSimulationTools:permutations', ...
                'The requested number of shift assignments exceeds the factorial limit.');
            rng(spec.seed+1,'twister');
            orders=zeros(spec.shiftPermutations,pf.nDirections);
            for r=1:spec.shiftPermutations
                order=randperm(pf.nDirections);
                while any(all(orders(1:r-1,:)==order,2))
                    order=randperm(pf.nDirections);
                end
                orders(r,:)=order;
            end
            selected=pf.activeModalities;
            widths=cellfun(@(X)size(X,2),source.Y(selected));
            calibrationBlocks=cellfun(@(X)X(pf.calibrationRows,:), ...
                source.Y(selected),'UniformOutput',false);
            calibrationX=[calibrationBlocks{:}];
            covs=[];
            % nm2-allow: Covariates are optional in inherited NM workspaces.
            if isfield(source,'covars') && ~isempty(source.covars)
                covs=source.covars(pf.calibrationRows,:);
            end
            nM=numel(work.Y);
            n0=pf.observedN;
            synthAnalysisId=parent.id;
            work.SYNTH.analysis{parentIndex}.analysisIndices=[];
            runId=0;
            for s=1:numel(spec.sampleSizes)
                totalN=double(spec.sampleSizes(s));
                nAdd=totalN-n0;
                siblings=completedIndices(arrayfun(@(idx) ...
                    work.analysis{idx}.simulation.sampleSize==totalN,completedIndices));
                assert(numel(siblings)<=spec.shiftPermutations, ...
                    'NMSimulationTools:duplicateChild', ...
                    'Too many completed children at N=%d.',totalN);
                cohortFile=sprintf('synth_cohort_N%d.mat',totalN);
                cohortPath=fullfile(experimentDir,cohortFile);
                legacyFormat=false;
                cohortHash='';
                if ~isempty(siblings)
                    % A completed sibling owns this size's training cohort
                    % and extended nested-CV partition. Read it only once.
                    A=work.analysis{siblings(1)};
                    [data,stored]=NMSimulationTools.loadSynthData(A);
                    % nm2-allow: Completed v1 children predate cohortFile.
                    legacyFormat=~isfield(stored,'cohortFile');
                    offset=n0-pf.observedN;
                    chunks=cellfun(@(X)X(offset+1:end,:), ...
                        data.Y(selected),'UniformOutput',false);
                    joint=[chunks{:}];
                    labels=data.label(offset+1:end,:);
                    covars=[];
                    if ~isempty(covs),covars=data.covars(offset+1:end,:);end
                    if legacyFormat
                        % v1 has no RNG checkpoint or signed cohort. Replay
                        % its historical draw for integrity and continuity;
                        % v2 never needs a fit for an existing cohort.
                        syn.numSyntheticObservations=nAdd;
                        rng(generationRng);
                        [verifiedX,verifiedL,verifiedC,verified] = ...
                            nk_SynthGenerate(calibrationX, ...
                            source.label(pf.calibrationRows,:),covs,syn,pf.modeflag,[]);
                        generationRng=rng;
                        assert(verified && isequaln(verifiedX,joint) && ...
                            isequaln(verifiedL,labels) && isequaln(verifiedC,covars), ...
                            'NMSimulationTools:resumeCohortMismatch', ...
                            'Legacy cohort N=%d differs from its original RNG realization.',totalN);
                        clear verifiedX verifiedL verifiedC
                    else
                        assert(strcmp(stored.cohortFile,cohortFile), ...
                            'NMSimulationTools:resumeCohortMismatch', ...
                            'Persisted cohort reference is not canonical for N=%d.',totalN);
                        generationRng=data.generationRng;
                        cohortHash=stored.cohortHash;
                    end
                    % A second completed sibling must use the same observed
                    % synthetic population, even if its AltY differs.
                    for siblingIndex=siblings(2:end)
                        A=work.analysis{siblingIndex};
                        if legacyFormat
                            otherData=NMSimulationTools.loadSynthData(A);
                            assert(isequaln(otherData.Y,data.Y) && ...
                                isequaln(otherData.label,data.label) && ...
                                isequaln(otherData.cases,data.cases), ...
                                'NMSimulationTools:resumeCohortMismatch', ...
                                'Completed v1 siblings disagree at N=%d.',totalN);
                            if ~isempty(covs)
                                assert(isequaln(otherData.covars,data.covars), ...
                                    'NMSimulationTools:resumeCohortMismatch', ...
                                    'Completed v1 siblings disagree in their covariates.');
                            end
                        else
                            other=load(fullfile(A.rootdir,'synth_data.mat'),'synthData');
                            assert(strcmp(other.synthData.cohortFile,cohortFile) && ...
                                strcmp(other.synthData.cohortHash,cohortHash) && ...
                                isequal(other.synthData.activeModalities,selected), ...
                                'NMSimulationTools:resumeCohortMismatch', ...
                                'Completed v2 siblings disagree at N=%d.',totalN);
                        end
                    end
                else
                    syn.numSyntheticObservations=nAdd;
                    rng(generationRng);
                    [joint,labels,covars,activated]=nk_SynthGenerate( ...
                        calibrationX,source.label(pf.calibrationRows,:), ...
                        covs,syn,pf.modeflag,[]);
                    generationRng=rng;
                    assert(activated,'NMSimulationTools:generatorContract', ...
                        'SYNTH generation was not activated.');
                end
                assert(size(joint,1)==nAdd, ...
                    'NMSimulationTools:generatorContract', ...
                    'Generated SYNTH predictors have an incorrect subject axis.');
                assert(size(joint,2)==sum(widths), ...
                    'NMSimulationTools:generatorContract', ...
                    'Generated SYNTH predictors have an incorrect feature axis.');
                assert(size(labels,1)==nAdd, ...
                    'NMSimulationTools:generatorContract', ...
                    'Generated SYNTH outcomes have an incorrect subject axis.');
                if ~isempty(covars)
                    assert(size(covars,1)==nAdd, ...
                        'NMSimulationTools:generatorContract', ...
                        'Generated SYNTH covariates have an incorrect subject axis.');
                end
                if isempty(siblings) && syn.method==4
                    % sklearn GMM.sample emits component-grouped observations.
                    % De-order only new GMM cohorts, keeping each entire
                    % synthetic (predictor,label,covariate) record intact.
                    rng(generationRng);
                    mixed=randperm(nAdd);
                    joint=joint(mixed,:);
                    labels=labels(mixed,:);
                    if ~isempty(covars),covars=covars(mixed,:);end
                    generationRng=rng;
                end
                for m=1:nM
                    work.Y{m}=[work.Y{m};nan(nAdd,size(work.Y{m},2))];
                end
                col=0;
                for k=1:numel(selected)
                    m=selected(k);
                    work.Y{m}(end-nAdd+1:end,:)=joint(:,col+(1:widths(k)));
                    col=col+widths(k);
                end
                clear joint
                work.label=[work.label;labels];
                if ~isempty(covs),work.covars=[work.covars;covars];end
                newCases=arrayfun(@(j)sprintf('SYN_%s_%06d',sessionId(1:8),j), ...
                    (n0+1:totalN)','UniformOutput',false);
                work.cases=[work.cases(:);newCases];
                if ~isempty(siblings)
                    % A cumulative cohort must agree with its previously
                    % committed prefix at every earlier sample size.
                    assert(isequaln(data.label,work.label(pf.observedN+1:end,:)) && ...
                        isequaln(data.cases,work.cases(pf.observedN+1:end)), ...
                        'NMSimulationTools:resumeCohortMismatch', ...
                        'Cumulative SYNTH labels/cases disagree at N=%d.',totalN);
                    for m=1:nM
                        assert(isequaln(data.Y{m},work.Y{m}(pf.observedN+1:end,:)), ...
                            'NMSimulationTools:resumeCohortMismatch', ...
                            'Cumulative modality %d differs at N=%d.',m,totalN);
                    end
                    if ~isempty(covs)
                        assert(isequaln(data.covars,work.covars(pf.observedN+1:end,:)), ...
                            'NMSimulationTools:resumeCohortMismatch', ...
                            'Cumulative covariates differ at N=%d.',totalN);
                    end
                end
                work=NMSimulationTools.updateSubjectCounts(work,pf.modeflag);
                if ~isempty(siblings)
                    work.cv=work.analysis{siblings(1)}.params.cv;
                else
                    rng(spec.seed+200000+s,'twister');
                    work=NMCVPartitionTools.extendSubjects(work,n0);
                end
                n0=totalN;
                if isempty(siblings)
                    % Version 2: one immutable cumulative population per
                    % sample size. CV is NOT stored here: params.cv owns it.
                    cohort=struct('synthAnalysisId',synthAnalysisId, ...
                        'observedN',pf.observedN,'sampleSize',totalN, ...
                        'generationRng',generationRng, ...
                        'activeModalities',selected, ...
                        'featureWidths',cellfun(@(X)size(X,2),work.Y), ...
                        'Y',{cellfun(@(X)X(pf.observedN+1:end,:), ...
                            work.Y(selected),'UniformOutput',false)}, ...
                        'label',work.label(pf.observedN+1:end,:), ...
                        'cases',{work.cases(pf.observedN+1:end)});
                    if ~isempty(covs)
                        cohort.covars=work.covars(pf.observedN+1:end,:);
                    end
                    stagingFile=[cohortPath '.partial'];
                    save(stagingFile,'cohort','-v7.3');
                    [moved,msg]=movefile(stagingFile,cohortPath,'f');
                    assert(moved,'NMSimulationTools:cohortCommit', ...
                        'Cannot finalize the per-size SYNTH cohort: %s',msg);
                    cohortHash=NMSimulationTools.sha256File(cohortPath);
                end
                for r=1:spec.shiftPermutations
                    stageIndex=(s-1)*spec.shiftPermutations+r;
                    stageText=sprintf('CV training: N=%d, permutation %d/%d', ...
                        totalN,r,spec.shiftPermutations);
                    runtimeUI=NMRuntimeProgressTools.setStage(runtimeUI, ...
                        stageText,stageIndex,nPlanned,false);
                    NMSimulationTools.appendLog(logFile,['Starting ' stageText]);
                    coordinate=arrayfun(@(idx) ...
                        work.analysis{idx}.simulation.sampleSize==totalN && ...
                        work.analysis{idx}.simulation.permutation==r,completedIndices);
                    if any(coordinate)
                        idx=completedIndices(coordinate);
                        assert(isscalar(idx) && ...
                            isequal(work.analysis{idx}.simulation.shiftOrder,orders(r,:)), ...
                            'NMSimulationTools:shiftOrder', ...
                            'Persisted SYNTH child has a different shift assignment.');
                        work.SYNTH.analysis{parentIndex}.analysisIndices(end+1)=idx;
                        runId=runId+1;
                        runs(runId)=struct('analysisIndex',idx, ...
                            'sampleSize',totalN,'permutation',r, ...
                            'shiftOrder',orders(r,:), ...
                            'rootdir',work.analysis{idx}.rootdir);
                        runtimeUI=NMRuntimeProgressTools.setStage(runtimeUI, ...
                            stageText,stageIndex,nPlanned,true);
                        continue;
                    end
                    work.altY=work.Y;
                    for m=selected(:)'
                        count=size(work.Y{m},1)-pf.observedN;
                        block=mod(floor(((0:count-1)')/spec.shiftBlockSize), ...
                            numel(orders(r,:)))+1;
                        work.altY{m}(pf.observedN+1:end,:)= ...
                            work.Y{m}(pf.observedN+1:end,:) + ...
                            pf.directions{m}(orders(r,block),:);
                    end
                    childId=sprintf('SYN_%s_N%d_P%d',synthAnalysisId(7:14),totalN,r);
                    manifest=struct('synthAnalysisId',synthAnalysisId, ...
                        'observedN',pf.observedN,'sampleSize',totalN, ...
                        'permutation',r,'shiftBlockSize',spec.shiftBlockSize, ...
                        'shiftOrder',orders(r,:));
                    if legacyFormat
                        % Complete v1 siblings keep their original child
                        % representation. A partial plan is not migrated.
                        synthData=struct('Y',{cellfun(@(X)X(pf.observedN+1:end,:), ...
                            work.Y,'UniformOutput',false)}, ...
                            'altY',{cellfun(@(X)X(pf.observedN+1:end,:), ...
                            work.altY,'UniformOutput',false)}, ...
                            'label',work.label(pf.observedN+1:end,:), ...
                            'cases',{work.cases(pf.observedN+1:end)});
                        if ~isempty(covs)
                            synthData.covars=work.covars(pf.observedN+1:end,:);
                        end
                    else
                        shifted=cell(1,numel(selected));
                        for k=1:numel(selected)
                            shifted{k}=work.altY{selected(k)}(pf.observedN+1:end,:);
                        end
                        synthData=struct('version',2,'cohortFile',cohortFile, ...
                            'cohortHash',cohortHash, ...
                            'activeModalities',selected,'altY',{shifted});
                    end
                    try
                        [work,idx]=NMSimulationTools.trainAndPersistChild( ...
                            work,childId,sprintf('SYNTH N=%d / shift permutation %d',totalN,r), ...
                            experimentDir,synthData,manifest,runtimeUI,spec.seed+100000+s);
                    catch ME
                        NMSimulationTools.appendLog(logFile, ...
                            getReport(ME,'extended','hyperlinks','off'));
                        rethrow(ME);
                    end
                    NMSimulationTools.restoreLegacyObservedNM(NM);
                    clear synthData
                    work.SYNTH.analysis{parentIndex}.analysisIndices(end+1)=idx;
                    runId=runId+1;
                    runs(runId)=struct('analysisIndex',idx, ...
                        'sampleSize',totalN,'permutation',r, ...
                        'shiftOrder',orders(r,:), ...
                        'rootdir',work.analysis{idx}.rootdir);
                    NMSimulationTools.appendLog(logFile,sprintf( ...
                        'Completed analysis %d in %s',idx,work.analysis{idx}.rootdir));
                    committed=NM;
                    committed.analysis=work.analysis;
                    committed.SYNTH=work.SYNTH;
                    commit(committed);
                    runtimeUI=NMRuntimeProgressTools.setStage(runtimeUI, ...
                        stageText,stageIndex,nPlanned,true);
                end
            end
            work.SYNTH.analysis{parentIndex}.status='completed';
            committed=NM;
            committed.analysis=work.analysis;
            committed.SYNTH=work.SYNTH;
            committed.SYNTH.analysis{parentIndex}.performanceSummary= ...
                NMSynthPerformanceTools.buildSummary(committed,parentIndex);
            NMSimulationTools.appendLog(logFile,'Completed SYNTH experiment.');
            commit(committed);
            NMRuntimeProgressTools.finish(runtimeUI,'SYNTH simulation completed.');
            clear restoreObservedGlobal
            NMSimulationTools.restoreLegacyObservedNM(committed);
            session=struct('ok',true,'NM',committed,'preflight',pf, ...
                'runs',runs,'originalAnalysisIndex',0);
        end

        function work = restoreRun(NM,analysisIndex)
            % Explicit materialisation of a completed child's training data.
            manifest=NM.analysis{analysisIndex}.simulation;
            % Fully synthetic children restore from their own DataIO population.
            % nm2-allow: NMSimulationTools.runExistingData persists child simulation records without a mode field.
            if isfield(manifest,'mode') && strcmp(manifest.mode,'fully_synthetic')
                parents=cellfun(@(p)strcmp(p.id,manifest.synthAnalysisId),NM.SYNTH.analysis);
                assert(nnz(parents)==1,'NMSimulationTools:parentIdentity', ...
                    'Fully synthetic child does not identify exactly one parent.');
                parent=NM.SYNTH.analysis{find(parents)};
                saved=load(fullfile(parent.rootdir,'synth_training_template.mat'),'template');
                data=NMSimulationTools.loadSynthData(NM.analysis{analysisIndex});
                work=NMSimulationTools.applySyntheticPopulation(saved.template,data);
                work.analysis={NM.analysis{analysisIndex}};
                [work,~]=NMAnalysisManagerTools.restoreTemplateFromAnalysis(work,1);
                work.cv=work.analysis{1}.params.cv;
                return;
            end
            data=NMSimulationTools.loadSynthData(NM.analysis{analysisIndex});
            work=nk_LoadLinkedData(NM,1:numel(NM.Y));
            parents=cellfun(@(A)strcmp(A.id,manifest.synthAnalysisId), ...
                work.SYNTH.analysis);
            assert(nnz(parents)==1,'NMSimulationTools:parentIdentity', ...
                'Restored SYNTH child does not identify exactly one parent experiment.');
            parentIndex=find(parents);
            [verified,sourceIndex]=NMSimulationTools.sourceTemplate(work,parentIndex);
            pf=NMSimulationTools.preflightExistingData(verified,sourceIndex);
            cfg=work.SYNTH.analysis{parentIndex}.configuration;
            % nm2-allow: Older SYNTH experiment manifests were written without observedDataHash.
            assert(isfield(cfg,'observedDataHash'), ...
                'NMSimulationTools:missingObservedIdentity', ...
                'Restoring an unsigned legacy SYNTH child requires re-registration.');
            assert(strcmp(NMSimulationTools.observedDataFingerprint(verified,pf), ...
                cfg.observedDataHash),'NMSimulationTools:observedDataChanged', ...
                'Observed inputs differ from registration; refusing SYNTH child restoration.');
            for m=1:numel(work.Y)
                work.Y{m}=[work.Y{m};data.Y{m}];
            end
            work.label=[work.label;data.label];
            work.cases=[work.cases(:);data.cases(:)];
            % nm2-allow: Covariates are optional in inherited NM workspaces.
            if isfield(data,'covars')
                work.covars=[work.covars;data.covars];
            end
            assert(size(work.label,1)==manifest.sampleSize, ...
                'NMSimulationTools:reconstruction', ...
                'Restored synthetic cohort has the wrong sample axis.');
            work=NMSimulationTools.updateSubjectCounts(work, ...
                NMAlternativeLabelTools.effectiveMode(NM));
            [work,~]=NMAnalysisManagerTools.restoreTemplateFromAnalysis(work,analysisIndex);
            work.altY=cell(1,numel(work.Y));
            for m=1:numel(work.Y)
                work.altY{m}=[work.Y{m}(1:manifest.observedN,:);data.altY{m}];
            end
        end

        function [data,stored] = loadSynthData(analysis)
            % Persisted scientific data reader: self-contained v1 child files
            % and shared v2 cohorts expose the same data schema.
            saved=load(fullfile(analysis.rootdir,'synth_data.mat'),'synthData');
            stored=saved.synthData;
            data=stored;
            % nm2-allow: Historical v1 artifacts have no cohortFile field.
            if isfield(data,'cohortFile')
                path=fullfile(fileparts(analysis.rootdir),data.cohortFile);
                assert(strcmp(data.cohortHash,NMSimulationTools.sha256File(path)), ...
                    'NMSimulationTools:resumeCohortMismatch', ...
                    'The persisted SYNTH cohort has changed: %s',path);
                savedCohort=load(path,'cohort');
                C=savedCohort.cohort;
                assert(strcmp(C.synthAnalysisId,analysis.simulation.synthAnalysisId) && ...
                    C.sampleSize==analysis.simulation.sampleSize && ...
                    C.observedN==analysis.simulation.observedN, ...
                    'NMSimulationTools:childIdentity', ...
                    'SYNTH cohort identity does not match its child analysis.');
                shifted=data.altY;
                selected=data.activeModalities;
                assert(isequal(selected,C.activeModalities), ...
                    'NMSimulationTools:childIdentity', ...
                    'Shifted modalities differ from the fitted population.');
                data=C;
                generated=C.Y;
                nSynthetic=C.sampleSize-C.observedN;
                data.Y=cell(1,numel(C.featureWidths));
                for m=1:numel(data.Y)
                    data.Y{m}=nan(nSynthetic,C.featureWidths(m));
                end
                for k=1:numel(selected)
                    data.Y{selected(k)}=generated{k};
                end
                data.altY=data.Y;
                for k=1:numel(selected)
                    data.altY{selected(k)}=shifted{k};
                end
            end
        end

        function hash = observedDataFingerprint(source,pf)
            % Persistence identity for the observed materialization feeding
            % this SYNTH experiment. This is not the DataIO cache identity.
            % Stream bounded numeric chunks so imaging predictors are not
            % duplicated or converted to one enormous JSON/byte array.
            md=java.security.MessageDigest.getInstance('SHA-256');
            NMSimulationTools.updateScientificDigest(md,'identityVersion',uint8(1));
            NMSimulationTools.updateScientificDigest(md,'activeModalities',pf.activeModalities);
            NMSimulationTools.updateScientificDigest(md,'calibrationRows',pf.calibrationRows);
            NMSimulationTools.updateScientificDigest(md,'observedLabels',source.label);
            NMSimulationTools.updateScientificDigest(md,'observedCaseIDs',source.cases(:));
            NMSimulationTools.updateScientificDigest(md,'featureNames',source.featnames(pf.activeModalities));
            % nm2-allow: Inherited NM workspaces may omit covariates entirely.
            if isfield(source,'covars')
                NMSimulationTools.updateScientificDigest(md,'observedCovariates',source.covars);
            else
                NMSimulationTools.updateScientificDigest(md,'observedCovariates',[]);
            end
            cv=source.analysis{pf.sourceAnalysisIndex}.params.cv;
            NMSimulationTools.updateScientificDigest(md,'trainPartitions',cv.TrainInd);
            NMSimulationTools.updateScientificDigest(md,'testPartitions',cv.TestInd);
            for m=pf.activeModalities(:)'
                NMSimulationTools.updateScientificDigest(md,sprintf('predictors_%d',m),source.Y{m});
            end
            hash=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
        end

        function updateScientificDigest(md,field,value)
            header=sprintf('%s|%s|%s|',field,class(value),mat2str(size(value)));
            md.update(typecast(uint8(unicode2native(header,'UTF-8')),'int8'));
            if isnumeric(value) || islogical(value)
                for first=1:131072:numel(value)
                    chunk=value(first:min(first+131071,numel(value)));
                    if isfloat(chunk)
                        chunk(isnan(chunk))=cast(NaN,'like',chunk);
                    end
                    if islogical(chunk),chunk=uint8(chunk);end
                    md.update(typecast(typecast(chunk(:),'uint8'),'int8'));
                end
            else
                bytes=uint8(unicode2native(jsonencode(value),'UTF-8'));
                md.update(typecast(bytes(:),'int8'));
            end
        end

        function hash = sha256File(path)
            % Integrity of one immutable shared cohort, checked once per
            % size on Resume (and on explicit child materialisation).
            fid=fopen(path,'rb');
            assert(fid>=0,'NMSimulationTools:cohortUnavailable', ...
                'Cannot open SYNTH cohort: %s',path);
            closeFile=onCleanup(@()fclose(fid)); %#ok<NASGU>
            md=java.security.MessageDigest.getInstance('SHA-256');
            while true
                bytes=fread(fid,1048576,'*uint8');
                if isempty(bytes),break;end
                md.update(bytes);
            end
            hash=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
        end

        function restoreLegacyObservedNM(observedNM)
            % Restore the observed NM/CV after transient model training.
            global NM CV
            NM=observedNM;
            CV=observedNM.cv;
        end

        function appendLog(path,message)
            fid=fopen(path,'a');
            assert(fid>=0,'NMSimulationTools:logFile', ...
                'Cannot write SYNTH coordinator log: %s',path);
            closer=onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid,'[%s] %s\n',datestr(now,31),message);
        end

        function NM = updateSubjectCounts(NM,mode)
            % Shared subject-axis metadata update after append and replay.
            NM.n_subjects_all=size(NM.label,1);
            if strcmp(mode,'classification')
                NM.n_subjects=arrayfun(@(k)nnz(NM.label==k), ...
                    1:numel(NM.groupnames));
            else
                NM.n_subjects=NM.n_subjects_all;
            end
        end

    end
end
