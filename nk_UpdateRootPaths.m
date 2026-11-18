function [NM, report] = nk_UpdateRootPaths(NM, AnalVec, NewRootDir, opts)
% nk_UpdateRootPaths  Update stored root paths for one or more NM analyses.
%
%   NM = nk_UpdateRootPaths(NM, AnalVec, NewRootDir) preserves the legacy
%   behavior: NewRootDir is the new parent directory that contains the
%   existing per-analysis folder name. If NewRootDir is omitted or invalid,
%   the legacy directory selector is opened, and a summary dialog is shown.
%
%   [NM, report] = nk_UpdateRootPaths(..., opts) additionally returns a
%   fixed-schema report. opts.showDialog=false suppresses msgbox output for
%   browser/API callers. The function does not create directories; the new
%   parent and resolved analysis folders must already exist.

if nargin < 4 || isempty(opts), opts = struct(); end
showDialog = true;
if isstruct(opts) && isfield(opts,'showDialog') && ~isempty(opts.showDialog)
    showDialog = logical(opts.showDialog);
elseif nargout > 1
    showDialog = false;
end

report = struct('ok',false, 'message','', ...
    'succeededIndices',[], 'succeededIds',{{}}, ...
    'failedIndices',[], 'failedIds',{{}}, 'failedMessages',{{}}, ...
    'newParentDir','', 'newRootDirs',{{}});

if ~isstruct(NM) || ~isfield(NM,'analysis') || isempty(NM.analysis) || ~iscell(NM.analysis)
    report.message = 'No analyses found in NM structure.';
    if showDialog, fprintf('\n%s\n', report.message); end
    return;
end

if ~exist('NewRootDir','var') || isempty(NewRootDir) || exist(char(string(NewRootDir)),'dir') ~= 7
    if exist('nk_DirSelector','file') == 2
        NewRootDir = nk_DirSelector('Update analyses'' root paths');
    else
        NewRootDir = '';
    end
end
NewRootDir = char(string(NewRootDir));
report.newParentDir = NewRootDir;
if isempty(NewRootDir) || exist(NewRootDir,'dir') ~= 7
    report.message = sprintf('New analysis parent directory does not exist: %s', NewRootDir);
    if showDialog, msgbox(report.message); end
    return;
end

if ~exist('AnalVec','var') || isempty(AnalVec)
    AnalVec = 1:numel(NM.analysis);
