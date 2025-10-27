function F = nk_FScoreFeatRank(Y, L, N, meanfun, varfun, decomp)
% =========================================================================
% function F = nk_FScoreFeatRank(Y, L, N, meanfun, varfun)
% =========================================================================
% Y      : Data
% L      : Target Labels
% N      : Nuisance Labels (optional)
% meanfun: mean function to be used [ default is nm_nanmean ]
% varfun : variance function to be used [ default is nm_nanstd ]
% decomp : Decomposition mode in multi-class label settings. 0 [default] =
%          one-vs-all, 1 = one-vs-one decomposition. Within NM, the global
%          variable RAND is used to define the decomposition mode.
% =========================================================================
% (c) Nikolaos Koutsouleris, 01/2024
global RAND

if ~exist('meanfun','var') || isempty(meanfun)
    meanfun = 'nm_nanmean';
end
if ~exist('varfun','var') || isempty(varfun)
    varfun = 'nm_nanstd';
end

classes = unique(L);
numClasses = numel(classes);
if numClasses > 2
    if ~isempty(RAND)
        decomp = RAND.Decompose;
    elseif ~exist('decomp','var') || isempty(decomp)
        decomp = 0;
    end
else
    decomp=0;
end

if numClasses>2
    switch decomp
        case 0
            % One-vs-all decomposition
            if numClasses>2
                allFScores = zeros(size(Y, 2), numClasses);
                for i=1:numClasses
                    % Get indices to classes
                    indP = L==classes(i); indM = ~indP;
                    % Compute Fscore
                    allFScores(:, i) = computeF(Y, indP, indM, meanfun, varfun);
                end
            end
        case 1
            % One-vs-one decomposition
            mx = numClasses*(numClasses-1)/2;
            allFScores = zeros(size(Y, 2), mx); 
            cnt=1;
            for i=1:numClasses-1
                % Positive class
                indP = L==classes(i); 
                for j=i+1:numClasses
                    % Negative class
                    indM = L==classes(j);
                    % Compute Fscore
                    allFScores(:, cnt) = computeF(Y, indP, indM, meanfun, varfun);
                    cnt=cnt+1;
                end
            end
    end
    F = nm_nansum(allFScores,2);
else
    indP = L==classes(1); indM = ~indP;
    F = computeF(Y, indP, indM, meanfun, varfun)';
end

if exist('N','var') && ~isempty(N)

    ND = zeros(size(Y,2),size(N,2));
    
    % Compute nuisance Fscore(s)
    for i = 1:size(N,2)
        classes = unique(N(:,i));
        numClasses = numel(classes);
        if numClasses > 2
            switch decompose
                case 0
                    allND = zeros(size(Y, 2), numClasses);
                    for j=1:numClasses
                        % Get indices to classes
                        indNP = N(:,i)==classes(j); indNM = ~indP;
                        % Compute nuisance Fscore
                        allND(:, j) = computeF(Y, indNP, indNM, meanfun, varfun);
                    end
    
                case 1
                    mx = numClasses*(numClasses-1)/2;
                    allND = zeros(size(Y, 2), mx); 
                    cnt=1;
                    for j=1:numClasses-1
                        indNP = N(:,i)==classes(j); 
                        for k=i+1:numClasses
                            % Get indices to classes
                            indNM = N(:,i)==classes(k);
                            % Compute nuisance Fscore
                            allND(:, cnt) = computeF(Y, indNP, indNM, meanfun, varfun);
                            cnt=cnt+1;
                        end
                    end
            end
        else
            indNP = N(:,i)==classes(1); indNM = ~indP;
            allND = computeF(Y, indNP, indNM, meanfun, varfun)';
        end
        ND(:,i) = nm_nansum(allND,2);
    end
end

if exist('ND','var'), F = F ./ nm_nansum(ND,2); end

% _________________________________________________________________________
function F = computeF(Y, indP, indM, meanfun, varfun)

meanfun = str2func(meanfun);
varfun = str2func(varfun);

YP = Y(indP,:); YM = Y(indM,:);

% Mean of Positive / Negative Labels
mP = meanfun(YP); mM = meanfun(YM);

% Standard Deviations of Positive / Negative Labels
sP = varfun(YP); sM = varfun(YM);

F= ( mP - mM ).^2 ./ ( sP + sM );