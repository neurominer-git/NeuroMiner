% ===================================================================================
% FORMAT cv = nk_CVpartition(nperms, K, Labels, Constraint, Eq, AutoAdjust, varargin)
% ===================================================================================
% Generates nperms × K train/test splits for cross-validation,
% stratified by class labels and optional constraints, with
% optional histogram-equalization of training sets.
%
% Inputs:
%   nperms     – number of random permutations (repeats) of the data
%   K          – number of folds in each cross-validation repeat
%   Labels     – vector of class labels (numeric), one per subject
%   Constraint – (optional) vector defining subgroups to be balanced
%   Eq         – (optional) struct controlling histogram equalization:
%                  Eq.Covar    – covariate values used for equalizing
%                  Eq.AddRemoved2Test – flag to move removed samples to test
%                %%% NEW (optional):
%                  Eq.SmallBatchMaxN  – threshold k for "too small" batches 
%                  Eq.SilenceCVLog    – true to suppress end-of-operation log (default false)
%   AutoAdjust – (optional) if true, return nClassMem when K>nClassMem 
%
% Optional name–value arguments (added):
%   'SmallBatchMaxN'  – threshold k for "too small" batches 
%   'SilenceCVLog'    – true to suppress end-of-operation log (default false)
%   'CVLogFile'       – full path of a log file to write messages to (default: auto)
%   'CVLogAppend'     – true to append to existing log file (default true)
%
% Output:
%   cv.TrainInd – nperms-by-K cell array of training indices (uint16)
%   cv.TestInd  – nperms-by-K cell array of testing  indices (uint16)
%   cv.HoldoutBatches  – constraint values held out as test-only (2..k)
%   cv.ExcludedBatches – constraint values excluded entirely (N==1)
%   cv.ExcludedIdx     – subject indices excluded entirely (N==1)
%   cv.LogFile         – path to the log file if something was logged, '' otherwise
%   cv.LogWritten      – logical flag whether any message was written
%
% =========================================================================
% NeuroMiner 1.4, (c) Nikolaos Koutsouleris, 10/2025
function cv = nk_CVpartition(nperms, K, Labels, Constraint, Eq, AutoAdjust, varargin)
global NM

% --------- parse name–value arguments -------------------------------
p = inputParser;
addParameter(p,'SmallBatchMaxN',2,@(x)isscalar(x)&&x>0);
addParameter(p,'SilenceCVLog',true,@(x)islogical(x)||ismember(x,[0 1]));
addParameter(p,'CVLogFile','',@(x)ischar(x)||isstring(x));
addParameter(p,'CVLogAppend',true,@(x)islogical(x)||ismember(x,[0 1]));
addParameter(p,'StrictPerLabelTest',false,@(x)islogical(x)||ismember(x,[0 1]));
addParameter(p,'TrainSmallBatchAction','move2test',@(s)ischar(s)||isstring(s)); % 'move2test' or 'drop'
parse(p,varargin{:});
argSmallBatchMaxN = p.Results.SmallBatchMaxN;
TrainSmallBatchAction = char(p.Results.TrainSmallBatchAction);
CVLogFileArg      = char(p.Results.CVLogFile);
CVLogAppend       = logical(p.Results.CVLogAppend);
% -------------------------------------------------------------------------

trainidxs = cell(nperms,K); testidxs = cell(nperms,K); 

uLabels = unique(Labels);
if any(~isfinite(uLabels))
    NaNflag = true; 
    uLabels(~isfinite(uLabels))=[];
else
    NaNflag = false;
end

mL = numel(uLabels);
if ~exist('Eq','var'), Eq = []; end
if ~exist('Constraint','var') || isempty(Constraint)
    uConstraint = []; Constraint = [];
else
    uConstraint = unique(Constraint);
end

% Authoritative batch vector (must match what ComBat uses)
if exist('HarmonizerBatch','var') && ~isempty(HarmonizerBatch)
    BaseBatch = HarmonizerBatch;
else
    BaseBatch = Constraint;
end

% Enumerate batches (keep stable order if possible)
if ~isempty(BaseBatch)
    try
        uBatchesAll = unique(BaseBatch,'stable');
    catch
        uBatchesAll = unique(BaseBatch);
    end
else
    uBatchesAll = [];
end

% Preallocate report holders
BatchReportTables = cell(nperms,1);   % 1 table per permutation


% ---------- determine thresholds / log flags with priority ----------
SmallBatchMaxN = 5;

