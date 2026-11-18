function [ inp, contfl, analysis, mapY, GD, MD, Param, P, mapYocv ] = nk_ApplyTrainedPreproc(analysis, inp, paramfl, Param)
% =========================================================================
% [ contfl, analysis, mapY, GD, MD, Param, P, mapYocv ] = ...
%                           nk_ApplyTrainedPreproc(analysis, inp, paramfl)
% =========================================================================
% Main function to compute /load and return preprocessing parameters and
% preprocessed data for trained analysis chains. The functions is used by
% nk_VisModels, nk_OOCV, nk_MLInterpreter, and model export. It identifies the
% smallest number of preprocessing
% parameter combinations needed for a trained model, for which the preprocessing 
% chains have to be computed. This set of parameter combinations is then
% forwarded to nk_PerfPreprocess or nk_Prepwhere the actual computations are
% coordinated.
% 
% Input:
% -------
% analysis
% inp
% paramfl: struct => use_exist,         Use existing data
%                    loadparam,         Load parameter files
%                    found,             Flag for found data files
%                    write,             Write parameters to disk 
%                    CV1op,             Operate at CV1 level
%                    multiflag          Multi-class mode
%                    template_flag      Run preprocessing on all data to
%                                       generate template for reordering
%                                       operations
% Param :   Pretrained parameter structure
%
% Output:
% -------
% inp, contfl, analysis, mapY, GD, MD, Param, P, mapYocv
% =========================================================================
% (c) Nikolaos Koutsouleris, 08/2023

global VERBOSE PREPROC SAV OCTAVE

contfl = false; 
mapYocv = []; mapY = []; GD = []; MD = []; P = paramfl; 
% Load CVdatamat for current CV2 partition
if ~exist(analysis.RootPath,'dir'), analysis.RootPath = nk_DirSelector('Specify root directory of analysis'); end
if isempty(analysis.GDfilenames{inp.f,inp.d}), contfl = true; return; end
GDpath = fullfile(analysis.RootPath, analysis.GDfilenames{inp.f,inp.d});
if ~exist(GDpath,'file'), fprintf('\n%s not found! Skipping CV2 partition [%g,%g]:\n%s',GDpath, inp.f, inp.d); contfl = true; end

smoothonly = false; if isfield(inp,'smoothonly') && inp.smoothonly, smoothonly = true; end
% Loop through modalities ( if needed )

if isfield(inp,'loadGD') && ~isempty(inp.loadGD) && inp.loadGD
    if VERBOSE, fprintf('\nLoading CVdatamat for CV2 partition [%g,%g]:\n%s', inp.f, inp.d, GDpath); end
    load(GDpath);
    % --- Auto-recognize and decode GD_enc -> GD (triplet format) ---
    if exist('GD_enc','var')
        fprintf('\nDetected GD_enc (triplet). Decoding to full GD ...');
        GD = nm_decode_nan_triplets(GD_enc);  % idempotent decoder
        clear GD_enc
        fprintf(' done.');
    end
end
if smoothonly
    inp = nk_PerfInitSpatial(analysis, inp, paramfl);
    nM = numel(inp.PREPROC);
    inp.isSpatialPreprocessed = true(1,nM);
    inp.smoothonly = false;
    Param = [];
