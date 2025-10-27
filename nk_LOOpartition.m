function cv = nk_LOOpartition(Labels, varargin)
% =====================================================================================================
% function cv = nk_LOOpartition(Labels, ['SilenceCVLog', tf], ['CVLogFile', path], ['CVLogAppend', tf])
% =====================================================================================================
% Leave-One-Out CV:
%  - For each subject with a finite label, make a fold where that subject
%    is TEST and all others are TRAIN.
%  - Subjects with non-finite labels (NaN/Inf) are included in TRAIN for
%    every fold (mirrors nk_CVpartition behavior).
%
% Optional name–value arguments:
%   'SilenceCVLog'  : true to suppress command-window output (default true)
%   'CVLogFile'     : full path to log file (default auto in NM.Paths.Log or pwd)
%   'CVLogAppend'   : append to existing log file (default true)
%
% Outputs:
%   cv.TrainInd, cv.TestInd : 1-by-K cell arrays of uint16 column indices
%   cv.LogFile              : path to log file if written, '' otherwise
%   cv.LogWritten           : logical flag whether any log lines were written
% =============================================================================
% NeuroMiner 1.4, (c) Nikolaos Koutsouleris, 10/2025

% ---- parse name–value args ------------------------------------------------
p = inputParser;
addParameter(p,'SilenceCVLog',true,@(x)islogical(x)||ismember(x,[0 1]));
addParameter(p,'CVLogFile','',@(x)ischar(x)||isstring(x));
addParameter(p,'CVLogAppend',true,@(x)islogical(x)||ismember(x,[0 1]));
parse(p,varargin{:});
SilenceCVLog = logical(p.Results.SilenceCVLog);
CVLogFileArg = char(p.Results.CVLogFile);
CVLogAppend  = logical(p.Results.CVLogAppend);
% ----------------------------------------------------------------------------

% ---- set up file logger (buffer -> single write) ---------------------------
logbuf = {};
% choose default log path if not provided
if ~isempty(CVLogFileArg)
    CVLogFile = CVLogFileArg;
else
    logdir = pwd;
    ts = char(datetime('now','Format','yyyyMMdd_HHmmss')); % safe for filenames
    CVLogFile = fullfile(logdir, ['LOOpartition_log_' ts '.txt']);
end
% helper to collect log lines
    function addlog(fmt, varargin)
        logbuf{end+1} = sprintf(fmt, varargin{:}); 
    end
% ----------------------------------------------------------------------------

% ---- core LOO logic --------------------------------------------------------
validMask = isfinite(Labels);
N         = numel(Labels);
K         = sum(validMask);

addlog('[nk_LOOpartition] N=%d subjects, K=%d finite labels, NaN/Inf=%d.', N, K, N-K);

trainidxs = cell(1, K);
testidxs  = cell(1, K);

if K == 0
    addlog('[nk_LOOpartition] WARNING: No finite labels found. Returning empty CV.');
    % write log (if any) and finalize flags
    if ~isempty(logbuf)
        writeLog(CVLogFile, logbuf, CVLogAppend, K, N);
    end
    cv.TrainInd   = trainidxs;
    cv.TestInd    = testidxs;
    if exist(CVLogFile,'file')==2
        d = dir(CVLogFile);  wrote = d.bytes > 0;
    else
        wrote = false;
    end
    cv.LogFile    = ternary(wrote, CVLogFile, '');
    cv.LogWritten = wrote;
    return;
end

allIdx = (1:N)'; % column vector indices
cnt = 1;

for i = 1:N
    if ~validMask(i), continue; end

    % TEST is the left-out valid subject
    testIdx  = allIdx(i);

    % TRAIN is everyone else (including NaN-label subjects)
    if i == 1
        trainIdx = allIdx(2:N);
    elseif i == N
        trainIdx = allIdx(1:N-1);
    else
        trainIdx = [allIdx(1:i-1); allIdx(i+1:N)];
    end
    trainidxs{cnt} = uint16(trainIdx);
    testidxs{cnt}  = uint16(testIdx);
    cnt = cnt + 1;
end

cv.TrainInd = trainidxs;
cv.TestInd  = testidxs;

% ---- write log (once) and expose path/flag ---------------------------------
if ~SilenceCVLog
    % optional one-line console notice (kept minimal)
    fprintf('[nk_LOOpartition] Generated %d LOO folds (N=%d; NaN=%d).\n', K, N, N-K);
end

if ~isempty(logbuf)
    writeLog(CVLogFile, logbuf, CVLogAppend, K, N);
end

if exist(CVLogFile,'file')==2
    d = dir(CVLogFile);  wrote = d.bytes > 0;
else
    wrote = false;
end
cv.LogFile    = ternary(wrote, CVLogFile, '');
cv.LogWritten = wrote;

end 

% --- helpers ---------------------------------------------------------------
function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end

function writeLog(filepath, lines, doAppend, K, N)
try
    if nargin<3 || isempty(doAppend), doAppend = true; end
    mode = 'w';
    if doAppend && exist(filepath,'file')==2
        mode = 'a';
    end
    fid = fopen(filepath, mode);
    if fid < 0
        warning('[nk_LOOpartition] Could not open log file %s for writing.', filepath);
        return;
    end
    stamp = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
    fprintf(fid, '=== nk_LOOpartition run @ %s ===\n', stamp);
    fprintf(fid, 'Params: N=%d, K=%d\n', N, K);
    for k=1:numel(lines)
        fprintf(fid, '%s\n', lines{k});
    end
    fprintf(fid, '=== end ===\n\n');
    fclose(fid);
catch ME
    warning('[nk_LOOpartition] Failed writing log (%s): %s', filepath, ME.message);
end
end
