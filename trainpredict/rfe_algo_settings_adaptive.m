function [AdIn, Hist] = rfe_algo_settings_adaptive(RFE)

% =========================================================================
%                         ADAPTIVE WRAPPER SETTINGS
% Centralize the config here so the wrapper can consume r.AdRef directly.
% Shows up *only* if EarlyStop is disabled in the configurator, but we
% still pass the struct through (Enable=true/false decides behavior).
% =========================================================================

AdIn = struct(); Hist = struct();

% Pull user config if present; otherwise start from a small default shell.
if isfield(RFE,'Wrapper') && isfield(RFE.Wrapper,'GreedySearch') && isfield(RFE.Wrapper.GreedySearch,'AdRef')
    User = RFE.Wrapper.GreedySearch.AdRef;
else
    User = struct();
end

% Safe get with default (no accidental field deref errors)
def = @(S, fld, dflt) getfield_default(S, fld, dflt);

% ---------------- Core knobs (manual; still supported) ----------------
AdIn.Enable         = def(User,'Enable', false);  % turn ON to activate adaptive reg
AdIn.gamma          = def(User,'gamma',  0.98);   % memory decay
AdIn.eta0           = def(User,'eta0',   1e-3);   % global drift
AdIn.eta1           = def(User,'eta1',   5e-3);   % similarity bump scale
AdIn.lambda         = def(User,'lambda', 0.5);    % manual λ (used if Auto disabled)
AdIn.rmax           = def(User,'rmax',   10);     % cap for rvec
AdIn.kNN            = def(User,'kNN',    20);     % neighbors per feature

% ---------------- Redundancy penalty φ(s) params ----------------------
AdIn.c              = def(User,'c', 0.55);
AdIn.w              = def(User,'w', 0.15);
AdIn.beta_well      = def(User,'beta_well', 1);
AdIn.beta_hi        = def(User,'beta_hi',  1);
AdIn.sigma_lo       = def(User,'sigma_lo', AdIn.w/3);
AdIn.sigma_hi       = def(User,'sigma_hi',  0.08);

% ---------------- Natural stopping (noise-aware τ) --------------------
if ~isfield(User,'Stop') || ~isstruct(User.Stop), User.Stop = struct(); end
AdIn.Stop.Enable    = def(User.Stop,'Enable',   true);
AdIn.Stop.TauAbs    = def(User.Stop,'TauAbs',   1e-4);
AdIn.Stop.UseMAD    = def(User.Stop,'UseMAD',   true);
AdIn.Stop.MADWinsz  = def(User.Stop,'MADWinsz', 8);
AdIn.Stop.Zmad      = def(User.Stop,'Zmad',     2.0);
AdIn.Stop.Patience  = def(User.Stop,'Patience', 0);
AdIn.Stop.hist      = [];
AdIn.Stop.holdcnt   = 0;

% --------------------------- AUTO MODE -------------------------------
% Turn this on to make λ (and optionally γ, η0, η1, kNN, τ_abs) self-tune.
if ~isfield(User,'Auto') || ~isstruct(User.Auto), User.Auto = struct(); end
AdIn.Auto.Enable      = def(User.Auto,'Enable',      false);  % master switch
AdIn.Auto.LambdaC     = def(User.Auto,'LambdaC',     0.8);    % scales lambda_eff
AdIn.Auto.HalfLife    = def(User.Auto,'HalfLife',    10);     % steps of memory
AdIn.Auto.TargetBumpS = def(User.Auto,'TargetBumpS', 0.90);   % s at which bump is targeted
AdIn.Auto.TargetBump  = def(User.Auto,'TargetBump',  0.10);   % desired bump magnitude at s
AdIn.Auto.AutoKNN     = def(User.Auto,'AutoKNN',     true);   % kNN from p
AdIn.Auto.ZeroTauAbs  = def(User.Auto,'ZeroTauAbs',  true);   % set TauAbs=0 in Auto

