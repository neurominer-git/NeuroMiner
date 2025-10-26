function cost = logRegCost(y,f,iparams)
%LOGREGCOST Logistic regression cost
% cost = logRegCost(y,f,iparams) calculates the cost of the logistic
% function given truth y, prediction f, and logistic params iparams.
% Specify y and f as column vectors. Specify iparams as a two-element row
% vector in the form [A,B], where A and B are the model parameters:
%
%                1
% p(x) = ------------------
%         1 + e^(-A*f - B)
%

% Copyright 2021 The MathWorks, Inc.

arguments
    y (:,1) {mustBeA(y,["single","double"])}
    f (:,1) {mustBeA(f,["single","double"])}
    iparams (1,2) {mustBeA(iparams,["single","double"])}
end
p = logistic(f,iparams);
cost = -sum(y.*log(p) + (1-y).*log(1-p));
end