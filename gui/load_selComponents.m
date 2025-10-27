function load_selComponents(hDropdown, visData, curclass, curmod)
% load_selComponents  Populate a dropdown with kept component info (per modality).
%
% load_selComponents(hDropdown, visData, curclass, curmod)
%   hDropdown : handle to popupmenu
%   visData   : NM.analysis{x}.visdata{y}
%   curclass  : current class index
%   curmod    : current modality index

if nargin < 4, curmod = 1; end
if ~isfield(visData,'Report') || ~isfield(visData.Report{curclass},'components')
    set(hDropdown, 'String', {'<no components available>'}, ...
                           'Enable','off', 'Value',1, 'UserData',[]);
    return
end

cmp = visData.Report{curclass}.components;
if iscell(cmp) 
    isInter = true;
    idx = visData.Report{curclass}.components_idxs == curmod;
else
    isInter = false;
    idx =[];
end
meanPval = []; meanCorr=[]; selPct = [];
if isInter
    if ~isempty(idx)
        meanPval = cmp{idx}.mean_p_cv2;
        meanCorr = cmp{idx}.mean_r_cv2;
        selPct = cmp{idx}.coverage_cv1(:,1) *100 ./ cmp{idx}.coverage_cv1(:,2);
        keptMask  = visData.CompKept{1}{idx};    
    end
else
    meanPval = cmp.mean_p_cv2;
    meanCorr = cmp.mean_r_cv2;
    selPct = cmp.coverage_cv1(:,1) *100 ./ cmp.coverage_cv1(:,2);
    keptMask  = visData.CompKept{1};
end

if isempty(meanCorr) && isempty(meanPval)
    % If there are no kept components, disable
    set(hDropdown, 'String', {'<no components available>'}, ...
                       'Enable','off', 'Value',1, 'UserData',[]);
    return
end
idxs      = find(keptMask);
nKept     = numel(idxs);

% Means across CV2 models

% Build item list (+1 for the “stats” entry at the top)
items = cell(nKept+1, 1);
items{1} = '↗ View component statistics…';

for ii = 1:nKept

    % safe fetches in case arrays are shorter than k
    if ~isempty(selPct),   sf = selPct(ii);     end
    if ~isempty(meanCorr), cc = meanCorr(ii);   end

    if ~isempty(meanPval) && isfinite(meanPval(ii))
        ptxt = sprintf('-log10(p)=%.3f', meanPval(ii)); 
        items{ii+1} = sprintf('Component #%d: pres=%1.1f%% | avg corr=%.3f | %s', idxs(ii), sf, cc, ptxt);
    else
        items{ii+1} = sprintf('Component #%d: pres=%1.1f%% | avg corr=%.3f', idxs(ii), sf, cc);
    end
end

% Map dropdown rows → component indices (row 1 = stats entry)
ud.componentIdx = [NaN, idxs(:)'];  % NaN marks the stats item
ud.modality     = curmod;
ud.class        = curclass;

set(hDropdown, 'String', items, 'Value', 2, 'Enable', 'on', 'UserData', ud);