else
    Yocv = []; 
    nM = numel(inp.PREPROC);
    isSpatialPreprocessed = false(1,nM); if isfield(inp,'isSpatialPreprocessed') && any(inp.isSpatialPreprocessed), isSpatialPreprocessed = inp.isSpatialPreprocessed; end
    if ~isfield(inp,'saveparam'), inp.saveparam = false; end

    P = cell(1, nM); mapY = cell(1, nM); mapYocv = cell(1,nM); 
    % Check whether optimized preprocessing params exist
    if exist("Param",'var') && ~isempty(Param)
        if iscell(paramfl)
            paramfl{1}.found= true;
        else
            paramfl.found = true;
        end
    else
        Param = cell(1,nM);
        if isfield(inp,'optpreprocmat') && ~isempty(inp.optpreprocmat) && ~inp.saveparam
            if exist(inp.optpreprocmat{inp.f,inp.d},'file')
                fprintf('\nLoading optimized pre-processing parameters for CV2 [%g,%g]:\n%s', ...
                        inp.f, inp.d, inp.optpreprocmat{inp.f,inp.d}); 
                load(inp.optpreprocmat{inp.f,inp.d}); 
                if iscell(paramfl)
                    paramfl{1}.found= true;
                else
                    paramfl.found = true;
                end
            else
                if VERBOSE, fprintf('ERROR: Loading of pre-computed parameters not possible because path to file does not anymore exist. Update your paths!'); end
            end
        else
            if VERBOSE, fprintf('\nComputing pre-processing parameters for CV2 [%g,%g].\n', inp.f, inp.d); end
        end
    end

    for n=1:nM
        
        % Check if the modality has to be skipped in case all observations
        % consist of NaN

        % Has the [imaging] data been smoothed already?
        if isSpatialPreprocessed(n), sstr='s'; else, sstr=''; end

        % Training/CV data extraction from container
        Y = inp.X(n).([ sstr 'Y']);

        % Is the a second Yocv container (e.g. if OOCV data is interpreted, 
        % and multiple OOCV case instances have been generated in nk_MLInterpreter)
        if isfield(inp.X(n),[ sstr 'Yocv2']) && ~isempty(inp.X(n).([ sstr 'Yocv2']))
            Yocv = inp.X(n).([ sstr 'Yocv2']);
        elseif isfield(inp.X(n),[ sstr 'Yocv']) && ~isempty(inp.X(n).([ sstr 'Yocv']))
            Yocv = inp.X(n).([ sstr 'Yocv']); 
        end

        % Do we need to extract a weighting mask, too?
        if isfield(inp.X(n), [ sstr 'Yw']) && ~isempty(inp.X(n).([ sstr 'Yw']))
            inp.iYw = inp.X(n).([ sstr 'Yw']);
        elseif isfield(inp,'iYw')
            inp = rmfield(inp,'iYw');
        end

        % Restore modality-local companion shelves at the same boundary as Y.
        % Downstream consumers must not interpret spatial shelf containers.
        if isSpatialPreprocessed(n)
            if isfield(inp.X(n),'sAltY') && ~isempty(inp.X(n).sAltY)
                inp.AltY = inp.X(n).sAltY;
            elseif isfield(inp,'AltY')
                inp = rmfield(inp,'AltY');
            end
            if isfield(inp,'C') && ~isempty(inp.C) && inp.C{1,1}.calibflag
                if ~isfield(inp.X(n),'sCocv') || isempty(inp.X(n).sCocv)
                    error('nk_ApplyTrainedPreproc:MissingCalibrationShelves', ...
                        ['Spatial shelves are resident for modality #%g, but its ' ...
                         'calibration shelves are missing.'], n);
                end
                inp.C{1,1}.Y = inp.X(n).sCocv;
            end
        else
            if isfield(inp.X(n),'altY') && ~isempty(inp.X(n).altY)
                inp.AltY = inp.X(n).altY;
            elseif isfield(inp,'AltY')
                inp = rmfield(inp,'AltY');
            end
        end
    
        % Are there modality-specific runtime parameters that should be extracted?
        if iscell(paramfl)
            tparamfl = paramfl{n};
        else
            tparamfl = paramfl;
        end
        
        % ... and modality-specific preprocessing params?
        if iscell(inp.PREPROC)
            PREPROC = inp.PREPROC{n};
        else
            PREPROC = inp.PREPROC;
        end
        % nm2-allow: current NM2 optionally supplies OOCV-only preprocessing at this legacy ingress boundary.
        if isfield(inp,'OOCVApplicationPreprocByIndex')
            preprocIndex = inp.tF(n);
            runtimeProjection = inp.OOCVApplicationPreprocByIndex{preprocIndex};
            if ~isempty(runtimeProjection)
                if runtimeProjection.preprocIndex ~= preprocIndex
                    error('nk_ApplyTrainedPreproc:InvalidOOCVApplicationProjection', ...
                        'OOCV application preprocessing projection does not match PREPROC{%d}.', preprocIndex);
                end
                PREPROC = runtimeProjection.PREPROC;
                PREPROC.OOCVAPP_RUNTIME = runtimeProjection;
            end
        end
        tparamfl.PV = inp.X(n);

        if VERBOSE, fprintf('\nGenerate pre-processing parameter array for CV2 partition [%g,%g].\n',inp.f,inp.d); end
        tparamfl = nk_PrepPreprocParams(PREPROC, tparamfl, analysis, n, inp.ll, inp.curlabel);

        % Param is a structure that contains all relevant info to generate the features 
        % needed by the optimized classifier / predictor system
        if tparamfl.found 
            tparamfl.Param = Param{n};
        elseif isfield(tparamfl,'Param')
            tparamfl = rmfield(tparamfl,'Param');
        end
        
        % now we are ready to run the preprocessing pipeline
        tparamfl.currmodal = n;

        if inp.stacking
            [mapY{n}, Param{n}, P{n}, mapYocv{n}] = nk_PerfPreprocessMeta(inp, inp.label, tparamfl);
        else
            [mapY{n}, Param{n}, P{n}, mapYocv{n}] = nk_PerfPreprocess(Y, inp, inp.label, tparamfl, Yocv);
        end
    end
        
    % Save parameters to disk
    if isfield(inp,'saveparam') && inp.saveparam
        CV2p = inp.f; CV2f = inp.d; 
        if isfield(inp,'CV1') && inp.CV1 == 1
            CV1p = inp.CV1p;  CV1f = inp.CV1f;
        else
            CV1p = []; CV1f = [];
        end
        OptPreprocParamFilename = ...
            nk_GenerateNMFilePath( inp.saveoptdir, SAV.matname, 'OptPreprocParam', [], inp.varstr, inp.id, CV2p , CV2f, CV1p, CV1f );
        fprintf('\nSaving %s to disk...', OptPreprocParamFilename)
        if ~exist(inp.saveoptdir,'dir'), mkdir(inp.saveoptdir); end
        ofold = CV2f; operm = CV2p;
        if OCTAVE
            save(OptPreprocParamFilename,'Param','ofold','operm');
        else
            save(OptPreprocParamFilename,'-v7.3', 'Param','ofold','operm');     
        end
    end

    % Transfer mapped data to appropriate container
    if nM > 1
       [mapY, Param] = nk_mapY2Struct(mapY, Param, P, inp);
       [iy,jy] = size(mapY.Tr);
       DealWithCompleteNanCases = 1; %2 = Impute missing cases
       mapY = nk_DealWithNaNCases(mapY, iy, jy, inp.nclass, DealWithCompleteNanCases );
       if (iscell(mapYocv) && ~sum(cellfun(@isempty,mapYocv))) || ( ~iscell(mapYocv) && ~isempty(mapYocv))
           mapYocv = nk_mapY2Struct(mapYocv, Param, P, inp); 
           mapYocv = nk_DealWithNaNCases_OOCV(mapYocv, iy, jy, inp.nclass, DealWithCompleteNanCases );
       end
    else
        mapY = mapY{n};
        if ~isempty(mapYocv), mapYocv = mapYocv{n}; end
    end
end
