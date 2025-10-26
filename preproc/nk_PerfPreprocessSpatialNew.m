function [sY, sYocv, sCocv, sAltY, sYw, inp, optfl] = nk_PerfPreprocessSpatialNew( Y, Yocv, Cocv, AltY, inp, paramfl, kbin)

global PREPROC
sYocv = []; sCocv = []; sAltY = []; sYw = [];

%Eventually, apply spatial operations on image data
if isfield(paramfl,'PREPROC') && isfield(paramfl.PREPROC,'SPATIAL') && paramfl.PREPROC.SPATIAL.cubetype>1 

    % Filter the data (imaging only)
    smoothfl = true; if isfield(inp,'issmoothed') && inp.issmoothed, smoothfl = false; end
    sY = cell(kbin,1); 
    if ~isempty(Yocv), sYocv = cell(kbin,1); end
    if ~isempty(Cocv), sCocv = cell(kbin,1); end
    if ~isempty(AltY), sAltY = cell(kbin,1); end
    if isfield(inp,'iYw'), sYw = cell(kbin,1); end
    optfl = true; 

    if smoothfl

        if inp.multiflag % All binary containers are treated equally.
            
            uPREPROC = nk_SetParamChain(paramfl, 1, PREPROC);
            tP = nk_ReturnParamChain(uPREPROC, 1); 

            % Smooth training/CV data
            tsY = smooth_container(Y, [], inp, 'training/CV', PREPROC, paramfl);

            % Smoothing of out-of-crossvalidation data (can be multiple containers)
            if ~isempty(Yocv), tsYocv = smooth_container(Yocv, [], inp, 'independent test', PREPROC, paramfl); end

            % Smoothing of calibration data (can be multiple containers)
            if ~isempty(Cocv), tsCocv = smooth_container(Cocv, [], inp, 'calibration', PREPROC, paramfl); end
            
            % Smoothing of alternative training/CV data (can be multiple containers)
            if ~isempty(AltY), tsAltY = smooth_container(AltY, [], inp, 'alternative training/CV', PREPROC, paramfl); end

            % Is there a weighting mask that must be smoothed, too?
            if isfield(inp,'iYw')
                % Here a weighting mask for a given modality "i" has been
                % mapped from inp.X(n).Yw to inp.iYw by a parent function
                tsYw = nk_PerfSpatFilt( inp.iYw, uPREPROC, paramfl.PV ); 
            else
                % Here a weighting mask needs to be found in the
                % preprocessing parameters (e.g. as part of the ranking
                % function)
                tsYw = nk_SmoothMaskInActParam(uPREPROC, paramfl.PV);
            end

            for u=1:kbin
                paramfl.P{u} = tP;
                sY{u} = tsY;
                if isfield(inp,'iYw'), sYw{u} = tsYw; end
                if ~isempty(Yocv), sYocv{u} = tsYocv; end
                if ~isempty(Cocv), sCocv{u} = tsCocv; end
                if ~isempty(AltY), sAltY{u} = tsAltY; end
            end

        else
            
            % Smooth training/CV data
            [sY, inp, paramfl] = smooth_container( Y, kbin, inp, 'training/CV', PREPROC, paramfl ); 

            % Processing of out-of-crossvalidation data (can be multiple containers)
            if ~isempty(Yocv), sYocv = smooth_container(Yocv, inp, 'independent test', PREPROC, paramfl); end

            % Processing of calibration data (can be multiple containers)
            if ~isempty(Cocv), sCocv = smooth_container(Cocv, inp, 'calibration', PREPROC, paramfl); end
            
            % Processing of alternative training/CV data (can be multiple containers)
            if ~isempty(AltY), sAltY = smooth_container(AltY, inp, 'alternative training/CV', PREPROC, paramfl); end
            
            % Smooth weighting map, if needed
            for u=1:kbin
                uPREPROC = nk_SetParamChain(paramfl, u, PREPROC); 
                if isfield(inp,'iYw') && ~isempty(inp.iYw{1}) 
                    fprintf('\nSmoothing weighting map')
                    sYw{u} = nk_PerfSpatFilt( inp.iYw, uPREPROC, paramfl.PV ); 
                else
                    sYw{u} = nk_SmoothMaskInActParam(uPREPROC, paramfl.PV);
                end
            end
        end
    else
        % Check whether only some of the pre-smoothed data shelves are needed. 
        % If so extract, extract only the smoothed data shelves needed for the 
        % current CV2 partition
        sY = cell(kbin,1); 
        if ~isempty(Yocv), sYocv = cell(kbin,1); end
        if ~isempty(Cocv), sCocv = cell(kbin,1); end
        if ~isempty(AltY), sAltY = cell(kbin,1); end
        if isfield(inp,'iYw'), sYw = cell(kbin,1); end

        for u=1:kbin
            uPREPROC = nk_SetParamChain(paramfl, u, PREPROC);
            if numel(Y{u}) ~= numel(uPREPROC.SPATIAL.PX.opt)
                idx = ismember(inp.smoothing_kernels, uPREPROC.SPATIAL.PX.opt);
            else
                idx = true(numel(Y{u}),1);
            end
            sY{u} = Y{u}(idx);
            if ~isempty(Yocv), sYocv{u} = Yocv{u}(idx); end
            if ~isempty(Cocv), sCocv{u} = Cocv{u}(idx); end
            if ~isempty(AltY), sAltY{u} = AltY{u}(idx); end
            if isfield(inp,'iYw') &&  ~isempty(sYw{u}), sYw{u} = inp.iYw{u}(idx); end
        end
    end
else
    optfl = false;
    sY = Y;
    if ~isempty(Yocv), sYocv = Yocv; end
    if ~isempty(Cocv), sCocv = Cocv; end
    if ~isempty(AltY), sAltY = AltY; end
    if isfield(inp,'iYw'), sYw = inp.iYw; end
end

function [sY, inp, paramfl] = smooth_container(Y, kbin, inp, typestr, PREPROC, paramfl)

if iscell(Y)
    nY = numel(Y);
    if isempty(kbin)
        sY = cell(numel(Y),1);
        uPREPROC = nk_SetParamChain(paramfl, 1, PREPROC);
        for n=1:nY
            sY{n} = nk_PerfSpatFilt( Y{n}, uPREPROC, paramfl.PV ); 
        end
    else
        sY = cell(kbin,numel(Y));
        for u=1:kbin
            uPREPROC = nk_SetParamChain(paramfl, u, PREPROC);
            if nargout>1
                paramfl.P{u} = nk_ReturnParamChain(uPREPROC, 1); 
                inp.smoothing_kernels = uPREPROC.SPATIAL.PX.opt;    
            end
            for n=1:nY
                fprintf('\nSmoothing %s data (%s) for binary comparison #%g', typestr, inp.desc_oocv{n}, u);
                sY{u,n} = nk_PerfSpatFilt( Y{n}, uPREPROC, paramfl.PV ); 
            end
        end
    end
    
else
    fprintf('\nSmoothing %s test data (%s)', typestr, inp.desc_oocv);
    if isempty(kbin)
        uPREPROC = nk_SetParamChain(paramfl, 1, PREPROC);
        sY = nk_PerfSpatFilt( Yocv, uPREPROC, paramfl.PV ); 
    else
        sY = cell(kbin,1);
        for u=1:kbin
            uPREPROC = nk_SetParamChain(paramfl, u, PREPROC);
            sY{u} = nk_PerfSpatFilt( Yocv, uPREPROC, paramfl.PV ); 
        end
    end
end

