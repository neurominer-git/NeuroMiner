function [nl, labelsel] = nk_GetLabelDim(MULTILABEL)

nl =1; labelsel = 1;
if ~isempty(MULTILABEL) && MULTILABEL.flag==true
    if isfield(MULTILABEL,'sel')
        nl = numel(MULTILABEL.sel);
        labelsel = MULTILABEL.sel;
    else
        nl = MULTILABEL.dim;
        labelsel = 1:MULTILABEL.dim;
    end
end