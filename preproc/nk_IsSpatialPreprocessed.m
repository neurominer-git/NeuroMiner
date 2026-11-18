function tf = nk_IsSpatialPreprocessed(inp, modal)
% nk_IsSpatialPreprocessed - Robust reader for subject-spatial precompute state.
%
% New code should use inp.isSpatialPreprocessed. The legacy inp.issmoothed
% fallback is read-only compatibility for old saved containers.

tf = false;
if nargin < 2 || isempty(modal)
    modal = 1;
end

if isfield(inp,'isSpatialPreprocessed') && ~isempty(inp.isSpatialPreprocessed)
    vals = inp.isSpatialPreprocessed;
elseif isfield(inp,'issmoothed') && ~isempty(inp.issmoothed)
    vals = inp.issmoothed;
else
    return
end

if isscalar(vals)
    tf = logical(vals);
elseif numel(vals) >= modal
    tf = logical(vals(modal));
else
    tf = any(logical(vals(:)));
end
end
