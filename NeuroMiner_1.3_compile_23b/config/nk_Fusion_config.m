function [res, FusionType] = nk_Fusion_config(res, varind)

if exist('varind','var') && numel(varind) > 1
    FusionType = nk_input('Select multimodal fusion strategy',0,'m', ...
            ['Early fusion -> Modality concatenation BEFORE feature preprocessing|' ...
             'Intermediate fusion -> Modality concatenation AFTER preprocessing'],1:2);
else
    FusionType = nk_input('Select multimodal fusion strategy',0,'m', ...
            ['No fusion|' ...
             'Early fusion -> Modality concatenation BEFORE feature preprocessing|' ...
             'Intermediate fusion -> Modality concatenation AFTER preprocessing|' ...
             'Late fusion -> Decision-based data fusion (bagging)'],0:3);
end

DealWithCompleteNanRows = 1;
if FusionType == 1 || FusionType == 2
    if isfield(res.TrainParam.FUSION,'DealWithCompleteNanRows')
        DealWithCompleteNanRowsDef = res.TrainParam.FUSION.DealWithCompleteNanRows;
    else
        DealWithCompleteNanRowsDef = 1;
    end
    DealWithCompleteNanRows = nk_input('Select strategy to deal with cases having completely missing data', 0, 'm', ...
            ['Set rows in combined matrix to NaN where cases have completely missing data in at least one modality (cases will be dynamically removed during further processing)|', ...
             'Impute completely missing data using the data of the other modality (can be very time-consuming if the given data modality has a high dimensionality)'], [1 2], DealWithCompleteNanRowsDef);
end

res.TrainParam.FUSION.flag = FusionType;
res.TrainParam.FUSION.DealWithCompleteNanRows = DealWithCompleteNanRows;


