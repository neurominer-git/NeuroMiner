function inp = nk_PerfInitSpatial(analysis, inp, paramfl)

global VERBOSE MODEFL

kbin = inp.nclass;
nM  = numel(inp.PREPROC);
Yocv = []; Cocv = []; AltY = [];
inp.issmoothed = false(1,nM);

for n=1:nM
    
    if nM>1
        Y = inp.X(n).Y; 
        if isfield(inp.X(n),'Yocv') && ~isempty(inp.X(n).Yocv), Yocv = inp.X(n).Yocv; end
        if isfield(inp.X(n),'altY') && ~isempty(inp.X(n).altY), AltY = inp.X(n).altY; end
        if isfield(inp.X(n),'Yw') && ~isempty(inp.X(n).Yw), inp.iYw = inp.X(n).Yw; end
        PREPROC = inp.PREPROC{n};
    else
        Y = inp.X.Y; 
        if isfield(inp.X,'Yocv') && ~isempty(inp.X.Yocv), Yocv = inp.X.Yocv; end
        if isfield(inp.X,'altY') && ~isempty(inp.X.altY), AltY = inp.X.altY; end
        if isfield(inp.X,'Yw') && ~isempty(inp.X.Yw), inp.iYw = inp.X.Yw; end
        PREPROC = inp.PREPROC; 
    end
    
    if iscell(paramfl)
        tparamfl = paramfl{n};
    else
        tparamfl = paramfl;
    end
    
    tparamfl.PV = inp.X(n);
    if VERBOSE
        if isfield(inp,'f')
            fprintf('\nGenerate pre-processing parameter array for CV2 partition [%g,%g].\n',inp.f,inp.d); 
        else
            fprintf('\nGenerate pre-processing parameter array for CV2 partition.')
        end
    end
    tparamfl = nk_PrepPreprocParams(PREPROC, tparamfl, analysis, n, inp.ll, inp.curlabel);
    
    if iscell(PREPROC)
        BINMOD = PREPROC{1}.BINMOD;
    else
        BINMOD = PREPROC.BINMOD;
    end
    if BINMOD || strcmp(MODEFL,'regression')
        if VERBOSE; fprintf('\nProcessing Mode: binary / regression preprocessing'); end
    else
        if VERBOSE; fprintf('\nProcessing Mode: multi-group preprocessing'); end
    end
    
    % Set current modality
    tparamfl.currmodal = n;

    % Smooth data
    [ sY, sYocv, sCocv, sAltY, sYw, inp ] = nk_PerfPreprocessSpatial( Y, Yocv, Cocv, AltY, inp, tparamfl, kbin);
    
    % Assign smoothed training/CV data to container and ...
    inp.X(n).sY = sY;
    % External data?
    if ~isempty(sYocv), inp.X(n).sYocv = sYocv; end
    % Alternative data?
    if ~isempty(sAltY), inp.X(n).sAltY = sAltY; end
    % Calibration data?
    if ~isempty(sCocv), inp.X(n).sCocv = sCocv; end
    % External weighting mask?
    if ~isempty(sYw), inp.X(n).sYw = sYw; end

   if isfield(PREPROC,'SPATIAL') && PREPROC.SPATIAL.cubetype>1
       inp.issmoothed(n) = true;
   else
       inp.issmoothed(n) = false;
   end 
end