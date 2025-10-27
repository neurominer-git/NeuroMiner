classdef nk_StandardizeMod < handle
% nk_StandardizeMod 
% =========================================================================
% NM class for the "Standardization" preprocessing step, 
% consisting of:
%   1) Config => calls nk_Standardize_config to pick method, winsorize, etc.
%   2) Perform => calls nk_PerfStandardizeObj on user data
%   3) Description => builds a display string akin to "standardize" snippet 
%                     in nk_GetParamDescription2.m.
%
% PROPERTIES:
%   name         : unique identifier ('standardize')
%   stepParams   : struct storing fields from nk_Standardize_config 
%                  (METHOD, WINSOPT, sIND, dIND, zerooutflag, etc.)
%
% METHODS:
%   configure    : calls nk_StandardizeConf => user picks method
%   perform      : calls nk_PerfStandardizeObj => standardizes data
%   describe     : returns a textual summary of the chosen settings
%   
% EXAMPLE:
%   SM = StandardizeModule();
%   SM.configFcn();                % user sets standardization method, etc.
%   [Ystd, finalStd] = SM.performFcn(Yraw);
%   disp( SM.descriptionFcn() );
% =========================================================================
% (c) Nikolaos Koutsouleris, 04/2025

    properties
        name = 'standardize'        % Unique module identifier
        stepParams = struct();      % Will hold the struct from nk_Standardize_config#
        PX = struct();
        ExecutedInCV = false;
    end

    methods

        % --------------------- Constructor -----------------------
        function obj = nk_StandardizeMod(initialParams)
            % Optional constructor: user can pass initial standardization struct
            if nargin > 0
                obj.stepParams = initialParams;
            end
        end

        % --------------------- Config Fcn ------------------------
        function configure(obj, defaultsfl, NM)
            % configFcn: calls nk_Standardize_config to let user pick standardization options
            %
            % We'll assume the signature is:
            %   [STANDARD, act] = nk_StandardizeConf(NM, STANDARD, parentstr, defaultsfl)
            % where 'STANDARD' is your config struct with fields 
            %   .METHOD, .WINSOPT, .sIND, .dIND, .IQRFUN, .PX, etc.
            %
            % We'll store the result in obj.stepParams.STANDARD.

            fprintf('\n--- Configuring the %s module ---\n', obj.name);
            if ~exist("NM","var") || isempty(NM)
                error("Standarization Module: Call configure() with NM structure as input argument.");
            end
            parentstr  = 'Standardization Module'; 
            if ~exist("defaultsfl","var") || isempty(defaultsfl), defaultsfl = false;  end % set to true if skipping user input

            % call the config function
            act = Inf;
            while act>0
                [obj.stepParams, obj.PX, act] = nk_StandardizeConf(NM, obj.stepParams, obj.PX, parentstr, defaultsfl);
            end

            fprintf('Standardization config done. Method=%s, WinsOpt=%s\n', ...
                obj.stepParams.METHOD, nk_ConcatParamstr(obj.stepParams.WINSOPT));
        end

        % ---------------------      Perform Fcn      ---------------------
        function [Yout, obj] = perform(obj, Y)
            % performFcn: calls nk_PerfStandardizeObj(Y, IN) to standardize data.

            fprintf('\n--- Performing %s on data ---\n', obj.name);

            if isempty(obj.stepParams)
                error('StandardizeModule: not configured yet. Call configure() first.');
            end

            [ Yout, obj.stepParams ] = nk_PerfStandardizeObj(Y, obj.stepParams);
            
            fprintf('Standardization done. Method=%s\n', obj.stepParams.METHOD);
        end

        % ---------------------    Description Fcn    ---------------------
        function descStr = describe(obj)
            % descriptionFcn: returns a string describing the standardization 
            % settings, mimicking the snippet from nk_GetParamDescription2.m 
            % for 'standardize'.
            %
            % The original snippet does things like:
            %   preprocact{i} = 'Standardize data';
            %   if ~isempty(params.ActParam{i}.WINSOPT), ...
            %   if isfield(params.ActParam{i},'METHOD'), ...
            %   etc.
            %
            % We'll build a short summary here.

            if isempty(obj.stepParams)
                descStr = sprintf('[%s] Standardization: not configured', obj.name);
                return;
            end

            S = obj.stepParams;
            if isfield(S,'METHOD'), methodStr = S.METHOD; else, methodStr = 'undefined'; end

            descStr = sprintf('[%s] Standardize data [method=%s', obj.name, methodStr);

            % Check WINSOPT
            if isfield(S,'WINSOPT') && ~isempty(S.WINSOPT)
                descStr = sprintf('%s, Winsorize: +/- %s SD', descStr, mat2str(S.WINSOPT));
            end

            % Check sIND or dIND
            if isfield(S,'sIND') && ~isempty(S.sIND)
                descStr = sprintf('%s, sIND: yes', descStr);
            else
                descStr = sprintf('%s, sIND: no', descStr);
            end
            if isfield(S,'dIND') && ~isempty(S.dIND)
                descStr = sprintf('%s, dIND: yes', descStr);
            else
                descStr = sprintf('%s, dIND: no', descStr);
            end

            % IQRFUN => if method is 'standardization using median' + IQRFUN=1 => iqr
            if isfield(S,'IQRFUN') && (S.IQRFUN == 1)
                descStr = sprintf('%s, use IQR', descStr);
            end

            % zerooutflag 
            if isfield(S,'zerooutflag') && (S.zerooutflag == 1)
                descStr = sprintf('%s, zero-out non-finite feats=yes', descStr);
            end

            descStr = sprintf('%s ]', descStr);
        end
        
        % ---------------------   Execute in CV Fcn   ---------------------
        function [SourceParam, DataContainer, TrainedParam, ActParam] = executeInCV(obj, SourceParam, DataContainer, ~, TrainedParam, ActParam, VERBOSE)
            
            % Optional inputs
            if ~exist("SourceParam","var") || isempty(SourceParam), SourceParam = []; end
            if ~exist("TrainedParam","var") || isempty(TrainedParam), TrainedParam = []; end
            if ~exist("VERBOSE","var") || isempty(VERBOSE), VERBOSE = false; end

            tsproc = false;            
            
            if isfield(ActParam,'opt')
                obj.stepParams.WINSOPT = ActParam.opt;
            end
            
            if VERBOSE; fprintf('\tStandardizing data ...'); end
            if ActParam.paramfl && ActParam.tsfl && isfield(TrainedParam,'meanY') && isfield(TrainedParam,'stdY')
                % Here we activate the application mode
                tsproc = true;
            else
                % Otherwise enter training mode if trfl = true
                if ActParam.trfl    
                    % Check for synthetic data
                    if ActParam.synthfl && isfield(obj.stepParams,'sTrInd') && ~isempty(obj.stepParams.sTrInd)
                        if iscell(SourceParam.covarsSyn)
                            obj.stepParams.sTrInd = [obj.stepParams.sTrInd; SourceParam.covarsSyn{ActParam.j}(:, obj.stepParams.sIND)]; 
                        else
                            obj.stepParams.sTrInd = [obj.stepParams.sTrInd; SourceParam.covarsSyn(:, obj.stepParams.sIND)]; 
                        end
                    end
                    [DataContainer.Tr, obj] = obj.perform(DataContainer.Tr);
                end
                % Then go into application mode
                if ActParam.tsfl, tsproc = true; end
            end
            
            % Apply preproc params to new data.
            if tsproc
                if ActParam.copy_ts
                    % here we copy from DataContainer.Tr to .Ts because
                    % data is identical which can save a significant
                    % computational time
                    DataContainer.Ts{1} = DataContainer.Tr;
                    Ts = obj.perform(DataContainer.Ts(2:end)); 
                    DataContainer.Ts(2:end) = Ts;
                else
                    DataContainer.Ts = obj.perform(DataContainer.Ts); 
                end
                obj.ExecutedInCV = true;
            end
        end
            
        end % methods
    end
            