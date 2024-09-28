function [sY, IN] = cv_perfJuSpace(Y, IN, INDPruneVec)
% =========================================================================

% =========================== WRAPPER FUNCTION ============================ 
    if ~exist('IN','var'), IN = []; end
    if iscell(Y) 
        sY = cell(1,numel(Y)); 
        for i=1:numel(Y), [sY{i}, IN] =  PerfJuSpace(Y{i}, IN, INDPruneVec); end
    else
        [ sY, IN ] = PerfJuSpace(Y, IN, INDPruneVec);
    end
end

% =========================================================================
function [Y, IN] = PerfJuSpace(Y, IN, INDPruneVec)
    
    inputStr = '';
    
    if ~isempty(IN.NTROIs) && ~isempty(IN.YAtlas) && ~isempty(IN.cortype) && ~isempty(IN.autocorcorrect)
        Y = JuSpace_no_GUI_2D_faster(Y, IN, INDPruneVec);
    end
           
end
