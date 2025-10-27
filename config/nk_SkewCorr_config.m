function [SKW, PX, act] = nk_SkewCorr_config(SKW, PX, parentstr, defaultsfl)
% =========================================================================
% FORMAT: [SKW, PX, act] = nk_SkewCorr_config(SKW, PX, parentstr, defaultsfl)
% =========================================================================
% NeuroMiner-style configuration function for skewness correction (SkewCorr).
%
% PURPOSE:
%   Lets the user interactively select parameters for the 'skewcorr' module,
%   such as transform method ('log','boxcox','yeojohnson'), skewness threshold(s),
%   and manual/auto lambda for Box–Cox or Yeo–Johnson. 
%
%   By returning "PX" separately, we can add SkewCorr parameters (SkewThr,
%   BoxCoxLambdaVal, etc.) to the hyperparameter search space in NM.
%
%   Typically invoked from nk_Preproc_config via:
%       [CURACT.SKEWCORR, CURACT.PX, act] = nk_SkewCorr_config(CURACT.SKEWCORR, ...
%                                                              CURACT.PX, navistr);
%
% INPUTS:
%   SKW       : struct with skewness-correction fields (see below).
%   PX        : parameter-expansion struct (for hyperparam search).
%   parentstr : string for navigation context in interactive mode.
%   defaultsfl: if true => no user interaction, just set defaults.
%
% OUTPUTS:
%   SKW : updated struct with the user’s final skew-correction settings
%         (e.g., .transformMethod, .SkewThr, etc.).
%   PX  : updated param-expansion struct with any new SkewCorr parameters.
%   act : integer controlling interactive loops. If 0 => done.
%
% FIELDS in SKW:
%   .transformMethod   : 'log' | 'boxcox' | 'yeojohnson' (default 'log')
%   .SkewThr           : numeric scalar or vector (default 2)
%   .BoxCoxLambdaType  : 'auto' | 'manual' (default 'auto')
%   .BoxCoxLambdaVal   : numeric scalar/vector => per-feature lambda(s) if manual
%   .YJLambdaType      : 'auto' | 'manual' (default 'auto')
%   .YJLambdaVal       : numeric scalar/vector => per-feature if manual
%   .CALIBUSE          : e.g., 1 or 2 (calibration usage)
%
% FIELDS in PX (if needed):
%   .Px.Params         : cell array describing hyperparam expansions
%   .Px.Params_desc    : descriptions of the expansions
%   .opt               : allcomb(...) expansions
% =========================================================================
% (c) Nikolaos Koutsouleris, 2025

%% 1. Handle Inputs & Defaults
if ~exist('defaultsfl','var') || isempty(defaultsfl)
    defaultsfl = false;
end
if ~exist('SKW','var') || isempty(SKW), SKW = struct; end
if ~exist('PX','var')  || isempty(PX),  PX  = struct; end

% Default field values (if missing)
if ~isfield(SKW, 'transformMethod'),  SKW.transformMethod  = 'yeojohnson'; end
if ~isfield(SKW, 'SkewThr'),          SKW.SkewThr          = 2;     end
if ~isfield(SKW, 'BoxCoxLambdaType'), SKW.BoxCoxLambdaType = 'auto';end
if ~isfield(SKW, 'BoxCoxLambdaVal'),  SKW.BoxCoxLambdaVal  = 0;     end
if ~isfield(SKW, 'YJLambdaType'),     SKW.YJLambdaType     = 'auto';end
if ~isfield(SKW, 'YJLambdaVal'),      SKW.YJLambdaVal      = 0;     end
if ~isfield(SKW, 'CALIBUSE'),         SKW.CALIBUSE         = 2;     end  % 1 => calibrate

% If defaults only => finalize & return
if defaultsfl
    act = 0;
    [SKW, PX] = updatePX(SKW, PX);
    return;
end

