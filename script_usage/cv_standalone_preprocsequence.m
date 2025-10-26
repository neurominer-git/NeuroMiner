% NeuroMiner stand‑alone preprocessing pipeline  (corr‑prune removed)
% ------------------------------------------------------------
% Order after user update (2025‑06‑03):
%   1) scaling / centring
%   2) prune obvious rubbish (zero‑var / NaN / Inf / low‑uniqueness)
%   3) impute missing values
%   4) regress out covariates (partial correlations) — keep β
%
% ── INPUTS ───────────────────────────────────────────────────────────────
% Yraw : [subjects × features] numeric matrix (may include NaNs)
% Age  : column vector (years)
% Sex  : column vector (0 / 1)
% ------------------------------------------------------------------------

addpath(genpath('/Users/claravetter/local/Code/NeuroMiner/NeuroMiner_Current'));

%% 0 LOAD DATA
load('/Users/claravetter/local/Code/NeuroMiner/SummerSchool/2024/Day1/NMstruct.mat');

Yraw = NM.Y;        
Age  = NM.covars(:,strcmp(NM.covnames, 'age')); 
Sex  = NM.covars(:,strcmp(NM.covnames, 'sex'));   

%% 1 ▸ SCALE / CENTRE (z‑score)
optScale = struct('method','zscore');
[Ysc , pScale] = nk_PerfScaleObj(Yraw , optScale);

%% 2 ▸ SANITY PRUNE (zero‑var / NaN / Inf / low uniqueness)
optZero = struct('zero',1,'nan',1,'inf',1,'perc',99);
[Ypruned , pZero] = nk_PerfElimZeroObj(Ysc , optZero);

%% 3 ▸ IMPUTE (Seq k‑NN, k = 7)
% For k‑NN imputation the training matrix that defines the neighbourhoods
% must be supplied in optImp.X.  Here we use the *pruned* (already scaled)
% data from step 2 so dimensions match exactly.
optImp = struct('method','SeqkNN', ...  % Sequential k‑NN imputation
                'k',7, ...
                'X',Ypruned);           % reference sample
[Yimp , pImp] = nk_PerfImputeObj(Ypruned , optImp);

%% 4 ▸ COVARIATE CONTROL (partial correlations) ▸ COVARIATE CONTROL (partial correlations)
G = [Age Sex];
optCov = struct;
optCov.TrCovars{1} = G; % 1 CV: because NM only has one modality, for more modalities I need to double check
optCov.METHOD   = 1;      % partial correlations
[Yclean , pCov] = nk_UnivCorrProcsObj(Yimp , optCov);

%% 5 ▸ SAVE PARAMETERS (optional)
save('PreprocParams.mat','pScale','pZero','pImp','pCov');

%% 6 ▸ APPLY TO NEW DATA (no function, just run these lines)
% ---------------------------------------------------------
%  Load learned parameters
load('PreprocParams.mat','pScale','pZero','pImp','pCov');

%  Provide new cohort variables
Ynew      = randn(50,500);      % new subjects × features  (replace)
Age_new   = randi([18 75],50,1);% replace
Sex_new   = randi([0 1],50,1);  % replace

%  Step‑by‑step transform reusing the stored objects
Ynew_sc  = nk_PerfScale    (Ynew , pScale);
Ynew_pr  = nk_PerfElimZeroObj(Ynew_sc , pZero);
Ynew_imp = nk_PerfImputeObj(Ynew_pr , pImp);

pCov.TsCovars = [Age_new Sex_new];   % supply covariates for new data
Ynew_clean = nk_UnivCorrProcsObj(Ynew_imp , pCov);

%  Ynew_clean now matches the training‑time preprocessing.


%  Ynew_clean now matches the training‑time preprocessing.
