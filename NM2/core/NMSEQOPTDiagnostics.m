function D = NMSEQOPTDiagnostics(labels, trajectory, terminalNode, positiveClass)
% NMSEQOPTDiagnostics  Stage-wise diagnostics for one applied SEQOPT sequence.
%
% INPUT CONTRACT
%   labels       N-by-1 signed dichotomizer labels (+1/-1). NaN and 0 mean
%                no evaluable label; this is the genuine evaluation target,
%                never the dummy labels passed during model application.
%   trajectory   N-by-K cumulative decision scores after each *active*
%                examination, using the trained sequence order. For the
%                inherited nk_OptPredSeq applied model, obtain this as
%                model.optDh(:,1:numel(model.SequenceCols)). Training
%                processes every configured transition. SequenceCols is
%                then limited to max(model.Nremain), so unused storage
%                columns of optDh do not represent applied examinations.
%   terminalNode N-by-1 last examination reached by each evaluated case,
%                with integer values in 1:K. In the inherited application
%                model this is model.Nremain_test. Subset trajectories and
%                terminal nodes on the same evaluation case axis.
%   positiveClass +1 or -1; selects the target-group polarity without
%                changing the persisted binary decision-score coordinate.
%
% ALLPARAM is the sole NeuroMiner authority for confusion counts and binary
% performance metrics; retain its native output per examination. Evaluate the fixed labeled population at each stage,
% excluding nonfinite/zero decisions (unclassified) before calling ALLPARAM.
% In particular, LR+ follows ALLPARAM's established perfect-specificity
% convention. Case-propagation frequencies include unlabeled cases.
% This function neither selects/averages sequences nor aggregates models:
% callers own those identity and repeated-subject decisions. The selected
% optimization criterion remains with its existing scientific producer.

nCases = size(trajectory,1);
nStages = size(trajectory,2);
assert(isequal(size(labels),[nCases 1]), ...
    'NMSEQOPTDiagnostics:CaseAxis', ...
    'Labels must be one value per evaluation case.');
assert(isequal(size(terminalNode),[nCases 1]), ...
    'NMSEQOPTDiagnostics:CaseAxis', ...
    'Terminal nodes must be one value per evaluation case.');
assert(nStages>=1, 'NMSEQOPTDiagnostics:EmptySequence', ...
    'At least one examination is required.');
assert(positiveClass==1 || positiveClass==-1, ...
    'NMSEQOPTDiagnostics:TargetPolarity', ...
    'Positive-class polarity must be +1 or -1.');
assert(all(isfinite(terminalNode) & terminalNode==fix(terminalNode) & ...
    terminalNode>=1 & terminalNode<=nStages), ...
    'NMSEQOPTDiagnostics:TerminalNode', ...
    'Terminal nodes must index examinations of the applied sequence.');
assert(all(isnan(labels) | labels==0 | labels==1 | labels==-1), ...
    'NMSEQOPTDiagnostics:Labels', ...
    'Labels must be signed binary dichotomizer targets (+1/-1), zero or NaN.');

isLabeled = labels==1 | labels==-1;
isPositive = labels==positiveClass;

D = struct('nCases',nCases, 'nStages',nStages, ...
    'positiveClass',positiveClass, 'nLabeled',sum(isLabeled), ...
    'nReached',zeros(1,nStages), 'nTerminal',zeros(1,nStages), ...
    'percentReached',nan(1,nStages), ...
    'nLabeledReached',zeros(1,nStages), ...
    'nTargetReached',zeros(1,nStages), ...
    'targetPrevalenceReached',nan(1,nStages), ...
    'nScored',zeros(1,nStages), ...
    'performance',{cell(1,nStages)});

for j = 1:nStages
    reached = terminalNode>=j;
    D.nReached(j) = sum(reached);
    D.nTerminal(j) = sum(terminalNode==j);
    D.nLabeledReached(j) = sum(reached & isLabeled);
    D.nTargetReached(j) = sum(reached & isPositive);
    if nCases>0
        D.percentReached(j) = 100*D.nReached(j)/nCases;
    end
    if D.nLabeledReached(j)>0
        D.targetPrevalenceReached(j) = ...
            100*D.nTargetReached(j)/D.nLabeledReached(j);
    end

    % Cumulative performance refers to the original eligible labeled
    % population, NOT only cases propagating to examination j.
    decision = trajectory(:,j);
    scored = isLabeled & isfinite(decision) & decision~=0;
    D.nScored(j) = sum(scored);
    if D.nScored(j)>0
        D.performance{j} = ALLPARAM(labels(scored),decision(scored),positiveClass==-1);
    end
end
end
