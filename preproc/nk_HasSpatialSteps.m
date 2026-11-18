function tf = nk_HasSpatialSteps(PREPROC)
% nk_HasSpatialSteps - True if a subject-specific spatial chain is configured.
steps = nk_NormalizeSpatialSteps(PREPROC);
tf = ~isempty(steps);
end
