function [act, NM, setup] = cv_estimate_samplesize_config(NM, act, setup, parentstr)

if isfield(NM,'simulation') && isempty(setup)
    setup = NM.simulation.run(end).setup;
end

% defaults
if ~isfield(setup, 'mode')
    setup.mode                          = 'pre';
end
if strcmp(setup.mode, 'pre') && ~isfield(setup, 'pre')
    setup.pre = [];

    if ~isfield(setup.pre, 'NFeats')
        setup.pre.NFeats                    = 100;
    end
    if ~isfield(setup.pre, 'NMarkers')
        setup.pre.NMarkers                  = 0.5;
    end
    if ~isfield(setup.pre, 'NCases')
        setup.pre.NCases                    = [100, 200, 300, 400];
    end
    if ~isfield(setup.pre, 'EventProb')
        setup.pre.EventProb                 = 0.5;
    end
    if ~isfield(setup.pre, 'AUCmax')
        setup.pre.AUCmax                    = 0.7;
    end
    if ~isfield(setup.pre, 'AUCmin')
        setup.pre.AUCmin                    = 0.5;
    end
    if ~isfield(setup.pre, 'NBatches')
        setup.pre.NBatches                  = 0;
    end
    if ~isfield(setup.pre, 'NBatchPerc')
        setup.pre.BatchPerc                 = 0.1;
    end
    if ~isfield(setup.pre, 'NCasesMiss')
        setup.pre.NCasesMiss                = 0;
    end
    if ~isfield(setup.pre, 'NFeatsMiss')
        setup.pre.NFeatsMiss                = 0;
    end
    if ~isfield(setup.pre, 'Algorithm')
        setup.pre.Algorithm                 = 'LINKERNSVM'; 
    end
    if ~isfield(setup.pre, 'NReps')
        setup.pre.NReps                     = 10;
    end
    if ~isfield(setup.pre,'GridParam')
        setup.pre.GridParam                 = 14;
    end

elseif strcmp(setup.mode, 'posthoc') %&&
    if ~isfield(setup, 'posthoc')
        % posthoc
        % here: default values as currently defined in NM
        setup.posthoc = [];
    end
    na_str                      = '?';
    synth_flag                  = 2;
    methodnum                   = 1;
    k                           = 5;
    distanceMeasure             = 'Euclidean';
    standardize_data            = 2;
    numSyntheticObservations    = round(size(NM.label,1)*0.1);
    write2disk                  = 1;
    adasyn_beta                 = 0.5;
    adasyn_kdensity             = 5;
    adasyn_kSMOTE               = 5;

    if ~isfield(setup.posthoc,'NRanalysis'),                setup.posthoc.NRanalysis = 1; end
    if ~isfield(setup.posthoc,'NCases'),                    setup.posthoc.NCases = [100, 200, 300, 400]; end
    if ~isfield(setup.posthoc,'add2orig'),                  setup.posthoc.add2orig = 0; end
    if ~isfield(setup.posthoc, 'NReps'),                    setup.posthoc.NReps = 10; end
    if ~isfield(setup.posthoc, 'SitesIdx'),                 setup.posthoc.SitesIdx = 0; end
    if ~isfield(setup.posthoc, 'condIdx'),                  setup.posthoc.condIdx = -1; end

    if setup.posthoc.add2orig == 1
        add2orig_str = 'Yes';
    else
        add2orig_str = 'No';
    end
    
    % Generate synthetic data?
    if isfield(setup.posthoc,'method'),                     methodnum = setup.posthoc.method; else, setup.posthoc.method = methodnum; end
    if isfield(setup.posthoc,'k'),                          k = setup.posthoc.k; else, setup.posthoc.k = k; end
    if isfield(setup.posthoc,'distanceMeasure'),            distanceMeasure = setup.posthoc.distanceMeasure; else, setup.posthoc.distanceMeasure = distanceMeasure; end
    if isfield(setup.posthoc,'standardize_data'),           standardize_data = setup.posthoc.standardize_data; else, setup.posthoc.standardize_data = standardize_data; end
    if isfield(setup.posthoc,'write2disk'),                 write2disk = setup.posthoc.write2disk; else,  setup.posthoc.write2disk = write2disk;  end
    if isfield(setup.posthoc,'beta'),                       adasyn_beta = setup.posthoc.beta; else, setup.posthoc.beta = adasyn_beta; end
    if isfield(setup.posthoc,'kDensity'),                   adasyn_kdensity = setup.posthoc.kDensity; else, setup.posthoc.kDensity = adasyn_kdensity; end
    if isfield(setup.posthoc,'kSMOTE'),                     adasyn_kSMOTE = setup.posthoc.kSMOTE; else, setup.posthoc.kSMOTE = adasyn_kSMOTE; end


    setup.output.outputdir          = NM.analysis{1,setup.posthoc.NRanalysis}.rootdir;
    if ~isfield(setup.posthoc,'GridParam')
        setup.posthoc.GridParam                 = 14;
    end