end
AnalVec = unique(round(double(AnalVec(:)')));
AnalVec = AnalVec(isfinite(AnalVec) & AnalVec >= 1 & AnalVec <= numel(NM.analysis));
if isempty(AnalVec)
    report.message = 'No valid analysis index was supplied.';
    if showDialog, msgbox(report.message); end
    return;
end

for j = 1:numel(AnalVec)
    analind = AnalVec(j);
    try
        if isempty(NM.analysis{analind}) || ~isstruct(NM.analysis{analind})
            error('nk_UpdateRootPaths:badAnalysisEntry', 'NM.analysis{%d} is empty or not a struct.', analind);
        end
        A = NM.analysis{analind};
        oldRoot = local_char_field(A, 'rootdir', '');
        [~, analdir] = fileparts(oldRoot);
        if isempty(analdir)
            analdir = sprintf('NM_ID%s_A%d_%s', local_char_field(NM,'id',''), analind, local_char_field(A,'id',sprintf('Analysis_%d',analind)));
        end
        NewAnalDir = fullfile(NewRootDir, analdir);
        if exist(NewAnalDir,'dir') ~= 7
            error('nk_UpdateRootPaths:missingAnalysisDir', 'Resolved analysis directory does not exist: %s', NewAnalDir);
        end

        A.parentdir = NewRootDir;
        A.rootdir = NewAnalDir;
        A.logfile = fullfile(NewAnalDir, ['NM_Analysis' local_char_field(A,'id',sprintf('Analysis_%d',analind)) '.log']);
        paramBase = '';
        if isfield(A,'paramfile') && ~isempty(A.paramfile)
            [~, paramBase] = fileparts(char(string(A.paramfile)));
        end
        if isempty(paramBase)
            paramBase = sprintf('NM_Analysis_%s_params', local_char_field(A,'id',sprintf('Analysis_%d',analind)));
        end
        A.paramdir = fullfile(NewAnalDir, 'params');
        A.paramfile = fullfile(A.paramdir, [paramBase '.mat']);

        algostr = local_algorithm_string(A);
        if ~isempty(algostr) && isfield(A,'GDdims') && iscell(A.GDdims)
            for ii = 1:numel(A.GDdims)
                if isstruct(A.GDdims{ii})
                    A.GDdims{ii}.RootPath = fullfile(NewAnalDir, algostr);
                end
            end
        end

        if ~isempty(algostr) && isfield(A,'OOCV') && iscell(A.OOCV)
            for ii = 1:numel(A.OOCV)
                if isstruct(A.OOCV{ii})
                    A.OOCV{ii}.RootPath = fullfile(NewAnalDir, algostr, sprintf('OOCV_%g',ii));
                end
            end
        end

        NM.analysis{analind} = A;
        report.succeededIndices(end+1) = analind; %#ok<AGROW>
        report.succeededIds{end+1} = local_char_field(A,'id',sprintf('Analysis_%d',analind)); %#ok<AGROW>
        report.newRootDirs{end+1} = NewAnalDir; %#ok<AGROW>
    catch ME
        report.failedIndices(end+1) = analind; %#ok<AGROW>
        if analind <= numel(NM.analysis) && isstruct(NM.analysis{analind})
            report.failedIds{end+1} = local_char_field(NM.analysis{analind},'id',sprintf('Analysis_%d',analind)); %#ok<AGROW>
        else
            report.failedIds{end+1} = sprintf('Analysis_%d', analind); %#ok<AGROW>
        end
        report.failedMessages{end+1} = sprintf('%s: %s', ME.identifier, ME.message); %#ok<AGROW>
    end
end

report.ok = isempty(report.failedIndices) && ~isempty(report.succeededIndices);
report.message = local_report_message(report);
if showDialog
    msgbox(report.message);
end
end

function txt = local_char_field(S, fieldName, defaultValue)
txt = defaultValue;
if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
    txt = char(string(S.(fieldName)));
end
end

function algostr = local_algorithm_string(A)
algostr = '';
if isstruct(A) && isfield(A,'params') && isstruct(A.params) && isfield(A.params,'TrainParam') && ...
        isstruct(A.params.TrainParam) && isfield(A.params.TrainParam,'SVM') && ...
        isstruct(A.params.TrainParam.SVM) && isfield(A.params.TrainParam.SVM,'prog') && ...
        ~isempty(A.params.TrainParam.SVM.prog)
    algostr = char(string(A.params.TrainParam.SVM.prog));
end
end

function msg = local_report_message(report)
parts = {};
if ~isempty(report.succeededIds)
    parts{end+1} = sprintf('The following analyses have been successfully adjusted to the new root directory:\n%s', ...
        strjoin(report.succeededIds, newline)); %#ok<AGROW>
end
if ~isempty(report.failedIds)
    failRows = cell(1,numel(report.failedIds));
    for i = 1:numel(report.failedIds)
        if i <= numel(report.failedMessages)
            failRows{i} = sprintf('%s — %s', report.failedIds{i}, report.failedMessages{i});
        else
            failRows{i} = report.failedIds{i};
        end
    end
    parts{end+1} = sprintf('The following analyses could not be adjusted to the new root directory:\n%s', ...
        strjoin(failRows, newline)); %#ok<AGROW>
end
if isempty(parts)
    msg = 'No analysis root paths were updated.';
else
    msg = strjoin(parts, [newline newline]);
end
end
