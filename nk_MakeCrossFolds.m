% =========================================================================
% cv = nk_MakeCrossFolds(label, RAND, ...
%                        modeflag, groups, groupnames, ...
%                        oldcv, appendfl, auto_adjust)
% =========================================================================
% 
% The function produces an outer/inner CV structure using random
% resampling. To assess the correct indices for each inner CV
% training/testing fold the following syntax has to be used:
%
% EXAMPLES:
% cv.TrainInd{1,1}(cv.class{1,1}{1}.TestInd{1,1}))
%
% This will give you the row indices of the inner CV data fold [1,1] 
% in the binary class{1} for the outer cross-validation fold [1,1].
% 
% The outer CV data fold [1,1] of binary classifier 1 is accessed via:
% cv.TestInd{1,1}(cv.classnew{1,1}{1}.ind)
%
% If you want to access one inner CV fold [k,l] of a binary classifier b 
% with the current outer CV index [i,j] you should use the expression:
% cv.TrainInd{i,j}(cv.class{i,j}{b}.TrainInd{k,l}/TestInd{k,l})
%
% First generate outer CV folds. Whole data is split into training folds
% (used for model generation/learning and validation fold, that are
% completely unseen by the learning algorithm)
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% NeuroMiner 1.4, (c) Nikolaos Koutsouleris, 10/2025

function cv = nk_MakeCrossFolds(label, RAND, modeflag, groups, groupnames, oldcv, appendfl, auto_adjust)

OutPerms        = RAND.OuterPerm;
OutFold         = RAND.OuterFold;
InPerms         = RAND.InnerPerm;
InFold          = RAND.InnerFold;
   
% One vs One, One vs All, Multigroup 
decomposeflag   = RAND.Decompose;
CV2LCO = []; if isfield(RAND,'CV2LCO'), CV2LCO = RAND.CV2LCO; end
CV1LCO = []; if isfield(RAND,'CV1LCO'), CV1LCO = RAND.CV1LCO; end

% Check whether leave-group-in or leave-group-out has been selected.
if isfield(RAND,'CV2Frame') && RAND.CV2Frame == 4 , cv2frame = true; else, cv2frame = false; end
if ~exist('auto_adjust', 'var'), auto_adjust = false; end

try
    if isfield(NM,'Paths') && isfield(NM.Paths,'Log') && exist(NM.Paths.Log,'dir')
        cvlogdir = NM.Paths.Log;
    else
        cvlogdir = pwd;
    end
catch
    cvlogdir = pwd;
end
ts = char(datetime('now','Format','yyyyMMdd_HHmmss'));
cvlogfile = fullfile(cvlogdir, ['CVcycle_' ts '.txt']);

if isempty(CV2LCO)
    if OutFold == -1 || OutFold == numel(label)
        CV2LOO = true;
        OutPerms = 1;
    else
        CV2LOO = false;
    end
end

if InFold == -1 || InFold == numel(label)
    CV1LOO = true;
    InPerms = 1;
else
    CV1LOO = false;
end

% Number of class labels
if ~exist('modeflag','var') || isempty(modeflag), modeflag = 'classification'; end
if ~exist('appendfl','var') || isempty(appendfl), appendfl = false; end

% Does the user want constrained, stratified CV?
% (this helps to keep the distribution of e.g. sites across partitions
% largely constant)
Constraint = [];
if isfield(RAND,'ConstrainedCV') && RAND.ConstrainedCV == 1
    if isfield(RAND,'ConstrainedGroupIndex') && ~isempty(RAND.ConstrainedGroupIndex)
        Constraint = RAND.ConstrainedGroupIndex;
    end
end

[ulb, Label, NaNflag, g, nclass] = nk_Prep4CV(label, modeflag, decomposeflag, groups, groupnames, oldcv);

