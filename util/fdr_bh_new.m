function [h, crit_p, adj_ci_cvrg, adj_p]=fdr_bh_new(pvals,q,method,report)

if nargin<1,
    error('You need to provide a vector or matrix of p-values.');
else
    if ~isempty(find(pvals<0,1)),
        error('Some p-values are less than 0.');
    elseif ~isempty(find(pvals>1,1)),
        error('Some p-values are greater than 1.');
    end
end

if nargin<2, q=.05; end
if nargin<3, method='pdep'; end
if nargin<4, report='no'; end

s = size(pvals);
p = pvals(:);                            % N x 1

% ---------- NEW: operate on finite p only ----------
finiteMask = isfinite(p);
p_f        = p(finiteMask);              % m x 1 (finite only)
m          = numel(p_f);
if m==0
    % No finite tests -> nothing significant, adj_p all NaN
    h            = zeros(s);
    crit_p       = 0;
    adj_ci_cvrg  = NaN;
    adj_p        = nan(s);
    if strcmpi(report,'yes')
        fprintf('Out of %d tests, %d are significant using a false discovery rate of %f.\n',0,0,q);
    end
    return
end

% Sort finite p-values only
[p_sorted, sort_ids] = sort(p_f(:), 'ascend');         % m x 1
% (we do NOT define unsort_ids here; we’ll invert sort_ids later)

% ---------- BH / BY thresholds on finite set ----------
switch lower(method)
    case 'pdep'  % BH 1995 (independent/positive dependence)
        thresh = (1:m) * q / m;
        wtd_p  = (m ./ (1:m))' .* p_sorted;           % m x 1
    case 'dep'   % BY 2001 (arbitrary dependence)
        denomH = sum(1./(1:m));
        thresh = (1:m) * q / (m * denomH);
        wtd_p  = (m * denomH ./ (1:m))' .* p_sorted;  % m x 1
    otherwise
        error('Argument ''method'' needs to be ''pdep'' or ''dep''.');
end

% ---------- Rejections / crit_p on finite set (unchanged policy) ----------
rej    = p_sorted(:) <= thresh(:);
max_id = find(rej, 1, 'last');
if isempty(max_id)
    crit_p      = 0;
    h           = zeros(s);                    % none significant
    adj_ci_cvrg = NaN;
else
    crit_p      = p_sorted(max_id);
    % Mark significant where p <= crit_p and finite
    h_full      = false(numel(p),1);
    h_full(finiteMask) = p_f <= crit_p;
    h           = reshape(h_full, s);
    adj_ci_cvrg = 1 - thresh(max_id);
end

% ---------- Adjusted p-values (standard BH/BY step-up) ----------
if nargout>3
    % Step-up on sorted finite p’s:
    %   adj_sorted(i) = min_{j>=i} wtd_p(j), then cap at 1
    adj_sorted = flipud( cummin( flipud(wtd_p) ) );   % m x 1
    adj_sorted = min(adj_sorted, 1);

    % Invert the sort to original finite order
    inv_perm = zeros(m,1);
    inv_perm(sort_ids) = (1:m)';                      % inverse permutation
    adj_f = adj_sorted(inv_perm);                     % finite positions, original order (m x 1)

    % Scatter back into full shape
    adj_p_vec              = nan(numel(p),1);         % N x 1
    adj_p_vec(finiteMask)  = adj_f;                   % finite entries only
    adj_p                  = reshape(adj_p_vec, s);
end

if strcmpi(report,'yes'),
    n_sig = sum(rej);
    if n_sig==1
        fprintf('Out of %d tests, %d is significant using a false discovery rate of %f.\n',m,n_sig,q);
    else
        fprintf('Out of %d tests, %d are significant using a false discovery rate of %f.\n',m,n_sig,q);
    end
    if strcmpi(method,'pdep'),
        fprintf('FDR/FCR procedure used is guaranteed valid for independent or positively dependent tests.\n');
    else
        fprintf('FDR/FCR procedure used is guaranteed valid for independent or dependent tests.\n');
    end
end
