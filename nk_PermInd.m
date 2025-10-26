% =========================================================================
% FORMAT permmat = nk_PermInd(nPerms,Labels,Constraint)
% =========================================================================
%
% Generate 'nPerms' within-group permutations of class membership indices
% 'Labels' and guarantee that replicated permutations do not occur
% where mathematically possible. If a (label x constraint) cell has
% lindcl <= 1, or nPerms exceeds the number of unique permutations,
% uniqueness is relaxed to avoid infinite retries.
% =========================================================================
% Neurominer, (c) Nikolaos Koutsouleris 12/2025
function permmat = nk_PermInd(nPerms, Labels, Constraint)

uLabels = unique(Labels);
if any(~isfinite(uLabels))
    uLabels(~isfinite(uLabels)) = [];
    uLabels(end+1) = NaN;
end
mL = numel(uLabels);

ll = size(Labels,1);
trylim = 500;
permmat = zeros(nPerms,ll);

if ~exist('Constraint','var') || isempty(Constraint)
    uConstraint = []; mC = 1; cfl = false;
else
    uConstraint = unique(Constraint);
    mC = numel(uConstraint); cfl = true;
end

for i = 1:mL % Loop through classes
    for h = 1:mC % Loop through constraint levels (if any)

        % --- indices in current (label x constraint) cell
        if cfl
            if ~isfinite(uLabels(i))
                indcl = find(~isfinite(Labels) & Constraint == uConstraint(h));
            else
                indcl = find(Labels == uLabels(i) & Constraint == uConstraint(h));
            end
        else
            if ~isfinite(uLabels(i))
                indcl = find(~isfinite(Labels));
            else
                indcl = find(Labels == uLabels(i));
            end
        end

        % If the cell is empty, just continue (nothing to permute for this cell)
        if isempty(indcl), continue; end

        lindcl = numel(indcl);

        % --- Fast paths to avoid impossible-uniqueness crashes
        % Case A: lindcl <= 1 → only one ordering exists; replicate it
        if lindcl <= 1
            permmat(:, indcl) = repmat(indcl(:)', nPerms, 1);
            continue;
        end

        % Case B: requested nPerms exceeds the number of unique permutations
        % Compute maxUnique safely (double precision is fine for small lindcl)
        % For lindcl > 170, factorial overflows double; but uniqueness is moot then.
        if lindcl <= 12
            maxUnique = factorial(lindcl); % exact for small lindcl
        else
            % use gamma to avoid overflow in factorial for moderately larger lindcl
            maxUnique = real(round(gamma(lindcl+1))); % may overflow > 171, but then nPerms << maxUnique anyway
            if ~isfinite(maxUnique), maxUnique = Inf; end
        end

        enforceUnique = nPerms <= maxUnique;
        if ~enforceUnique
            fprintf('\n[nk_PermInd] Note: Requesting %d permutations for a cell of size %d (max unique = %s). Allowing repeats for this cell.', ...
                nPerms, lindcl, ternary(isfinite(maxUnique), num2str(maxUnique), 'Inf'));
        end

        % --- Generate permutations for this cell
        trycnt = 0;
        j = 1;
        while j <= nPerms
            rclass = randperm(lindcl);
            rindcl = indcl(rclass)';      % permuted indices for this cell
            permmat(j, indcl) = rindcl;

            if ~enforceUnique || j == 1
                j = j + 1;
                trycnt = 0;
            else
                % uniqueness check vs previous rows for this cell
                if ~any(ismember(permmat(1:j-1, indcl), rindcl, 'rows'))
                    j = j + 1;
                    trycnt = 0;
                else
                    trycnt = trycnt + 1;
                    if trycnt >= trylim
                        if cfl
                            error(['\nTry limit reached. Permutation of class membership data failed!\n' ...
                                   '\tConstrain index = %g\n' ...
                                   '\tNo. of observations in current class and constrain index = %g\n'], ...
                                   cfl * uConstraint(h) + ~cfl * NaN, numel(rindcl));
                        else
                            error('Try limit reached. Permutation of class membership data failed.');
                        end
                    end
                end
            end
        end
    end
end

end

% --- tiny local helper (avoids an inline if/else clutter)
function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
