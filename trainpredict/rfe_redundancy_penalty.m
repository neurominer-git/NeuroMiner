function pen = rfe_redundancy_penalty(s, c, w, beta_well, beta_hi, sigma_lo, sigma_hi)
%ASYMMETRIC ultra-smooth redundancy penalty ψ(s) using Gaussian CDF (erf) gates
%  - Smooth window W_erf over [c-w, c+w] with softness sigma_lo
%  - Smooth high-similarity ramp R_erf beyond c+w with softness sigma_hi
%  - Fully C^∞ smooth; no visible edge
%
% Inputs:
%   s          : vector of similarities (0..1)
%   c, w       : center and half-width of redundancy band
%   beta_well  : magnitude of negative well
%   beta_hi    : magnitude of high-similarity penalty
%   sigma_lo   : softness (std) for the window edges  (suggest: w/3 .. w/2)
%   sigma_hi   : softness (std) for the high-sim ramp (suggest: 0.06 .. 0.10)
%
% Output:
%   pen        : ψ(s), same size as s

    s = double(s(:));  % column
    % Gaussian CDF via erf
    Phi = @(z) 0.5*(1 + erf(z ./ sqrt(2)));

    % Smooth window and ramp
    W_lo = Phi( (s - (c - w)) ./ max(sigma_lo, eps) ) - ...
           Phi( (s - (c + w)) ./ max(sigma_lo, eps) );
    R_hi = Phi( (s - (c + w)) ./ max(sigma_hi, eps) );

    % Negative Gaussian well, softly gated by W_lo
    well  = -beta_well .* exp( -((s - c).^2) ./ (2*(w.^2) + eps) ) .* W_lo;

    % Positive ramp for near-duplicates
    ramp  =  beta_hi   .* R_hi;

    pen = well + ramp;
end
