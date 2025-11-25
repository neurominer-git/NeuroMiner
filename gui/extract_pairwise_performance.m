function [M, SD, levA, levB] = extract_pairwise_performance(P, Perf, idxPair)
% P: cell array of parameter tables per class (rows = trials, cols = params)
% Perf: vector (nTrials x 1) of performance for that measure
% idxPair: [colA, colB] indices into P{curclass}

PiA = P(:, idxPair(1));
PiB = P(:, idxPair(2));

% Ensure numeric vectors (unroll cells if needed)
if iscell(PiA), PiA = cell2mat(PiA); end
if iscell(PiB), PiB = cell2mat(PiB); end

% Unique levels (sorted)
levA = unique(PiA);
levB = unique(PiB);

% Guardrails for huge grids
MAX_CELLS = 2500;
if numel(levA)*numel(levB) > MAX_CELLS
    warning('Pairwise grid has %d cells; consider binning.', numel(levA)*numel(levB));
end

M  = nan(numel(levB), numel(levA)); % rows: B, cols: A (to match imagesc ij orientation)
SD = nan(size(M));

% Fill grid
for ia = 1:numel(levA)
    for ib = 1:numel(levB)
        mask = (PiA == levA(ia)) & (PiB == levB(ib));
        if any(mask)
            v = Perf(mask);
            M(ib, ia)  = nm_nanmean(v);
            SD(ib, ia) = nm_nanstd(v);
        end
    end
end
