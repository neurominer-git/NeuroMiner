function [cv, K, P] = nk_INDEPpartition(Groups, Labels, LGOflip, OutReps, varargin)
% =========================================================================
% [cv, K, P] = nk_INDEPpartition(Groups, Labels, LGOflip, OutReps, ...
%                                'SilenceCVLog', tf, ...
%                                'CVLogFile', path, ...
%                                'CVLogAppend', tf)
% =========================================================================
% Leave-Group-Out / Leave-Group-In partitioning.
%   LGOflip = 0  -> Leave-Group-OUT  (train: all groups except i; test: group i)
%   LGOflip = 1  -> Leave-Group-IN   (train: only group i; test: all others)
%
% Notes:
%   - Test indices exclude non-finite labels: test = (~I & isfinite(Labels)).
%   - NaN/Inf labels remain in TRAIN (mirrors CV functions).
%
% Optional name–value:
%   'SilenceCVLog'  (default true)  : suppress console prints
%   'CVLogFile'     (default auto)  : full path for the log file
%   'CVLogAppend'   (default true)  : append to existing file
%
% Outputs:
%   cv.TrainInd, cv.TestInd : OutReps-by-K cell arrays (uint16, column)
%   cv.Groups_u             : unique group identifiers (as returned by nk_MakeDummyVariables)
%   cv.LogFile              : path of the log file if written, '' otherwise
%   cv.LogWritten           : true if any log lines were written
%   K                       : number of groups (folds)
%   P                       : set to 1 (kept for compatibility)
% =========================================================================
% NeuroMiner 1.4, (c) Nikolaos Koutsouleris, 10/2025

if ~exist('OutReps','var') || isempty(OutReps), OutReps = 1; end

% ---------- optional logging args ----------
p = inputParser;
addParameter(p,'SilenceCVLog',true,@(x)islogical(x)||ismember(x,[0 1]));
addParameter(p,'CVLogFile','',@(x)ischar(x)||isstring(x));
addParameter(p,'CVLogAppend',true,@(x)islogical(x)||ismember(x,[0 1]));
parse(p,varargin{:});
SilenceCVLog = logical(p.Results.SilenceCVLog);
CVLogFileArg = char(p.Results.CVLogFile);
CVLogAppend  = logical(p.Results.CVLogAppend);

% ---------- set up buffered logger (writes once) ----------
logbuf = {};
if ~isempty(CVLogFileArg)
    CVLogFile = CVLogFileArg;
else
    ts = char(datetime('now','Format','yyyyMMdd_HHmmss')); % filename-safe
    CVLogFile = fullfile(pwd, ['INDEPpartition_log_' ts '.txt']);
end
    function addlog(fmt, varargin)
        logbuf{end+1} = sprintf(fmt, varargin{:});
    end

% ---------- core grouping ----------
[~, ~, Groups_u] = nk_MakeDummyVariables(Groups, [], 'sorted');
K = numel(Groups_u); 
P = 1;

if ~SilenceCVLog
    fprintf('[nk_INDEPpartition] Mode=%s | Groups=%d | Reps=%d\n', ...
        ternary(LGOflip,'Leave-Group-IN','Leave-Group-OUT'), K, OutReps);
end
addlog('[nk_INDEPpartition] Mode=%s | Groups=%d | Reps=%d', ...
    ternary(LGOflip,'Leave-Group-IN','Leave-Group-OUT'), K, OutReps);

trainidxs = cell(OutReps, K); 
testidxs  = cell(OutReps, K);

N = numel(Labels);
finiteMask = isfinite(Labels);

for j = 1:OutReps
    for i = 1:K
        gi = Groups_u(i);
        if LGOflip
            % Leave-Group-IN: train only this group, test all others (finite labels only)
            I = Groups == gi;
            testMask = (~I) & finiteMask;
        else
            % Leave-Group-OUT: train all except this group, test this group (finite labels only)
            I = Groups ~= gi;
            testMask = (~I) & finiteMask;
        end

        tr = uint16(find(I));                 % train (column)
        ts = uint16(find(testMask));          % test  (column)

        trainidxs{j,i} = tr;
        testidxs{j,i}  = ts;

        addlog('[rep %d] group=%s | train=%d | test=%d (finite)', ...
            j, oneval2str(gi), numel(tr), numel(ts));

        if isempty(tr)
            addlog('  WARNING: Empty TRAIN for group=%s (rep %d).', oneval2str(gi), j);
        end
        if isempty(ts)
            addlog('  WARNING: Empty TEST for group=%s (rep %d).', oneval2str(gi), j);
        end
    end
end

% ---------- assemble output ----------
cv.TrainInd = trainidxs;
cv.TestInd  = testidxs;
cv.Groups_u = Groups_u;

% ---------- write log once & expose path/flag ----------
if ~isempty(logbuf)
    writeLog(CVLogFile, logbuf, CVLogAppend, K, OutReps, LGOflip, N);
end
if exist(CVLogFile,'file') == 2
    d = dir(CVLogFile);
    wrote = d.bytes > 0;
else
    wrote = false;
end
cv.LogFile    = ternary(wrote, CVLogFile, '');
cv.LogWritten = wrote;

end 

% ---------- helpers ----------
function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end

function s = oneval2str(v)
% Robust single-value string for numeric/string/categorical
if iscategorical(v)
    v = char(v);
end
if isnumeric(v) || islogical(v)
    s = num2str(v);
elseif isstring(v)
    s = char(v);
elseif ischar(v)
    s = v;
else
    s = '[val]';
end
end

function writeLog(filepath, lines, doAppend, K, OutReps, LGOflip, N)
try
    mode = 'w';
    if doAppend && exist(filepath,'file') == 2
        mode = 'a';
    end
    fid = fopen(filepath, mode);
    if fid < 0
        warning('[nk_INDEPpartition] Could not open log file %s for writing.', filepath);
        return;
    end
    stamp = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
    fprintf(fid, '=== nk_INDEPpartition run @ %s ===\n', stamp);
    fprintf(fid, 'Params: N=%d | Groups=%d | Reps=%d | Mode=%s\n', ...
        N, K, OutReps, ternary(LGOflip,'Leave-Group-IN','Leave-Group-OUT'));
    for k = 1:numel(lines)
        fprintf(fid, '%s\n', lines{k});
    end
    fprintf(fid, '=== end ===\n\n');
    fclose(fid);
catch ME
    warning('[nk_INDEPpartition] Failed writing log (%s): %s', filepath, ME.message);
end
end
