function [Y,numIter,tElapsed] = orthnmfruletest(X,outTrain)
% orthnmfruletest Map the test/unknown samples into the orth-NMF feature space.
%
%   [Y,numIter,tElapsed] = orthnmfruletest(X,outTrain) computes the 
%   representation Y for the test data X given the trained model in outTrain.
%
%   Input:
%       X        : (r x c) test/unknown data matrix, where each column is a sample.
%       outTrain : struct with fields:
%                     - factors: a cell array {A, S} containing the trained basis 
%                                matrix A and scaling matrix S.
%                     - facts  : scalar, the number of features (clusters).
%                     - optionTr: struct, the options used during training.
%
%   Output:
%       Y        : (k x c) feature representation for test samples.
%       numIter  : scalar, number of iterations performed.
%       tElapsed : scalar, total time (in seconds) used.
%
%   The function initializes Y either by NNDSVD (if specified in the training
%   options) or by k-means clustering and then refines Y through an iterative update.
%
%   See also: orthnmfrule, NNDSVD.
%
%   Copyright (C) <2012>  <Yifeng Li>
%   This program is free software: you can redistribute it and/or modify
%   it under the terms of the GNU General Public License as published by
%   the Free Software Foundation.
%
%   Contact Information:
%   Yifeng Li
%   University of Windsor
%   li11112c@uwindsor.ca; yifeng.li.cn@gmail.com
%   May 03, 2011

tStart = tic;
optionDefault.orthogonal = [1,1];
optionDefault.iter       = 200;
optionDefault.dis        = 1;
optionDefault.residual   = 1e-4;
optionDefault.tof        = 1e-4;

if isfield(outTrain,'optionTr')
    option = outTrain.optionTr;
else
    option = [];
end
option = mergeOption(option, optionDefault);

A = outTrain.factors{1};
S = outTrain.factors{2};
k = outTrain.facts;

[r,c] = size(X);  % r: features, c: samples

% Initialize Y based on the training initialization method.
if isfield(option, 'init') && strncmpi(option.init, 'nndsvd', 6)
    % Use NNDSVD initialization.
    if isfield(option, 'initflag')
        flag = option.initflag;
    else
        % Determine flag based on the initialization string.
        if strcmpi(option.init, 'nndsvd')
            flag = 0;
        elseif strcmpi(option.init, 'nndsvda')
            flag = 1;
        elseif strcmpi(option.init, 'nndsvdar')
            flag = 2;
        else
            flag = 0; % default to NNDSVD if unrecognized.
        end
    end
    % NNDSVD is applied on the new data X.
    [~, H_init] = NNDSVD(X, k, flag);
    Y = H_init;
    Y(Y < eps) = eps;
else
    % Default initialization: use k-means clustering.
    inx = kmeans(X', k, 'Replicates', 50, 'Start', 'plus');
    % Create a binary membership matrix.
    Y = (inx * ones(1,k) - ones(c,1) * cumsum(ones(1,k))) == 0;
    Y = Y' + 0.2;
end

XfitPrevious = Inf;
for i = 1:option.iter
    if option.orthogonal(2) == 1
        Y = Y .* ((S' * A' * X) ./ (S' * A' * X * (Y' * Y)));
    else
        Y = Y .* ((A' * X) ./ (A' * A * Y));
    end
    Y = max(Y, eps);
    
    if mod(i,10) == 0 || i == option.iter
        if option.dis
            disp(['Iterating >>>>>> ', num2str(i), 'th']);
        end
        XfitThis = A * S * Y;
        fitRes = norm(XfitPrevious - XfitThis, 'fro');
        XfitPrevious = XfitThis;
        curRes = norm(X - XfitThis, 'fro');
        if option.tof >= fitRes || option.residual >= curRes || i == option.iter
            s = sprintf('Multiple rule based orthNMF successes! \n # of iterations: %0.0d. \n Final residual: %0.4d.', i, curRes);
            disp(s);
            numIter = i;
            break;
        end
    end
end
tElapsed = toc(tStart);
end
