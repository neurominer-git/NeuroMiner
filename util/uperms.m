function [pInds, k_adjusted] = uperms(X, k, ulim, progressFcn)
% uperms - Generate unique random fixed-size feature subsets.
%
% Purpose
%   Generate k unique logical subset masks without replacement. This function
%   retains the historical NeuroMiner MLI interface while replacing the former
%   quadratic full-mask duplicate scan with compact fingerprint indexing.
%   An optional progress callback allows the MLI owner to publish generation
%   progress through the NM2 runtime bridge without coupling this utility to UI
%   state.
%
% Syntax
%   [pInds, k_adjusted] = uperms(X, k, ulim)
%   [pInds, k_adjusted] = uperms(X, k, ulim, progressFcn)
%
% Inputs
%   X
%       Vector or matrix defining the available units. If X is logical, only
%       true entries are treated as available units, matching the historical
%       MLI behavior. For a nonlogical vector, numel(X) units are available;
%       for a matrix, size(X,1) units are available.
%
%   k
%       Requested number of unique subsets. If fewer than k distinct subsets
%       exist, k is reduced to the exact number available.
%
%   ulim
%       Number of units selected in every subset. Must be an integer in
%       [0,n], where n is the number of available units.
%
%   progressFcn
%       Optional function handle with signature progressFcn(done,total).
%       uperms invokes it only at the same throttled progress checkpoints used
%       by the command-window counter. The callback owns any UI/bridge routing.
%
% Outputs
%   pInds
%       k_adjusted-by-n logical matrix. Each row is one unique subset and
%       contains exactly ulim true entries.
%
%   k_adjusted
%       Actual number of returned subsets.
%
% Authority and flow
%   uperms owns only random fixed-cardinality subset generation and local
%   progress emission. It does not decide which MLI features are scientifically
%   eligible and has no dependency on NM2 UI/runtime classes.
%
% Invariants
%   - Every output row contains exactly ulim selected units.
%   - No two output rows are identical.
%   - Duplicate detection is exact. Compact fingerprints are only an index:
%     a fingerprint collision is resolved by comparing the actual subset.
%   - The random sampling distribution remains uniform over fixed-size subsets
%     on the normal rejection-sampling path.
%   - The existing 3-argument call remains valid.
%
% Materialization and performance
%   Let n be the number of available features, m=min(ulim,n-ulim), and k the
%   number of requested subsets.
%
%   The historical implementation rescanned progressively larger k-by-n
%   logical matrices for every candidate, giving approximately O(n*k^2)
%   duplicate checking and repeated full-width temporary allocations.
%
%   This implementation allocates the final k-by-n logical output once.
%   Candidate generation and fingerprinting are O(k*m) in the usual
%   high-dimensional regime. Exact full-width comparison occurs only after a
%   fingerprint collision. For small combinatorial spaces requested near
%   saturation, all combinations are materialized once and sampled directly
%   to avoid rejection slowdown.
%
%   Command-window and callback progress reporting are throttled to at most
%   approximately 200 updates, so reporting does not restore an O(k) stream of
%   expensive bridge/file writes for very large k.
%
% Failure semantics
%   Invalid X, k, ulim, or progressFcn values fail explicitly. Callback errors
%   are not suppressed here; NM2 supplies a safe bridge callback whose owner
%   contains browser-progress failures.
%
% Side effects
%   Advances MATLAB's current random-number generator state through randperm
%   and reports generation progress in the MATLAB command window.
%
% Consumers and dependencies
%   Used by nk_MLInterpreter to construct unique feature perturbation masks.
%   Depends only on MATLAB built-ins.
%
% Note
%   Despite the historical name, the active MLI contract is generation of
%   unique fixed-size subsets, not ordering permutations of all elements.
%
% See also: randperm, nchoosek
%
% Original uperms concept:
%   Copyright 2010 Ged Ridgway
%   http://www.mathworks.com/matlabcentral/fileexchange/authors/27434
%
% NeuroMiner optimized MLI implementation, 2026.

%% Validate and normalize inputs
if isempty(X) || isscalar(X) || ~ismatrix(X)
    error('Input X must be a vector or matrix')
end
if nargin < 2 || isempty(k)
    error('The number of requested subsets k must be specified.')
end
if ~(isscalar(k) && isnumeric(k) && isfinite(k) && k >= 0 && k == floor(k))
    error('k must be a finite non-negative integer scalar.')
end
if nargin < 4
    progressFcn = [];
elseif ~isempty(progressFcn) && ~isa(progressFcn,'function_handle')
    error('progressFcn must be empty or a function handle.')
end

if islogical(X)
    X = find(X);
end

if isvector(X)
    n = numel(X);
else
    n = size(X,1);
end

if nargin < 3 || isempty(ulim)
    % Preserve the historical default of this implementation family.
    if isvector(X)
        ulim = size(X,1);
    else
        ulim = size(X,2);
    end
end
if ~(isscalar(ulim) && isnumeric(ulim) && isfinite(ulim) && ...
        ulim >= 0 && ulim <= n && ulim == floor(ulim))
    error('ulim must be an integer scalar between 0 and the number of available units.')
