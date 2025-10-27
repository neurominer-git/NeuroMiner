function inp = nk_SmoothMask( uPREPROC, inp, paramfl, curclass )
% nk_SmoothMask - Smooths weighting masks in preprocessing workflows
%
% Syntax:
%   inp = nk_SmoothMask(uPREPROC, inp)
%
% Description:
%   The function `nk_SmoothMask` is designed to smooth weighting masks that
%   are used in preprocessing workflows. Depending on the structure of the 
%   input, the function checks for existing weighting masks that may have 
%   been uploaded during data import or through ranking modules that employ 
%   external weighting masks. If a valid weighting mask is identified, it 
%   applies a spatial filtering operation using `nk_PerfSpatFilt`.
%
% Input Arguments:
%   uPREPROC - Structure containing preprocessing parameters. This may include 
%              information about spatial processing, active parameters, and 
%              external ranking modules.
%   inp      - Structure containing input data, which may include a field 'Yw' 
%              (weighting map) and 'X' (data to be processed).
%
% Output:
%   inp      - The input structure is returned with the smoothed weighting map 
%              included in the field 'iYw', if applicable.
%
% Notes:
%   - The function assumes that only one weighting map needs to be smoothed
%     alongside the data. Handling of multiple weighting maps is not 
%     implemented in this version.
%
% Example:
%   inp = nk_SmoothMask(uPREPROC, inp, paramfl);
% See also:
%   nk_PerfSpatFilt
% =========================================================================
% (c) Nikolaos Koutsouleris, 26/08/2024

if isfield( uPREPROC,'SPATIAL') && uPREPROC.SPATIAL.cubetype>1
    if isfield(inp,'Yw') || isfield(inp,'iYw')
        if isfield(inp,'Yw')
            Yw = inp.Yw;
        elseif isfield(inp,'iYw')
            Yw = inp.iYw;
        end
        % Check for weighting masks which have been read-in during data
        % import
        if exist('curclass','var') && iscell(Yw) && ~isempty(Yw{1})
            fprintf('\nSmoothing the weighting map uploaded during data input for binary classifier #%g.', curclass)
            inp.iYw = nk_PerfSpatFilt( Yw{curclass}, uPREPROC, paramfl.PV ); 
        else
            fprintf('\nSmoothing the weighting map uploaded during data input.')
            if ~isfield(inp,'X')
                inp.iYw = nk_PerfSpatFilt( Yw, uPREPROC, inp.P.X ); 
            else
                inp.iYw = nk_PerfSpatFilt( Yw, uPREPROC, inp.X ); 
            end
        end 
    else
        % Check for ranking modules which uses external weighting masks
        if isfield(uPREPROC,'ACTPARAM')
            I = arrayfun( @(j) isfield(uPREPROC.ACTPARAM{j},'RANK'), 1:numel( uPREPROC.ACTPARAM ));
            if any(I)
                Ix = find(I);
                for qx = 1:numel(Ix)
                    if isfield(uPREPROC.ACTPARAM{Ix(qx)}.RANK,'EXTERN')
                        fprintf('\nSmoothing the weighting map found in preprocessing chain (preprocessing step #%g).', qx)
                        if exist('curclass','var') 
                            if ~exist("paramfl","var") || isempty(paramfl)
                                inp.iYw = nk_PerfSpatFilt( uPREPROC.ACTPARAM{Ix(qx)}.RANK.EXTERN, uPREPROC, inp.X ); 
                            elseif isfield(paramfl,'PV')
                                inp.iYw = nk_PerfSpatFilt( uPREPROC.ACTPARAM{Ix(qx)}.RANK.EXTERN, uPREPROC, paramfl.PV );
                            else
                                inp.iYw = nk_PerfSpatFilt( uPREPROC.ACTPARAM{Ix(qx)}.RANK.EXTERN, uPREPROC, paramfl.X );
                            end
                        else
                            if  ( ~exist("paramfl","var") || isempty(paramfl) ) 
                                inp.iYw = nk_PerfSpatFilt( uPREPROC.ACTPARAM{Ix(qx)}.RANK.EXTERN, uPREPROC, inp.X ); 
                            elseif isfield(paramfl,'PV')
                                inp.iYw = nk_PerfSpatFilt( uPREPROC.ACTPARAM{Ix(qx)}.RANK.EXTERN, uPREPROC, paramfl.PV ); 
                            else
                                inp.iYw = nk_PerfSpatFilt( uPREPROC.ACTPARAM{Ix(qx)}.RANK.EXTERN, uPREPROC, paramfl.X ); 
                            end
                        end
                        % Here, we assume that there is only one
                        % weighting map to be smoothed alongside the
                        % data. This will obviously not work for
                        % multiple weighting maps...
                        break
                    end
                end
            end
        end
    end
end


