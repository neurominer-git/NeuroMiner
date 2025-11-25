function qc = combat_qc(Y_pre, Y_post, batch)
% Y_pre, Y_post : p x n
% batch         : n x 1 (or 1 x n)

batch = batch(:)';
if size(Y_pre,2) ~= numel(batch) || size(Y_post,2) ~= numel(batch)
    error('combat_qc: Y and batch sizes mismatch.');
end

qc = struct();

[qc.R2_pre,  qc.R2_perfeat_pre]  = batch_R2(Y_pre,  batch);
[qc.R2_post, qc.R2_perfeat_post] = batch_R2(Y_post, batch);

[qc.z_pre,  qc.mu_batch_pre,  qc.mu_global_pre]  = batch_offsets(Y_pre,  batch);
[qc.z_post, qc.mu_batch_post, qc.mu_global_post] = batch_offsets(Y_post, batch);

% verdict
if qc.R2_pre < 0.01
    qc.verdict = 'no_batch_effect';
    qc.message = 'ComBat QC: little to no detectable batch effect before correction.';
else
    red  = 1 - qc.R2_post / max(qc.R2_pre, eps);
    maxz = max(abs(qc.z_post));

    if red > 0.75 && maxz < 0.3
        qc.verdict = 'good';
        qc.message = sprintf(['ComBat QC: strong batch-effect reduction (%.1f%%). ', ...
                              'All batches well aligned (max |z|=%.2f).'], ...
                              100*red, maxz);
    elseif red > 0.25 && maxz < 0.7
        qc.verdict = 'partial';
        qc.message = sprintf(['ComBat QC: partial batch-effect reduction (%.1f%%). ', ...
                              'Residual offsets remain (max |z|=%.2f).'], ...
                              100*red, maxz);
    else
        qc.verdict = 'poor';
        qc.message = sprintf(['ComBat QC: limited batch-effect reduction (%.1f%%). ', ...
                              'Substantial residual offsets (max |z|=%.2f). ', ...
                              'Check batch structure or unseen-batch settings.'], ...
                              100*red, maxz);
    end
end

end

function [R2_med, R2_perfeat] = batch_R2(Y, batch)
[p,n] = size(Y);
levels = unique(batch);
B = numel(levels);

R2_perfeat = zeros(p,1);
for j = 1:p
    y = Y(j,:);
    mu_all = mean(y);
    mu_b   = zeros(1,B);
    var_w  = zeros(1,B);
    n_b    = zeros(1,B);
    for i = 1:B
        idx = (batch==levels(i));
        yb  = y(idx);
        mu_b(i)  = mean(yb);
        var_w(i) = var(yb,0,2);
        n_b(i)   = sum(idx);
    end
    VB = var(mu_b,0,2);
    VW = mean(var_w);
    R2_perfeat(j) = VB / (VB + VW + eps);
end
R2_med = median(R2_perfeat);
end

function [z_b, mu_b, mu_all] = batch_offsets(Y, batch)
[~,n] = size(Y);
levels = unique(batch);
B = numel(levels);

mu_all = mean(Y(:));
mu_b   = zeros(B,1);
for i = 1:B
    idx = (batch==levels(i));
    mu_b(i) = mean(Y(:,idx),'all');
end
sd_all = std(Y(:));
z_b = (mu_b - mu_all) / (sd_all + eps);
end
