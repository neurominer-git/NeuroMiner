function Yout = nk_SurfaceGraphWavelet(Y, op, level, W, onBatchComplete)
% nk_SurfaceGraphWavelet  Undecimated multiscale surface heat-wavelet frame.
% A_j = heat(A_0,t_j), D_j = A_(j-1)-A_j; A_J + sum(D_j) = A_0.
% This is a distinct graph heat-wavelet family, not volumetric Haar/B3-spline.
% All outputs preserve the input vertex order and cardinality.
% Optional onBatchComplete(completedSubjects, batchSubjects) reports only
% completed vectorized subject batches; it does not modify wavelet values.

if ~strcmp(W.family,'heat')
    error('nk_SurfaceGraphWavelet:invalidFamily', ...
        'Surface decomposition requires the explicit heat graph-wavelet family.');
end
if ~isscalar(level) || level < 1 || fix(level) ~= level
    error('nk_SurfaceGraphWavelet:invalidLevel','Level must be a positive integer.');
end
% Existing four-argument numerical callers do not request progress.
% nm2-allow: nk_PerfSpatFilt supplies the fifth progress callback; established numerical invocations use four arguments.
if nargin < 5, onBatchComplete = []; end
% Base spatial scale from average vertex area, invariant to mesh sampling.
baseFWHM = sqrt(4*sum(op.sqrtMass.^2)/op.vertexCount);
retainBands = any(strcmp(W.reconstructionMode,{'selected_details','denoised'}));
Yout = zeros(size(Y),'like',Y);
for st = 1:W.batchSize:size(Y,1)
    rows = st:min(st+W.batchSize-1,size(Y,1));
    Yb = Y(rows,:);
    A = Yb;
    firstLevel = 1;
    if strcmp(W.reconstructionMode,'approximation')
        firstLevel = level;
    elseif any(strcmp(W.reconstructionMode,{'detail_bands','detail_magnitude','detail_energy'}))
        firstLevel = max(1,level-1);
    end
    if retainBands, D = cell(level,1); end
    for j = firstLevel:level
        next = nk_SurfaceHeatFilter(Yb,op,baseFWHM*2^(j-1));
        band = A-next;
        if retainBands, D{j} = band; end
        A = next;
    end
switch W.reconstructionMode
    case 'approximation'
        R = A;
    case 'selected_details'
        R = zeros(size(Yb),'like',Yb);
        for j = W.detailLevels(:)'
            if j >= 1 && j <= level
                R = R+D{j};
            end
        end
    case 'detail_bands'
        R = band;
    case 'detail_magnitude'
        R = abs(band);
    case 'detail_energy'
        R = band.^2;
    case 'denoised'
        R = A;
        for j = 1:level
            dj = D{j};
            if ~strcmp(W.thresholdMode,'none') && W.thresholdSigma > 0
                validDetails = dj(:,op.vertexMask);
                med = median(validDetails,2);
                sigma = median(abs(validDetails-med),2)/0.6745;
                threshold = W.thresholdSigma*sigma;
                switch W.thresholdMode
                    case 'soft'
                        dj = sign(dj).*max(abs(dj)-threshold,0);
                    case 'hard'
                        dj(abs(dj)<threshold) = 0;
                    otherwise
                        error('nk_SurfaceGraphWavelet:invalidThreshold','Unknown wavelet threshold mode.');
                end
            end
            R = R+dj;
        end
    otherwise
        error('nk_SurfaceGraphWavelet:invalidMode', ...
            'Unsupported graph-wavelet reconstruction mode: %s',W.reconstructionMode);
end
    Yout(rows,:) = R;
    if ~isempty(onBatchComplete)
        onBatchComplete(rows(end),numel(rows));
    end
end
end
