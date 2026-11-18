classdef NMSynthPerformanceTools
% Completion-only SYNTH aggregation of stored per-analysis metric scalars.
% No Results Viewer dependency, no input data reconstruction and no file I/O.
    methods (Static)
        function summary=buildSummary(NM,experimentIndex)
            parent=NM.SYNTH.analysis{experimentIndex};
            indices=parent.analysisIndices;
            cfg=parent.configuration;
            fullMode=strcmp(parent.mode,'fully_synthetic');
            if fullMode
                expected=size(cfg.combinations,1)*cfg.plan.NReps;
            else
                expected=numel(cfg.sampleSizes)*cfg.shiftPermutations;
            end
            assert(numel(indices)==expected, ...
                'NMSynthPerformanceTools:IncompleteChildren', ...
                'SYNTH performance summary requires all completed children.');
            A=NM.analysis{indices(1)};
            assert(size(A.params.label.label,2)==1, ...
                'NMSynthPerformanceTools:TargetContract', ...
                'The SYNTH coordinator supports exactly one native target.');
            criterion=NMPerformanceMetricTools.optimizationCriterion(A);
            assert(~isempty(criterion.metricId),'NMSynthPerformanceTools:CriterionUnexposed', ...
                'Optimization criterion %s has no tabulated metric identity.',criterion.shortLabel);
            mode=A.params.label.modeflag;
            % Membership and learning-context identity are child invariants,
            % independent of the number of displayed metric/model contexts.
            for ii=1:numel(indices)
                child=NM.analysis{indices(ii)};
                assert(strcmp(child.simulation.synthAnalysisId,parent.id), ...
                    'NMSynthPerformanceTools:MembershipMismatch', ...
                    'SYNTH child is not part of the selected experiment.');
                childCriterion=NMPerformanceMetricTools.optimizationCriterion(child);
                assert(strcmp(child.params.label.modeflag,mode) && ...
                    strcmp(childCriterion.key,criterion.key), ...
                    'NMSynthPerformanceTools:ContextMismatch', ...
                    'SYNTH children have incompatible learning contexts.');
            end
            sizes=unique(arrayfun(@(i)NM.analysis{i}.simulation.sampleSize,indices));
            sampleSizes=arrayfun(@(i)NM.analysis{i}.simulation.sampleSize,indices);
            % A completed child owns the exact ML result families and sources.
            if A.params.TrainParam.FUSION.flag==3
                sources=arrayfun(@(m)sprintf('modality:%d',m),1:numel(A.GDdims),'UniformOutput',false);
                % nm2-allow: nk_MLOptimizerMeta conditionally produces analysis.META for late fusion.
                if isfield(A,'META'),sources{end+1}='meta';end %#ok<AGROW>
            else
                sources={''};
            end
            contexts=repmat(struct('targetNativeIndex',0,'modelSource','', ...
                'classifierIndex',0,'multiClassModeIndex',0, ...
                'metricIds',{{}},'metricLabels',{{}},'mean',[],'sd',[],'count',[]),1,0);
            defaultValues=[];rawValues={};
            for ss=1:numel(sources)
                source=sources{ss};
                GD=NMPerformanceMetricTools.sourceContainer(A,source);
                models=repmat(struct('kind','','classifierIndex',0,'multiMode',0),1,0);
                if strcmp(mode,'regression')
                    % nm2-allow: nk_MultiPerfComp writes Regr only for regression analyses; this selects available stored contexts.
                    if isfield(GD,'Regr')&&~isempty(GD.Regr)
                        models(1)=struct('kind','regression','classifierIndex',1,'multiMode',0);
                    end
                else
                    % The optimizer conditionally produces binary and multi-group families.
                    % nm2-allow: nk_MultiPerfComp conditionally writes BinClass for binary/one-vs-rest classifier models.
                    if isfield(GD,'BinClass')&&~isempty(GD.BinClass)
                        models=[models,arrayfun(@(cc)struct('kind','classification', ...
                            'classifierIndex',cc,'multiMode',0),1:numel(GD.BinClass))];
                    end
                    % nm2-allow: nk_MultiEvalPerf writes MultiClass only for multiclass outcomes.
                    if isfield(GD,'MultiClass')&&~isempty(GD.MultiClass)
                        models=[models,arrayfun(@(mm)struct('kind','multiclass', ...
                            'classifierIndex',numel(GD.BinClass)+1,'multiMode',mm+1), ...
                            1:numel(GD.MultiClass.class))];
                    end
                end
                for model=models
                    first=NMPerformanceMetricTools.fromAnalysis(A,source,model.kind, ...
                        model.classifierIndex,1,model.multiMode);
                    catalogue=NMPerformanceMetricTools.metricCatalogue(model.kind,first);
                    ids={catalogue.id};vals=nan(numel(indices),numel(ids));
                    for ii=1:numel(indices)
                        if ii==1,rows=first;
                        else
                            rows=NMPerformanceMetricTools.fromAnalysis(NM.analysis{indices(ii)},source,model.kind, ...
                                model.classifierIndex,1,model.multiMode);
                        end
                        for jj=1:numel(ids)
                            [v,found]=NMPerformanceMetricTools.value(rows,ids{jj});
                            if found,vals(ii,jj)=v;end
                        end
                    end
                    keep=any(isfinite(vals),1);
                    catalogue=catalogue(keep);ids=ids(keep);vals=vals(:,keep);
                    if isempty(ids),continue;end
                    binaryTask=strcmp(mode,'classification') && numel(unique(A.params.label.label))==2;
                    if any(strcmp(ids,'AUC')) && (strcmp(model.kind,'multiclass') || (strcmp(model.kind,'classification') && binaryTask))
                        positive=min(A.params.label.label);
                        if strcmp(model.kind,'multiclass'),positive=model.multiMode-1;end
                        prevalence=arrayfun(@(i)mean(NM.analysis{i}.params.label.label==positive),indices)';
                        infer=auc_to_effect_and_power(sampleSizes(:),vals(:,strcmp(ids,'AUC')),'Prev',prevalence,'Plot',false);
                        ids=[ids,{'cohen_d','power'}]; vals=[vals,infer.cohen_d,infer.power];
                        catalogue=[catalogue,struct('id',{'cohen_d','power'}, ...
                            'label',{'AUC-derived Cohen''s d','AUC power (two-sided; alpha 0.05)'},'enabled',{true,true})];
                    end
                    avg=nan(numel(sizes),numel(ids));dev=avg;count=zeros(size(avg));
                    for nn=1:numel(sizes)
                        subset=vals(sampleSizes==sizes(nn),:);
                        finite=isfinite(subset);
                        count(nn,:)=sum(finite,1);
                        subset(~finite)=NaN;
                        avg(nn,:)=mean(subset,1,'omitnan');
                        dev(nn,:)=std(subset,0,1,'omitnan');
                    end
                    dev(count<2)=NaN;
                    contexts(end+1)=struct('targetNativeIndex',1, ... %#ok<AGROW>
                        'modelSource',source,'classifierIndex',model.classifierIndex, ...
                        'multiClassModeIndex',model.multiMode,'metricIds',{ids}, ...
                        'metricLabels',{{catalogue.label}}, ...
                        'mean',avg,'sd',dev,'count',count);
                    if fullMode,rawValues{end+1}=vals;end %#ok<AGROW>
                    if isempty(defaultValues) && ss==1 && model.classifierIndex==1
                        defaultValues=vals(:,strcmp(ids,criterion.metricId));
                    end
                end
            end
            assert(~isempty(defaultValues),'NMSynthPerformanceTools:CriterionUnavailable', ...
                'The completed children do not expose metric %s.',criterion.metricId);
            if fullMode
                [contexts.childValues]=rawValues{:};
                row=struct('analysisId','','sampleSize',0, ...
                    'combinationIndex',0,'repetitionIndex',0,'value',NaN);
            else
                row=struct('analysisId','','sampleSize',0,'permutation',0,'value',NaN);
            end
            rows=repmat(row,1,numel(indices));
            for ii=1:numel(indices)
                child=NM.analysis{indices(ii)};
                rows(ii).analysisId=child.id;
                rows(ii).sampleSize=child.simulation.sampleSize;
                rows(ii).value=defaultValues(ii);
                if fullMode
                    rows(ii).combinationIndex=child.simulation.combinationIndex;
                    rows(ii).repetitionIndex=child.simulation.repetitionIndex;
                else
                    rows(ii).permutation=child.simulation.permutation;
                end
            end
            summary=struct('criterion',criterion,'rows',rows, ...
                'sampleSizes',sizes,'contexts',contexts);
            if fullMode
                summary.parameterNames=NMSynthPopulationGenerator.factorNames(cfg.plan);
                summary.parameterRows=cfg.combinations;
            end
        end

    end
end
