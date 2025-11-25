function idx_exp = lift_idx(idx_orig, idx_map)
% Lift original (pre-expansion) column indices to expanded indices.
% idx_map is the cell array returned by expand_splines.
if isempty(idx_orig)
    idx_exp = [];
else
    cells = idx_map(idx_orig);
    idx_exp = unique([cells{:}]);
end