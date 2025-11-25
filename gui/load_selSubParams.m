function handles = load_selSubParams(handles)

curclass = get(handles.popupmenu1,'Value');
if curclass>numel(handles.ModelParamsDesc), curclass=1; end

% Normalize descriptor names to column cell
desc = handles.ModelParamsDesc{curclass};
if iscell(desc)
    names = desc(:);
else
    % works for char arrays, string arrays, and scalar strings
    names = cellstr(desc);
    names = names(:);
end
[names_enum, ~] = FindIdentStringsEnum(names);

% Which params vary?
nParams = numel(names_enum);
varyMask = false(nParams,1);
P = handles.ModelParams{curclass};
for i = 1:nParams
    if iscell(P), varyMask(i) = numel(unique(cell2mat(P(:,i)))) > 1;
    else,        varyMask(i) = numel(unique(P(:,i))) > 1;
    end
end
singleIdx     = find(varyMask);
popupSingles  = names_enum(singleIdx);   % column

% Pairwise labels + indices
pairLabels = {};
pairIdx    = {};
for a=1:numel(singleIdx)-1
    for b=a+1:numel(singleIdx)
        pairLabels{end+1,1} = sprintf('%s × %s', popupSingles{a}, popupSingles{b});
        pairIdx{end+1,1}    = [singleIdx(a) singleIdx(b)];                         
    end
end

% Assemble dropdown entries (column)
rows = {'All parameters'};
if ~isempty(popupSingles), rows = [rows(:); popupSingles(:)]; end
if ~isempty(pairLabels),   rows = [rows(:); {'— pairwise —'}; pairLabels(:)]; end
rows = rows(:); % ensure column

% Build per-row metadata
PairwiseMask        = false(numel(rows),1);
PairwiseIdxByRow    = cell(numel(rows),1);
if ~isempty(pairLabels)
    sepRow = find(strcmp(rows,'— pairwise —'),1,'first');
    if ~isempty(sepRow)
        pr = sepRow+1 : numel(rows);
        PairwiseMask(pr) = true;
        % map pair indices to those rows
        for k = 1:numel(pairIdx)
            PairwiseIdxByRow{pr(k)} = pairIdx{k};
        end
    end
end

PairwiseNamesByRow = cell(numel(rows),1);
if ~isempty(pairLabels)
    sepRow = find(strcmp(rows,'— pairwise —'),1,'first');
    if ~isempty(sepRow)
        pr = sepRow+1 : numel(rows);
        for k = 1:numel(pr)
            % names to display for X and Y axes
            a = pairIdx{k}(1); b = pairIdx{k}(2);
            PairwiseNamesByRow{pr(k)} = { names_enum{a}, names_enum{b} };
        end
    end
end

% Store back
handles.selSubParam.String = rows;
handles.selSubParam.Value  = 1;
handles.PairwiseMap.labels         = pairLabels;
handles.PairwiseMap.idxs           = pairIdx;
handles.PairwiseMap.byDropdown     = PairwiseIdxByRow;
handles.PairwiseMap.pairwiseMask   = PairwiseMask;
handles.PairwiseMap.nameByDropdown = PairwiseNamesByRow;