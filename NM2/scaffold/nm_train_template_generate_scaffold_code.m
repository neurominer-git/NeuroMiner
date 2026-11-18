function out = nm_train_template_generate_scaffold_code(NM, outDir, ctx)
% nm_train_template_generate_scaffold_code  Generate scaffold files that validate and replay the current training-template configuration.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

if nargin < 1 || isempty(NM), NM = struct(); end
if nargin < 2 || isempty(outDir)
    outDir = fullfile(pwd, 'NM_train_template_exports', ['nm_train_template_scaffold_' datestr(now,'yyyymmdd_HHMMSS')]);
end
if nargin < 3 || isempty(ctx), ctx = struct(); end
if ~exist(outDir,'dir'), mkdir(outDir); end

if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam)
    try
        active = 1;
        if isfield(NM,'analysis') && iscell(NM.analysis) && ~isempty(NM.analysis) && ...
                isfield(NM.analysis{1},'params') && isfield(NM.analysis{1}.params,'TrainParam')
            NM.TrainParam = NM.analysis{1}.params.TrainParam;
        end
        orch = NMTrainTemplateOrchestrator.fromNM(NM, active, ctx);
        NM = orch.toNM(NM, ctx);
    catch ME
        error('nm_train_template_generate_scaffold_code:noTrainParam', ...
            'Could not materialize NM.TrainParam for scaffold export: %s', ME.message);
    end
end

apiOut = nm_train_template_generate_api_reconstruction_code(NM, outDir, ctx);
readmeFile = fullfile(outDir, 'README_train_template_scaffold.txt');
[validateOk, validateReport] = run_nm_train_template_scaffold(NM, 'Mode','validate', 'Context',ctx);
local_write_text(readmeFile, local_readme_text(validateReport, apiOut));

files = {'build_nm_train_template_from_api.m', 'README_train_template_scaffold.txt'};
out = struct('ok',true, ...
    'message','MATLAB training-template API scaffold exported.', ...
    'exportDir',outDir,'apiFile',apiOut.apiFile,'readmeFile',readmeFile, ...
    'files',{files},'validateOk',validateOk, ...
    'auditSummary',validateReport.auditSummary,'api',apiOut);
end

function txt = local_readme_text(validateReport, apiOut)
% Export packaging is separate from P12A source-generation semantics.
L = { ...
'NeuroMiner training-template MATLAB scaffold'
'============================================'
''
'Generated script: build_nm_train_template_from_api.m'
''
'Add NM2 to the MATLAB path and load an imported dataset into NM.'
'  [NMconfigured, report] = build_nm_train_template_from_api(NM);'
'Existing TrainParam settings are replaced in NMconfigured, not in NM.'
'Check report.ok; save NMconfigured separately if needed.'
'This configures training; it does not train or regenerate CV folds.'
''
'Use compatible modalities, labels, subject order and covariate columns.'
'PRIVACY: The generated source may include participant-derived values.'
'Review it before sharing; the dataset and CV fold matrices are not packaged.'
''
'Inspect each configured module using its cli_configureHelp() or configSpec().'
['Preprocessing steps: ' num2str(apiOut.nPreprocSteps)]
['Configuration validation: ' validateReport.auditSummary.displayText]};
txt = strjoin(L,newline);
end

function local_write_text(path, txt)
% local_write_text  Perform the local write text step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

txt = local_ascii_mfile_text(txt);
fid = fopen(path, 'w');
if fid < 0, error('nm_train_template_generate_scaffold_code:writeFile', 'Could not write %s.', path); end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, uint8(txt), 'uint8');
end

function txt = local_ascii_mfile_text(txt)
% local_ascii_mfile_text  Perform the local ascii mfile text step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

if isstring(txt), txt = char(txt); end
if isempty(txt), return; end
repl = {char(65279), ''; char(160), ' '; char(8239), ' '; char(8201), ' '; char(8203), ''; ...
    char(8211), '-'; char(8212), '-'; char(8216), ''''; char(8217), ''''; ...
    char(8220), '"'; char(8221), '"'; char(8230), '...'};
for i = 1:size(repl,1), txt = strrep(txt, repl{i,1}, repl{i,2}); end
mask = double(txt) > 127;
txt(mask) = ' ';
end
