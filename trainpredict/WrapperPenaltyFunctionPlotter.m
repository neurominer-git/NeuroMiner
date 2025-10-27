%% Ultra-smooth Asymmetric Redundancy Penalty: quick plotter
% This script plots the ultra-smooth ψ(s) built with erf-based gates.
% It also overlays the logistic-window version for comparison (optional).

% ====== Parameters (edit these) ======
c         = 0.55;   % center of redundancy band
w         = 0.25;   % half-width of redundancy band
beta_well = 1.00;   % magnitude of negative well
beta_hi   = 1.00;   % magnitude of high-similarity penalty

% Ultra-smooth (erf-window) softness (std dev in s-units)
sigma_lo  = w/2;    % softness of well window edges (try: w/3 .. w/2)
sigma_hi  = 0.05;   % softness of high-similarity ramp (try: 0.06 .. 0.10)

% Logistic-window (older smooth) parameters for comparison
alpha_lo  = 20/w;   % window sharpness (logistic)
alpha_hi  = 25.0;   % ramp sharpness (logistic)

% ====== Plot range ======
s = linspace(0,1,600);

% ====== Compute curves ======
psi_ultra = redundancy_penalty_asym_ultrasmooth(s, c, w, beta_well, beta_hi, sigma_lo, sigma_hi);
psi_logis = redundancy_penalty_asym_smooth   (s, c, w, beta_well, beta_hi, alpha_lo, alpha_hi); % optional overlay

% ====== Plot ======
figure('Color','w'); hold on;
p1 = plot(s, psi_ultra, 'LineWidth', 2, 'DisplayName', 'ultra-smooth (erf window)');
p2 = plot(s, psi_logis, '--', 'LineWidth', 1.75, 'DisplayName', 'logistic window (ref)');
yl = ylim;

% Guides: redundancy band and zero line
plot([c-w c-w], yl, 'k--', 'HandleVisibility','off');
plot([c+w c+w], yl, 'k--', 'HandleVisibility','off');
plot([0 1], [0 0], 'k:', 'HandleVisibility','off');

title(sprintf('Asymmetric Redundancy Penalty  \\psi(s)  (c=%.2f, w=%.2f)', c, w));
xlabel('similarity  s  (e.g., |corr|)');
ylabel('\psi(s)');
legend('Location','best'); grid on; box off;

% ====== Annotate regions (optional) ======
text(c, yl(1) + 0.10*range(yl), 'encourage redundancy', 'HorizontalAlignment','center');
text(c+w+0.06, yl(1) + 0.75*range(yl), 'penalize near-duplicates', 'HorizontalAlignment','left');
text((c-w)/2, yl(1) + 0.12*range(yl), 'no penalty (low similarity)', 'HorizontalAlignment','center');

%% ====== Helper: ultra-smooth asymmetric penalty ψ(s) using erf-based gates ======
function pen = redundancy_penalty_asym_ultrasmooth(s, c, w, beta_well, beta_hi, sigma_lo, sigma_hi)
%ASYMMETRIC ultra-smooth redundancy penalty ψ(s) using Gaussian CDF (erf) gates
%  - Smooth window over [c-w, c+w] with softness sigma_lo
%  - Smooth high-similarity ramp beyond c+w with softness sigma_hi
%  - Fully C^∞ smooth; no hard edges

    s = double(s(:));  % column vector
    Phi = @(z) 0.5*(1 + erf(z./sqrt(2)));          % Gaussian CDF

    % Smooth window (turns well on in [c-w, c+w])
    W_lo = Phi( (s - (c - w)) ./ max(sigma_lo, eps) ) - ...
           Phi( (s - (c + w)) ./ max(sigma_lo, eps) );

    % Negative Gaussian well gated by W_lo
    well  = -beta_well .* exp( -((s - c).^2) ./ (2*(w.^2) + eps) ) .* W_lo;

    % Positive high-similarity ramp
    R_hi  =  beta_hi   .* Phi( (s - (c + w)) ./ max(sigma_hi, eps) );

    pen = well + R_hi;
end

%% ====== Helper: logistic-window asymmetric penalty ψ(s) (reference) ======
function pen = redundancy_penalty_asym_smooth(s, c, w, beta_well, beta_hi, alpha_lo, alpha_hi)
%ASYMMETRIC smooth redundancy penalty ψ(s) using logistic gates
%  - Smooth logistic window around [c-w, c+w] gates a negative Gaussian well
%  - Positive logistic ramp activates for s > c+w

    s = double(s(:)).';
    sig    = @(x) 1./(1+exp(-x));
    window = sig(alpha_lo*(s - (c - w))) - sig(alpha_lo*(s - (c + w))); % smooth on/off
    well   = -beta_well .* exp( -((s - c).^2) ./ (2*(w.^2) + eps) ) .* window;
    ramp   =  beta_hi   .* sig(alpha_hi*(s - (c + w)));
    pen    = well + ramp;
    pen    = pen(:); % column for consistency with ultra-smooth
end
