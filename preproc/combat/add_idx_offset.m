function idx_map = add_idx_offset(idx, label_idx)

nL = numel(label_idx);
idx_map = cell(1, nL + numel(idx));
idx_map(1:nL) = num2cell(label_idx);  
for i = 1:numel(idx)
    idx_map{i+nL} = idx{i} + nL;
end
