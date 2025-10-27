% =========================================================================
% FORMAT param = DOR(expected, predicted)
% =========================================================================
% Compute Diagnostic Odds Ratio of classification: 
% sens/(1-spec)/((1-spec)/sens);
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Nikolaos Koutsouleris, 06/2024

function param = DOR(expected, predicted)
if isempty(expected), param = []; return; end
sens = SENSITIVITY(expected,predicted);
spec = SPECIFICITY(expected,predicted);
param = ( sens * spec ) / ((100-sens) * (100-spec));