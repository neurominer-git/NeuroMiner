function TEMPL = nk_GenTemplParam(PREPROC, CV, MODEFL, RAND, Y, inp, kbin, paramfl, act)
global MULTILABEL

if ~exist("act","var") || isempty(act), act = 'params'; end

% For factorization methods: TEMPLATE MAPPING 
if PREPROC.BINMOD
    ukbin = kbin; 
    SrcParam.binmult = 1;
else
    ukbin = 1;
    SrcParam.binmult = 0;
end
SrcParam.CV1perm            = 1; 
SrcParam.CV1fold            = 1;

fprintf('\nGenerating template preprocessing parameters using CV1 training + CV1 test data of CV2 [ %g, %g ].', inp.f, inp.d);

if MULTILABEL.flag && size(inp.labels,2)>1
    lb = MULTILABEL.sel;
else
    lb = 1;
end

% If OOCV data are available and the user wants this explicitly the whole
% discovery data can be used. However, then the discovery results will be
% likely be too good to be true!
if ~isfield(inp,'template_useall') || ( isfield(inp,'template_useall') && ~inp.template_useall )
    TrInd = CV.TrainInd{inp.f,inp.d}; 
else
    fprintf('\nUSING ALL THE DATA FOR TEMPLATE GENERATION !!! THIS WILL LEAD TO OVERFITTING !!! MAKE SURE YOU VALIDATE YOUR MODELS IN EXTERNAL (OOCV) DATA !!!')
    TrInd = (1:height(inp.labels))';
end
SrcParam.covars             = inp.covars;
SrcParam.covars_oocv        = inp.covars_oocv;

for u = 1 : ukbin

    SrcParam.u = u;
    uPREPROC = nk_SetParamChain(paramfl, u, PREPROC);
    paramfl.P{u} = nk_ReturnParamChain(uPREPROC, 1);

     %% Push data into partition / folds
    if ~ukbin>1 || strcmp(MODEFL,'regression')
        TrX = TrInd;
    else
        indtr = create_binary_labels(inp.labels(TrInd), CV.class{inp.f,inp.d}{u}); 
        TrX = TrInd(indtr); 
    end
    SrcParam.TrX = TrX;

    if isfield(uPREPROC,'SPATIAL') && uPREPROC.SPATIAL.cubetype==4
        iY = cell(size(Y,1),1); InputParam.Tr = iY;
        if isfield(paramfl,'PXopt')
            idx = contains(paramfl.PXfull.Params_desc,'FWHM');
            n_fwhm = numel(unique(paramfl.PXunique{u}(:,idx)));
            InputParam.Tr = cell(n_fwhm,1);
            for i=1:n_fwhm
               iY{i} = Y{u}{i}(TrX,:);
               [InputParam.Tr{i}, ~, SrcParam.iTrX] = nk_ManageNanCases(iY{i}, SrcParam.TrX); 
            end
        else
            idx = contains(paramfl.P{u}.Params_desc,'FWHM'); % Check if multiple smoothing kernels have been selected
            n_fwhm=1; if any(idx), n_fwhm = numel(unique(paramfl.P{u}.Params{idx}));end
            InputParam.Tr = cell(n_fwhm,1);
            for i=1:n_fwhm
               iY{i} = Y{i}(TrX,:);
               [InputParam.Tr{i}, ~, SrcParam.iTrX] = nk_ManageNanCases(iY{i}, SrcParam.TrX); 
            end
        end
    else
        iY = Y(TrX,:);
        [InputParam.Tr, ~, SrcParam.iTrX] = nk_ManageNanCases(iY, SrcParam.TrX); 
    end

    switch MODEFL
        case 'classification' 
             if RAND.Decompose ~=9
                SrcParam.BinaryTrainLabel   = SrcParam.TrX;
                SrcParam.BinaryCVLabel      = SrcParam.TrX;
            end
            SrcParam.MultiTrainLabel    = inp.labels(:,lb);
            SrcParam.MultiCVLabel       = inp.labels(:,lb);
        case 'regression'
            SrcParam.TrainLabel         = inp.labels(:,lb);
            SrcParam.CVLabel            = inp.labels(:,lb);
    end
    if isfield(inp,'Yw')
        if isfield(paramfl,'PXopt')
            InputParam.Yw = inp.Yw{u};
        else
            InputParam.Yw = inp.Yw;
        end 
    end
    [TEMPL.Tr{u}, oTrainedParam] = nk_GenPreprocSequence(InputParam, uPREPROC, SrcParam);

    if isfield(paramfl,'PREPROC') && isfield(paramfl,'PXfull') && ~isempty(paramfl.PXopt{u})
        % Here an optimized parameter space exists that has
        % been used to limit the computation to the unique
        % parameter cominations. We create and store the pointers
        % and used them later on to retrieve the right preproc
        % version of the data and the respective preproc params
        [ TEMPL.Param(1,1,u).data_ind, ...
          TEMPL.Param(1,1,u).train_ind, ...
          TEMPL.Param(1,1,u).nP, ...
          TEMPL.Param(1,1,u).nA] = nk_ParamReplicator(paramfl.P{u}, paramfl.PXopt{u}, paramfl.PREPROC, numel(oTrainedParam));
    end
    TEMPL.Param(1,1,u).TrainedParam = oTrainedParam;

end
if strcmp(act,'params'), TEMPL.Tr = []; end