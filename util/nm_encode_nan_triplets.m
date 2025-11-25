function out = nm_encode_nan_triplets(in)
% Recursively encode NaN-heavy numeric matrices into triplet structs.
% Heuristic: encode if NaNs dominate and array is big enough.

NAN_DOM_THRESHOLD = 0.5;   % encode when (nnan / numel) > 0.5
MIN_ELEMS = 1e4;           % avoid small arrays

if isnumeric(in)
    if ~ismatrix(in) || isempty(in)
        out = in; return;
    end
    n = numel(in);
    if n < MIN_ELEMS
        out = in; return;
    end
    isn = isnan(in);
    nn_obs = n - nnz(isn);
    if nn_obs == 0
        % all NaNs: store only size
        out = struct('idx_i',[],'idx_j',[],'vals',[],'sz',size(in), ...
                     'fmt','triplet_nan');
        return
    end
    if (nnz(isn) / n) > NAN_DOM_THRESHOLD
        [idx_i, idx_j] = find(~isn);
        vals = in(~isn);
        out = struct('idx_i',int32(idx_i), 'idx_j',int32(idx_j), ...
                     'vals',vals, 'sz',size(in), 'fmt','triplet_nan');
    else
        out = in;
    end
elseif iscell(in)
    out = in;
    for k = 1:numel(in)
        if ~isempty(in{k})
            out{k} = nm_encode_nan_triplets(in{k});
        end
    end
elseif isstruct(in)
    out = in;
    fns = fieldnames(in);
    for ii = 1:numel(in)
        for jj = 1:numel(fns)
            fn = fns{jj};
            out(ii).(fn) = nm_encode_nan_triplets(in(ii).(fn));
        end
    end
else
    out = in;
end