% If Auto is ON, compute auto defaults *only if user didn't override*.
if AdIn.Auto.Enable
    % gamma from half-life; eta0 gentle fraction of (1-gamma)
    if ~isfield(User,'gamma') || isempty(User.gamma)
        AdIn.gamma = 2^(-1 / max(1, AdIn.Auto.HalfLife));
    end
    if ~isfield(User,'eta0') || isempty(User.eta0)
        AdIn.eta0 = 0.1 * (1 - AdIn.gamma);
    end
    % eta1 from target bump at similarity s_tgt (using φ params)
    if ~isfield(User,'eta1')  || isempty(User.eta1)
        z = (AdIn.Auto.TargetBumpS - AdIn.c)^2 - AdIn.w^2;
        denom = AdIn.beta * tanh(AdIn.alpha * z);
        if abs(denom) < eps, denom = sign(denom) * eps + (denom==0)*eps; end
        AdIn.eta1 = AdIn.Auto.TargetBump / denom;
    end
    % kNN from dimensionality
    if AdIn.Auto.AutoKNN && (~isfield(User,'kNN') || isempty(User.kNN))
        p = r.kFea;
        AdIn.kNN = min(30, max(10, floor(3*log(max(p,3)))));
    end
    % τ_abs→0 (rely on MAD band) unless user set it explicitly
    if AdIn.Auto.ZeroTauAbs && ( ~isfield(User,'Stop') || ...
       isfield(User,'Stop') || ~isfield(AdIn.User,'TauAbs'))
        AdIn.Stop.TauAbs = 0;
    end
    % Beta_well
    if ~isfield(User,'beta_well') || isempty(User.beta_well)
        AdIn.beta_well = 1.0;          % default
    end
    % Beta_high
    if ~isfield(User,'beta_hi') || isempty(User.beta_hi)
        % Use beta_well as default
        AdIn.beta_hi = AdIn.beta_well; 
    end
    % 2) Softness (std dev, erf gates). Defaults scale nicely across datasets
    if ~isfield(User,'sigma_lo') || isempty(User.sigma_lo)
        AdIn.sigma_lo = max(AdIn.w, 1e-6)/3; 
    end
    if ~isfield(User,'sigma_hi') || isempty(User.sigma_hi)
        AdIn.sigma_hi = 0.08; 
    end
end

if AdIn.Enable
    % ---- Trace history (lightweight; summaries only) ----
    Hist = struct();
    switch RFE.Wrapper.type
        case 1
            Hist.mode= 'forward';          % or 'backward' (set per file)
        case 2
            Hist.mode= 'backward';
    end
    Hist.multiclass  = false;              % true in _multi_ wrappers
    Hist.optparam    = [];                 % best objective each accepted step
    Hist.it          = [];                 % iteration index (outer loop)
    Hist.block_size  = [];                 % lstep (or min(lstep) in multi)
    Hist.n_selected  = [];                 % #selected features after acceptance
    Hist.lambda_eff  = [];                 % λ_eff used that iteration (NaN if manual off/not used)
    Hist.rho_med     = [];                 % median(ρ) across candidates (or across classes)
    Hist.rho_max     = [];                 % max(ρ)
    Hist.raw_maxGain = [];                 % max(val - current_best)
    Hist.max_mprime  = [];                 % max penalized marginal gain
    Hist.tau_used    = [];                 % τ used in natural stop (Abs or MAD-augmented)
    Hist.stopped     = false;              % set true if natural stop terminates
    Hist.sel_idx     = {};                 % accepted feature indices (per acceptance step)
    % Optional: occasional snapshots of rvec (every K accepts) for heatmap (keeps memory small)
    Hist.rvec_snap   = {};                 % cell of rvec (or per-class cell) snapshots
    Hist.rvec_snap_it= 1;                 % iteration when snapshot taken
    Hist.snap_every  = 1;                  % take snapshot every 5 accepts (tune or set 0 to disable)
end

end 

function val = getfield_default(S, fld, dflt)
%GETFIELD_DEFAULT  Safely get S.(fld) or return dflt if missing/empty.
    if isstruct(S) && isfield(S, fld) && ~isempty(S.(fld))
        val = S.(fld);
    else
        val = dflt;
    end
end