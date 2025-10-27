function [inp, mapY_updated, mapYocv_updated] = compute_average_mapY(inp,mapY,mapYocv,CV,CV2_perm,CV2_fold,nx,modificationflag)

if ~exist('modificationflag','var')
    modificationflag = false;
end

kbin = inp.nclass;

numPermutations = size(CV.cvin{CV2_perm,CV2_fold}.TrainInd,1);
numFolds = size(CV.cvin{CV2_perm,CV2_fold}.TrainInd,2);

if ~modificationflag

    numSubjects = size(CV.TrainInd{CV2_perm,CV2_fold},1) + size(CV.TestInd{CV2_perm,CV2_fold},1);
    
    CV2TrainIndices = CV.TrainInd{CV2_perm,CV2_fold};
    CV2TestIndices = CV.TestInd{CV2_perm,CV2_fold};
    
    trainIdxAll = cell(numSubjects, 1);
    testIdxAll = cell(numSubjects, 1);
    CV2_testIdxAll = cell(numSubjects, 1);

%     commonIdxAll = cell(numSubjects, numPermutations, numFolds);

    for v = 1:numSubjects
        
        for perm = 1:numPermutations

            for fold = 1:numFolds

                if ismember(v,CV2TrainIndices)
                    trainIndices = CV.cvin{CV2_perm,CV2_fold}.TrainInd{perm, fold};
                    testIndices = CV.cvin{CV2_perm,CV2_fold}.TestInd{perm, fold};

                    v_curr = find(CV2TrainIndices==v);

                    trainIdx = find(trainIndices == v_curr);
                    testIdx = find(testIndices == v_curr);
    
                    if isempty(trainIdx)
                        trainIdxAll{v,1}(perm,fold) = NaN;
                    else
                        trainIdxAll{v,1}(perm,fold) = trainIdx;
                    end
    
                    if isempty(testIdx)
                        testIdxAll{v,1}(perm,fold) = NaN;
                    else
                        testIdxAll{v,1}(perm,fold) = testIdx;
                    end

                    CV2_testIdxAll{v,1}(perm,fold) = NaN;

                elseif ismember(v,CV2TestIndices)

                    v_curr = find(CV2TestIndices==v);

                    CV2_testIdxAll{v,1}(perm,fold) = v_curr;

                    trainIdxAll{v,1}(perm,fold) = NaN;

                    testIdxAll{v,1}(perm,fold) = NaN;
                end
    
%                 commonIdxAll{v, perm, fold} = intersect(trainIdx, testIdx);
            end
        end
    end

    mapY_updated = mapY; 
    
    for subj = 1:numSubjects

        allValues = [];
    
        for perm = 1:numPermutations

            for fold = 1:numFolds     

                trainIdx = trainIdxAll{subj};
                testIdx = testIdxAll{subj};
                CV2_testIdx = CV2_testIdxAll{subj};
                
                trainIdxSel = trainIdx(perm,fold);
                testIdxSel = testIdx(perm,fold);
                CV2_testIdxSel = CV2_testIdx(perm,fold);

                validTrainIndices = trainIdxSel(~isnan(trainIdxSel));
                validTestIndices = testIdxSel(~isnan(testIdxSel));
                valid_CV2_TestIndices = CV2_testIdxSel(~isnan(CV2_testIdxSel));
                
                if ~isempty(validTrainIndices)
                    allValues = [allValues; mapY.Tr{perm,fold}{kbin}{1,1}(validTrainIndices,:)];
                end

                if ~isempty(validTestIndices)
                    allValues = [allValues; mapY.CV{perm,fold}{kbin}{1,1}(validTestIndices,:)];
                end

                if ~isempty(valid_CV2_TestIndices)
                    allValues = [allValues; mapY.Ts{perm,fold}{kbin}{1,1}(valid_CV2_TestIndices,:)];
                end
            end
        end
        
        if ~isempty(allValues)
            subjectAverages(subj,:) = mean(allValues, 'omitnan');
        end

        for perm = 1:numPermutations

            for fold = 1:numFolds

                trainIdx = trainIdxAll{subj};
                testIdx = testIdxAll{subj};
                CV2_testIdx = CV2_testIdxAll{subj};
                
                trainIdxSel = trainIdx(perm, fold);
                testIdxSel = testIdx(perm, fold);
                CV2_testIdxSel = CV2_testIdx(perm,fold);

                validTrainIndices = trainIdxSel(~isnan(trainIdxSel));
                validTestIndices = testIdxSel(~isnan(testIdxSel));
                valid_CV2_TestIndices = CV2_testIdxSel(~isnan(CV2_testIdxSel));

                if ~isempty(validTrainIndices)
                    mapY_updated.Tr{perm,fold}{kbin}{1,1}(validTrainIndices,:) = subjectAverages(subj,:);
                end

                if ~isempty(validTestIndices)
                    mapY_updated.CV{perm,fold}{kbin}{1,1}(validTestIndices,:) = subjectAverages(subj,:);
                end

                if ~isempty(valid_CV2_TestIndices)
                    mapY_updated.Ts{perm,fold}{kbin}{1,1}(valid_CV2_TestIndices,:) = subjectAverages(subj,:);
                end
            end
        end
    end

    issmoothed = false(1,nx); if isfield(inp,'issmoothed') && any(inp.issmoothed), issmoothed = inp.issmoothed; end

    if issmoothed, sstr='s'; else, sstr=''; end

    inp.X(nx).([ sstr 'Y']) = subjectAverages;

    if isfield(inp,'oocvflag') && inp.oocvflag

        mapYocv_updated = mapYocv;

        numSubjectsocv = size(inp.X.Yocv,1);

        for subj = 1:numSubjectsocv

            allValues_ocv = [];

            for perm = 1:numPermutations
                for fold = 1:numFolds
                        allValues_ocv = [allValues_ocv; mapYocv.Ts{perm,fold}{kbin}{1,1}(subj,:)];
                end
            end
            subjectAverages_ocv(subj,:) = mean(allValues_ocv, 'omitnan');
        end

        for perm = 1:numPermutations
            for fold = 1:numFolds
                mapYocv_updated.Ts{perm,fold}{kbin}{1,1} = subjectAverages_ocv;
            end
        end

        inp.X(nx).([ sstr 'Yocv']) = subjectAverages_ocv;
    else
        mapYocv_updated = [];
    end
else
    mapY_updated = [];
    if isfield(inp,'oocvflag') && inp.oocvflag
        for perm = 1:numPermutations
            for fold = 1:numFolds
                mapYocv_updated.Ts{perm,fold}{kbin}{1,1} = inp.X(nx).Yocv2;
            end
        end
    else
        for perm = 1:numPermutations
            for fold = 1:numFolds
                mapYocv_updated.Ts{perm,fold}{kbin}{1,1} = inp.X(nx).Yocv;
            end
        end
    end

end