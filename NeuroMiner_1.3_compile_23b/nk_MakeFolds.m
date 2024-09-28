function [class, cv, xfolds] = nk_MakeFolds(label, class, nfolds, nperms, decomposeflag, constraint, appendfl, oldcv, eq, lco, auto_adjust, cv2frame)

groupind = [1,-1]; if ~exist('auto_adjust', 'var'), auto_adjust = false; end
xfolds = nfolds;
% Generate CV1 partitions
if appendfl ~=3
    if exist('lco','var') && ~isempty(lco)
        [cv, nfolds, nperms] = nk_INDEPpartition(lco, label, cv2frame);
    else
        LOOflag = false; if nfolds == -1; LOOflag = true; end
        if ~LOOflag
            cv = nk_CVpartition(nperms, nfolds, label, constraint, eq, auto_adjust);
            if ~isstruct(cv)
                nfolds = cv; cv = nk_CVpartition(nperms, nfolds, label, constraint, eq, auto_adjust);
            end
        else
            nfolds = numel(label); nperms = 1;
            cv = nk_LOOpartition(label);
        end
    end
else
    cv = oldcv; clear oldcv;
end
tclass = class;

for i=1:length(class)
    
    if isfield(tclass,'TrainInd')
        tclass{i}.TrainInd{nperms,nfolds}   = [];
        tclass{i}.TestInd{nperms,nfolds}    = [];
        tclass{i}.TrainLabel{nperms,nfolds} = [];
        tclass{i}.TestLabel{nperms,nfolds}  = [];
    else
        if iscell(tclass)
            tclass{i}.TrainInd              = cell(nperms,nfolds);
            tclass{i}.TestInd               = cell(nperms,nfolds);
            tclass{i}.TrainLabel            = cell(nperms,nfolds);
            tclass{i}.TestLabel             = cell(nperms,nfolds);
        else
            tclass.TrainInd                 = cell(nperms,nfolds);
            tclass.TestInd                  = cell(nperms,nfolds);
            tclass.TrainLabel               = cell(nperms,nfolds);
            tclass.TestLabel                = cell(nperms,nfolds);
        end
    end    
    
    for j=1:nperms

        for k=1:nfolds
 
                switch decomposeflag
                    
                    case 1 % One-vs-One
                        
                        for l=1:length(groupind)
                        
                            belongstrain = find(label(cv.TrainInd{j,k}) == class{i}.groups(l));
                            belongstest = find(label(cv.TestInd{j,k}) == class{i}.groups(l));

                            if ~isempty(belongstrain)
                                tclass{i}.TrainInd{j,k} = [tclass{i}.TrainInd{j,k}; ...
                                    cv.TrainInd{j,k}(belongstrain)];
                                tclass{i}.TrainLabel{j,k} = [tclass{i}.TrainLabel{j,k}; ...
                                    groupind(l)*ones(size(belongstrain,1),1)];
                            end

                            if ~isempty(belongstest)
                                tclass{i}.TestInd{j,k} = [tclass{i}.TestInd{j,k}; ...
                                     cv.TestInd{j,k}(belongstest)];
                                tclass{i}.TestLabel{j,k} = [tclass{i}.TestLabel{j,k}; ...
                                    groupind(l)*ones(size(belongstest,1),1)];
                            end
                            
                        end
                        belongstrain = find(~isfinite(label(cv.TrainInd{j,k})));
                        if ~isempty(belongstrain)
                            tclass{i}.TrainInd{j,k} = [tclass{i}.TrainInd{j,k}; ...
                                cv.TrainInd{j,k}(belongstrain)];
                            tclass{i}.TrainLabel{j,k} = [tclass{i}.TrainLabel{j,k}; ...
                                nan(size(belongstrain,1),1)];
                        end
                        
                    case 2 % One-Vs-All
                        
                        tclass{i}.TrainInd{j,k}  = cv.TrainInd{j,k};
                        lb = zeros(size(cv.TrainInd{j,k}));
                        indpos = label(cv.TrainInd{j,k}) == class{i}.groups; 
                        indneg = label(cv.TrainInd{j,k}) ~= class{i}.groups;
                        indnan = ~isfinite(label(cv.TrainInd{j,k}));
                        lb(indpos) = 1; lb(indneg) = -1;
                        if ~isempty(indnan), lb(indnan) = NaN; end
                        tclass{i}.TrainLabel{j,k} = lb;
                        
                        tclass{i}.TestInd{j,k}   = cv.TestInd{j,k};
                        lb = zeros(size(cv.TestInd{j,k}));
                        indpos = label(cv.TestInd{j,k}) == class{i}.groups; 
                        indneg = label(cv.TestInd{j,k}) ~= class{i}.groups;
                        lb(indpos) = 1; lb(indneg) = -1;
                        tclass{i}.TestLabel{j,k} = lb;
                        
                    case 9 % Multi-group

                        tclass.TrainInd{j,k}  = cv.TrainInd{j,k};
                        tclass.TestInd{j,k}   = cv.TestInd{j,k};
                        tclass.TrainLabel{j,k} = label(cv.TrainInd{j,k});
                        tclass.TestLabel{j,k} = label(cv.TestInd{j,k});
                end
        end
        
    end
    if iscell(tclass)
        switch appendfl
            case {0,1,3}
                class{i} = tclass{i};
            case 2
                class{i}.TrainInd = [ class{i}.TrainInd; tclass{i}.TrainInd ];
                class{i}.TestInd = [ class{i}.TestInd; tclass{i}.TestInd ];
                class{i}.TrainLabel = [ class{i}.TrainLabel; tclass{i}.TrainLabel ];
                class{i}.TestLabel = [ class{i}.TestLabel; tclass{i}.TestLabel ];
        end
    else
        switch appendfl
            case {0,1,3}
                class = tclass;
            case 2
                class.TrainInd = [ class.TrainInd; tclass.TrainInd ];
                class.TestInd = [ class.TestInd; tclass.TestInd ];
                class.TrainLabel = [ class.TrainLabel; tclass.TrainLabel ];
                class.TestLabel = [ class.TestLabel; tclass.TestLabel ];
        end
    end
end

if exist('oldcv','var') && ~isempty(oldcv) && appendfl == 2
     cv.TrainInd = [ oldcv.TrainInd; cv.TrainInd];
     cv.TestInd = [ oldcv.TestInd; cv.TestInd];
end

return
