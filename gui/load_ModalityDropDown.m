function handles = load_ModalityDropDown(handles)
% Populate modality dropdown when analysis switches (not on click)

curlabel = handles.curlabel; 

% Remember previous modality selection (default to 1)
prevMod = 1;
if isfield(handles,'curmodal') && ~isempty(handles.curmodal)
    prevMod = handles.curmodal;
end

nMods = size(handles.visdata, 1);
modList = cell(nMods,1);
for i = 1:nMods
    try
        varind  = handles.visdata{i, curlabel}.params.varind;
        desc    = handles.NM.datadescriptor{varind}.desc;
    catch
        desc = '';
    end
    modList{i} = sprintf('Modality #%g: %s', i, desc);
end

% Optionally prepend the special “shares” item
if has_modality_share(handles)
    fullList = [{'↗ Inspect modality statistics…'}; modList(:)];
    handles.idxModalShare = 1;
    % shift previous selection by +1
    setVal = min(prevMod + 1, numel(fullList));
else
    fullList = modList;
    handles.idxModalShare = [];
    setVal = min(prevMod, numel(fullList));
end

% Write dropdown and update state
handles.selModality.String = fullList;
handles.selModality.Value  = max(1, setVal);

% Update handles.curmodal to a real modality index (ignore the shares row)
if ~isempty(handles.idxModalShare)
    if handles.selModality.Value == handles.idxModalShare
        % keep previous real modality; if invalid, fallback to 1
        if prevMod < 1 || prevMod > nMods, prevMod = 1; end
        handles.curmodal = prevMod;
    else
        handles.curmodal = handles.selModality.Value - 1;
    end
else
    handles.curmodal = handles.selModality.Value;
end

% After populating the modality list, also build the measures list for it
handles = load_selVisMeasDropDown(handles);

end

function tf = has_modality_share(h)
tf = false;
try
    S = h.visdata{1}.ModAgg_L2nShare;
catch
    S = [];
end
if isempty(S), return; end
if iscell(S)
    tf = any(cellfun(@(c) ~isempty(c) && any(isfinite(c(:))), S));
elseif isnumeric(S)
    tf = any(isfinite(S(:)));
end
end