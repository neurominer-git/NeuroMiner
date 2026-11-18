function [values, metricIds] = NMSEQOPTDiagnosticValues(models, sequenceCols)
% Project applied-model diagnostics onto their ordered examination axis.
% ALLPARAM remains the only authority for classification performance.
% Caller owns model grouping and mean/SD aggregation.
% Preserve every scalar native ALLPARAM output (including fields that
% should not be offered as clinically interpretable viewer metrics).
% X is a 2-by-2 contingency matrix, not a stage-wise scalar.
metricIds = {'TP','TN','FP','FN','P','N','acc','sens','spec','FPR', ...
    'PPV','NPV','GMean','AUC','AUC_lower','AUC_upper','BAC', ...
    'Fscore','MCC','pLR','nLR','PSI','NNP','NND', ...
    'Youden','DOR','Kappa','Kappa_Z','Kappa_P', ...
    'percentReached','targetPrevalenceReached','nReached','nTerminal'};
nStages = numel(sequenceCols);
values = nan(numel(models),nStages,numel(metricIds));
for m = 1:numel(models)
    D = models{m};
    if isempty(D), continue; end
    n = D.nStages;
    assert(n<=nStages && isequal(D.sequenceCols,sequenceCols(1:n)), ...
        'NMSEQOPTDiagnosticValues:SequenceOrder', ...
        'Only identical ordered sequences or their prefixes may be combined.');
    for j = 1:n
        P = D.performance{j};
        for q = 1:numel(metricIds)
            id = metricIds{q};
            switch id
                case 'percentReached', value = D.percentReached(j);
                case 'targetPrevalenceReached'
                    value = D.targetPrevalenceReached(j);
                case 'nReached', value = D.nReached(j);
                case 'nTerminal', value = D.nTerminal(j);
                otherwise
                    if isempty(P), continue; end
                    % nm2-allow: ALLPARAM conditionally emits AUC when both classes are observed.
                    if strcmp(id,'AUC') && ~isfield(P,'AUC'), continue; end
                    value = P.(id);
            end
            values(m,j,q) = value;
        end
    end
end
end
