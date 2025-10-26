function [data_ind, train_ind, nP, nA] = nk_ParamReplicatorNew(P, PXopt, PREPROC, nA)
% ==========================================================================
% nk_ParamReplicator
% Build indices that point from the *overall* optimized parameter array
% (PXopt; may include constant columns) to the *trained* parameter shelves
% (TrainedParam) for each preprocessing step in the pipeline.
%
% KEY CONTRACT (important for correctness)
% ---------------------------------------
% • P.opt  : matrix of *trained* parameter combinations (nU x nPz). It
%            contains ONLY NON-CONSTANT parameter columns, in the pipeline’s
%            column order used during training.
% • PXopt  : matrix of all parameter combinations (nP x ?). It MAY CONTAIN
%            CONSTANT columns. Its non-constant columns are in the SAME ORDER
%            as P.opt (so that removing PXopt’s constant columns yields a
%            column-wise comparable matrix to P.opt).
% • P.steps: 1 x nPz vector. P.steps(j) is the pipeline step index (zz) at
%            which the j-th (non-constant) parameter column in P.opt becomes
%            active.
%
% WHAT THIS FUNCTION RETURNS
% --------------------------
% • data_ind (nP x 1):
%      For each row of PXopt, the row index u into P.opt it maps to.
% • train_ind (nP x nA):
%      For each row of PXopt and each pipeline step zz, which trained shelf
%      index to use when indexing TrainedParam{zz}.
%
% HOW THE INDICES ARE BUILT
% -------------------------
% Part 1) From P.opt and P.steps we compute a cumulative, per-step index:
%         indA(u,zz) = groupID of P.opt(u, J(zz)), with
%         J(zz) = { j | P.steps(j) <= zz }.
%         This yields shelf counts that reflect products of levels introduced
%         up to step zz (e.g., 2 → 6 → 6 → 12 → 12 → 60 → 60).
%
% Part 2) We map PXopt rows to P.opt rows by FIRST removing *only* PXopt’s
%         constant columns (because P.opt already removed them). The reduced
%         PXc must then have the same number of columns as P.opt. We then
%         row-match PXc to P.opt and copy the corresponding per-step indices
%         from indA into train_ind.
%
% NOTE: We do NOT need any command-string special cases (e.g., 'spatialfilter'):
%       P.steps fully specifies when each parameter column is active.
%
% ==========================================================================
% (c) Nikolaos Koutsouleris, 2016
% Robustness & documentation pass: 2025-10-03
% ==========================================================================

% ------------------------------
% 0) Dimensions and trivial case
% ------------------------------
nP = size(PXopt, 1);        % rows in the overall parameter grid (may include dups)
emptfl = true;              % assume no hyperparameterized columns unless P is provided
nU = 1;                     % rows in P.opt (trained unique combos)
nPz = 0;                    % non-constant parameter columns (width of P.opt)

if ~isempty(P)
    % P.opt contains ONLY non-constant columns (by design)
    Popt  = P.opt;          % [nU x nPz]
    nU    = size(Popt, 1);
    nPz   = size(Popt, 2);
    emptfl = false;
else
    % No hyperparameters: degenerate case
    Popt = [];
end

% --------------------------------------------------------
% 1) Build per-step cumulative indices directly from P.opt
% --------------------------------------------------------
% indA(u,zz) gives, for the u-th trained row in P.opt, the shelf index to use
% at pipeline step zz. It is defined as the stable group id of P.opt(:, J(zz)),
% where J(zz) are all parameter columns that are active by step zz.

