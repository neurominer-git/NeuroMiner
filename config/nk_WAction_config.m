function [W_ACT, PX] = nk_WAction_config(W_ACT, PX, datadesc, brainmask, defaultsfl, parentstr)

if ~exist('defaultsfl','var') || isempty(defaultsfl),  defaultsfl = 0; end
softflag            = 1;
threshvec           = [25 50 75];
absvec              = [ 0.25 0.50 0.75 ];
topfeats            = ( 10:10:100 );
clustfl             = 2; 
exppar              = 1;
operator            = @ge;
cutoff              = 0;
act = 0;

if ~defaultsfl
    
    if ~isfield(W_ACT,'softflag'),      W_ACT.softflag = softflag; end
    if ~isfield(W_ACT,'threshvec'),     W_ACT.threshvec = threshvec; end
    if ~isfield(W_ACT,'absvec'),        W_ACT.absvec = absvec; end
    if ~isfield(W_ACT,'topfeats'),      W_ACT.topfeats = topfeats; end
    if ~isfield(W_ACT,'clustflag'),     W_ACT.clustflag = clustfl; end
    if ~isfield(W_ACT,'exponent'),      W_ACT.exponent = exppar; end
    if ~isfield(W_ACT,'operator'),      W_ACT.operator = operator; end
    if ~isfield(W_ACT,'cutoff'),        W_ACT.cutoff = cutoff; end
    if ~exist('PX','var'),              PX = []; end
    cluststr            = {'yes','no'};
    weightstr           = {'Soft weighting','Percentile thresholding','Absolute thresholding', 'Top X features', 'Operator at cutoff'};
    menustr = sprintf('Thresholding or weighting of features using weight vector(s) [ %s ]', weightstr{W_ACT.softflag}); menuact = 1;
    
    switch W_ACT.softflag 
        case 1
            menustr = sprintf('%s|Define exponential multiplier [ %s ]',menustr,nk_ConcatParamstr(W_ACT.exponent)); menuact = [ menuact 4 ];
        case 2
            menustr = sprintf('%s|Define percentile thresholds for feature extraction [ %s ]', menustr, nk_ConcatParamstr(W_ACT.threshvec)); menuact = [ menuact  2];
            if datadesc.type
                menustr = sprintf('%s|Clusterize extracted voxels [ %s ]', menustr, cluststr{W_ACT.clustflag}) ; menuact = [ menuact 3 ];
            end
        case 3
            menustr = sprintf('%s|Define absolute thresholds for feature extraction [ %s ]',menustr, nk_ConcatParamstr(W_ACT.absvec)); menuact = [ menuact  5];
            if datadesc.type
                menustr = sprintf('%s|Clusterize extracted voxels [ %s ]', menustr, cluststr{W_ACT.clustflag}) ; menuact = [ menuact 3 ];
            end
        case 4
            menustr = sprintf('%s|Define absolute numbers of feature for extraction [ %s ]',menustr, nk_ConcatParamstr(W_ACT.topfeats)); menuact = [ menuact  6];
            if datadesc.type
                menustr = sprintf('%s|Clusterize extracted voxels [ %s ]', menustr, cluststr{W_ACT.clustflag}) ; menuact = [ menuact 3 ];
            end
        case 5
            menustr = sprintf('%s|Define operator and cutoff for extraction [ Operator %s => Cutoffs: %s ]',menustr, func2str(W_ACT.operator), nk_ConcatParamstr(W_ACT.cutoff)); menuact = [ menuact  7];
            if datadesc.type
                menustr = sprintf('%s|Clusterize extracted voxels [ %s ]', menustr, cluststr{W_ACT.clustflag}) ; menuact = [ menuact 3 ];
            end
    end
    
    nk_PrintLogo
    mestr = 'Extract features from rank / weight vector'; navistr = [parentstr ' >>> ' mestr]; fprintf('\nYou are here: %s >>> ',parentstr); 

    act = nk_input(mestr,0,'mq', menustr , menuact);
    
    switch act
        case 1
            W_ACT.softflag  = nk_input('Define ranking mode',0,'m','Soft weighting|Percentile thresholding|Absolute thresholding|Top X features|Operator threshold at cutoff',1:5, W_ACT.softflag);
        case 2
            W_ACT.threshvec = nk_input('Define vector of percentile thresholds',0,'e',W_ACT.threshvec);
        case 3
            W_ACT.clustflag = nk_input('Clusterize voxels based on thresholded weight vector',0,'yes|no',[1,2], W_ACT.clustflag);
            if W_ACT.clustflag, W_ACT.brainmask = brainmask; end
        case 4
            W_ACT.exponent = nk_input('Define exponential multiplier(s)',0,'e', W_ACT.exponent);
        case 5
            W_ACT.absvec = nk_input('Define vector of absolute thresholds',0,'e',W_ACT.absvec);
        case 6
            W_ACT.topfeats = nk_input('Define vector of top X features',0,'e',W_ACT.topfeats);
        case 7
            operators = {@ge,@gt,@le,@lt,@ne};
            mask = cellfun(@(f) isequal(f, W_ACT.operator), operators);
            operator_def = find(mask,1); if isempty(operator_def), operator_def = 1; end
            sel = nk_input('Select operator for feature extraction',0,'m','>=|>|<=|<|~=',1:5,operator_def);
            W_ACT.operator = operators{sel};
            W_ACT.cutoff = nk_input('Define operator cutoff value', 0,'e',W_ACT.cutoff);
    end
else 
    W_ACT.softflag = softflag;
    W_ACT.threshvec = threshvec;
    W_ACT.absvec = absvec;
    W_ACT.topfeats = topfeats;
    W_ACT.clustflag = clustfl;
    W_ACT.exponent = exppar;
    W_ACT.operator = operator;
    W_ACT.cutoff = cutoff;
end
PX = nk_AddParam([], [],1, PX,'reset');
switch W_ACT.softflag
    case 1
        PX = nk_AddParam(W_ACT.exponent,'ExpMult', 1, PX);
    case 2
        PX = nk_AddParam(W_ACT.threshvec,'Thresholds', 1, PX);
    case 3
        PX = nk_AddParam(W_ACT.absvec,'Absolute thresholds', 1, PX);
    case 4
        PX = nk_AddParam(W_ACT.topfeats,'Top feats', 1, PX);
    case 5
        PX = nk_AddParam(W_ACT.cutoff,'Cutoffs', 1, PX);
end
if act, [W_ACT, PX] = nk_WAction_config(W_ACT, PX, datadesc, brainmask, [], parentstr); end
