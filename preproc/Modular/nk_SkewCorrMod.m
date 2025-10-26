classdef nk_SkewCorrMod < handle
% nk_SkewCorrMod
% ==================================================================================
% NM class for the "Skewness Correction" preprocessing step, 
% consisting of:
%   1) Configuration: calls nk_SkewCorr_config
%   2) Perform: calls nk_PerfSkewCorrObj
%   3) Description: similar to nk_GetParamDescription2 snippet
%
% PROPERTIES:
%   name           : unique identifier for this module ('skewcorr')
%   stepParams     : struct storing user-chosen parameters from config 
%   PX             : Hyperparameter optimization structure
%
% METHODS:
%   configure      : calls nk_SkewCorrConf to configure the step
%   perform(Y)     : calls nk_PerfSkewCorrObj on data Y
%   describe()     : returns a display string, akin to nk_GetParamDescription
%   prepare4CV(obj, VERBOSE) : prepares the execution of the the class 
%                    functionality within NM's pipeline runner
%   executeInCV(SourceParam, ...) : runs class instance within NM's 
%                    pipeline runner
%
% Example:
%   SCM = nk_SkewCorrMod();
%   SCM.configure();              % user sets transformMethod, SkewThr, ...
%   [Ycorr, SCM] = SCM.perform(Yraw);
%   disp(SCM.describe());
% ===================================================================================
% (c) Nikolaos Koutsouleris, 04/2025

    properties
        name = 'skewcorr'          % Unique name/identifier
        stepParams = struct();     % Will store config from nk_SkewCorr_config
                                   % e.g., .transformMethod, .SkewThr, .PX, etc.
        PX = struct();
        ExecutedInCV = false;
    end

    methods

        % --------------------- Constructor -----------------------
        function obj = nk_SkewCorrMod(initialParams)
            % Optional constructor: user can provide an initial struct
            if nargin > 0
                obj.stepParams = initialParams;
            end
        end

        % --------------------- Config Fcn ------------------------
        function configure(obj, defaultsfl)
            % configure: calls nk_SkewCorrConf to let the user define
            % parameters for Skewness Correction (transformMethod, SkewThr, etc.)

            fprintf('\n--- Configuring the %s module ---\n', obj.name);
           
            % Call the config function. Adjust the parentstr or defaults as needed.
            parentstr = 'SkewCorr Module';
            if ~exist("defaultsfl","var") || isempty(defaultsfl), defaultsfl = false;  end % set to true if skipping user input
            
            act = Inf;
            while act>0
                [obj.stepParams, obj.PX, act] = nk_SkewCorrConf(obj.stepParams, obj.PX, parentstr, defaultsfl);
            end
            
            fprintf('Configuration done. transformMethod = %s, SkewThr= %g\n', ...
                obj.stepParams.transformMethod, obj.stepParams.SkewThr);
        end

        % --------------------- Perform Fcn -----------------------
        function [Yout, obj] = perform(obj, Y)
            % perform: apply skewness correction to data Y

            fprintf('\n--- Performing %s on data ---\n', obj.name);

            if ~isempty(obj.stepParams)
                error('SkewCorrModule: Parameters not configured. Call configure() first.');
            end

            [Yout, obj.stepParams] = nk_PerfSkewCorrObj(Y, obj.stepParams);
            
            fprintf('Skewness correction done. Method=%s, SkewThr=%g\n', ...
                obj.stepParams.transformMethod, obj.stepParams.SkewThr);
        end
    

        % -------- Prepare module instance for execution within CV --------
        function ParamContainer = prepare4CV(obj, VERBOSE)
             
	        if ~exist("VERBOSE","var") || isempty(VERBOSE), VERBOSE = false; end

            % Store the SKEWCORR struct so that nk_PerfPreprocessObj_core can use it
            if VERBOSE, fprintf('\n* SKEWNESS CORRECTION'); end
             
            ParamContainer.SKEWCORR = obj;
            
            % If there is a PX with hyperparams, copy them into the parameter container
            if isfield(obj, 'PX') && ~isempty(obj.PX) 
                if ~isempty(obj.PX.opt)
                   ParamContainer.opt = obj.PX.opt;
                   ParamContainer.Params_desc = obj.PX.Px.Params_desc;
                end
            else
                error('SkewCorrModule: Configure parameters of module instance first using configure()!');
            end
        end
        
        function [ SourceParam, DataContainer, TrainedParam, ActParam ] = executeInCV(obj, SourceParam, DataContainer, ~, TrainedParam, ActParam, VERBOSE, CALIB)
            % executeInCV: Perform Skewness Correction (log, Box–Cox, Yeo–Johnson) on 
            %               training and test data. Called by nk_PerfPreprocessObj_core.
            %
            % INPUTS:
            %   SourceParam :   struct with global settings (labels, config)
            %   ParamContainer: struct with fields .Tr (train data), .Ts (test data), .P, etc.
            %   TrainedParam :  parameters for this step (either newly computed or stored from prior run)
            %   ActParam :      struct with flags (trfl, tsfl, paramfl, etc.)
            %
            % OUTPUTS:
            %   SourceParam  :  possibly updated (e.g., if synthetic data, label adjustments)
            %   ParamContainer: updated data (train/test) after skew correction
            %   TrainedParam :  updated transformation parameters (e.g. offsets, lambdas)
            %   ActParam  :     pass-through ActParam
            
            % Mandatory inputs
            if ~exist("ParamContainer","var") || isempty(ParamContainer), ...
                    error("SkewCorrModule: Parameter container cannot be empty! Prepare module instance for execution in CV first."); 
            end
            if ~exist("ActParam","var") || isempty(ActParam), ...
                    error("SkewCorrModule: Action parameter container cannot be empty! The module instance has to be called from within nk_PerfPreprocessingObj."); 
            end

            % Optional inputs
            if ~exist("SourceParam","var") || isempty(SourceParam), SourceParam = []; end
            if ~exist("TrainedParam","var") || isempty(TrainedParam), TrainedParam = []; end
            if ~exist("VERBOSE","var") || isempty(VERBOSE), VERBOSE = false; end
            if ~exist("CALIB","var") || isempty(CALIB), CALIB.calibflag = false; end

            tsproc  = false;            % indicates whether we also process test data
            
            if VERBOSE
                fprintf('\tPerforming skewness correction ...');
            end
            
            if isfield(ActParam,'opt') && ~isempty(ActParam.opt)
                obj.stepParams.SkewThr = nk_ReturnParam('skewthr', obj.PX.Px.Params_desc, ActParam.opt); 
                obj.stepParams.BoxCoxLambdaVal = nk_ReturnParam('boxcoxlambda', obj.PX.Px.Params_desc, ActParam.opt); 
                obj.stepParams.YJLambdaVal = nk_ReturnParam('yjlambda', obj.PX.Px.Params_desc, ActParam.opt); 
            end
            
            % If we already have stored transformation parameters (TrainedParam) and are in 
            % out-of-sample mode with test data => just apply to test data
            if ActParam.paramfl && ActParam.tsfl && isfield(TrainedParam, 'SKEWCORR') 
                % We assume TrainedParam.SKEWCORR holds necessary info for applying transforms
                tsproc = true;
            else
                % Otherwise, if we have training data => do "forward" transform on train
                if ActParam.trfl
                    [DataContainer.Tr, obj] = obj.perform(obj.stepParams, DataContainer.Tr);
                    % Suppose nk_PerfSkewCorrObj returns a second output "TrainedParam" 
                    % that has offsets, lambdas, etc. in TrainedParam.SKEWCORR 
                end
                % If there's test data, we will apply the same transform to it
                if ActParam.tsfl
                    tsproc = true;
                end
            end
            
            % Apply to test data if needed
            if tsproc
                ParamContainer.Ts = nk_PerfSkewCorrObj(ParamContainer.Ts, TrainedParam);
            end
            
            % we might also handle calibration data (ParamContainer.C) if it exists, 
            % or synthetic label data, etc. following the same pattern 
            % (like in act_scale, act_standardize).
            if CALIB.calibflag && isfield(ParamContainer, 'C') %&& CALIB.preprocstep > i 
                ParamContainer.C = nk_PerfSkewCorrObj(ParamContainer.C, ParamContainer.P.SKEWCORR);
            end
            obj.ExecutedInCV = true;
        end

        % --------------------- Description Fcn ---------------------------
        function descStr = describe(obj)
            % descriptionFcn: returns a display string akin to the snippet
            % from nk_GetParamDescription.m for 'skewcorr'.
            %
            %   case 'skewcorr' => build a text like
            %      'Skewness correction [ Method: <method>, Threshold: <thr>, ...]'

            if ~isfield(obj.stepParams) || isempty(obj.stepParams)
                descStr = sprintf('[%s] Skewness Correction: not configured.', obj.name);
                return;
            end

            SKW = obj.stepParams;
            if ~isfield(SKW,'transformMethod')
                descStr = sprintf('[%s] SkewCorr: transformMethod undefined.', obj.name);
                return;
            end

            % Start building the string
            descStr = sprintf('[%s] Skewness Correction [', obj.name);

            % Method
            descStr = sprintf('%s Method: %s', descStr, SKW.transformMethod);

            % Show threshold if present
            if isfield(SKW, 'SkewThr')
                descStr = sprintf('%s, Threshold: %g', descStr, SKW.SkewThr);
            end

            % If Box–Cox or Yeo–Johnson, show lambdas
            switch lower(SKW.transformMethod)
                case 'boxcox'
                    if isfield(SKW,'BoxCoxLambdaType')
                        if strcmpi(SKW.BoxCoxLambdaType,'auto')
                            descStr = sprintf('%s, BoxCox lambda: auto (MLE)', descStr);
                        else
                            lamStr = mat2str(SKW.BoxCoxLambdaVal);
                            descStr = sprintf('%s, BoxCox lambda: manual [%s]', descStr, lamStr);
                        end
                    end
                case 'yeojohnson'
                    if isfield(SKW,'YJLambdaType')
                        if strcmpi(SKW.YJLambdaType,'auto')
                            descStr = sprintf('%s, YJ lambda: auto (MLE)', descStr);
                        else
                            lamStr = mat2str(SKW.YJLambdaVal);
                            descStr = sprintf('%s, YJ lambda: manual [%s]', descStr, lamStr);
                        end
                    end
                otherwise
                    % 'log' => no extra param to show
            end

            descStr = sprintf('%s ]', descStr);
        end

    end % methods
end
