function [sY, sYocv, sCocv, sAltY, sYw, inp, optfl] = nk_PerfPreprocessSpatial( Y, Yocv, Cocv, AltY, inp, paramfl, kbin)

global PREPROC
sYocv = []; sCocv = []; sAltY = []; sYw = [];

%Eventually, apply spatial operations on image data
if isfield(paramfl,'PREPROC') && isfield(paramfl.PREPROC,'SPATIAL') && paramfl.PREPROC.SPATIAL.cubetype>1 

    % Filter the data (imaging only)
    smoothfl = true; if isfield(inp,'issmoothed') && inp.issmoothed(paramfl.currmodal), smoothfl = false; end
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
            [tsY, inp, paramfl] = smooth_container(Y, [], inp, 'training/CV', PREPROC, paramfl);

            % Smoothing of out-of-crossvalidation data (can be multiple containers)
            if ~isempty(Yocv), tsYocv = smooth_container(Yocv, [], inp, 'independent test', PREPROC, paramfl, true); end

            % Smoothing of calibration data (can be multiple containers)
            if ~isempty(Cocv), tsCocv = smooth_container(Cocv, [], inp, 'calibration', PREPROC, paramfl); end
            
            % Smoothing of alternative training/CV data (can be multiple containers)
            if ~isempty(AltY), tsAltY = smooth_container(AltY, [], inp, 'alternative training/CV', PREPROC, paramfl); end

            % Is there a weighting mask that must be smoothed, too?
            inp = nk_SmoothMask( uPREPROC, inp, paramfl );

            for u=1:kbin
                paramfl.P{u} = tP;
                sY{u} = tsY;
                if ~inp.PREPROC.BINMOD
                    if isfield(inp,'iYw'), sYw{u} = inp.iYw; end
                else
                    if isfield(inp,'iYw'), sYw{u} = inp.iYw{u}; end
                end
                if ~isempty(Yocv), sYocv{u} = tsYocv; end
                if ~isempty(Cocv), sCocv{u} = tsCocv; end
                if ~isempty(AltY), sAltY{u} = tsAltY; end
            end

        else
            
            % Smooth training/CV data
            [sY, inp, paramfl] = smooth_container( Y, kbin, inp, 'training/CV', PREPROC, paramfl ); 

            % Processing of out-of-crossvalidation data (can be multiple containers)
            if ~isempty(Yocv), sYocv = smooth_container(Yocv, kbin, inp, 'independent test', PREPROC, paramfl, true); end

            % Processing of calibration data (can be multiple containers)
            if ~isempty(Cocv), sCocv = smooth_container(Cocv, kbin, inp, 'calibration', PREPROC, paramfl); end
            
            % Processing of alternative training/CV data (can be multiple containers)
            if ~isempty(AltY), sAltY = smooth_container(AltY, kbin, inp, 'alternative training/CV', PREPROC, paramfl); end
            
            % Smooth weighting map, if needed
            sYw = cell(kbin,1);
            for u=1:kbin
                uPREPROC = nk_SetParamChain(paramfl, u, PREPROC); 
                inp = nk_SmoothMask( uPREPROC, inp, paramfl, u );
                if isfield(inp,'iYw') && ~isempty(inp.iYw), sYw{u} = inp.iYw; end
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
        if ~iscell(Y)
            tY{1} = Y;
            if ~isempty(Yocv), tYocv{1} = Yocv; end
            if ~isempty(Cocv), tCocv{1} = Cocv; end
            if ~isempty(AltY), tAltY{1} = AltY; end
        else
            tY = Y;
            if ~isempty(Yocv), tYocv = Yocv; end
            if ~isempty(Cocv), tCocv = Cocv; end
            if ~isempty(AltY), tAltY = AltY; end
        end
        for u=1:kbin
            uPREPROC = nk_SetParamChain(paramfl, u, PREPROC);
            if uPREPROC.SPATIAL.cubetype == 4 && numel(tY{u}) ~= numel(uPREPROC.SPATIAL.PX.opt)
                idx = ismember(inp.smoothing_kernels, uPREPROC.SPATIAL.PX.opt);
                fprintf('\nChoosing smoothing kernel %g',inp.smoothing_kernels(idx));
            else
                if uPREPROC.SPATIAL.cubetype == 4 && numel(uPREPROC.SPATIAL.PX.opt)>1
                    fprintf('\nAll smoothing kernels needed');
                end
                idx = true(numel(tY{u}),1);
            end
            sY{u} = tY{u}(idx);
            if ~isempty(Yocv), sYocv{u} = tYocv{u}(idx); end
            if ~isempty(Cocv), sCocv{u} = tCocv{u}(idx); end
            if ~isempty(AltY), sAltY{u} = tAltY{u}(idx); end
            if isfield(inp,'iYw') &&  ~isempty(inp.iYw{u})
                if iscell(inp.iYw{u})
                    sYw{u} = inp.iYw{u}(idx); 
                else
                    sYw{u} = inp.iYw(idx);
                end
            end
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