if ~isempty(argSmallBatchMaxN), SmallBatchMaxN = argSmallBatchMaxN; end

if isempty(argSmallBatchMaxN) && ~isempty(Eq) && isstruct(Eq) && isfield(Eq,'SmallBatchMaxN')
    if ~isempty(Eq.SmallBatchMaxN), SmallBatchMaxN = Eq.SmallBatchMaxN; end
end
try
    if isempty(argSmallBatchMaxN) && isfield(NM,'CV') && isfield(NM.CV,'SmallBatchMaxN')
        if ~isempty(NM.CV.SmallBatchMaxN), SmallBatchMaxN = NM.CV.SmallBatchMaxN; end
    end
catch
end

% ---------- set up file logger (accumulate messages -> write once) -------
logbuf = {};      % cell array of strings
% determine default log path if not provided
if ~isempty(CVLogFileArg)
    CVLogFile = CVLogFileArg;
else
    logdir = pwd;
    ts = char(datetime('now','Format','yyyyMMdd_HHmmss')); 
    CVLogFile = fullfile(logdir, ['CVpartition_log_' ts '.txt']);
end
% nested helper to add a line to the buffer
    function addlog(fmt, varargin)
        logbuf{end+1} = sprintf(fmt, varargin{:}); 
    end

% -------------------------------------------------------------------------

%%% Pre-screen batches — EXCLUDE (N==1) and HOLDOUT (2..SmallBatchMaxN)
ExcludeMask     = false(size(Labels));     % N==1 → exclude entirely
HoldoutMask     = false(size(Labels));     % 2..k → test-only
ExcludedBatches = [];
HoldoutBatches  = [];

if ~isempty(uConstraint)
    batchCounts = arrayfun(@(c) sum(Constraint==c), uConstraint);

    % Exclude all N==1 batches from cross-validation setup
    N1Mask = batchCounts == 1;
    if any(N1Mask)
        ExcludedBatches = uConstraint(N1Mask);
        ExcludeMask = ismember(Constraint, ExcludedBatches);
    end

    % Hold out all batches with 2..SmallBatchMaxN subjects (move to test
    % data folds)
    SmallMask = (batchCounts <= SmallBatchMaxN) & ~N1Mask;
    if any(SmallMask)
        HoldoutBatches = uConstraint(SmallMask);
        HoldoutMask = ismember(Constraint, HoldoutBatches);
    end
end

% Build constraint levels for TRAINING pool only
uConstrainTrain = []; 
if ~isempty(uConstraint)
    uConstrainTrain = setdiff(uConstraint,union(HoldoutBatches,ExcludedBatches,'stable'),'stable');
end

