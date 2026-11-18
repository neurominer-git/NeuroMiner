function [txt, outFile] = nm_train_template_export_methods_summary(orch, outFile, ctx)
% nm_train_template_export_methods_summary  Export a human-readable summary of configured training-template methods.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

if nargin < 2 || isempty(outFile), outFile = pwd; end
if nargin < 3 || isempty(ctx), ctx = struct(); end %#ok<NASGU>
if exist(outFile,'dir') == 7
    outFile = fullfile(outFile, ['NMTrainTemplate_MethodsSummary_' datestr(now,'yyyymmdd_HHMMSS') '.txt']);
end
[parentDir,~,ext] = fileparts(outFile);
if isempty(ext), outFile = [outFile '.txt']; end
if ~isempty(parentDir) && exist(parentDir,'dir') ~= 7, mkdir(parentDir); end
state = orch.menuState();
audit = state.audit;
canvas = state.canvas;
txt = orch.methodsSummary(state, canvas, audit);
fid = fopen(outFile,'w');
if fid < 0, error('NMTrainTemplateMethodsSummary:writeFile','Could not write %s.', outFile); end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, txt, 'char');
end
