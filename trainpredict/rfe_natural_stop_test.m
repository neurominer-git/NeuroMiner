function [should_stop, Tau, info] = rfe_natural_stop_test(val, optparam, rsub, lambda, StopCfg)
%==========================================================================
% Helper: Natural stopping test
%--------------------------------------------------------------------------
% Decide if we should stop by checking whether the best penalized
% marginal gain (over all remaining candidates) is ≤ tolerance τ.
% Logic:
% Stop if no candidate’s penalized gain exceeds τ, with optional patience 
% across iterations m'_m = (val(m) - optparam) - λ_eff * rho(m)
% ----------------------------------------------------------
%
% Inputs
%   val      : [lc x 1] raw candidate performance values for S ∪ {j}
%   optparam : scalar, current best performance
%   rsub     : [lc x 1] refusal penalties for the candidate pool
%   lambda   : scalar, penalty weight
%   StopCfg  : struct with fields:
%                .TauAbs (absolute floor)
%                .UseMAD (enable rolling MAD band)
%                .MADWinsz (window length for recent accepted improvements)
%                .Zmad (multiplier for MAD band)
%                .hist (vector of recent accepted raw improvements)
%
% Outputs
%   should_stop : true if max penalized marginal gain ≤ τ
%   Tau         : tolerance used this time (max of abs and MAD band)
%   info        : struct with diagnostic info for logging
    

% Raw improvement each candidate would yield over current best
raw_delta = val - optparam;             % positive if candidate beats current best

% Penalized marginal gain for each candidate
mprime    = raw_delta - lambda * rsub;  % subtract refusal weighted by λ

% Best achievable penalized gain
max_mprime = max(mprime);

% Build tolerance τ
Tau = StopCfg.TauAbs;
TauMAD = NaN;
if StopCfg.UseMAD && numel(StopCfg.hist) >= 3
    h = StopCfg.hist(:);
    med = median(h);
    mad = median(abs(h - med));
    TauMAD = StopCfg.Zmad * 1.4826 * mad;   % robust σ estimate under normality
    Tau = max(Tau, TauMAD);
end

% Decide to stop if even the best candidate cannot overcome its penalty
should_stop = (max_mprime <= Tau);

% Provide diagnostics back to caller
info = struct('max_mprime',    max_mprime, ...
              'max_raw_delta', max(raw_delta), ...
              'TauMAD',        TauMAD, ...
              'TauAbs',        StopCfg.TauAbs);
end