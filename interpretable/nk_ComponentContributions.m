function [contrAbs, contrRel, decisionRecon, S] = ...
          nk_ComponentContributions(Y, M, alpha, b, doNorm)
% =========================================================================
%   [absC, relC, fHat, S] = nm_ComponentContributions(Y, M, w, b, doNorm)
% =========================================================================
% nk_ComponentContributions  From raw data to per‑component decision
% shares.
%
% Theory:
%   --------------------------------------------------------------------
%   A linear decision function predicted for subject *i* can be written as
%
%        f(i) =  Σ_k  alpha(k) · S(i,k)  +  b                           (1)
%
%   The absolute contribution of component *k* for subject *i* is
%
%        C_abs(i,k) = alpha(k) · S(i,k)                                 (2)
%
%   For an *interpretable share* of how much each component drove the final
%   decision, one can normalise across K components:
%
%        C_rel(i,k) =  C_abs(i,k)  /  Σ_k |C_abs(i,k)|                  (3)
%
%   This yields a subject‑specific percentage (signed if desired).
%
% Inputs:
%   Y   :   [N×F]  subjects × features (voxels / vertices / sensors …)
%   M   :   [F×K]  reference component maps (columns = components)
%   alpha : [F×K]  learned weights in *the same order* as columns in M
%   b   :          scalar bias (set 0 if none)
%   doNorm : (logical)  if true (default), each component map is L2‑normalised
%                         before dot‑product ⇢ pure cosine projection.
% Outputs:
%   S   :   [N×K]  expression scores  S = Y·M   (optionally normalised)
%   absC:   [N×K]  absolute contributions  w(k)*S(i,k)
%   relC:   [N×K]  relative contributions  absC / Σ|absC|
%   fHat:   [N×1]  reconstructed decision scores (sanity‑check → Y*w + b)
%   --------------------------------------------------------------------
%   If your components are already orthonormal / unit‑length (e.g. ICA
%   with sphering) you can skip normalisation by calling with doNorm=false.
% =========================================================================
%   Nikolaos Koutsouleris – 05/2025

if nargin<5 || isempty(doNorm);   doNorm = true; end

% ---- 1) component expression scores S -------------------------------
if doNorm
    % pre‑divide each map column by its L2‑norm → unit vectors
    Mnorm  = sqrt(sum(M.^2,1));           % 1×K
    M      = bsxfun(@rdivide, M, Mnorm); % safe even if norm=0 (inf/NaN → later ignored)
end
S = Y * M;                               % [N×K]
w = mean( alpha, 1, 'omitnan' );         % 
w = w(:);                                % K × 1

% ---- 2) absolute & relative contributions ---------------------------
contrAbs = S .* w';                      % implicit expansion
den      = sum(abs(contrAbs),2);         % N×1
contrRel = contrAbs ./ den;              % N×K
contrRel(den==0,:) = NaN;

% ---- 3) reconstructed decision score --------------------------------
decisionRecon = sum(contrAbs,2) + b;

end