function [sY, inp, paramfl] = smooth_container(Y, kbin, inp, typestr, PREPROC, paramfl, oocvmode)

if ~exist("oocvmode","var") || isempty(oocvmode)
    oocvmode = false;
end

spatialstropts =   {'no spatial operation' , ...
                    'absolute difference weighting (6 neighbors)', ...
                    'spatial variance weighting (27 neighbors)', ...
                    'gaussian smoothing', ...
                    'neurotransmitter correlations', ...
                    'reslicing', ...
                    'ROI means computation'}; 

if iscell(Y)
    nY = numel(Y);
    if isempty(kbin)
        sY = cell(numel(Y),1);
        uPREPROC = nk_SetParamChain(paramfl, 1, PREPROC);
        for n=1:nY
            sY{n} = nk_PerfSpatFilt( Y{n}, uPREPROC, paramfl.PV ); 
        end
        if nargout>1
            inp.smoothing_kernels = uPREPROC.SPATIAL.PX.opt;    
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
                if isempty(inp.desc_oocv{n}) || ~oocvmode
                    fprintf('\nPerforming %s on %s data for binary comparison #%g', spatialstropts{uPREPROC.SPATIAL.cubetype}, typestr,  u);
                else
                    fprintf('\nPerforming %s on %s data (%s) for binary comparison #%g', spatialstropts{uPREPROC.SPATIAL.cubetype}, typestr, inp.desc_oocv{n}, u);
                end
                sY{u,n} = nk_PerfSpatFilt( Y{n}, uPREPROC, paramfl.PV ); 
            end
        end
    end
    
else
    if isempty(kbin)
        uPREPROC = nk_SetParamChain(paramfl, 1, PREPROC);
        if isempty(inp.desc_oocv) || ~oocvmode
            fprintf('\nPerforming %s on %s data', spatialstropts{uPREPROC.SPATIAL.cubetype}, typestr);
        else
            fprintf('\nPerforming %s on %s data (%s)', spatialstropts{uPREPROC.SPATIAL.cubetype}, typestr, inp.desc_oocv);
        end
        sY = nk_PerfSpatFilt( Y, uPREPROC, paramfl.PV ); 
        if nargout>1
            inp.smoothing_kernels = uPREPROC.SPATIAL.PX.opt;  
        end
    else
        sY = cell(kbin,1);
        for u=1:kbin
            uPREPROC = nk_SetParamChain(paramfl, u, PREPROC);
            if isempty(inp.desc_oocv) || ~oocvmode
                fprintf('\nPerforming %s on %s data', spatialstropts{uPREPROC.SPATIAL.cubetype}, typestr);
            else
                fprintf('\nPerforming %s on %s data (%s)', spatialstropts{uPREPROC.SPATIAL.cubetype}, typestr, inp.desc_oocv);
            end
            sY{u} = nk_PerfSpatFilt( Y, uPREPROC, paramfl.PV ); 
            if nargout>1
                inp.smoothing_kernels = uPREPROC.SPATIAL.PX.opt;  
            end
        end
    end
end

