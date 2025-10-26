function [nl, labelsel] = nk_GetLabelDim(MULTILABEL)

if isfield(MULTILABEL,'sel')
    nl = numel(MULTILABEL.sel);
    labelsel = MULTILABEL.sel;
else
    nl = MULTILABEL.dim;
    labelsel = 1:MULTILABEL.dim;
end