end

% the following dont have to be set(defaults: 1,1,5,5,1)
if ~isfield(setup.pre,'RAND')
    setup.pre.RAND.OuterPerm            = 1; % ==> Outer cross-validation permutations
    setup.pre.RAND.InnerPerm            = 1; % ==> Inner cross-validation permutations
    setup.pre.RAND.OuterFold            = 5; % ==> Outer cross-validation folds
    setup.pre.RAND.InnerFold            = 5; % ==> Inner cross-validation folds
    setup.pre.RAND.Decompose            = 1;
end

if ~isfield(setup,'output')
    setup.output.plot_flag              = 1;
    setup.output.save_performance_flag  = 1;
    setup.output.save_simdata_flag      = 1;
end

if ~isfield(setup.output, 'outputdir') && strcmp(setup.mode, 'pre')
    setup.output.outputdir          = pwd;
elseif ~isfield(setup.output, 'outputdir') && strcmp(setup.mode, 'posthoc')
    setup.output.outputdir          = NM.analysis{1,setup.posthoc.NRanalysis}.rootdir;
end

if setup.output.plot_flag, plot_flag_str = 'yes'; else, plot_flag_str = 'no'; end
if setup.output.save_performance_flag, save_performance_flag_str = 'yes'; else, save_performance_flag_str = 'no'; end   
if setup.output.save_simdata_flag, save_simdata_flag_str = 'yes'; else, save_simdata_flag_str = 'no'; end   

menustr = [];
menuact = [];
if isfield(NM, 'analysis') && size(NM.analysis,2) > 0
    % additionally to pre also give option for posthoc curve fitting (evaluate your performance in relation to
    % increasing sample size)

    menustr = sprintf('%sDefine simulation mode [ %s ]', menustr, setup.mode); menuact = 1;

end

if strcmp(setup.mode, 'pre')
    menustr = sprintf('%s|Define feature dimensionality [ %s ]', menustr, nk_ConcatParamstr(setup.pre.NFeats)); menuact = [menuact 2];
    menustr = sprintf('%s|Define number or fraction of predictive markers [ %s ]', menustr, nk_ConcatParamstr(setup.pre.NMarkers)); menuact = [menuact 3];
    menustr = sprintf('%s|Define sample size [ %s ]', menustr, nk_ConcatParamstr(setup.pre.NCases)); menuact = [menuact 4];
    menustr = sprintf('%s|Define event probability [ %s ]', menustr, nk_ConcatParamstr(setup.pre.EventProb)); menuact = [menuact 5];
    menustr = sprintf('%s|Define AUC max [ %s ]', menustr, nk_ConcatParamstr(setup.pre.AUCmax)); menuact = [menuact 6];
    menustr = sprintf('%s|Define AUC min [ %s ]', menustr, nk_ConcatParamstr(setup.pre.AUCmin)); menuact = [menuact 7];
    menustr = sprintf('%s|Define number of batches [ %s ]', menustr, nk_ConcatParamstr(setup.pre.NBatches)); menuact = [menuact 8];
    menustr = sprintf('%s|Define batch percentage [ %s ]', menustr, nk_ConcatParamstr(setup.pre.BatchPerc)); menuact = [menuact 9];
    menustr = sprintf('%s|Define fraction of cases with missing data [ %s ]', menustr, nk_ConcatParamstr(setup.pre.NCasesMiss)); menuact = [menuact 10];
    menustr = sprintf('%s|Define fraction of features with missing data [ %s ]', menustr, nk_ConcatParamstr(setup.pre.NFeatsMiss)); menuact = [menuact 11];
    menustr = sprintf('%s|Define no. of CV outer permutations [ %d ]', menustr, setup.pre.RAND.OuterPerm); menuact = [menuact 12];
    menustr = sprintf('%s|Define no. of CV inner permutations [ %d ]', menustr, setup.pre.RAND.InnerPerm); menuact = [menuact 13];
    menustr = sprintf('%s|Define no. of CV outer folds [ %d ]', menustr, setup.pre.RAND.OuterFold); menuact = [menuact 14];
    menustr = sprintf('%s|Define no. of CV inner folds [ %d ]', menustr, setup.pre.RAND.InnerFold); menuact = [menuact 15];
    menustr = sprintf('%s|Choose algorithm [ %s ]', menustr, setup.pre.Algorithm); menuact = [menuact 16];
    menustr = sprintf('%s|Define N reps [ %s ]', menustr, sprintf('%d',setup.pre.NReps)); menuact = [menuact 17];
    [~,~,GridParam] = nk_GetScaleYAxisLabel(setup.pre.GridParam);  
    menustr = sprintf('%s|Choose optimization criterion [ %s ]', menustr, func2str(GridParam)); menuact = [menuact 20];

