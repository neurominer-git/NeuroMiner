function [VIS, act] = nk_Vis_config(VIS, PREPROC, M, defaultsfl, parentstr)
global NM EXPERT

if ~exist('defaultsfl','var') || isempty(defaultsfl), defaultsfl=0; end
if ~exist('M','var') || isempty(M), M=1; end

PERM = struct('flag', 0, 'nperms', 5000, 'sigflag',0, 'sigPthresh', 0.05, 'sigPfdr', 1, 'mode', 1);
if isfield(VIS,'PERM') 
    if isfield(VIS.PERM,'flag'), PERM.flag = VIS.PERM.flag; end
    if isfield(VIS.PERM,'nperms'), PERM.nperms = VIS.PERM.nperms; end
    if isfield(VIS.PERM,'sigflag'), PERM.sigflag = VIS.PERM.sigflag; end
    if isfield(VIS.PERM,'sigPnperms'), PERM.sigPnperms = VIS.PERM.sigPnperms; end
    if isfield(VIS.PERM,'sigPthresh'), PERM.sigPthresh = VIS.PERM.sigPthresh; end
    if isfield(VIS.PERM,'sigPfdr'), PERM.sigPfdr = VIS.PERM.sigPfdr; end
    if isfield(VIS.PERM,'mode'), PERM.mode = VIS.PERM.mode; end
end

normfl = false; if any(strcmp({'LIBSVM','LIBLIN'}, NM.TrainParam.SVM.prog)), normfl = true; end
normdef = 2; if ~isfield(VIS,'norm'), VIS.norm = normdef; end 

if ~defaultsfl
    
    if ~exist('VIS','var') || isempty(VIS) , VIS = nk_Vis_config([], PREPROC, M, 1); end 
    menustr = []; menuact = [];
    yesno_str = {'yes','no'};
    
    %% Weight vector normalization setup
    if normfl
        if isfield(VIS,'norm'), normdef = VIS.norm; end
        menustr = sprintf('%sNormalize weight vectors [ %s ]|', menustr, yesno_str{normdef}); menuact = [ menuact 2 ];
    end
    
    %% Permuation setup    
    flgProj = nk_DetIfDimRefInPREPROC(PREPROC, M);
    if ~flgProj && PERM.sigflag, PERM.sigflag = false; end

    permstr = 'no'; if PERM.flag, permstr = sprintf('yes'); end
    if ~PERM.sigflag
        menustr = sprintf('%sPerform permutation test in input space [ %s ]|', menustr, permstr); menuact = [menuact 3];
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
        end
    end

    if flgProj
        if isfield(PERM,'sigflag') && PERM.sigflag
            sigstr = 'yes';
        else
            sigstr = 'no';
        end
        menustr = sprintf('%sPerform model permutation test in model space and back-project only signif. components [ %s ]', ...
            menustr, sigstr ); menuact = [menuact 7];

        if PERM.sigflag     
            menustr = sprintf('%s|Define no. of permutations [ %g ]', menustr, VIS.PERM.nperms); menuact = [menuact 4];
            permmodestropts = {'labels', 'features', 'labels and features'};
            if ~isfield(PERM,'mode'), PERM.mode = 1; end
            permmodestr = permmodestropts{PERM.mode};
            menustr = sprintf('%s|Define permutation mode [ %s ]', menustr, permmodestr ); menuact = [menuact 5];
            menustr = sprintf('%s|Define back-projection significance threshold [ %g ]', ...
                menustr, PERM.sigPthresh ); menuact = [menuact 9];
            menustr = sprintf('%s|Correct component P values for multiple comparisons using FDR [ %s ]', ...
                menustr, yesno_str{PERM.sigPfdr} ); menuact = [menuact 10];
            menustr = sprintf('%s|Perform additional permutation test of feature significance in input-space [ %s ]', menustr, permstr); menuact = [menuact 3];
        end
    end
    
    %% CONFIGURATION
    nk_PrintLogo
    mestr = 'Visualization parameters'; navistr = [parentstr ' >>> ' mestr]; fprintf('\nYou are here: %s >>> ', parentstr); 
    act = nk_input(mestr,0,'mq', menustr, menuact);

    switch act
      
        case 2
            if VIS.norm == 1, VIS.norm = 2; else, VIS.norm = 1; end
        case 3
            PERM.flag = ~VIS.PERM.flag;
        case 4
            PERM.nperms = nk_input('# of permutations',0,'i', PERM.nperms);
        case 5
            if isfield(NM,'covars') && ~isempty(NM.covars) && EXPERT 
                PERM.mode = nk_input('Permutation mode',0,'m','Labels|Features (within-label)|Labels & Features|Covariate(s)',1:4, PERM.mode);
            else 
                PERM.mode = nk_input('Permutation mode',0,'m','Labels|Features (within-label)|Labels & Features',1:3, PERM.mode);
            end
        case 6
             PERM.covars_idx = nk_SelectCovariateIndex(NM, PERM.covars_idx,1);
        case 7
            PERM.sigflag = ~VIS.PERM.sigflag;
        case 8
            PERM.sigPthresh = nk_input('Define alpha threshold for determining component significance',0,'e', PERM.sigPthresh);
        case 9
            PERM.sigPfdr = nk_input('Correcting components'' permutation-based significance using FDR',0,'e', [1,2], PERM.sigPfdr);
    end
    VIS.PERM = PERM;
else
    VIS.norm = normdef;
    VIS.PERM = PERM;
    act = 0;
end