% Validate label-by-constraint overlap on TRAINING pool
if ~isempty(uConstrainTrain)
    C = zeros(mL,numel(uConstrainTrain));
    for j = 1:mL
        for hu = 1:numel(uConstrainTrain)
            C(j,hu) = sum(Labels==uLabels(j) & ...
                          Constraint==uConstrainTrain(hu) & ...
                          ~HoldoutMask & ~ExcludeMask);
        end
    end

    % NEW: any column with a per-label count < SmallBatchMaxN is TRAIN-holdout
    thinCols_any = any(C < SmallBatchMaxN, 1);

    if any(thinCols_any)
        trainHoldout = uConstrainTrain(thinCols_any);
        HoldoutMask = HoldoutMask | ismember(Constraint, trainHoldout);
        HoldoutBatches = union(HoldoutBatches, trainHoldout, 'stable');
        addlog(['[nk_CVpartition] WARN: Moving %d constraint level(s) to TEST-only ' ...
                'because at least one label has < %d cases: %s'], ...
                nnz(thinCols_any), SmallBatchMaxN, list2str(trainHoldout(:)'));
    end

    % Recompute counts after extending HoldoutMask
    C = zeros(mL,numel(uConstrainTrain));
    for j = 1:mL
        for hu = 1:numel(uConstrainTrain)
            C(j,hu) = sum(Labels==uLabels(j) & ...
                          Constraint==uConstrainTrain(hu) & ...
                          ~HoldoutMask & ~ExcludeMask);
        end
    end

    % NEW: “good” columns now require per-label counts >= SmallBatchMaxN
    goodCols = all(C >= SmallBatchMaxN, 1);

    if any(goodCols)
        uConstrainTrainEff = uConstrainTrain(goodCols);
        if any(~goodCols)
            addlog(['[nk_CVpartition] INFO: %d/%d constraint level(s) excluded from ' ...
                    'constraint-balanced TRAIN because per-label counts < %d.'], ...
                    nnz(~goodCols), numel(uConstrainTrain), SmallBatchMaxN);
        end
    else
        % No column satisfies the per-label threshold -> fall back to label-only
        uConstrainTrainEff = [];
        addlog(['[nk_CVpartition] WARN: No constraint level meets per-label ≥ %d in the ' ...
                'training pool; falling back to label-only stratification.'], SmallBatchMaxN);
    end
else
    uConstrainTrainEff = [];
end

% Generate Permutation indices
permmat = nk_PermInd(nperms, Labels, Constraint);

for h=1:nperms
    rInd        = permmat(h,:)'; 
    trainidx    = cell(1,K);
    testidx     = cell(1,K);
    
    for j=1:mL
        indClassCX = [];
        indLabels  = find(Labels==uLabels(j) & ~HoldoutMask & ~ExcludeMask);
        if ~isempty(uConstrainTrainEff)
            % All indices (within this label) + their constraint codes
            indClass = [];
            for hu=1:numel(uConstrainTrainEff)
                indClass = [indClass; find(Labels==uLabels(j) & ...
                                           Constraint==uConstrainTrainEff(hu) & ...
                                           ~HoldoutMask & ~ExcludeMask)]; %#ok<AGROW>
            end
            % ConstrXClass is the per-index constraint code for the selected label indices
            ConstrXClass = Constraint(indClass);
        
            % --- NEW: per-cell leftovers bucket
            leftovers_per_cell = cell(1, numel(uConstrainTrainEff));
        
            % Pre-assign even chunks per cell; collect remainders to leftovers_per_cell
            indClassCX = []; % track what has been assigned to TEST in the pre-pass
            for hu = 1:numel(uConstrainTrainEff)
                indC = find(ConstrXClass == uConstrainTrainEff(hu)); % positions in indClass
                nc  = numel(indC);
                if nc == 0, continue; end
        
                q = floor(nc / K);    % even chunk size per fold for this cell
                r = mod(nc, K);       % remainder for leftovers
        
                % Assign q items per fold (if q>0)
                if q > 0
                    % chunk indices for this cell
                    for i=1:K
                        startpos = (i-1)*q + 1;
                        endpos   = i*q;
                        if startpos <= endpos
                            idx_local = indC(startpos:endpos);      % positions (within indC)
                            idx_global = indClass(idx_local);       % original indices into dataset
                            testidx{i}  = [testidx{i}; idx_global]; 
                            indClassCX  = [indClassCX; idx_global]; 
                        end
                    end
                end
        
                % Collect the remainder r (and the whole cell if nc < K) as leftovers
                if r > 0
                    rem_local  = indC(q*K + (1:r));
                    leftovers_per_cell{hu} = indClass(rem_local);
                elseif q == 0
                    % nc < K : everything is leftover
                    leftovers_per_cell{hu} = indClass(indC);
                else
                    leftovers_per_cell{hu} = []; % nothing left
                end
            end
        
            % --- Block-assign per-cell leftovers to a single fold
            for hu = 1:numel(uConstrainTrainEff)
                L = leftovers_per_cell{hu};
                if isempty(L), continue; end
            
                % Option A (balanced overall): send whole leftover block to the
                % fold with currently smallest TEST size (keeps folds balanced).
                fold_sizes = cellfun(@numel, testidx);
                [~, dest] = min(fold_sizes);
            
                % Option B (avoid 1-count cell in TEST when nc>=K):
                % if q>0 for this cell (meaning nc >= K), we can ensure the leftover
                % lands where the cell already contributes q items -> q+numel(L) >= 2.
                % Uncomment this block to prefer folds with existing items of this cell.
                %{
                q = floor(numel(find(ConstrXClass == uConstrainTrainEff(hu))) / K);
                if q > 0
                    % all folds have q for this cell; tie-break by smallest total TEST size
                    [~, dest] = min(fold_sizes);
                else
                    % nc < K: no fold has this cell yet — still choose smallest TEST fold
                    [~, dest] = min(fold_sizes);
                end
                %}
            
                % Append the entire leftover block to destination fold
                testidx{dest} = [testidx{dest}; L(:)];
                indClassCX    = [indClassCX; L(:)];
            
                % Optional log (handy when debugging)
                addlog('[nk_CVpartition] Block-assigned %d leftover(s) of cell %s to fold %d (label=%s).', ...
                        numel(L), list2str(uConstrainTrainEff(hu)), dest, num2str(uLabels(j)));
            end
        else
            % No constraint balancing -> all label indices belong to the pool
            indClass = indLabels;
        end
        
        nClassMem = length(indClass);
        testsize = floor(nClassMem/K);

        for i=1:K
            if testsize>0
                if isempty(uConstrainTrainEff)
                    startpos = (i-1)*testsize + 1; 
                    endpos   = i*testsize;
                    testidx{i} = [testidx{i}; indClass(startpos:endpos)];
                    indClassCX  = [indClassCX; indClass(startpos:endpos)];
                end
            else
                 % Not enough members of THIS label to guarantee >=1 test per fold.
                if exist('AutoAdjust','var') && ~isempty(AutoAdjust) && AutoAdjust
                    % Log and return suggested K (<= nClassMem) as in original code
                    addlog('[nk_CVpartition] AutoAdjust: label=%s has only %d members (<K=%d). Returning K<=%d.', ...
                           num2str(uLabels(j)), nClassMem, K, nClassMem);
                    if ~isempty(logbuf)
                        writeLog(CVLogFile, logbuf, CVLogAppend, nperms, K, SmallBatchMaxN);
                    end
                    cv = nClassMem; 
                    return;
                else
                    % Non-interactive path (no questdlg): keep running.
                    % We skip per-fold allocation for this label and let the leftover
                    % distributor place its members across folds.
                    addlog('[nk_CVpartition] WARN: label=%s has only %d members (<K=%d). Skipping per-fold allocation; will distribute as leftovers.', ...
                           num2str(uLabels(j)), nClassMem, K);
                    % mark that nothing was put into test for this label in the loop
                    % and break out of i=1:K so we go to the leftover distribution.
                    break;
                end
            end
        end
        
        % Label-only leftovers (after the per-fold testsize slicing for this label)
        indRemAll = setdiff(indClass, indClassCX, 'stable');   % <-- no 'indRem' anymore
        
        if ~isempty(indRemAll)
            % Greedy: always place next leftover on the currently smallest TEST fold
            fold_sizes = cellfun(@numel, testidx);
            for t = 1:numel(indRemAll)
                [~, dest] = min(fold_sizes);
                testidx{dest} = [testidx{dest}; indRemAll(t)];
                fold_sizes(dest) = fold_sizes(dest) + 1;
            end
        end

        if K>1
            for i=1:K
                trainidx{i} = [trainidx{i}; ...
                    setdiff(find(Labels==uLabels(j) & ~HoldoutMask & ~ExcludeMask), ...
                            testidx{i})];
            end        
        else
            trainidx = testidx;
        end
    end

    % --- HOLDOUT (test-only) subjects: assign whole batches to a single test fold
    if any(HoldoutMask)
        % choose batch vector for grouping: prefer HarmonizerBatch (if provided), else Constraint
        if exist('HarmonizerBatch','var') && ~isempty(HarmonizerBatch)
            HB = HarmonizerBatch;
        else
            HB = Constraint;
        end
        if ~isempty(HB)
            hold_ids = find(HoldoutMask);             % indices into Labels (pre-permutation space)
            hold_batches = HB(hold_ids);              % batch IDs for holdout subjects
            [uHB, ~, grp] = unique(hold_batches);     % group by batch
            % randomize fold order once to avoid systematic bias
            foldOrder = randperm(K);
            nextFoldIdx = 1;
            for ub = 1:numel(uHB)
                ids_b = hold_ids(grp == ub);          % all subjects of this holdout batch
                % pick a fold (cycle through folds to balance overall sizes)
                f = foldOrder(nextFoldIdx);
                nextFoldIdx = nextFoldIdx + 1; if nextFoldIdx > K, nextFoldIdx = 1; end
                % assign entire batch to that fold
                testidx{f} = [testidx{f}; ids_b(:)];
                addlog('[nk_CVpartition] (perm %d) assigned HOLDOUT batch %s (n=%d) to test fold %d.', ...
                    h, list2str(uHB(ub)), numel(ids_b), f);
            end
        else
            % Fallback: no batch info available -> keep old behavior but put all holdouts in fold 1
            testidx{1} = [testidx{1}; find(HoldoutMask)];
            addlog('[nk_CVpartition] (perm %d) HOLDOUT assigned to fold 1 (no batch vector).', h);
        end
    end

    if NaNflag
        for i=1:K
            trainidx{i} = [trainidx{i}; ...
                find(~isfinite(Labels) & ~ExcludeMask)];
        end
        if any(~isfinite(Labels))
            addlog('[nk_CVpartition] (perm %d) Added %d NaN-label cases to every training fold.', h, numel(find(~isfinite(Labels))));
        end
    end

    % --- TRAIN sanitizer: ensure per-fold batch counts are 0 or >= SmallBatchMaxN
    % Use the same batch vector ComBat will see
    if exist('HarmonizerBatch','var') && ~isempty(HarmonizerBatch)
        BaseBatch = HarmonizerBatch;
    else
        BaseBatch = Constraint;
    end
    
    if ~isempty(BaseBatch)
        for i = 1:K
            tr = double(trainidx{i});
            if isempty(tr), continue; end
    
            % Count batches in this TRAIN fold
            b_tr = BaseBatch(tr);
            [uB,~,g] = unique(b_tr);
            cnt = accumarray(g,1);
            badB = uB(cnt > 0 & cnt < SmallBatchMaxN);  % batches too small in TRAIN
    
            if ~isempty(badB)
                % Identify TRAIN members to act on
                move_mask = ismember(b_tr, badB);
                bad_ids   = tr(move_mask);
    
                switch lower(TrainSmallBatchAction)
                    case 'move2test'
                        % Move all these to TEST of the same fold
                        te = double(testidx{i});
                        % Avoid duplicates in TEST; preserve order ("stable")
                        append_ids = setdiff(bad_ids, te, 'stable');
                        testidx{i}  = uint16([te(:); append_ids(:)]);
                        trainidx{i} = uint16(tr(~move_mask));
    
                        addlog('[nk_CVpartition] WARN: (perm %d, fold %d) TRAIN batches %s had < %d; moved %d sample(s) to TEST.', ...
                               h, i, list2str(badB(:)'), SmallBatchMaxN, numel(append_ids));
    
                    case 'drop'
                        % Remove these subjects from CV for this perm (TRAIN and TEST)
                        trainidx{i} = uint16(tr(~move_mask));
                        te = double(testidx{i});
                        te_keep = ~ismember(te, bad_ids);
                        testidx{i} = uint16(te(te_keep));
    
                        addlog('[nk_CVpartition] WARN: (perm %d, fold %d) Dropped %d TRAIN sample(s) from batches %s (< %d).', ...
                               h, i, numel(bad_ids), list2str(badB(:)'), SmallBatchMaxN);
    
                    otherwise
                        % Fallback: move to TEST
                        te = double(testidx{i});
                        append_ids = setdiff(bad_ids, te, 'stable');
                        testidx{i}  = uint16([te(:); append_ids(:)]);
                        trainidx{i} = uint16(tr(~move_mask));
                        addlog('[nk_CVpartition] WARN: (perm %d, fold %d) TRAIN batches %s had < %d; moved %d sample(s) to TEST (default).', ...
                               h, i, list2str(badB(:)'), SmallBatchMaxN, numel(append_ids));
                end
            end
        end
    end

    if ~isempty(Eq)
        for i=1:K
            [ removed, retained ] = nk_EqualizeHisto(Eq, Eq.Covar(rInd(trainidx{i})), ...
                                                     rInd(trainidx{i}), NM.modeflag);
            trainidxs{h,i} = uint16(retained);
            if Eq.AddRemoved2Test
                testidxs{h,i} = uint16([rInd(testidx{i}); removed]);
            else
                testidxs{h,i} = uint16(rInd(testidx{i}));
            end
        end
    else
        for i=1:K
            testidxs{h,i}  = uint16(rInd(testidx{i}));
            trainidxs{h,i} = uint16(rInd(trainidx{i}));
        end
    end

    % --- FINAL TEST-FOLD SAFETY (single-pass, no loops): consolidate batches when needed
    % Choose batch vector for checks (prefer HarmonizerBatch, else Constraint)
    if exist('HarmonizerBatch','var') && ~isempty(HarmonizerBatch)
        batchVecForCheck = HarmonizerBatch;
    else
        batchVecForCheck = Constraint;
    end
    
    if ~isempty(batchVecForCheck)
        % Build per-fold TEST views once
        te_ids_f     = cell(1,K);
        te_batches_f = cell(1,K);
        for i = 1:K
            te_ids_f{i} = double(testidxs{h,i});
            if isempty(te_ids_f{i}), te_batches_f{i} = []; else
                te_batches_f{i} = batchVecForCheck(te_ids_f{i});
            end
        end
    
        % Precompute per-fold TEST sizes for tie-breaking
        fold_sizes = cellfun(@numel, te_ids_f);
    
        % Unique batches present anywhere in the dataset (stable if available)
        try
            uB_all = unique(batchVecForCheck,'stable');
        catch
            uB_all = unique(batchVecForCheck);
        end
    
        % Single sweep over batches
        for b = 1:numel(uB_all)
            bval = uB_all(b);
            members_b = find(batchVecForCheck == bval);
            Nb = numel(members_b);
            if Nb <= 1
                % Nb==1 batches should have been globally excluded upstream; skip defensively
                continue
            end
    
            % Counts of this batch in TEST per fold
            counts = zeros(1,K);
            pos_per_fold = cell(1,K); % positions inside te_ids_f{i} for this batch
            for i = 1:K
                if isempty(te_batches_f{i}), pos_per_fold{i} = []; continue; end
                pos_i = find(te_batches_f{i} == bval);
                pos_per_fold{i} = pos_i;
                counts(i) = numel(pos_i);
            end
    
            % Compute TRAIN counts per fold for this batch
            train_counts = Nb - counts;
    
            % Violation criteria:
            %  (A) any fold has TRAIN in 1..SmallBatchMaxN-1 for this batch, OR
            %  (B) any fold has TEST singleton for this batch
            hasTrainTooSmall = any(train_counts > 0 & train_counts < SmallBatchMaxN);
            hasTestSingleton = any(counts == 1);
    
            if ~(hasTrainTooSmall || hasTestSingleton)
                continue
            end
    
            % Pick destination fold:
            % 1) fold with max existing TEST count of this batch;
            % 2) if all zero or tie, choose fold with smallest overall TEST size
            [maxc, dest] = max(counts);
            if maxc == 0
                [~, dest] = min(fold_sizes);
            else
                % break ties by smallest fold size
                ties = find(counts == maxc);
                if numel(ties) > 1
                    [~, kmin] = min(fold_sizes(ties));
                    dest = ties(kmin);
                end
            end
    
            % Gather all current TEST members of this batch across folds except dest
            move_ids = [];
            for i = 1:K
                if counts(i) > 0 && i ~= dest
                    move_ids = [move_ids; te_ids_f{i}(pos_per_fold{i})]; %#ok<AGROW>
                end
            end
    
            if isempty(move_ids)
                % Still log reason if we triggered on TRAIN<SmallBatchMaxN but batch already localized
                if hasTrainTooSmall
                    addlog(['[nk_CVpartition] WARN: TRAIN<%d detected for batch %s (perm=%d), ' ...
                            'but batch already localized to a single fold; leaving as-is.'], ...
                            SmallBatchMaxN, list2str(bval), h);
                end
                continue
            end
    
            % Remove batch members from all non-destination folds
            for i = 1:K
                if counts(i) > 0 && i ~= dest
                    keep = true(size(te_ids_f{i}));
                    keep(pos_per_fold{i}) = false;
                    te_ids_f{i}     = te_ids_f{i}(keep);
                    te_batches_f{i} = te_batches_f{i}(keep);
                    fold_sizes(i)   = numel(te_ids_f{i});
                end
            end
    
            % Append them to destination fold
            te_ids_f{dest}     = [te_ids_f{dest}; move_ids(:)];
            te_batches_f{dest} = [te_batches_f{dest}; repmat(bval, numel(move_ids), 1)];
            fold_sizes(dest)   = numel(te_ids_f{dest});
    
            addlog(['[nk_CVpartition] WARN: Consolidated batch %s into TEST fold %d (perm=%d). ' ...
                    'Moved subjectIDs=%s.'], list2str(bval), dest, h, list2str(move_ids(:)'));
        end
    
        % Write back consolidated TEST indices (cast to uint16)
        for i = 1:K
            testidxs{h,i} = uint16(te_ids_f{i});
        end
    
        % Recompute TRAIN **from TEST** on the non-excluded, non-holdout pool
        poolTrain = find(~ExcludeMask & ~HoldoutMask);
        for i = 1:K
            tr_i = setdiff(poolTrain, double(testidxs{h,i}), 'stable');
            trainidxs{h,i} = uint16(tr_i(:));
        end
    end
    % ===== Batch Reporting (triplets per fold + perm summaries) =====
    % BaseBatch must be the same vector ComBat uses (e.g., Constraint or HarmonizerBatch)
    if exist('HarmonizerBatch','var') && ~isempty(HarmonizerBatch)
        BaseBatch = HarmonizerBatch;
    else
        BaseBatch = Constraint;
    end
    
    if ~isempty(BaseBatch)
        % Enumerate batches with stable order when possible
        try
            uBatchesAll = unique(BaseBatch,'stable');
        catch
            uBatchesAll = unique(BaseBatch);
        end
        nB = numel(uBatchesAll);
        Nsubj = numel(BaseBatch);
    
        % ---- Assigned mask for this permutation (any TRAIN/TEST fold)
        assigned = false(Nsubj,1);
        for i = 1:K
            if ~isempty(trainidxs{h,i}), assigned(double(trainidxs{h,i})) = true; end
            if ~isempty(testidxs{h,i}),  assigned(double(testidxs{h,i}))  = true; end
        end
    
        % Perm-local EXCLUDED
        permExcluded = find(~assigned);
    
        % Precompute EXCLUDED counts once (same row repeated for each fold)
        if isempty(permExcluded)
            cntEx = zeros(nB,1,'uint16');
        else
            [~,locEx] = ismember(BaseBatch(permExcluded), uBatchesAll);
            cntEx = accumarray(max(locEx,0)+1,1,[nB+1,1]); cntEx = uint16(cntEx(2:end));
        end
    
        % Precompute TOTAL once (dataset histogram by batch)
        [~,locAll] = ismember(BaseBatch, uBatchesAll);
        cntTotal = accumarray(max(locAll,0)+1,1,[nB+1,1]); cntTotal = uint16(cntTotal(2:end));
    
        % Allocate 3*K + 2 rows: (TRAIN, TEST, EXCLUDED) per fold + TEST_SUM + TOTAL
        R  = zeros(3*K + 2, nB, 'uint16');
        rownames = cell(3*K + 2, 1);
    
        % Also accumulate TEST_SUM across folds (each subject appears in TEST once)
        accTest = zeros(1,nB,'uint32');
    
        for i = 1:K
            % TRAIN counts for fold i
            tr_ids = double(trainidxs{h,i});
            if isempty(tr_ids)
                cntTr = zeros(nB,1,'uint16');
            else
                [~,locTr] = ismember(BaseBatch(tr_ids), uBatchesAll);
                cntTr = accumarray(max(locTr,0)+1,1,[nB+1,1]); cntTr = uint16(cntTr(2:end));
            end
            R(3*i-2,:) = reshape(cntTr,1,[]);
    
            % TEST counts for fold i
            te_ids = double(testidxs{h,i});
            if isempty(te_ids)
                cntTe = zeros(nB,1,'uint16');
            else
                [~,locTe] = ismember(BaseBatch(te_ids), uBatchesAll);
                cntTe = accumarray(max(locTe,0)+1,1,[nB+1,1]); cntTe = uint16(cntTe(2:end));
            end
            R(3*i-1,:) = reshape(cntTe,1,[]);
            accTest = accTest + uint32(R(3*i-1,:)); % accumulate TEST over folds
    
            % EXCLUDED (perm-local) – identical row repeated for clarity
            R(3*i,:) = reshape(cntEx,1,[]);
    
            % Row names
            rownames{3*i-2} = sprintf('perm%02d_fold%02d_TRAIN',    h, i);
            rownames{3*i-1} = sprintf('perm%02d_fold%02d_TEST',     h, i);
            rownames{3*i}   = sprintf('perm%02d_fold%02d_EXCLUDED', h, i);
    
            % Optional: flag TRAIN singletons (root cause of ComBat crash)
            if any(R(3*i-2,:)==1)
                badB = uBatchesAll(R(3*i-2,:)==1);
                addlog('[nk_CVpartition] ALERT: TRAIN singleton(s) in perm=%d, fold=%d for batches=%s', ...
                       h, i, list2str(badB(:)'));
            end
        end
    
        % Append TEST_SUM and TOTAL rows (once per perm)
        R(3*K+1,:) = uint16(accTest);             rownames{3*K+1} = sprintf('perm%02d_TEST_SUM', h);
        R(3*K+2,:) = reshape(cntTotal,1,[]);      rownames{3*K+2} = sprintf('perm%02d_TOTAL',    h);
    
        % Correct sanity check: TEST_SUM + EXCLUDED == TOTAL (per batch)
        mismatch = (uint32(R(3*K+1,:)) + uint32(R(3,:))) ~= uint32(R(3*K+2,:));
        if any(mismatch)
            badCols = uBatchesAll(mismatch);
            addlog('[nk_CVpartition] WARN: TEST_SUM + EXCLUDED != TOTAL in perm=%d for batches=%s', ...
                   h, list2str(badCols(:)'));
        end
    
        % Build table
        varnames = mkBatchVarNames(uBatchesAll); % your existing helper
        T = array2table(R, 'VariableNames', varnames, 'RowNames', rownames);
    
        % Store
        if ~exist('BatchReportTables','var') || numel(BatchReportTables) < h
            BatchReportTables = cell(nperms,1);
        end
        BatchReportTables{h} = T;
    
        % Optionally expose perm-local excluded indices
        PermExcludedIdx{h,1} = uint16(permExcluded);
    end
    % ===== end reporting =====


end

cv.TrainInd = trainidxs;
cv.TestInd  = testidxs;
cv.HoldoutBatches  = HoldoutBatches;
cv.ExcludedBatches = ExcludedBatches;
cv.ExcludedIdx     = uint16(find(ExcludeMask));

%%% write log file if we collected any messages
if ~isempty(logbuf)
    writeLog(CVLogFile, logbuf, CVLogAppend, nperms, K, SmallBatchMaxN);
end

% Compute final logWritten status from the file 
if exist(CVLogFile,'file') == 2
    d = dir(CVLogFile);
    logWritten = d.bytes > 0;
else
    logWritten = false;
end

cv.LogFile    = ternary(logWritten, CVLogFile, '');
cv.LogWritten = logWritten;

if exist('BatchReportTables','var')
    cv.BatchReportTables = BatchReportTables;
else
    cv.BatchReportTables = {};
end

if exist('uBatchesAll','var')
    cv.BatchLevels = uBatchesAll;
else
    cv.BatchLevels = [];
end

if exist('PermExcludedIdx','var')
    cv.PermExcludedIdx = PermExcludedIdx;
else
    cv.PermExcludedIdx = {};
end


% Build a single stacked report (optional)
if ~isempty(BaseBatch)
    Tcat = table();
    for h = 1:nperms
        if ~isempty(BatchReportTables{h})
            Tcat = [Tcat; BatchReportTables{h}]; %#ok<AGROW>
        end
    end
    cv.BatchReportAll = Tcat;
end


end

% --- helper to stringify lists robustly (numeric/string/cellstr/categorical)
function s = list2str(v)
    if isempty(v), s = '[]'; return; end
    if isnumeric(v) || islogical(v)
        s = mat2str(v(:)');
    elseif isstring(v)
        s = "[" + strjoin(cellstr(v(:))', ", ") + "]";
        s = char(s);
    elseif iscellstr(v) || iscell(v)
        s = "[" + strjoin(cellfun(@char, v(:)', 'UniformOutput', false), ", ") + "]";
        s = char(s);
    elseif iscategorical(v)
        s = "[" + strjoin(cellstr(v(:))', ", ") + "]";
        s = char(s);
    else
        s = '[list]';
    end
end

% --- tiny ternary helper
function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end

%%% NEW: writeLog subfunction (appends or overwrites)
function writeLog(filepath, lines, doAppend, nperms, K, SmallBatchMaxN)
try
    if nargin<3 || isempty(doAppend), doAppend = true; end
    mode = ternary(doAppend && exist(filepath,'file')==2, 'a', 'w');
    fid = fopen(filepath, mode);
    if fid<0, warning('[nk_CVpartition] Could not open log file %s for writing.', filepath); return; end
    runStamp = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));  
    fprintf(fid, '=== nk_CVpartition run @ %s ===\n', runStamp);
    fprintf(fid, 'Params: nperms=%d, K=%d, SmallBatchMaxN=%d\n', nperms, K, SmallBatchMaxN);
    for k=1:numel(lines)
        fprintf(fid, '%s\n', lines{k});
    end
    fprintf(fid, '=== end ===\n\n');
    fclose(fid);
catch ME
    warning('[nk_CVpartition] Failed writing log (%s): %s', filepath, ME.message);
end
end

function varnames = mkBatchVarNames(uB)
    varnames = cell(1,numel(uB));
    for k = 1:numel(uB)
        if isnumeric(uB) || islogical(uB)
            lbl = sprintf('B_%s', mat2str(uB(k)));
        elseif isstring(uB)
            lbl = char(uB(k));
        elseif iscategorical(uB)
            lbl = char(uB(k));
        else
            lbl = 'batch';
        end
        varnames{k} = matlab.lang.makeValidName(lbl);
    end
end