end
if n > double(intmax('uint32'))
    error('The feature universe exceeds the uint32 indexing capacity of uperms.')
end

k = double(k);
ulim = double(ulim);

%% Normalize k to the exact number of available subsets
keyWidth = min(ulim, n-ulim);
useComplement = ulim > n/2;

[totalToK, totalExceedsK] = localCombinationCountCapped(n, keyWidth, k);
if ~totalExceedsK
    k = min(k, totalToK);
end
k_adjusted = k;

if k == 0
    pInds = false(0,n);
    return
end

if keyWidth == 0
    if useComplement
        pInds = true(1,n);
    else
        pInds = false(1,n);
    end
    k_adjusted = 1;
    localReportProgress(progressFcn, 1, 1, true);
    return
end

%% Small-space near-saturation path
ENUM_MAX_COMBINATIONS = 200000;
ENUM_MAX_ELEMENTS = 5000000;

[enumCount, enumCountExceeded] = ...
    localCombinationCountCapped(n, keyWidth, ENUM_MAX_COMBINATIONS);

canEnumerate = ~enumCountExceeded && ...
               enumCount > 0 && ...
               k >= 0.20 * enumCount && ...
               enumCount * keyWidth <= ENUM_MAX_ELEMENTS;

if canEnumerate
    localReportProgress(progressFcn, 0, k, false);
    allKeys = uint32(nchoosek(1:n, keyWidth));
    if k < enumCount
        take = randperm(enumCount, k);
        keys = allKeys(take,:);
    else
        keys = allKeys;
    end
    pInds = localMaterializeMasks(keys, k, n, useComplement);
    localReportProgress(progressFcn, k, k, true);
    return
end

%% High-dimensional path: compact fingerprint index + exact collision check
if useComplement
    pInds = true(k,n);
else
    pInds = false(k,n);
end

fingerprintRows = containers.Map('KeyType','char','ValueType','any');
weights = 1:keyWidth;
accepted = 0;
progressStep = max(1, ceil(k / 200));
localReportProgress(progressFcn, accepted, k, false);

while accepted < k
    pos = sort(uint32(randperm(n, keyWidth)));
    fp = localFingerprint(pos, weights);

    isDuplicate = false;
    if isKey(fingerprintRows, fp)
        candidateRows = fingerprintRows(fp);
        candidateRows = candidateRows(:).';
        for rr = candidateRows
            if localSubsetEqualsRow(pInds, rr, pos, useComplement)
                isDuplicate = true;
                break
            end
        end
    end

    if isDuplicate
        continue
    end

    accepted = accepted + 1;
    if useComplement
        pInds(accepted, double(pos)) = false;
    else
        pInds(accepted, double(pos)) = true;
    end

    if isKey(fingerprintRows, fp)
        fingerprintRows(fp) = [fingerprintRows(fp), accepted];
    else
        fingerprintRows(fp) = accepted;
    end

    if accepted == k || mod(accepted, progressStep) == 0
        localReportProgress(progressFcn, accepted, k, accepted == k);
    end
end

end

function fp = localFingerprint(pos, weights)
% Compact deterministic fingerprint for lookup only.
dpos = double(pos);
mid = pos(ceil(numel(pos)/2));
s1 = sum(dpos);
s2 = sum(dpos .* weights);
fp = sprintf('%u|%u|%u|%.0f|%.0f', pos(1), mid, pos(end), s1, s2);
end

function tf = localSubsetEqualsRow(pInds, rowIndex, pos, useComplement)
% Exact subset comparison used only after a fingerprint collision.
if useComplement
    existing = find(~pInds(rowIndex,:));
else
    existing = find(pInds(rowIndex,:));
end
tf = numel(existing) == numel(pos) && ...
     all(uint32(existing(:).') == pos);
end

function pInds = localMaterializeMasks(keys, k, n, useComplement)
% Materialize the full logical masks exactly once from compact subset keys.
if useComplement
    pInds = true(k,n);
    for r = 1:k
        pInds(r, double(keys(r,:))) = false;
    end
else
    pInds = false(k,n);
    for r = 1:k
        pInds(r, double(keys(r,:))) = true;
    end
end
end

function [count, exceeded] = localCombinationCountCapped(n, m, cap)
% Compute nchoosek(n,m) exactly while it is <= cap.
m = min(m, n-m);
count = 1;
exceeded = false;
if m == 0
    return
end
for j = 1:m
    count = round(count * (n-m+j) / j);
    if count > cap
        count = cap + 1;
        exceeded = true;
        return
    end
end
end

function localReportProgress(progressFcn, done, total, finished)
% Report subset-generation progress to the CLI and optional caller callback.
%
% No NM2 bridge/UI dependency belongs here. The caller owns that routing.
if finished
    fprintf('\rCreating unique perms: %6.0f / %6.0f\n', done, total);
else
    fprintf('\rCreating unique perms: %6.0f / %6.0f', done, total);
end
if ~isempty(progressFcn)
    progressFcn(done, total);
end
end
