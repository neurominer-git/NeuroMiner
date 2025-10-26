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
parse(p,varargin{:});
argSmallBatchMaxN = p.Results.SmallBatchMaxN;
argSilenceCVLog   = p.Results.SilenceCVLog;
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

% ---------- determine thresholds / log flags with priority ----------
SmallBatchMaxN = 5;
SilenceCVLog   = false;

if ~isempty(argSmallBatchMaxN), SmallBatchMaxN = argSmallBatchMaxN; end
if ~isempty(argSilenceCVLog),   SilenceCVLog   = argSilenceCVLog;   end

if isempty(argSmallBatchMaxN) && ~isempty(Eq) && isstruct(Eq) && isfield(Eq,'SmallBatchMaxN')
    if ~isempty(Eq.SmallBatchMaxN), SmallBatchMaxN = Eq.SmallBatchMaxN; end
end
if isempty(argSilenceCVLog) && ~isempty(Eq) && isstruct(Eq) && isfield(Eq,'SilenceCVLog')
    if ~isempty(Eq.SilenceCVLog),   SilenceCVLog   = logical(Eq.SilenceCVLog); end
end
try
    if isempty(argSmallBatchMaxN) && isfield(NM,'CV') && isfield(NM.CV,'SmallBatchMaxN')
        if ~isempty(NM.CV.SmallBatchMaxN), SmallBatchMaxN = NM.CV.SmallBatchMaxN; end
    end
    if isempty(argSilenceCVLog) && isfield(NM,'CV') && isfield(NM.CV,'SilenceCVLog')
        if ~isempty(NM.CV.SilenceCVLog),   SilenceCVLog   = logical(NM.CV.SilenceCVLog); end
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
if ~isempty(uConstraint)
    uConstrainTrain = setdiff(uConstraint,union(HoldoutBatches,ExcludedBatches,'stable'),'stable');
    mCTrain = numel(uConstrainTrain);
else
    uConstrainTrain = []; mCTrain = 1;
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

    % columns (constraint levels) that have all labels present
    goodCols = all(C>0, 1);

    if any(goodCols)
        % keep only constraint levels that support all labels
        uConstrainTrainEff = uConstrainTrain(goodCols);
        Cgood = C(:,goodCols);
        minC  = min(Cgood,[],2);

        if any(~goodCols)
            addlog(['[nk_CVpartition] WARN: %d/%d constraint level(s) removed from ' ...
                    'constraint-balanced sampling because at least one label is missing.'], ...
                    sum(~goodCols), numel(uConstraintTrain));
        end
    else
        % no constraint level has all labels -> fall back to label-only
        uConstrainTrainEff = [];  % disable constraint-balanced sampling
        minC = [];
        addlog(['[nk_CVpartition] WARN: No constraint level contains all labels in the training pool; ' ...
                'falling back to label-only stratification.']);
    end
else
    uConstrainTrainEff = [];
    minC = [];
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
            indClass = [];
            for hu=1:mCTrain
                indClassX = find(Labels==uLabels(j) & ...
                                 Constraint==uConstrainTrainEff(hu) & ...
                                 ~HoldoutMask & ~ExcludeMask);
                % defensive clamp against rare shrinkage
                takeN = min(minC(j), numel(indClassX));
                if takeN > 0
                    indClass  = [indClass; indClassX(1:takeN)];
                end
            end
            indRem = setdiff(indLabels,indClass);
            ConstrXClass = Constraint(indClass);
            if (numel(ConstrXClass)/K) < numel(uConstrainTrainEff)
                CXfl = true;
                addlog('[nk_CVpartition] (perm %d) Constraint cells < K for label=%g; distributing left-overs.', h, uLabels(j));
            else
                CXfl = false;
            end
        else
            indClass = indLabels;
            indRem = [];
        end
        
        nClassMem = length(indClass);
        testsize = floor(nClassMem/K);

        for i=1:K
            if testsize>0
                if ~isempty(uConstrainTrainEff)
                    for hu = 1:mCTrain
                        indC = find(ConstrXClass == uConstrainTrainEff(hu));
                        testsizeC = ~CXfl * floor(numel(indC)/K) + CXfl * 1;
                        startpos = (i-1)*testsizeC + 1;
                        endpos   = i*testsizeC;
                        if CXfl
                            endpos   = min(endpos, numel(indC));
                            startpos = min(startpos,numel(indC));
                            if startpos <= endpos
                                addlog('[nk_CVpartition] (perm %d, fold %d) adding left-over test subjects (%d) for a constraint cell.', ...
                                       h, i, max(0,endpos-startpos+1));
                            end
                        end
                        indCx = indC(startpos:endpos);
                        testidx{i} = [testidx{i}; indClass(indCx)];
                        indClassCX  = [indClassCX; indClass(indCx)];
                    end
                else
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
        
        % Distribute any remaining members of this label across folds.
        % This includes: (a) leftovers after pre-assignment, and (b) the whole
        % class if we skipped per-fold allocation because nClassMem < K.
        indRemAll = unique([indRem; setdiff(indClass, indClassCX)], 'stable');
        
        if ~isempty(indRemAll)
            cnt = numel(indRemAll); 
            pInd = [];
            cntK = min(cnt, K);
            while cnt > 0
                p = randperm(K);
                pInd = [pInd p(1:cntK)];
                cnt = cnt - cntK;
                cntK = min(cnt, K);
            end
            for ii = 1:numel(indRemAll)
                testidx{pInd(ii)} = [testidx{pInd(ii)}; indRemAll(ii)];
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

    % --- FINAL TEST-FOLD SAFETY: no 1-sample batches in TEST
    % Use the batch vector ComBat uses (fallback to Constraint if that's it)
    if exist('HarmonizerBatch','var') && ~isempty(HarmonizerBatch)
        batchVecForCheck = HarmonizerBatch;
    else
        batchVecForCheck = Constraint;
    end
    
    if ~isempty(batchVecForCheck)
        for i = 1:K
            te_ids = double(testidxs{h,i});         % subject IDs in TEST
            if isempty(te_ids), continue; end
            te_batches = batchVecForCheck(te_ids);
            [uB, ~, ib] = unique(te_batches);
            cnt = accumarray(ib, 1);
            if any(cnt == 1)
                badB = uB(cnt == 1);
                addlog('[nk_CVpartition] ERROR: TEST singleton(s) in perm=%d, fold=%d. Batches=%s | counts=%s', ...
                       h, i, list2str(badB(:)'), mat2str(cnt(cnt==1)'));
                if ~isempty(logbuf)
                    writeLog(CVLogFile, logbuf, CVLogAppend, nperms, K, SmallBatchMaxN);
                end
                logPathMsg = strrep(CVLogFile, '\', '/');
                error('nk_CVpartition:SingletonBatchInTest', ...
                      'Testing fold has 1-sample batch(es): perm=%d, fold=%d. See log: %s', ...
                      h, i, logPathMsg);
            end
        end
    end

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