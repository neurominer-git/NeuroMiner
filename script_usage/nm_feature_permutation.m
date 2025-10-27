function NM = nm_feature_permutation(NM, n_perm, analysis_ind, modality_ind, all_features_modality_ind, optimal_features_ind)
% NM_FEATURE_PERMUTATION Conducts feature permutation analysis in NeuroMiner
%
% This function permutes non-optimal features, retrains the model on each
% permutation (in a separate feat_perm subdirectory), and computes a
% nonparametric p-value testing whether the original performance is better
% than chance.
%
% INPUTS:
%   NM                        - NeuroMiner struct with data & analysis config.
%   n_perm                    - Number of permutations.
%   analysis_ind              - Which analysis in NM.analysis{…} to use.
%   modality_ind              - Which modality’s slot to overwrite with permuted features.
%   all_features_modality_ind - Which modality holds the full feature set.
%   optimal_features_ind      - (opt.) logical mask of “optimal” features to keep fixed.
%
% OUTPUT:
%   NM – same struct, but NM.analysis{analysis_ind} now contains:
%        .permutations        : 1×n_perm cell array of permuted-analysis structs
%        .permutationPerf     : n_perm×1 array of permuted performances
%        .permutationField    : name of the performance field used
%        .permutation_pValue  : scalar p-value
%        .feat_perm_analysis  : true

    %% 0) optional mask
    if ~exist('optimal_features_ind','var') || isempty(optimal_features_ind)
        optimal_features_ind = [];
    end

    %% 1) extract features to permute
    if ~isempty(optimal_features_ind)
        rest_feats      = NM.Y{1,all_features_modality_ind}(:, ~optimal_features_ind);
        rest_feat_names = NM.featnames{1,all_features_modality_ind}(~optimal_features_ind);
    else
        rest_feats      = NM.Y{1,all_features_modality_ind};
        rest_feat_names = NM.featnames{1,all_features_modality_ind};
    end
    num_rest = size(rest_feats,2);

    %% 2) prepare train_model params
    analind    = analysis_ind;
    ovrwrtfl   = 1;
    CV2x1      = size(NM.analysis{analind}.params.cv.TrainInd,1);
    CV2x2      = size(NM.analysis{analind}.params.cv.TrainInd,2);

    %% 3) grab ORIGINAL performance from nested field (no retrain)
    perfField = 'GDdims{1,1}.BinClass{1,1}.costfun_crit';
    origPerf  = NM.analysis{analind}.GDdims{1,1}.BinClass{1,1}.costfun_crit;
    fprintf('Using existing "%s" = %.4f as original performance.\n', perfField, origPerf);

    %% 4) ensure a feat_perm subdirectory under rootdir
    orig_root = NM.analysis{analind}.rootdir;
    perm_root = fullfile(orig_root, 'feat_perm');
    if ~exist(perm_root, 'dir')
        mkdir(perm_root);
    end

    %% 5) pre-generate random shuffles
    permIdx = arrayfun(@(x) randperm(num_rest), 1:n_perm, 'UniformOutput', false);

    %% 6) loop over permutations
    perms    = cell(1,n_perm);
    perfVals = zeros(n_perm,1);
    for i = 1:n_perm
        NT  = NM;       % copy
        idx = permIdx{i};

        % shuffle features
        NT.Y{1,modality_ind}         = rest_feats(:, idx);
        NT.featnames{1,modality_ind} = rest_feat_names(idx);

        % point analysis at feat_perm folder
        NT.analysis{analind}.rootdir = perm_root;
        NT.analysis{analind}.logfile  = strrep(NT.analysis{analind}.logfile,  orig_root, perm_root);
        NT.analysis{analind}.paramdir = strrep(NT.analysis{analind}.paramdir, orig_root, perm_root);
        NT.analysis{analind}.paramfile= strrep(NT.analysis{analind}.paramfile,orig_root, perm_root);

        % clear any existing GDdims before training
        NT.analysis{analind}.GDdims = {};

        % retrain model
        NT = train_model(NT, analind, ovrwrtfl, CV2x1, CV2x2, [], [], []);
        
        % cleanup on disk: remove feat_perm contents
        if exist(perm_root, 'dir')
            rmdir(perm_root, 's');
        end
        
        % collect results
        perms{i}    = NT.analysis{analind};
        perfVals(i) = NT.analysis{analind}.GDdims{1,1}.BinClass{1,1}.costfun_crit;
    end

    %% 7) compute p-value
    if isfield(NM.analysis{analind}.params,'optDir') && ...
       strcmpi(NM.analysis{analind}.params.optDir,'max')
        cmp = @ge;
    else
        cmp = @le;
    end
    beats = cmp(perfVals, origPerf);
    pVal  = (sum(beats) + 1) / (n_perm + 1);

    %% 8) store back under analysis
    A.permutations       = perms;
    A.permutationPerf    = perfVals;
    A.permutationField   = perfField;
    A.permutation_pValue = pVal;
    A.feat_perm_analysis = true;
    NM.analysis{analind}.feature_permutations = A;

    fprintf('Feature-perm test done: %s=%.4f → p=%.4f\n', perfField, origPerf, pVal);
end
