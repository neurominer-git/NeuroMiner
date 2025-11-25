function [mod_exp, idx_map] = expand_splines(mod, opts)
% Returns expanded mod and a mapping from original columns to new columns.
% idx_map is a cell array; idx_map{i} lists the new column indices in mod_exp
% corresponding to original column i (length 1 if unchanged).
mod_exp = [];
idx_map = cell(1, size(mod,2));
cur = 0;

if ~isfield(opts,'spline') || ...
   (~isfield(opts.spline,'df_map') && ~isfield(opts.spline,'spec'))
    % no expansion
    for i=1:size(mod,2)
        mod_exp = [mod_exp, mod(:,i)]; 
        idx_map{i} = cur + (1:1); cur = cur + 1;
    end
    return
end

% normalize spec to a map from original col -> df
df_map = containers.Map('KeyType','double','ValueType','double');
if isfield(opts.spline,'df_map')
    df_map = opts.spline.df_map;
elseif isfield(opts.spline,'spec')
    for k = 1:numel(opts.spline.spec)
        df_map(opts.spline.spec(k).col) = opts.spline.spec(k).df;
    end
end

for i = 1:size(mod,2)
    if isKey(df_map, i)
        df = df_map(i);
        B  = ns_basis(mod(:,i), df);  
        mod_exp = [mod_exp, B];       
        idx_map{i} = cur + (1:df);
        cur = cur + df;
    else
        mod_exp = [mod_exp, mod(:,i)]; 
        idx_map{i} = cur + (1:1);
        cur = cur + 1;
    end
end
