function NM = nk_UpdateNMModalityInfo(NM, varind, info)
% nk_UpdateNMModalityInfo
% Store lightweight modality metadata in the canonical DataIO provenance slot.
%
% Canonical location:
%   NM.datadescriptor{varind}.input_settings.modalityInfo
%
% This helper intentionally does not load feature data and does not modify
% legacy modality fields other than ensuring the metadata slot exists.

if nargin < 1 || isempty(NM), NM = struct(); end
if nargin < 2 || isempty(varind), error('nk_UpdateNMModalityInfo:missingIndex', 'A modality index is required.'); end
if nargin < 3 || isempty(info), info = NMModalityInfoTools.emptyInfo(); end

if ~isfield(NM,'datadescriptor') || isempty(NM.datadescriptor)
    NM.datadescriptor = cell(1,varind);
elseif numel(NM.datadescriptor) < varind
    NM.datadescriptor{varind} = [];
end

if isempty(NM.datadescriptor{varind}) || ~isstruct(NM.datadescriptor{varind})
    NM.datadescriptor{varind} = struct();
end
if ~isfield(NM.datadescriptor{varind}, 'input_settings') || ~isstruct(NM.datadescriptor{varind}.input_settings)
    NM.datadescriptor{varind}.input_settings = struct();
end

info.modalityIndex = double(varind);
if ~isfield(info,'schemaVersion') || isempty(info.schemaVersion)
    info.schemaVersion = 1;
end
if ~isfield(info,'createdAt') || isempty(info.createdAt)
    info.createdAt = datestr(now, 30);
end

NM.datadescriptor{varind}.input_settings.modalityInfo = info;
end