elseif strcmp(setup.mode, 'posthoc')
    %synthstr        = {'enabled','disabled'};
    methodstr       = {'kNN-based','PCAGauss', 'Gaussian Copula'}; % ADASYN at second
    %write2diskstr   = {'use data permanently by writing it to disk','recreate data in each model training run'};
    stdstr          = {'standardize data', 'data already standardized/standardization not needed'};
    menustr = sprintf('%s|Define analysis index [ %d ]', menustr, setup.posthoc.NRanalysis); menuact = [menuact 50];
    menustr = sprintf('%s|Define N of cases [ %s ]', menustr, nk_ConcatParamstr(setup.posthoc.NCases)); menuact = [menuact 51];
    menustr = sprintf('%s|Add data to original data [ %s ]', menustr, add2orig_str); menuact = [menuact 52];
    menustr = sprintf('%s|Define N reps [ %s ]', menustr, sprintf('%d',setup.posthoc.NReps)); menuact = [menuact 53];
    menustr = [menustr sprintf('|Choose method for synthetic data generation [ %s ]', methodstr{methodnum})]; menuact = [menuact 54];
    menustr = [menustr sprintf('|Define whether data should be standardized before running distance analysis [ %s ]', stdstr{standardize_data})]; menuact = [menuact 55];
    switch methodnum
        case 1
            menustr = sprintf('%s|Define no. of nearest neighbors for interpolation [ k=%g ]', menustr, k);                                               menuact = [menuact 56];
            menustr = sprintf('%s|Choose distance measure [ %s ]', menustr, distanceMeasure);                                                             menuact = [menuact 57];

%         case 2
%             menustr = sprintf('%s|Define beta value (defines how much balancing will be applied, 0<->1) [ beta=%g ]|', menustr, adasyn_beta);             menuact = [menuact 58];
%             menustr = sprintf('%s|Define k value of density algorithm (kNN looking at both classes) [ k=%g ]|', menustr, adasyn_kdensity);                 menuact = [menuact 59];
%             menustr = sprintf('%s|Define k value of SMOTE algorithm (kNN looking only at the minority class) [ k=%g ]|',menustr, adasyn_kSMOTE);          menuact = [menuact 60];
    end
    if isfield(NM, 'covars')
        menustr = sprintf('%s|Define dummy-coded covariates[ %s ]|', menustr, sprintf('%d ', setup.posthoc.SitesIdx));             menuact = [menuact 61];
    end


end
menustr = sprintf('%s|Plot results? (& save plot) [ %s ]', menustr, plot_flag_str); menuact = [menuact 21];
menustr = sprintf('%s|Save performance results per estimated sample size (.mat-file) [ %s ]', menustr, save_performance_flag_str ); menuact = [menuact 22];
menustr = sprintf('%s|Save simulated data per estimated sample size (.mat-file) [ %s ]', menustr, save_simdata_flag_str); menuact = [menuact 23];

if strcmp(setup.mode, 'pre')
    menustr = sprintf('%s|Define output directory [ %s ]', menustr, setup.output.outputdir); menuact = [menuact 19]; %  or analysis folder (posthoc)
end
menustr = sprintf('%s|START sample size simulation ', menustr); menuact = [menuact 100];


if isfield(NM,'simulation') 
    nruns = numel(NM.simulation.run);
    if nruns>1
        menustr = sprintf('%s|Inspect sample size simulation results (%g runs available)', menustr, nruns); 
    else
        menustr = sprintf('%s|Inspect sample size simulation results', menustr); 
    end
    menuact = [menuact 101]; 
