function [M, SD, levA, levB] = extract_pairwise_grid(P, Perf, idxPair)
% P: params matrix or cell array (rows=trials, cols=params)
% Perf: nTrials x 1 (or vector)
% idxPair: [colA colB]

% Get columns A,B as numeric vectors
if iscell(P)
    colA = P(:, idxPair(1)); colB = P(:, idxPair(2));
    if iscell(colA), colA = cell2mat(colA); end
    if iscell(colB), colB = cell2mat(colB); end
else
    colA = P(:, idxPair(1)); colB = P(:, idxPair(2));
end

levA = unique(colA); levB = unique(colB);

% guard for huge grids
if numel(levA)*numel(levB) > 2500
    warning('Pairwise grid has %d cells; consider binning.', numel(levA)*numel(levB));
end

M  = nan(numel(levB), numel(levA)); % rows: B, cols: A
SD = nan(size(M));
for ia = 1:numel(levA)
    for ib = 1:numel(levB)
        mask = (colA == levA(ia)) & (colB == levB(ib));
        if any(mask)
            v = Perf(mask);
            M(ib, ia)  = nm_nanmean(v);
            SD(ib, ia) = nm_nanstd(v);
        end
    end
end