%% Function: nk_RecompPerfCV2subgroups
%  Description:
%  This function computes the performance metrics for subgroups across nested
%  cross-validation (CV) partitions. It processes subgroup-specific predictions
%  using data from a binary grid search and calculates performance metrics
%  for each subgroup. The function handles multi-level CV structures (CV1 and CV2).
%  Additionally, it allows specifying a specific performance metric to compute.
% 
%  Inputs:
%    GDmats     - Cell array containing paths to grid search result files for each
%                 outer CV2 fold.
%    CV         - Struct containing information about the nested CV partitions.
%                 Includes TestInd for CV2 and CV1 folds.
%    Labels     - Array of true labels corresponding to the data points.
%    SubIdx     - Vector or matrix indicating subgroup indices for each data point.
%                 If more than one column, it will be transposed.
%    PerfMetric - String specifying the performance metric to compute (e.g., 'BAC',
%                 'AUC', etc.).
% 
%  Outputs:
%    PerfSubGroups - Matrix containing performance metrics for each subgroup
%                    across CV2 partitions and folds.
% 
%  Usage:
%    PerfSubGroups = nk_RecompPerfCV2subgroups(GDmats, CV, Labels, SubIdx, PerfMetric)

function PerfSubGroups = nk_RecompPerfCV2subgroups(GDmats, CV, Labels, SubIdx, PerfMetric)

% Determine the size of CV2 and CV1 partitions
[ nCV2partitions, nCV2folds ] = size(CV.TestInd);
[ nCV1partitions, nCV1folds ] = size(CV.cvin{1,1}.TestInd);

% Ensure SubIdx is a column vector
if width(SubIdx) > 1
    SubIdx = SubIdx';
end

% Identify unique subgroups and count cases per subgroup
nSubGroups = unique(SubIdx);
U = nk_CountUniques(SubIdx); 
nCasesInSub = U.UN{1};
nCases = height(SubIdx);

% Initialize output matrix
PerfSubGroups = zeros(nCases, nSubGroups);

% Counter for CV2 folds
cntCV2 = 1;

% Loop through CV2 partitions and folds
for pCV2 = 1:nCV2partitions
    for fCV2 = 1:nCV2folds
        
        % Extract subgroup indices for the current CV2 fold
        SubIdxCV2 = SubIdx(CV.TestInd{pCV2, fCV2});
        
        % Load grid search results for the current fold
        load(GDmats{pCV2, fCV2});
        
        % Loop through subgroups
        for g = 1:nSubGroups
            
            % Initialize matrix for storing predictions across CV1 folds
            dSubGroups = zeros(nCasesInSub(g), nCV1partitions * nCV1folds);
            cntCV1 = 1;
            
            % Filter data for the current subgroup
            SubIdxG = SubIdxCV2 == g;
            LabelsG = Labels(CV.TestInd{pCV2, fCV2});
            
            % Loop through CV1 partitions and folds
            for pCV1 = 1:nCV1partitions
                for fCV1 = 1:nCV1folds
                    
                    % Extract predictions for the current subgroup
                    dSubGroups(:, cntCV1) = GD.BinaryGridSelection{1}{1}.bestpred{1}{pCV1, fCV1}(SubIdxG);
                    cntCV1 = cntCV1 + 1;
                end
            end
            
            % Calculate the median prediction for the subgroup
            pSubGroup = nm_nanmedian(dSubGroups, 2);
            
            % Compute performance metric for the subgroup
            tPerf = ALLPARAM(LabelsG, dSubGroups);
            PerfSubGroups(cntCV2, g) = tPerf.(PerfMetric); 
        end
        
        % Increment CV2 fold counter
        cntCV2 = cntCV2 + 1;
    end
end