end

nk_PrintLogo
mestr = 'Sample size estimation setup'; navistr = sprintf('%s\n\t>>> %s', parentstr, mestr); fprintf('\nYou are here: >>> %s ', parentstr);
act = nk_input(mestr, 0,'mq', menustr, menuact);

switch act
    case 1
        if strcmp(setup.mode,'pre')
            setup.mode = 'posthoc';
        else
            setup.mode = 'pre';
        end
    case 2
        setup.pre.NFeats = nk_input('Define feature dimensionality',0,'e');
    case 3
        setup.pre.NMarkers = nk_input('Define number or fraction of prediction markers [>=1 or 0-1]',0,'e');
    case 4
        setup.pre.NCases = nk_input('Define sample size',0,'e');
    case 5
        setup.pre.EventProb = nk_input('Define event probability [0-1]',0,'e');
    case 6
        setup.pre.AUCmax = nk_input('Define maximum AUC [0-1]',0,'e');
    case 7
        setup.pre.AUCmin = nk_input('Define minumum AUC [0-1]',0,'e');
    case 8
        setup.pre.NBatches = nk_input('Define number of batches in the data',0,'e');
    case 9
        setup.pre.BatchPerc = nk_input('Define batch strength as fraction [0-1] of feature range',0,'e');
    case 10
        setup.pre.NCasesMiss = nk_input('Define fraction [0-1] of cases with missing values',0,'e');
    case 11
        setup.pre.NFeatsMiss = nk_input('Define fraction [0-1] of features within missing values',0,'e');
    case 12
        setup.pre.RAND.OuterPerm = nk_input('Define number of outer CV permutations',0,'e');
    case 13
        setup.pre.RAND.InnerPerm = nk_input('Define number of inner CV permutations',0,'e');
    case 14
        setup.pre.RAND.OuterFold = nk_input('Define number of outer CV folds',0,'e');
    case 15
        setup.pre.RAND.InnerFold = nk_input('Define number of inner CV folds',0,'e');
    case 16
        setup.pre.Algorithm = char(nk_input('Select input', 0, 'm', 'LINKERNSVM|LINSVM|L2LR|L1LR|L1SVC', {'LINKERSVM', 'LINSVM', 'L2LR', 'L1LR', 'L1SVC'}, 1));
    case 17
        setup.pre.NReps = nk_input('Define number of repetitions',0,'e');
    case 19 
        setup.output.outputdir = nk_DirSelector('Select output directory');
    case 20
        setup.pre.GridParam = nk_EvalFunc_config([],setup.pre,'Investigate sample size configurator','classification');
    case 21
        setup.output.plot_flag = ~setup.output.plot_flag;
    case 22
        setup.output.save_performance_flag = ~setup.output.save_performance_flag;
    case 23
        setup.output.save_simdata_flag = ~setup.output.save_simdata_flag;
    case 50
        setup.posthoc.NRanalysis = nk_input('Define  analysis index',0,'e');
    case 51
        condIdx_flag = nk_input('Would you like to generate synthetic data based on a conditional variable (the label or a covariate?)',0, 'b', 'No|Yes', 0:1);
        if condIdx_flag
            if isfield(NM, 'covars')
                condIdx_label_flag = nk_input('Use label as conditional variable',0, 'b', 'No|Yes', 0:1);
                if ~condIdx_label_flag % i.e., use a covariate
                    setup.posthoc.condIdx = nk_SelectCovariateIndex(NM);
                else
                    setup.posthoc.condIdx = 0;
                end 
            else
                setup.posthoc.condIdx = 0;
            end
        else
            setup.posthoc.condIdx = -1;
        end
        fprintf(['\nThe number of synthetic cases to simulate should be entered as a matrix of the size \n' ...
            'n_rows = number of groups in conditional variable (if no conditional variable was defined, then = 1); \n' ...
            'n_cols = number of simulation rounds \n' ...
            'Example: [100, 200; 150, 300]' ...
            '\nRound 1  Round 2\nGroup 1: 100   200\nGroup 2: 150   300\n' ...
            'In this example, in the first round 100 synthetic cases will be added to the first group in the conditional variable, \n' ...
            'and 150 to the second group. In the second simulation round, 200 cases are added to the first, and 300 to the second group. \n' ...
            'Note: this variable can also be read from MATLAB Workspace.'])
        setup.posthoc.NCases = nk_input('Define how many synthetic cases you would like to generate (can be a an array of Ns)',0,'e');
    case 52
        setup.posthoc.add2orig = nk_input('Should the data be added to the original data?', 0, 'b', 'No|Yes', 0:1);
    case 53
        setup.posthoc.NReps = nk_input('Define  N reps',0,'e');
    case 54
        setup.posthoc.method= nk_input('Choose synthetic data generation method', 0, 'm', 'kNN-based|PCAGauss|Gaussian Copula', 1:3, methodnum); % ADASYN
    case 55
        if setup.posthoc.standardize_data == 1, setup.posthoc.standardize_data = 2; else, setup.posthoc.standardize_data = 1; end
    case 56
        setup.posthoc.k = nk_input('Define no. of nearest neighbors for interpolation',0,'i', k);
    case 57
        sel = 'Euclidean|Manhattan|Cosine|Mahalanobis';
        defsel = strsplit(sel,'|');
        setup.posthoc.distanceMeasure = char(nk_input('Choose distance measure',0,'m', sel, defsel, find(contains(defsel, distanceMeasure))));