cv2onlyfl = false; tConstraint = Constraint; tLabel = Label;
if isfield(RAND,'CVOnlyGroup') && RAND.CVOnlyGroup.flag == 1 && ~isempty(RAND.CVOnlyGroup.index)
    cv2onlyfl = true;
    if islogical(RAND.CVOnlyGroup.index) 
        CVOnlyGroupIndex = find(RAND.CVOnlyGroup.index); 
        TrainOnlyGroupIndex = find(~RAND.CVOnlyGroup.index); 
    else
        CVOnlyGroupIndex = RAND.CVOnlyGroup.index;
        TrainOnlyGroupIndex = 1:size(Label,1); TrainOnlyGroupIndex(CVOnlyGroupIndex) =[]; 
    end
    if size(CVOnlyGroupIndex,2)>1
        CVOnlyGroupIndex = CVOnlyGroupIndex'; 
        TrainOnlyGroupIndex = TrainOnlyGroupIndex';
    end
    if ~isempty(Constraint)
        tConstraint = Constraint;
        tConstraint(RAND.CVOnlyGroupIndex) = [];
    end
else
    TrainOnlyGroupIndex = (1:size(Label,1))';
end

if ~isempty(CV2LCO)
    fprintf('\nGenerating outer (CV2) independent group / site partitioning.')
elseif CV2LOO
    fprintf('\nGenerating outer (CV2) LOO partitioning.')
else
    fprintf('\nGenerating outer (CV2) crossvalidation partitioning.')
    fprintf('\nK-fold: %g, Perms: %g', OutFold, OutPerms)
end

% cv is a struct containing TrainInd/TestInd vectors (row indices) and
% Train/TestFold vectors assigning the subjects to each of the defined fold
% per permutation
switch appendfl
    case {0, 1}
        if ~isempty(CV2LCO)
            % Independent group / site validation: Enables e.g. the
            % leave-center-out validation of prediction systems
            cv = nk_INDEPpartition(CV2LCO.ind, Label(TrainOnlyGroupIndex,:), cv2frame, OutPerms, 'SilenceCVLog', true, 'CVLogFile', cvlogfile, 'CVLogAppend', true);
        else
            switch CV2LOO
                case true
                    % This is LOO cross-validation
                    cv = nk_LOOpartition(Label(TrainOnlyGroupIndex,:),'SilenceCVLog', true, 'CVLogFile', cvlogfile, 'CVLogAppend', true);
                case false
                    % This is stratified k-fold cross-validation
                    cv = nk_CVpartition(OutPerms, OutFold, Label(TrainOnlyGroupIndex,:), tConstraint,[],[],'SilenceCVLog', true, 'CVLogFile', cvlogfile, 'CVLogAppend', true);
                    if ~isstruct(cv)
                        OutFold = cv; cv = nk_CVpartition(OutPerms, OutFold, Label(TrainOnlyGroupIndex,:), tConstraint,[],[],'SilenceCVLog', true, 'CVLogFile', cvlogfile, 'CVLogAppend', true);
                        InFold = OutFold - 1;
                    end
            end
        end
        if isempty(cv), return, end
        % Add CV2-only cases to CV2 validation data indices
        if cv2onlyfl
            [ix, jx] = size(cv.TrainInd);
            for i=1:ix
                for j=1:jx
                    cv.TrainInd{i,j} = TrainOnlyGroupIndex(cv.TrainInd{i,j});
                    cv.TestInd{i,j} = [TrainOnlyGroupIndex(cv.TestInd{i,j}); CVOnlyGroupIndex];
                end
            end
        end
    case {2,3}
        cv = oldcv;
end

% Then generate inner CV folds for each outer training fold 
% This will split the training samples further into training / CV
% folds) used for model generation.
[ix,jx] = size(cv.TrainInd);

