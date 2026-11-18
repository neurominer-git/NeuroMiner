function [mode, reason] = nk_ResolveWaveletWeightHandling(SPATIAL, requestedMode)
% nk_ResolveWaveletWeightHandling
% Resolve external weighting-image handling for wavelet spatial reconstruction.
%
% Usage:
%   mode = nk_ResolveWaveletWeightHandling(SPATIAL)
%   [mode, reason] = nk_ResolveWaveletWeightHandling(SPATIAL, requestedMode)
%
% Inputs:
%   SPATIAL       Spatial preprocessing step struct. The function tolerates
%                 several NM 1.5/v29-v31 field layouts.
%   requestedMode Optional override: 'auto', 'copy', or 'wavelet'.
%
% Output:
%   mode          Resolved mode: 'copy' or 'wavelet'.
%   reason        Human-readable reason for logs/debugging.
%
% Policy:
%   - 'copy'    : keep the external weighting image unchanged and replicate
%                 it across wavelet branches.
%   - 'wavelet' : apply the same wavelet reconstruction to the external
%                 weighting image.
%   - 'auto'    : approximation -> wavelet; denoised/detail-like -> copy.
%
% This helper is intentionally dependency-light and suitable for use from
% both modular UI code and legacy-compatible backend code.

    if nargin < 1 || isempty(SPATIAL)
        SPATIAL = struct();
    end

    if nargin < 2 || isempty(requestedMode)
        requestedMode = local_get_weight_mode(SPATIAL);
    end

    if isempty(requestedMode)
        requestedMode = 'auto';
    end

    requestedMode = lower(strtrim(char(requestedMode)));

    switch requestedMode
        case {'copy','replicate','none','unchanged'}
            mode = 'copy';
            reason = 'explicit copy/replicate setting';
            return
        case {'wavelet','transform','reconstruct'}
            mode = 'wavelet';
            reason = 'explicit wavelet setting';
            return
        case {'auto','default'}
            % Continue below.
        otherwise
            warning('nk_ResolveWaveletWeightHandling:UnknownMode', ...
                'Unknown weightImageHandling value "%s". Falling back to auto.', requestedMode);
    end

    reconMode = local_get_reconstruction_mode(SPATIAL);

    if any(strcmp(reconMode, {'approximation','approx','lowpass','coarse'}))
        mode = 'wavelet';
        reason = sprintf('auto: reconstruction mode "%s" is approximation-like', reconMode);
    else
        mode = 'copy';
        if isempty(reconMode)
            reason = 'auto: reconstruction mode unavailable; conservative copy policy';
        else
            reason = sprintf('auto: reconstruction mode "%s" is detail/denoised-like', reconMode);
        end
    end
end

function mode = local_get_weight_mode(SPATIAL)
    mode = '';

    if isstruct(SPATIAL)
        if isfield(SPATIAL, 'weightImageHandling') && ~isempty(SPATIAL.weightImageHandling)
            mode = SPATIAL.weightImageHandling;
            return
        end
        if isfield(SPATIAL, 'WeightImageHandling') && ~isempty(SPATIAL.WeightImageHandling)
            mode = SPATIAL.WeightImageHandling;
            return
        end
        if isfield(SPATIAL, 'WAVELET') && isstruct(SPATIAL.WAVELET)
            W = SPATIAL.WAVELET;
            if isfield(W, 'weightImageHandling') && ~isempty(W.weightImageHandling)
                mode = W.weightImageHandling;
                return
            end
            if isfield(W, 'WeightImageHandling') && ~isempty(W.WeightImageHandling)
                mode = W.WeightImageHandling;
                return
            end
        end
    end
end

function reconMode = local_get_reconstruction_mode(SPATIAL)
    reconMode = '';

    if ~isstruct(SPATIAL)
        return
    end

    candidateFields = {'reconstruction','reconstructionMode','reconMode','recon','mode','type'};

    if isfield(SPATIAL, 'WAVELET') && isstruct(SPATIAL.WAVELET)
        reconMode = local_first_string_field(SPATIAL.WAVELET, candidateFields);
        if ~isempty(reconMode)
            reconMode = lower(strtrim(reconMode));
            return
        end
    end

    reconMode = local_first_string_field(SPATIAL, candidateFields);
    if ~isempty(reconMode)
        reconMode = lower(strtrim(reconMode));
    end
end

function value = local_first_string_field(S, fields)
    value = '';
    for i = 1:numel(fields)
        f = fields{i};
        if isfield(S, f) && ~isempty(S.(f))
            v = S.(f);
            if ischar(v) || (isstring(v) && isscalar(v))
                value = char(v);
                return
            end
        end
    end
end
