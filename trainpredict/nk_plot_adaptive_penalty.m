function nk_plot_adaptive_penalty(AdRef)
%NK_PLOT_ADAPTIVE_PENALTY  Plot ψ(s) for current EXPERT adaptive settings.
%
% Supports both:
%   - New fields: beta_well, beta_hi, sigma_lo, sigma_hi
%   - Legacy fields: alpha (→ beta_well), beta (→ beta_hi), no sigmas (defaults)
%
% Uses ultra-smooth (erf-window) ψ(s).

    % --- read core band params
    c = getf(AdRef,'c', 0.55);
    w = getf(AdRef,'w', 0.15);

    % --- read magnitudes (new first, fall back to legacy)
    beta_well = getf(AdRef,'beta_well', []);
    if isempty(beta_well)
        beta_well = getf(AdRef,'alpha', 1.0);  % reuse legacy alpha as beta_well
    end
    beta_hi   = getf(AdRef,'beta_hi',   []);
    if isempty(beta_hi)
        beta_hi = getf(AdRef,'beta',     beta_well); % reuse global beta or beta_well
    end

    % --- softness (std in s-units) for erf gates
    sigma_lo = getf(AdRef,'sigma_lo', max(w,1e-6)/3); % smooth window edges
    sigma_hi = getf(AdRef,'sigma_hi', 0.08);          % near-duplicate ramp

    % --- generate curve
    s   = linspace(0,1,600);
    psi = rfe_redundancy_penalty(s, c, w, beta_well, beta_hi, sigma_lo, sigma_hi);

    % --- plot
    figure('Color','w'); hold on;
    plot(s, psi, 'LineWidth', 2);
    yl = ylim; 
    plot([c-w c-w], yl, 'k--', 'HandleVisibility','off');
    plot([c+w c+w], yl, 'k--', 'HandleVisibility','off');
    plot([0 1], [0 0], 'k:',  'HandleVisibility','off');
    title(sprintf('Asymmetric penalty \\psi(s)  c=%.2f, w=%.2f | \\beta_w=%.2f, \\beta_h=%.2f | \\sigma_l=%.2f, \\sigma_h=%.2f', ...
                  c, w, beta_well, beta_hi, sigma_lo, sigma_hi));
    xlabel('similarity  s  (e.g., |corr|)');
    ylabel('\psi(s)');
    grid on; box off;

    % Optional region hints
    text(c, yl(1)+0.10*range(yl), 'encourage redundancy', 'HorizontalAlignment','center');
    text(c+w+0.06, yl(1)+0.75*range(yl), 'penalize near-duplicates', 'HorizontalAlignment','left');
    text((c-w)/2, yl(1)+0.12*range(yl), 'no penalty (low similarity)', 'HorizontalAlignment','center');
end

function v = getf(S, fld, dflt)
    if isstruct(S) && isfield(S,fld) && ~isempty(S.(fld)), v = S.(fld); else, v = dflt; end
end