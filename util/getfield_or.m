function v = getfield_or(s, f, d)
    if ~isstruct(s) || ~isfield(s,f) || isempty(s.(f)), v = d; else, v = s.(f); end
end