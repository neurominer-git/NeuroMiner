function p = logistic(f,iparams)
%LOGISTIC Logistic function
% p = logistic(f,iparams) applies the general logistic function to input f
% with parameters iparams. Specify f as a numeric array. Specify iparams as
% a two-element vector. p is returned as the same size as f.

% Copyright 2021 The MathWorks, Inc.

arguments
    f
    iparams = [1 0];
end
p = 1./(1+exp(-iparams(1).*f - iparams(2)));
end