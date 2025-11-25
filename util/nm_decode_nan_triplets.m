function out = nm_decode_nan_triplets(in)
% Recursively decode triplet structs produced by nm_encode_nan_triplets.

if isstruct(in) && isfield(in,'fmt') && isequal(in.fmt,'triplet_nan')
    sz = double(in.sz);
    out = NaN(sz);
    if ~isempty(in.idx_i)
        lin = sub2ind(sz, double(in.idx_i), double(in.idx_j));
        out(lin) = in.vals;
    end
elseif iscell(in)
    out = in;
    for k = 1:numel(in)
        if ~isempty(in{k})
            out{k} = nm_decode_nan_triplets(in{k});
        end
    end
elseif isstruct(in)
    out = in;
    fns = fieldnames(in);
    for ii = 1:numel(in)
        for jj = 1:numel(fns)
            fn = fns{jj};
            out(ii).(fn) = nm_decode_nan_triplets(in(ii).(fn));
        end
    end
else
    out = in;
end