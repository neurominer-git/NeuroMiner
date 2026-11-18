function info = nk_GetNMModalityInfo(NM, varind, opts)
% nk_GetNMModalityInfo
% Compatibility reader for lightweight modality metadata.
%
% Behavior:
%   - reads NM.datadescriptor{i}.input_settings.modalityInfo if present;
%   - otherwise derives lightweight fallback information from the NM structure;
%   - scans in-memory numeric matrices for NaN/Inf, but never loads external feature matrices.
%
% Usage:
%   info  = nk_GetNMModalityInfo(NM, 1);
%   infos = nk_GetNMModalityInfo(NM);

if nargin < 2 || isempty(varind)
    n = NMModalityInfoTools.numModalities(NM);
    varind = 1:n;
end
if nargin < 3, opts = struct(); end

if numel(varind) > 1
    tmpl = NMModalityInfoTools.emptyInfo();
    info = repmat(tmpl, 1, numel(varind));
    for i = 1:numel(varind)
        info(i) = NMModalityInfoTools.fromNM(NM, varind(i), opts);
    end
else
    info = NMModalityInfoTools.fromNM(NM, varind, opts);
end
end
