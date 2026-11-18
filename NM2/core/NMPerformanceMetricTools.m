classdef NMPerformanceMetricTools
% Shared, read-only projection of persisted NeuroMiner performance metrics.
% No Results Viewer state, model restoration, prediction recomputation or I/O.
% The classifier/regression writers own metric values; this class owns their
% fixed tabulation schema for both SYNTH and Results Viewer consumers.
    methods (Static)
        function rows=fromAnalysis(A,modelSource,kind,classifierIndex,targetIndex,multiClassModeIndex)
            % Read a completed analysis directly, at its exact persisted source.
            GD=NMPerformanceMetricTools.sourceContainer(A,modelSource);
            switch kind
                case 'regression'
                    % Regr fields are compact target-indexed scalar measures.
                    rows=NMPerformanceMetricTools.regressionRows(GD.Regr,targetIndex);
                case 'classification'
                    % This is the inherited writer spelling, not an alias.
                    rows=NMPerformanceMetricTools.classificationRows( ...
                        GD.BinClass{classifierIndex}.contigency);
                case 'multiclass'
                    assert(multiClassModeIndex>=2, ...
                        'NMPerformanceMetricTools:InvalidMulticlassMode', ...
                        'Multi-group aggregate has no one-vs-rest scalar tabulation.');
                    rows=NMPerformanceMetricTools.classificationRows( ...
                        GD.MultiClass.class{multiClassModeIndex-1});
                otherwise
                    error('NMPerformanceMetricTools:UnknownResultType', ...
                        'Unknown performance result type %s.',kind);
            end
        end

        function GD=sourceContainer(A,modelSource)
            if strcmp(modelSource,'meta')
                GD=A.META;
            elseif startsWith(modelSource,'modality:')
                sourceIndex=sscanf(modelSource,'modality:%d');
                assert(isscalar(sourceIndex) && sourceIndex>=1 && ...
                    sourceIndex<=numel(A.GDdims), ...
                    'NMPerformanceMetricTools:InvalidSource','Invalid model-source index.');
                GD=A.GDdims{sourceIndex};
            else
                first=find(~cellfun(@isempty,A.GDdims),1);
                assert(~isempty(first),'NMPerformanceMetricTools:MissingResult', ...
                    'Completed analysis has no optimizer result.');
                GD=A.GDdims{first};
            end
        end

        function rows=classificationRows(c)
            % Project exactly the numeric/logical scalar fields selected by
            % Model Performance; omit vector X and nonmetric arrays.
            rows=NMPerformanceMetricTools.emptyRows();
            if isempty(c),return;end
            fields=fieldnames(c);
            for ii=1:numel(fields)
                name=fields{ii};
                if strcmp(name,'X'),continue;end
                raw=c.(name);
                % nm2-allow: ALLPARAM contingency producer includes nonmetric vector X and other non-scalar fields.
                if ~(isnumeric(raw)||islogical(raw))||~isscalar(raw),continue;end
                rows(end+1)=struct('metric',name,'value',double(raw), ... %#ok<AGROW>
                    'source','model_performance/contingency');
            end
        end

        function rows=regressionRows(R,targetIdx)
            % The inherited regression result stores a sparse set of named
            % metrics; enumerate its existing names, never invent defaults.
            rows=NMPerformanceMetricTools.emptyRows();
            if isempty(R),return;end
            names={'R2','r','r_95CI_low','r_95CI_up','t','p','MAE','MSE','NRSMD'};
            produced=fieldnames(R);
            for ii=1:numel(names)
                name=names{ii};
                if ~any(strcmp(produced,name)),continue;end
                raw=R.(name);
                if isempty(raw),continue;end
                % nm2-allow: nk_MultiPerfComp persists regression metrics as numeric or logical target arrays.
                assert(isnumeric(raw)||islogical(raw), ...
                    'NMPerformanceMetricTools:InvalidRegressionMetric', ...
                    'Stored regression metric %s is not numeric.',name);
                raw=double(raw);
                if isscalar(raw)
                    value=raw;
                else
                    % nm2-allow: nk_MultiPerfComp stores target-indexed vectors; reject invalid selected target.
                    assert(targetIdx>=1 && targetIdx<=numel(raw) && ...
                        targetIdx==round(targetIdx), ...
                        'NMPerformanceMetricTools:InvalidTarget', ...
                        'Target index is outside stored metric %s.',name);
                    value=raw(targetIdx);
                end
                outputName=name;
                if strcmp(name,'NRSMD'),outputName='NRMSD';end
                rows(end+1)=struct('metric',outputName,'value',value, ... %#ok<AGROW>
                    'source','model_performance/regression');
            end
        end

        function rows=emptyRows()
            rows=repmat(struct('metric','','value',NaN,'source',''),1,0);
        end

        function rows=canonicalRows(raw)
            % Transport projection: strict schema; never parse display text.
            rows=repmat(struct('metric','','value',NaN,'source',''),1,numel(raw));
            for ii=1:numel(raw)
                value=double(raw(ii).value);
                assert(~isempty(raw(ii).metric)&&isscalar(value), ...
                    'NMPerformanceMetricTools:InvalidRows', ...
                    'Performance tabulation row %d violates the metric/value contract.',ii);
                rows(ii)=struct('metric',raw(ii).metric, ...
                    'value',value,'source',raw(ii).source);
            end
        end

        function [value,found]=value(rows,id)
            value=NaN;found=false;
            if isempty(rows),return;end
            hit=find(strcmp({rows.metric},id));
            assert(numel(hit)<=1,'NMPerformanceMetricTools:DuplicateMetric', ...
                'Metric %s appears more than once in one performance context.',id);
            if isempty(hit),return;end
            value=double(rows(hit).value);found=isscalar(value);
        end

        function catalogue=metricCatalogue(kind,rows)
            if strcmp(kind,'regression')
                catalogue=repmat(struct('id','','label','','enabled',true),1,0);
                seen={};
                for ii=1:numel(rows)
                    id=rows(ii).metric;
                    if isempty(id)||any(strcmp(seen,id)),continue;end
                    seen{end+1}=id; %#ok<AGROW>
                    catalogue(end+1)=struct('id',id,'label',id,'enabled',true); %#ok<AGROW>
                end
                return;
            end
            ids={'BAC','acc','sens','spec','PPV','NPV','FPR','PSI','pLR','nLR', ...
                'DOR','NNP','NND','Youden','MCC','Fscore','GMean','AUC','ECE'};
            labels={'Balanced Accuracy','Accuracy','Sensitivity','Specificity', ...
                'Positive Predictive Value','Negative Predictive Value', ...
                'False Positive Rate','Prognostic Summary Index', ...
                'Positive Likelihood Ratio','Negative Likelihood Ratio', ...
                'Diagnostic Odds Ratio','Number Needed to Predict', ...
                'Number Needed to Diagnose','Youden-Index', ...
                'Matthews Correlation Coefficient','F-Score','G-Mean', ...
                'Area Under Curve','Expected Calibration Error'};
            catalogue=repmat(struct('id','','label','','enabled',true),1,numel(ids));
            for ii=1:numel(ids)
                catalogue(ii)=struct('id',ids{ii},'label',labels{ii},'enabled',true);
            end
        end

        function criterion=optimizationCriterion(A)
            % Shared criterion interpretation from the existing ML library.
            code=double(A.params.TrainParam.SVM.GridParam);
            catalog=NMLearnerLibrary.criterionCatalog();
            hit=find([catalog.code]==code,1);
            assert(~isempty(hit),'NMPerformanceMetricTools:UnknownCriterion', ...
                'GridParam %g is not registered in NMLearnerLibrary.',code);
            entry=catalog(hit);
            scale=struct('mode',entry.scaleMode,'minimum',entry.scaleMinimum, ...
                'maximum',entry.scaleMaximum,'referenceValue',entry.referenceValue, ...
                'referenceLabel',entry.referenceLabel);
            criterion=struct('key',sprintf('grid_param:%d',code),'code',code, ...
                'label',entry.displayLabel,'shortLabel',entry.shortLabel, ...
                'metricId',entry.metricId,'scale',scale);
        end
    end
end
