function PREPROC = nk_DefPREPROC_config(modeflag, nan_in_pred, nan_in_label)

if ~exist('nan_in_pred','var') || isempty(nan_in_pred), nan_in_pred = false; end
if ~exist('nan_in_label','var') || isempty(nan_in_label), nan_in_label = false; end

PREPROC.BINMOD = 1; PREPROC.FEATSEL.active = 0;

PREPROC.ACTPARAM{1}.SCALE   = nk_Scale_config([],[],1);
PREPROC.ACTPARAM{1}.cmd     = 'scale';

PREPROC.ACTPARAM{2}.PRUNE   = nk_Prune_config([],[],[],1);
PREPROC.ACTPARAM{2}.cmd     = 'elimzero';

if nan_in_pred % Adjust defaults to NaN in the predictor data
    PREPROC.ACTPARAM{1}.SCALE.zerooutflag   = 1;
    PREPROC.ACTPARAM{2}.PRUNE.nan           = 2;
    PREPROC.ACTPARAM{2}.PRUNE.inf           = 2;
    PREPROC.ACTPARAM{3}.IMPUTE              = nk_Impute_config([],[],[],[],1);
    PREPROC.ACTPARAM{3}.cmd                 = 'impute';
end

if nan_in_label % Adjust defaults to NaN in the labels data
    PREPROC.LABELMOD.LABELIMPUTE            = nk_Impute_config([], [], [], [], 1);
    PREPROC.LABELMOD.cmd                    = 'labelimpute';
end

if strcmp(modeflag,'regression'), PREPROC.LABELMOD.TARGETSCALE = true; end