%% 2. Interactive Menu
act = 1; 
while act > 0
    % Build menu strings
    methodStr = SKW.transformMethod;
    thrStr    = nk_ConcatParamstr(SKW.SkewThr, true);
    
    menuStr = [ ...
        'Set transform method [ ' methodStr ' ]|' ...
        'Set skewness threshold [ ' thrStr ' ]' ];
    menuAct = [1,2];
    
    % Possibly add line for Box–Cox or Yeo–Johnson lambdas
    if strcmpi(SKW.transformMethod, 'boxcox')
        if strcmpi(SKW.BoxCoxLambdaType,'auto')
            lamStr = 'auto (MLE)';
        else
            lamStr = ['manual (' nk_ConcatParamstr(SKW.BoxCoxLambdaVal,true) ')'];
        end
        menuStr = [menuStr '|' 'Set Box–Cox lambda [ ' lamStr ' ]'];
        menuAct = [menuAct, 3];
    elseif strcmpi(SKW.transformMethod, 'yeojohnson')
        if strcmpi(SKW.YJLambdaType,'auto')
            lamStr = 'auto (MLE)';
        else
            lamStr = ['manual (' nk_ConcatParamstr(SKW.YJLambdaVal,true) ')'];
        end
        menuStr = [menuStr '|' 'Set Yeo–Johnson lambda [ ' lamStr ' ]'];
        menuAct = [menuAct, 3];
    end

    % Insert calibration usage if desired
    [menuStr, menuAct] = nk_CheckCalibAvailMenu_config(menuStr, menuAct, SKW.CALIBUSE);

    % Show the menu
    nk_PrintLogo;
    mestr  = 'Skewness Correction';
    fprintf('\nYou are here: %s >>> ', parentstr);
    act = nk_input(mestr, 0, 'mq', menuStr, menuAct);
    
    switch act
        case 1
            % Transform method
            val = nk_input('Transform method', 0, 'm', ...
                'Log transform|Box-Cox|Yeo-Johnson',[1 2 3],1);
            switch val
                case 1, SKW.transformMethod = 'log';
                case 2, SKW.transformMethod = 'boxcox';
                case 3, SKW.transformMethod = 'yeojohnson';
            end

        case 2
            % Skewness threshold can be scalar or vector
            prompt = 'Enter skewness threshold(s), e.g. 2 or [1 2 3]:';
            SKW.SkewThr = nk_input(prompt, 0, 'e', SKW.SkewThr);

        case 3
            % If user sees #3, it must be either boxcox or yeojohnson
            if strcmpi(SKW.transformMethod,'boxcox')
                [SKW.BoxCoxLambdaType, SKW.BoxCoxLambdaVal] = lambdaConfig(...
                    'Box–Cox', SKW.BoxCoxLambdaType, SKW.BoxCoxLambdaVal);
            else
                [SKW.YJLambdaType, SKW.YJLambdaVal] = lambdaConfig(...
                    'Yeo–Johnson', SKW.YJLambdaType, SKW.YJLambdaVal);
            end

        case 1000
            % Possibly refine usage of calibration data
            SKW.CALIBUSE = nk_AskCalibUse_config(mestr, SKW.CALIBUSE);

        otherwise
            % User canceled or no action
            act = 0;
    end
end

%% 3. Update PX with final config & Return
[SKW, PX] = updatePX(SKW, PX);

end % nk_SkewCorr_config
% =========================================================================


%% ========================== SUBFUNCTIONS ================================

function [lambdaType, lambdaVal] = lambdaConfig(nameStr, currentType, currentVal)
% lambdaConfig: simple sub-menu for picking manual vs. auto lambdas
% 
fprintf('\n--- %s lambda configuration ---\n', nameStr);
fprintf('1) Auto (MLE or pipeline approach)\n');
fprintf('2) Manual numeric range\n');

if strcmpi(currentType,'auto')
    disp('Current setting = AUTO.');
else
    disp(['Current setting = MANUAL. Current values: ' nk_ConcatParamstr(currentVal,true)]);
end

methodSel = nk_input(['Set ' nameStr ' lambda'], 0, 'm', ...
                     'Auto|Manual',[1 2], strcmpi(currentType,'manual')+1);

if methodSel == 1
    lambdaType = 'auto';
    lambdaVal  = 0;
else
    lambdaType = 'manual';
    prompt = sprintf('Enter one or more lambda values for %s', nameStr);
    lambdaVal = nk_input(prompt, 0, 'e', currentVal);
end

end

function [SKW, PX] = updatePX(SKW, PX)
% updatePX: Sets up parameter expansions for Skewness Correction
% so that SkewThr, BoxCoxLambdaVal, YJLambdaVal can be hyperparameters.

if ~isfield(PX,'Px'), PX.Px = struct('Params', {{}}, 'Params_desc', {{}}, 'opt', []); end

% 1) Always treat SkewThr as a hyperparam dimension #1 
%    (the user might have multiple thresholds).
PX = nk_AddParam(SKW.SkewThr, 'skewthr', 1, PX);

% 2) Box–Cox lambda => dimension #2 if manual
if strcmpi(SKW.transformMethod,'boxcox') && strcmpi(SKW.BoxCoxLambdaType,'manual')
    PX = nk_AddParam(SKW.BoxCoxLambdaVal, 'boxcoxlambda', 2, PX);
end

% 3) Yeo–Johnson => dimension #3 if manual
if strcmpi(SKW.transformMethod,'yeojohnson') && strcmpi(SKW.YJLambdaType,'manual')
    PX = nk_AddParam(SKW.YJLambdaVal, 'yjlambda', 3, PX);
end

% Build the combined param space
if isfield(PX,'Px') && isfield(PX.Px,'Params') 
    PX.opt = allcomb(PX.Px.Params, 'matlab');
else
    PX.opt = [];
end

end
