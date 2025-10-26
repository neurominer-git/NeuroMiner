% =========================================================================
% cParams = nk_PrepMLParams(Params, Params_desc, i)
% =========================================================================
% 
% DESCRIPTION:
%   Prepares machine learning (ML) parameters for the NeuroMiner framework 
%   based on the selected algorithm specified in the global variable SVM.prog.
%   The function selects and formats a subset of parameters along with their 
%   descriptions from the provided inputs. For some algorithms, additional 
%   command string fields (CMDSTR) are generated.
%
% INPUTS:
%   Params       - Matrix or array containing parameter values for various
%                  ML algorithms.
%   Params_desc  - Cell array (or similar) containing the descriptions for 
%                  each parameter.
%   i            - Index indicating the specific row/set of parameters to use.
%
% OUTPUT:
%   cParams      - Structure containing:
%                    .val  - The selected parameter values.
%                    .desc - The corresponding parameter descriptions.
%
% GLOBAL VARIABLES:
%   SVM      - Structure containing algorithm specifications and parameters.
%   GRD      - Structure holding additional parameters for some algorithms
%              (e.g., 'ROBSVM').
%   CMDSTR   - Structure used to store command strings or extra options for 
%              some SVM-based algorithms.
%
% DEPENDENT FUNCTIONS:
%   nk_GenRobSVMCmd, nk_ReturnParam, nk_ConcatLIBSVMParamStr
%
% =========================================================================
% (c) Nikolaos Koutsouleris, 03/2025 

function cParams = nk_PrepMLParams(Params, Params_desc, i)
global SVM GRD CMDSTR

% Select and format parameters based on the specified algorithm.
switch SVM.prog
    case 'matLRN'
        % For 'matLRN', use all parameters for the current index.
        cParams.val = Params(i,:);
        cParams.desc = Params_desc;
        
    case 'GLMNET'
        % For 'GLMNET', only the first 5 parameters are relevant.
        cParams.val = Params(i,1:5);
        cParams.desc = Params_desc(1:5);
        
    case 'GRDBST'
        % For 'GRDBST', use all parameters.
        cParams.val = Params(i,1:end);
        cParams.desc = Params_desc(1:end);
        
    case 'ROBSVM'
        % For 'ROBSVM', use all parameters and generate a command string.
        cParams.val = Params(i,:);
        cParams.desc = Params_desc;
        CMDSTR.cmd = nk_GenRobSVMCmd(GRD.ROBSVM, cParams);
        CMDSTR.quiet = ' -q';
        
    case 'SEQOPT'
        % For 'SEQOPT', use all parameters without additional formatting.
        cParams.val = Params(i,:);
        cParams.desc = Params_desc;
        
    case 'WBLCOX'
        % For 'WBLCOX', use all parameters.
        cParams.val = Params(i,:);
        cParams.desc = Params_desc;    
        
    otherwise
        % Default processing for algorithms not explicitly handled above.
        cParams = Params(i,:);
        switch SVM.prog
            case {'MKLRVM'}
                % For 'MKLRVM', further processing may be needed if multiple
                % variables are involved.
                % (e.g., if nvar > 1, cParams might need to be replicated)
                
            case 'MikRVM'
                % For 'MikRVM', extract the 'Kernel' parameter.
                cParams = nk_ReturnParam('Kernel', Params_desc, Params(i,:));
                
            case {'LIBSVM','LIBLIN','CCSSVM'}
                % For LIBSVM-type algorithms, convert numeric parameters into
                % a formatted character array.
                cParams = num2str(cParams','%1.10f');
                % Concatenate into a single parameter string.
                cParams = nk_ConcatLIBSVMParamStr(cParams);
                
                % Process additional weighting factor if required.
                if SVM.(SVM.prog).Weighting
                    CMDSTR.WeightFact = nk_ReturnParam('Weight Factor', Params_desc, Params(i,:));
                end
                
                % Optionally handle insensitive classification adjustments.
                if isfield(SVM.(SVM.prog),'MakeInsensitive') && SVM.(SVM.prog).MakeInsensitive
                    CMDSTR.CCLambda = nk_ReturnParam('CC-Lambda', Params_desc, Params(i,:));
                end
                
                % Handle specific kernel definitions (5, 6, 7) using the same 'Kernel'
                % parameter.
                if SVM.kernel.kerndef == 5 || SVM.kernel.kerndef == 6 || SVM.kernel.kerndef == 7
                    CMDSTR.WLiter = nk_ReturnParam('Kernel', Params_desc, Params(i,:));
                end
                
                % For custom kernels (kerndef == 8), loop through the required number
                % of custom function arguments.
                if SVM.kernel.kerndef == 8
                    if SVM.kernel.customfunc_nargin > 0
                        for n = 1:SVM.kernel.customfunc_nargin
                            % Create a dynamic argument name for each custom kernel parameter.
                            argName = sprintf('customkernel_arg%d', n);
                            % Dynamically evaluate and assign the custom kernel parameter.
                            eval(sprintf("CMDSTR.%s = nk_ReturnParam('Kernel function argument %d', Params_desc, Params(i,:))", argName, n));
                        end
                    end
                    % Additional custom kernel function handling can be inserted here.
                end
        end
end