if ~emptfl
    if ~isfield(P, 'steps') || numel(P.steps) ~= nPz
        error('nk_ParamReplicator:BadSteps', ...
            'P.steps must exist and have one entry per non-constant column in P.opt (expected %d).', nPz);
    end
    steps = P.steps(:)';                 % 1 x nPz

    % Sanity: steps must be positive integers within [1..nA]
    if any(~isfinite(steps)) || any(steps < 1) || any(steps > nA)
        error('nk_ParamReplicator:StepsOutOfRange', ...
            'P.steps contains invalid step indices. Expected integers in [1..%d].', nA);
    end

    % Build cumulative group ids per step, using STABLE grouping to preserve
    % the training enumeration order (so indices align with how shelves were stored).
    indA = ones(nU, nA);
    for zz = 1:nA
        J = find(steps <= zz);           % all non-constant columns active by this step
        if isempty(J)
            indA(:, zz) = 1;             % nothing active yet → single shelf
        else
            [~, ~, g] = unique(Popt(:, J), 'rows', 'stable');
            indA(:, zz) = g;             % shelf id for each trained row at step zz
        end
    end
else
    indA = ones(nU, nA);                 % no hyperparams → single shelf at every step
end

% ---------------------------------------------------------------
% 2) Map PXopt rows to P.opt rows (only drop PXopt’s constant cols)
% ---------------------------------------------------------------
% Because P.opt already removed constant columns, we MUST drop constant
% columns from PXopt to make it comparable to P.opt column-wise.

data_ind  = zeros(nP, 1);               % which P.opt row each PXopt row maps to
train_ind = zeros(nP, nA);              % per PXopt row, per step shelf index

if nP == 1 || emptfl
    % Trivial: single overall combo or no hyperparameters
    data_ind(:)    = 1;
    train_ind(:,:) = 1;
    return
end

% 2a) Identify and drop constant columns from PXopt ONLY
constPX = false(1, size(PXopt,2));
for c = 1:size(PXopt,2)
    constPX(c) = isscalar(unique(PXopt(:,c)));
end
PXc = PXopt;
PXc(:, constPX) = [];                    % reduced PXopt (non-constant columns only)

% 2b) Now PXc should match P.opt’s width exactly (by contract)
if size(PXc, 2) ~= size(Popt, 2)
    % Provide a clear, actionable error with diagnostics
    error('nk_ParamReplicator:ShapeMismatch', ...
        ['After removing ONLY constant columns from PXopt, the reduced PXc has %d columns, ', ...
         'but P.opt has %d non-constant columns.\n', ...
         'This indicates a column-order mismatch or that PXopt still contains ', ...
         'a column that was treated as constant during training (hence absent in P.opt). ', ...
         'Ensure PXopt''s non-constant columns are in the SAME order as P.opt.'], ...
         size(PXc,2), size(Popt,2));
end

% 2c) Row-wise mapping: for each trained row u in P.opt, tag all PXopt rows equal to it
%     (NB: we match against the REDUCED PXc, not the original PXopt)
for u = 1:nU
    mask_u = ismember(PXc, Popt(u, :), 'rows');
    if any(mask_u)
        data_ind(mask_u)     = u;
        train_ind(mask_u, :) = repmat(indA(u, :), sum(mask_u), 1);
    end
end

% 2d) Validate: every PXopt row must map to some P.opt row
if any(data_ind == 0)
    bad = find(data_ind == 0, 1, 'first');
    % Print the offending reduced row for faster debugging (optional)
    % disp(PXc(bad, :));
    error('nk_ParamReplicator:UnmappedPXoptRow', ...
        ['PXopt row %d did not map to any trained P.opt row after reducing PXopt to non-constant columns.\n', ...
         'Likely causes: column order mismatch; PXopt contains a non-constant column that was constant in training; ', ...
         'or P.opt/PXopt were built from different parameter definitions.'], bad);
end

% -------------------------------------------------------------------------
% 3) (Optional) Sanity: per-step shelf counts (helpful during debugging)
% -------------------------------------------------------------------------
%{
max_by_step = max(train_ind, [], 1);
fprintf('DEBUG shelves per step: ['); fprintf('%d ', max_by_step); fprintf(']\n');
% Compare to cellfun(@numel, oTrainedParam) to verify alignment.
%}

end
