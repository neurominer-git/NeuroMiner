function [ inp ] = nk_ApplyLabelTransform( PREPROC, MODEFL, inp )
global MULTILABEL

if MULTILABEL.flag
    % The user has selected some label to be processed one-by-one.
    if isfield(MULTILABEL,'sel')
        lb=MULTILABEL.sel(inp.curlabel);
    else % ... or wants all labels to be processed one-by-one.
        lb=inp.curlabel;
    end
else
    lb = 1;
end

[ inp.label, inp.targscale, inp.minLbCV, inp.maxLbCV, ~, inp.PolyFact ] = nk_LabelTransform(PREPROC, MODEFL, inp.labels(:,lb));

% Check whether OOCV labels exist and transform them, too, if so.
if isfield(inp,'labelOOCV')
    inp.curlabelOOCV = inp.labelOOCV(:,lb);
    if inp.targscale
        IN.minY = inp.minLbCV; IN.maxY = inp.maxLbCV; 
        inp.curlabelOOCV = nk_PerfScaleObj(inp.labelOOCV(:, lb), IN); 
    end
    if ~isempty(inp.PolyFact), inp.curlabelOOCV = inp.labelOOCV(:,inp.curlabel) .^ (1/inp.PolyFact); end 
end



