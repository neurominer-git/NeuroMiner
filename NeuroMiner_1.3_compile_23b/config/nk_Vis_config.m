function [VIS, act] = nk_Vis_config(VIS, PREPROC, M, defaultsfl, parentstr)
global NM EXPERT

if ~exist('defaultsfl','var') || isempty(defaultsfl), defaultsfl=0; end
if ~exist('M','var') || isempty(M), M=1; end

fwhm = []; flgProj = false; 

PERM = struct('flag',0,'nperms',1000,'sigflag',0,'sigPthresh',0.05, 'mode',1);
if isfield(VIS,'PERM'), PERM = VIS.PERM; end

normfl = false; if any(strcmp({'LIBSVM','LIBLIN'}, NM.TrainParam.SVM.prog)), normfl = true; end
normdef = 1; if ~isfield(VIS,'norm'), VIS.norm = normdef; end 

if ~defaultsfl
    
    if ~exist('VIS','var') || isempty(VIS) , VIS = nk_Vis_config([], PREPROC, M, 1); end
    D = NM.datadescriptor{M}; 
    sourcestr = D.source; 
    menustr = []; menuact = [];
    
    if ~strcmp(sourcestr,'matrix')
        %% Gaussian smoothing setup
        if isfield(VIS,'fwhm') && ~isempty(VIS.fwhm)
            fwhmstr = sprintf('yes (FHWM = %g)', VIS.fwhm);
            fwhmdef = VIS.fwhm; fwhmflagdef = 1;
        else
            fwhmstr = 'no';
            fwhmdef = 8; fwhmflagdef = 2;
        end
        menustr = sprintf('%sApply gaussian smoothing to weight vectors [ %s ]|', menustr, fwhmstr);
        menuact = [menuact 1];
        
    end
    
    %% Weight vector normalization setup
    if normfl
        if isfield(VIS,'norm'), normdef = VIS.norm; end
        normstr = {'yes','no'};
        menustr = sprintf('%sNormalize weight vectors [ %s ]|', menustr, normstr{normdef}); menuact = [ menuact 2 ];
    end
    
    %% Permuation setup    
    permstr = 'disabled'; if PERM.flag, permstr = sprintf('enabled'); end
    menustr = sprintf('%sPerform permutation analysis [ %s ]|', menustr, permstr); menuact = [menuact 3];

    if PERM.flag
        menustr = sprintf('%sDefine no. of permutations [ %g ]|', menustr, VIS.PERM.nperms); menuact = [menuact 4];
        permmodestropts = {'labels', 'features', 'labels and features', 'covariate(s)'};
        if ~isfield(PERM,'mode'), PERM.mode = 1; end
        permmodestr = permmodestropts{PERM.mode};
        menustr = sprintf('%sDefine permutation mode [ %s ]|', menustr, permmodestr ); menuact = [menuact 5];
        if PERM.mode == 4
            if isfield(PERM,'covars_idx')
                covstr = sprintf('%s', strjoin(NM.covars(PERM.covars_idx)), ', ');
            else
                covstr = 'undefined';
            end
            menustr = sprintf('%sSelect covariates [ %s ]|', menustr, covstr); menuact = [menuact 6];
        end
        flgProj = nk_DetIfDimRefInPREPROC(PREPROC, M);
        if flgProj
            if isfield(PERM,'sigflag') && PERM.sigflag
                sigstr = sprintf('back-project only significant features');
            else
                sigstr = 'back-project all features';
            end
            menustr = sprintf('%sDefine back-projection mode in dimensionality reduction steps [ %s ]|', ...
                menustr, sigstr ); menuact = [menuact 7];
            if PERM.sigflag
                menustr = sprintf('%sDefine back-projection significance threshold [ %g ]', ...
                    menustr, PERM.sigPthresh ); menuact = [menuact 8];
            end
        end
    end
    
    %% CONFIGURATION
    nk_PrintLogo
    mestr = 'Visualization parameters'; navistr = [parentstr ' >>> ' mestr]; fprintf('\nYou are here: %s >>> ', parentstr); 
    act = nk_input(mestr,0,'mq', menustr, menuact);

    switch act
      
        case 1
            fwhmflag = nk_input('Do you want to apply Gaussian smoothing to the weight vectors ?',0,'yes|no',[1,2], fwhmflagdef);
            if fwhmflag == 1
                VIS.fwhm = nk_input('Specify FWHM width [in mm]',0,'e', fwhmdef);
            else
                VIS.fwhm = [];
            end
        case 2
            if VIS.norm == 1, VIS.norm = 2; else, VIS.norm = 1; end
        case 3
            VIS.PERM.flag = ~VIS.PERM.flag;
            if ~VIS.PERM.flag && flgProj, VIS.PERM.sigflag = 0; end
        case 4
            VIS.PERM.nperms = nk_input('# of permutations',0,'i', PERM.nperms);
        case 5
            if isfield(NM,'covars') && ~isempty(NM.covars) && EXPERT 
                VIS.PERM.mode = nk_input('Permutation mode',0,'m','Labels|Features (within-label)|Labels & Features|Covariate(s)',1:4, PERM.mode);
            else 
                VIS.PERM.mode = nk_input('Permutation mode',0,'m','Labels|Features (within-label)|Labels & Features',1:3, PERM.mode);
            end
        case 6
             VIS.PERM.covars_idx = nk_SelectCovariateIndex(NM, PERM.covars_idx,1);
        case 7
            VIS.PERM.sigflag = ~VIS.PERM.sigflag;
        case 8
            VIS.PERM.sigPthresh = nk_input('Define alpha threshold for determining feature significance',0,'e', PERM.sigPthresh);
      
    end
else
    VIS.fwhm = fwhm;
    VIS.norm = normdef;
    VIS.PERM = PERM;
    act = 0;
end