%     case 58
%         setup.posthoc.beta = nk_input('Define beta for degree of balancing',0,'e',adasyn_beta);
%     case 59
%         setup.posthoc.kDensity = nk_input('Define k for Density estimation in ADASYN',0,'i',adasyn_kDensity);
%     case 60
%         setup.posthoc.kSMOTE = nk_input('Define k for SMOTE in ADASYN',0,'i',adasyn_kSMOTE);
    case 61
        setup.posthoc.NCases = nk_input('Index/indices of dummy-coded covariates',0,'e');
    case 70
        setup.output.plot_flag = ~setup.output.plot_flag;
    case 71
        setup.output.save_performance_flag = ~setup.output.save_performance_flag;
    case 72
        setup.output.save_simdata_flag = ~setup.output.save_simdata_flag;
    case 73
        setup.output.outputdir = nk_input('Define output directory', 0, 's');
    case 100
        if ~exist("nruns","var"), nruns=0; end
        cnt = nruns + 1;
        [NM.simulation.run(cnt).performance_results, ~] = cv_estimate_samplesize_simu(setup);
        NM.simulation.run(cnt).setup = setup;
        NM.simulation.run(cnt).date = date;
    case 101
        if nruns>1
            % Open simulation run selector
            nk_PrintLogo
            mestr = 'Sample size estimation setup [run selection]'; navistr = sprintf('%s\n\t>>> %s', parentstr, mestr); fprintf('\nYou are here: >>> %s ', parentstr);
            run_descriptor = cell(nruns,1);
            for i=1:nruns
                if strcmp(NM.simulation.run(i).setup.mode, 'pre')
                    run_descriptor{i} = sprintf('Date: %s, Nf: %g, Nm: %g, Nc: %g, Eprob: %g, AUC (max): %g, Nbatch: %g, BatchS: %g, Frac-miss(cases): %g, Frac-miss(feats): %g', ...
                        NM.simulation.run(i).date, ...
                        max(NM.simulation.run(i).setup.pre.NFeats), ...
                        max(NM.simulation.run(i).setup.pre.NMarkers), ...
                        max(NM.simulation.run(i).setup.pre.NCases), ...
                        max(NM.simulation.run(i).setup.pre.EventProb), ...
                        max(NM.simulation.run(i).setup.pre.AUCmax), ...
                        max(NM.simulation.run(i).setup.pre.NBatches), ...
                        max(NM.simulation.run(i).setup.pre.BatchPerc), ...
                        max(NM.simulation.run(i).setup.pre.NCasesMiss), ...
                        max(NM.simulation.run(i).setup.pre.NFeatsMiss));
                else
        
                    run_descriptor{i} = sprintf('Date: %s, Analysis-ID: %d, Nc: %g, Method: %s', ...
                        NM.simulation.run(i).date, ...
                        NM.simulation.run(i).setup.posthoc.NRanalysis, ...
                        max(NM.simulation.run(i).setup.posthoc.NCases), ...
                        methodstr{NM.simulation.run(i).setup.posthoc.method});
                end
            end
            cnt = nk_input('Choose simulation analysis for display', 0, 'mq', strjoin(run_descriptor,'|'), 1:nruns);
        else
            cnt=1;
        end
        if cnt>0,cv_visualize_samlesize_estimation_results(NM.simulation.run(cnt).performance_results);end
end
