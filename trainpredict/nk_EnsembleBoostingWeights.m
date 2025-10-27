function w = nk_EnsembleBoostingWeights(H, y, opts)
% H: N x M (probabilities or scores depending on mode)
% y: N x 1 (regression or binary {0,1}/{-1,+1}); multiclass = loop OVR
if ~isfield(opts,'mode'),    opts.mode = 'ridge'; end
if ~isfield(opts,'lambda'),  opts.lambda = 1e-3;  end
if ~isfield(opts,'alpha'),   opts.alpha  = 0;     end
if ~isfield(opts,'clip'),    opts.clip   = 1e-7;  end
if ~isfield(opts,'useLogits'), opts.useLogits = false; end
if ~isfield(opts,'eta'),     opts.eta    = 0.3;   end
if ~isfield(opts,'T'),       opts.T      = 200;   end
if ~isfield(opts,'metric'),  opts.metric = 2;     end    
if ~isfield(opts,'R'),       opts.R      = [];    end    % no diversity unless provided

mode = getfielddef(opts,'mode','ridge'); % 'ridge'|'logloss'|'expgrad'
switch lower(mode)
  case 'ridge'
    lambda = getfielddef(opts,'lambda',1e-3);
    R = getfielddef(opts,'R', []);
    alpha = getfielddef(opts,'alpha', 0);
    w = nm_weights_ridge_simplex(H, y, lambda, R, alpha);
  case 'logloss'
    lambda = getfielddef(opts,'lambda',1e-3);
    R = getfielddef(opts,'R', []);
    alpha = getfielddef(opts,'alpha', 0);
    clip= getfielddef(opts,'clip', 1e-7);
    w = nm_weights_logloss_simplex(H, y, lambda,R, alpha, clip);
  case 'expgrad'
    w = nm_weights_expgrad(H, y, opts);
  otherwise
    error('Unknown mode.');
end
end

function w = nm_weights_ridge_simplex(H, y, lambda, R, alpha)
% H: N×M, y: N×1. Simplex-constrained ridge with optional diversity kernel R.

% ---- ensure doubles ----
H     = double(H);
y     = double(y);
lambda = double(lambda);
if nargin < 4 || isempty(R), R = []; end
if nargin < 5 || isempty(alpha), alpha = 0; end

M = size(H,2);

% ---- build QP (quadprog expects Q,c,A,b,Aeq,beq as double) ----
Q = 2*(H.'*H + lambda*eye(M,'double'));
if ~isempty(R) && alpha>0
    R = double((R+R.')/2);            % symmetrize
    Q = Q + 2*alpha*R;
end
Q = (Q+Q.')/2 + 1e-12*eye(M,'double'); % numerical hygiene

c   = -2*(H.'*y);
Aeq = ones(1,M,'double');  beq = 1;
A   = -eye(M,'double');    b   = zeros(M,1,'double');

opts = optimoptions('quadprog','Display','off','Algorithm','interior-point-convex');

try
    w = quadprog(Q,c,A,b,Aeq,beq,[],[],[],opts);
catch
    % ---- fallback: projected gradient onto simplex ----
    w = local_projgrad_simplex(Q,c,M);
end

% guard: normalize (rare numerical drift)
w = max(w,0); s = sum(w); if s>0, w = w/s; else, w = ones(M,1)/M; end
end

% ---------- helpers ----------
function w = local_projgrad_simplex(Q,c,M)
w = ones(M,1,'double')/M;
L = max(eig(Q)); if ~isfinite(L) || L<=0, L=1; end
t = 1/(L+1e-9);                % step size
for it=1:500
    g = Q*w + c;
    w = w - t*g;
    w = proj_simplex_euclid(w);
    if norm(g,inf) < 1e-6, break; end
end
end

function x = proj_simplex_euclid(v)
% Projects v onto {x >= 0, sum x = 1}
v = double(v(:));
n = numel(v);
u = sort(v,'descend');
rho = find(u + (1 - cumsum(u))./(1:n)' > 0, 1, 'last');
theta = (1 - sum(u(1:rho))) / rho;
x = max(v + theta, 0);
end

function w = nm_weights_logloss_simplex(Hprob, y, lambda, R, alpha, clip, u0)
% Hprob: N x M matrix of P(y=1) from base learners (double)
% y    : N x 1 labels in {0,1} (double)
% lambda: L2 penalty on w (>=0)
% R,alpha: diversity kernel and weight (optional; set alpha=0 or R=[] to disable)
% clip: probability clamp (default 1e-7)
% u0  : optional warm start for unconstrained params (Mx1)

    % ---- defaults & hygiene ----
    Hprob  = double(Hprob);
    y      = double(y(:));
    [~,M]  = size(Hprob);
    if nargin < 7 || isempty(u0),    u0 = zeros(M,1); end

    if ~isempty(R) && alpha>0
        R = double((R+R.')/2);             % symmetrize
    else
        R = []; alpha = 0;                  % disable if not both provided
    end

    % ---- objective over unconstrained u with softmax(w) ----
    obj = @(u) f_obj(u, Hprob, y, lambda, R, alpha, clip);

    opts = optimoptions('fminunc', ...
        'Algorithm','quasi-newton', ...
        'Display','off', ...
        'SpecifyObjectiveGradient',true);

    u = fminunc(obj, u0, opts);
    w = softmax_local(u);
end

% ---------- objective & gradient ----------
function [L,g] = f_obj(u,H,y,lambda,R,alpha,clip)
    w = softmax_local(u);                % Mx1, sum to 1, w>=0
    p = H*w;                             % Nx1
    p = min(max(p,clip), 1-clip);        % clamp

    % ----- loss -----
    L = -sum( y.*log(p) + (1-y).*log(1-p) ) ...
        + lambda*(w.'*w);

    % diversity penalty (if enabled)
    if alpha>0
        L = L + alpha*(w.'*(R*w));
    end

    % ----- gradient wrt w -----
    gw = H.'*(p - y) + 2*lambda*w;
    if alpha>0
        gw = gw + 2*alpha*(R*w);
    end

    % ----- chain rule through softmax: g_u = (diag(w)-w*w') * gw
    % Use the O(M) Jacobian-vector trick: J*gw = w .* (gw - (w.'*gw))
    g = w .* (gw - (w.'*gw));
end

function w = softmax_local(u)
u = u - max(u);
w = exp(u); w = w/sum(w);
end

function w = nm_weights_expgrad(Hscore, ypm1, opts)
% Hscore: N x M margin-like scores (larger = more +1), ypm1 in {-1,+1}
% opts: .eta (step), .alpha (diversity), .T (iters)
[~,M] = size(Hscore);
eta   = getfielddef(opts,'eta', 0.5);
alpha = getfielddef(opts,'alpha', 0.0);
T     = getfielddef(opts,'T',    200);
R     = getfielddef(opts,'R',    []);

% init on simplex
w = ones(M,1)/M;

for t=1:T
  f = Hscore*w;                         % Nx1
  e = exp(-ypm1.*f);                    % weights like AdaBoost
  % gradient wrt w_m
  g = -(Hscore.'*(ypm1.*e));            % Mx1
  if alpha>0, g = g + 2*alpha*(R*w); end
  % exponentiated gradient step + simplex projection
  w = w .* exp(-eta*g);
  s = sum(w); if s==0, w = ones(M,1)/M; else, w = w/s; end
  % early stopping (relative change)
  if t>5 && norm(g,1)/M < 1e-6, break; end
end
end

function v = getfielddef(s,f,def), if isfield(s,f), v=s.(f); else, v=def; end, end
