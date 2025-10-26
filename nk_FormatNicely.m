function N = nk_FormatNicely(S)
    [m, n] = size(S);
    I = strfind(cellstr(S), '[');  % Find occurrences of '['
    ind0 = ~cellfun(@isempty, I); % Identify non-empty cells

    if ~isempty(I)
        try
            maxI = max(cell2mat(I(ind0)));  % Get maximum index
        catch
            maxI = max(cellfun(@(v) v(1), I(ind0)));
        end
    else
        maxI = [];
    end

    if isempty(maxI)
        N = S; 
        return; 
    end

    N = cell(m, 1);
    for i = 1:m
        if ~isempty(I{i})
            % Ensure I{i} is scalar before using it
            idx = I{i};
            if isscalar(idx)
                N{i} = sprintf(['%-' num2str(maxI) 's%s'], S(i, 1:idx-1), deblank(S(i, idx:n)));
            else
                N{i} = sprintf(['%-' num2str(maxI) 's'], S(i, :)); % Handle unexpected cases gracefully
            end
        else
            N{i} = sprintf(['%-' num2str(maxI) 's'], S(i, :));
        end
    end

    N = char(N);
end