if isfield(RAND,'Eq') && RAND.Eq.enabled
    Eq = RAND.Eq;
    Eq.AddRemoved2Test = RAND.Eq.addremoved2test;
    if isfield(RAND.Eq,'maxcount')
        Eq.MaxCount = RAND.Eq.maxcount;
    else
        Eq.MaxCount = ceil(numel(Eq.Covar)/40);
    end
    if isfield(RAND.Eq,'mincount') 
        Eq.MinCount = RAND.Eq.mincount;
    else
        Eq.MinCount = ceil(numel(Eq.Covar)/40);
    end
    if isfield(RAND.Eq,'bincount') 
        Eq.BinCount = RAND.Eq.bincount;
    else
        Eq.BinCount = 7;
    end
else
    Eq = [];
end

for i=1:ix
    
    for j=1:jx
        
        if ~isempty(Eq)
            Eq.Covar = RAND.Eq.Covar(cv.TrainInd{i,j});
        end
        if strcmp(modeflag,'classification') && decomposeflag ~= 9
            % First generate label/index vectors for binary classification 
            % for each outer training fold:
            % 1) the training data:
            % label(cv.TrainInd{i,j}) = these are the subject labels of the
            % outer training partion [i,j]
            switch appendfl
                case {0,1,3}
                    
                    if appendfl == 3
                        cvin = cv.cvin{i,j};
                    else
                        cvin = [];
                    end
                    
                    cv.class{i,j} = nk_GenClass(g, ulb, nclass, tLabel(cv.TrainInd{i,j}), decomposeflag, NaNflag);

                    if ~isempty(tConstraint)
                        [cv.class{i,j}, cv.cvin{i,j}, InFold] = nk_MakeFolds(tLabel(cv.TrainInd{i,j}), ...
                            cv.class{i,j}, InFold, InPerms, decomposeflag, tConstraint(cv.TrainInd{i,j}), ...
                            appendfl , cvin , Eq, [], auto_adjust, cv2frame);
                    else
                        if ~isempty(CV1LCO)
                            fprintf('\nGenerate CV1 leave-group out partitions for outer training partition [%g,%g].',i,j)
                            [cv.class{i,j}, cv.cvin{i,j}, InFold] = nk_MakeFolds(tLabel(cv.TrainInd{i,j}), ...
                                cv.class{i,j}, InFold, InPerms, decomposeflag, [], appendfl, cvin, Eq, CV1LCO.ind(cv.TrainInd{i,j}), auto_adjust, cv2frame);
                        else
                            fprintf('\nGenerate CV1 crossvalidation partitions for outer training partition [%g,%g].',i,j)
                            [cv.class{i,j}, cv.cvin{i,j}, InFold] = nk_MakeFolds(tLabel(cv.TrainInd{i,j}), ...
                                cv.class{i,j}, InFold, InPerms, decomposeflag, [], appendfl, cvin, Eq, [], auto_adjust, cv2frame);
                        end
                    end
                    % 2) the validation data:
                    % label(cv.TestInd{i,j}) = these are the subject labels of the
                    % outer validation partion [i,j]
                    cv.classnew{i,j} = nk_GenClass(g, ulb, nclass, Label(cv.TestInd{i,j}), decomposeflag, NaNflag);
                    
                case 2
                    
                    if ~isempty(tConstraint)
                        [cv.class{i,j}, cv.cvin{i,j}, InFold] = nk_MakeFolds(tLabel(cv.TrainInd{i,j}), ...
                            cv.class{i,j}, InFold, InPerms, decomposeflag, tConstraint(cv.TrainInd{i,j}), ...
                            appendfl, cv.cvin{i,j}, Eq, [], auto_adjust, cv2frame);
                    else
                        if ~isempty(CV1LCO)
                            fprintf('\nGenerate CV1 leave-group out partitions for outer training partition [%g,%g].',i,j)
                            [cv.class{i,j}, cv.cvin{i,j}, InFold] = nk_MakeFolds(tLabel(cv.TrainInd{i,j}), ...
                                cv.class{i,j}, InFold, InPerms, decomposeflag, [], appendfl, cv.cvin{i,j}, Eq, CV1LCO.ind(cv.TrainInd{i,j}), auto_adjust, cv2frame);
                        else
                            fprintf('\nGenerate CV1 crossvalidation partitions for outer training partition [%g,%g].',i,j)
                            [cv.class{i,j}, cv.cvin{i,j}, InFold] = nk_MakeFolds(tLabel(cv.TrainInd{i,j}), ...
                                cv.class{i,j}, InFold, InPerms, decomposeflag, [], appendfl, cv.cvin{i,j}, Eq, [], auto_adjust, cv2frame);
                        end
                    end
            end
            
        elseif  strcmp(modeflag,'regression') || (strcmp(modeflag,'classification') && decomposeflag == 9)
            fprintf('\nGenerate CV1 crossvalidation partitions for outer training partition [%g,%g].',i,j)
            
            switch appendfl
               
                case {0,1}
                    if ~isempty(tConstraint)
                        cv.cvin{i,j} = nk_CVpartition(InPerms, InFold, ...
                            tLabel(cv.TrainInd{i,j}), tConstraint(cv.TrainInd{i,j}), Eq, auto_adjust, 'SilenceCVLog', true, 'CVLogFile', cvlogfile, 'CVLogAppend', true);
                    else
                        if CV1LOO
                            cv.cvin{i,j} = nk_LOOpartition(tLabel(cv.TrainInd{i,j}), 'SilenceCVLog', true, 'CVLogFile', cvlogfile, 'CVLogAppend', true);
                        elseif ~isempty(CV1LCO)
                            cv.cvin{i,j} = nk_INDEPpartition(CV1LCO.ind(cv.TrainInd{i,j}), tLabel(cv.TrainInd{i,j}), cv2frame, 'SilenceCVLog', true, 'CVLogFile', cvlogfile, 'CVLogAppend', true);
                        else
                            cv.cvin{i,j} = nk_CVpartition(InPerms, InFold, tLabel(cv.TrainInd{i,j}), [], Eq, auto_adjust, 'SilenceCVLog', true, 'CVLogFile', cvlogfile, 'CVLogAppend', true);
                        end
                    end
                case 2
                    if ~isempty(tConstraint)
                        cv.cvin{i,j} = nk_CVpartition(InPerms, InFold, ...
                            tLabel(cv.TrainInd{i,j}), tConstraint(cv.TrainInd{i,j}), Eq, auto_adjust,'SilenceCVLog', true, 'CVLogFile', cvlogfile, 'CVLogAppend', true);
                    else
                        if CV1LOO
                            cv.cvin{i,j} = nk_LOOpartition(tLabel(cv.TrainInd{i,j}));
                        elseif ~isempty(CV1LCO)
                            cv.cvin{i,j} = nk_INDEPpartition(CV1LCO.ind(cv.TrainInd{i,j}), tLabel(cv.TrainInd{i,j}), cv2frame, 'SilenceCVLog', true, 'CVLogFile', cvlogfile, 'CVLogAppend', true);
                        else
                            cv.cvin{i,j} = nk_CVpartition(InPerms, InFold, tLabel(cv.TrainInd{i,j}), [], Eq, auto_adjust,'SilenceCVLog', true, 'CVLogFile', cvlogfile, 'CVLogAppend', true);
                        end
                    end
            end
        end
    end
end

try
    if exist(cvlogfile,'file') == 2
        info = dir(cvlogfile);
        if info.bytes > 0
            % Show a dialog that survives command-window clears
            msg = sprintf('A cross-validation log was written to:\n\n%s', cvlogfile);
            try
                warndlg(msg, 'CV Log Created');
            catch
                % fallback to console if dialogs are disabled
                fprintf('\n[CV] %s\n', msg);
            end
        end
    end
catch
    % swallow any UI/log stat errors silently
end