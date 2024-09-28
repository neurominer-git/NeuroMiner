function [perf_results, simulated_data] = cv_estimate_samplesize_simu(setup)
global NM 
% Input arguments
% setup : structure with necessary information
% setup.mode = 'pre' or 'posthoc'
%   setup.output.outputdir
%
% setup.pre.NFeats
% setup.pre.NMarkers
% setup.pre.NCases
% setup.pre.EventProb
% setup.pre.AUCmax
% setup.pre.AUCmin
% setup.pre.NBatches
% setup.pre.BatchPerc
% setup.pre.NCasesMiss
% setup.pre.NFeatsMiss
% setup.pre.Algorithm
% setup.pre.Nreps
% setup.pre.seed
%
% the following dont have to be set(defaults: 1,1,5,5,1)
% setup.pre.RAND.OuterPerm = 1; % ==> Outer cross-validation permutations
% setup.pre.RAND.InnerPerm = 1; % ==> Inner cross-validation permutations
% setup.pre.RAND.OuterFold = 5; % ==> Outer cross-validation folds
% setup.pre.RAND.InnerFold = 5; % ==> Inner cross-validation folds
% setup.pre.RAND.Decompose = 1;
%
%
% setup.posthoc.Data
% setup.posthoc.Modalities
% setup.posthoc.DataLabel
% setup.posthoc.NFeats
% setup.posthoc.NCases
% setup.posthoc.NRanalysis
% setup.posthoc.verbose
% setup.posthoc.add2orig
% setup.posthoc.NReps
% setup.posthoc.SitesIdx
% setup.posthoc.condIdx
% setup.posthoc.seed
%
% setup.save_performance_flag
% setup.output.save_simdata_flag
% setup.output.plot_flag

if (isfield(setup.output, 'save_performance_flag') && setup.output.save_performance_flag) || (isfield(setup.output, 'save_simdata_flag') && setup.output.save_simdata_flag) || (isfield(setup.output, 'plot_flag') && setup.output.plot_flag)
    
    if isfield(setup.output, 'outputdir') && ~isempty(setup.output.outputdir)
        if  ~exist(setup.output.outputdir, 'dir')
            mkdir(setup.output.outputdir);
        end
    else 
        setup.output.outputdir = pwd;
    end

    setup.output.outputdir = [setup.output.outputdir, '/SampleSizeEstimation_', datestr(datetime('now'), 'dd-mmm-yyyy')];
    try
        mkdir(setup.output.outputdir);
        %cd(setup.output.outputdir);
    catch
        warning('output directory already exists');
    end

end

if strcmp(setup.mode,'pre')
    % pre
    %Algorithms = {'LINKERNSVM', 'LINSVM', 'L2LR', 'L1LR', 'L1SVC'};
    %     IN.NFeats = setup.pre.NFeats; %str2num(app.NFeaturesEditField.Value);
    %     IN.NMarkers = str2num(app.ratioofpredictivemarkersEditField.Value);
    %     IN.NCases = str2num(app.NCasesEditField.Value);
    %     IN.EventProb = str2num(app.eventrateEditField.Value);
    %     IN.AUCmax = app.maxAUCEditField.Value;
    %     IN.AUCmin = app.minAUCEditField.Value;
    %     IN.NBatches = app.NBatchesEditField.Value;
    %     IN.BatchPerc = app.BatchPercEditField.Value;
    %     IN.NCasesMiss = app.caseswithmissingvaluesEditField.Value;
    %     IN.NFeatsMiss = app.fractionofmissingfeaturespercaseEditField.Value;
    %     IN.Algorithm = Algorithms{app.MLmethodDropDown.Value};
    %
    %     IN.NReps = app.repetitionsperhyperparameterEditField.Value;
    if ~isfield(setup.output, 'outputdir') || isempty(setup.output.outputdir)
        setup.pre.outputdir = pwd;
    else
        setup.pre.outputdir = setup.output.outputdir;
    end
    if isfield(setup.output, 'save_performance_flag')
        setup.pre.save_performance_flag = setup.output.save_performance_flag;
    end
    if isfield(setup.output, 'save_simdata_flag')
        setup.pre.save_simdata_flag = setup.output.save_simdata_flag;
    end
    if isfield(setup.output, 'plot_flag')
        setup.pre.plot_flag = setup.output.plot_flag;
    end

    [perf_results, simulated_data] = nk_SimulateML(setup.pre);
    perf_results.settings = setup.pre; 
else
    %post-hoc
    setup.posthoc.Data = NM.Y{1,NM.analysis{1,setup.posthoc.NRanalysis}.params.TrainParam.FUSION.M};
    setup.posthoc.Modalities = NM.analysis{1,setup.posthoc.NRanalysis}.params.TrainParam.FUSION.M;
    setup.posthoc.DataLabel= NM.label;
    setup.posthoc.NFeats = size(setup.posthoc.Data,2);
    
    
    
    setup.posthoc.outputdir = setup.output.outputdir; 
    if isfield(setup.output, 'save_performance_flag')
        setup.posthoc.save_performance_flag = setup.output.save_performance_flag;
    end
    if isfield(setup.output, 'save_simdata_flag')
        setup.posthoc.save_simdata_flag = setup.output.save_simdata_flag;
    end
    if isfield(setup.output, 'plot_flag')
        setup.posthoc.plot_flag = setup.output.plot_flag;
    end

    [perf_results, simulated_data] = nk_SimulateML(setup.posthoc);
    perf_results.settings = setup.posthoc; 
end
perf_results.mode = setup.mode;
end
