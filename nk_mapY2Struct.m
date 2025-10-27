function [out, Param] = nk_mapY2Struct(mapY, Param, paramfl, inp)
% nk_mapY2Struct  Map and concatenate multi-modal data structures.
%
% Syntax:
%   [out, Param] = nk_mapY2Struct(mapY, Param, paramfl, inp)
%
% Description:
%   This function maps and optionally concatenates data structures from multiple modalities into a single multi-modal structure. 
%   It handles binary and multi-class data preprocessing and intermediate data fusion scenarios, with modality concatenation
%   activated based on specific flags.
%
% Inputs:
%   mapY    - Cell array containing data structures for each modality (1 x nModality). 
%             Each element of mapY contains fields like 'Tr' (training), 'CV' (cross-validation), 'Ts' (test), and 'VI' (variable importance).
%   Param   - Structure containing parameters for each modality and data type (1 x nModality).
%   paramfl - Cell array specifying pre-computed parameter options (1 x nModality). 
%             Contains subfields such as:
%           * 'PXopt' indicating optimized models' hyperparameters, 
%           * 'P' describing hyperparameter dimension of optimized data shelves.
%           * 'PXunique' describing the unique hyperparameter combination
%               in PXopt
%
%   inp     - Structure specifying input options for multi-class preprocessing, including 'nclass' for the number of classes.
%
% Outputs:
%   out     - Concatenated structure of multi-modal data. Fields include 'Tr', 'CV', 'Ts', and 'VI', with data combined across modalities.
%   Param   - Updated parameter structure reflecting the selected parameters after concatenation.
%
% Details:
%   - The function operates under various fusion flags (FUSION.flag) to determine the level of data concatenation.
%     0, 1, 3: No or limited fusion (data from individual modalities is retained separately).
%     2: Full multi-modal fusion, combining data across modalities into a single structure.
%   - Handles both binary and multi-class preprocessing scenarios, accommodating different data structures.
%   - Automatically identifies and removes columns in parameter matrices that contain only one value across all modalities.
%   - A bug related to intermediate data fusion was resolved on 14/10/2024.
%
% Example:
%   [out, Param] = nk_mapY2Struct(mapY, Param, paramfl, inp);
%
% Global Variables:
%   FUSION  - A global structure controlling the fusion behavior based on the fusion flag.
%
% Notes:
%   - Make sure that the structure of mapY and paramfl follows the expected format for the selected preprocessing type.
%   - Data is merged into a single matrix, ensuring consistency across modalities by matching parameter options.
%
% See also: cellmat_mergecols, cellmat_mergerows

global FUSION

switch FUSION.flag 
    
    case {0,1,3}
        
        out = mapY; 
        
    case 2 
        % Concatenate modality structure into single multi-modal structure
        % Major bug found in intermediate data fusion and resolved on
        % 14/10/2024.
        nvar    = numel(mapY);
        out     = mapY{1};
        
        if isfield(mapY{1},'Tr')

            for i=1:nvar

                if ~iscell(mapY{1}.Tr{1,1}{1})
                    t_nclass = 1;
                    multiproc = true;
                else
                    t_nclass = inp.nclass;
                    multiproc = false;
                end
    
                [iy,jy] = size(mapY{1}.Tr);
                if i==1
                    out.Tr = cell(iy,jy);
                    out.CV = cell(iy,jy);
                    out.Ts = cell(iy,jy);
                    out.VI = cell(iy,jy);
                    
                    if ~multiproc
                        for k=1:iy
                            for l=1:jy
                                out.Tr{k,l} = cell(t_nclass,1);
                                out.CV{k,l} = cell(t_nclass,1);
                                out.Ts{k,l} = cell(t_nclass,1);
                                out.VI{k,l} = cell(t_nclass,1);
                            end
                        end
                    end
                 end
            
                 fprintf('\nAdding data of modality #%g to single data matrix.',i);
                 for k=1:iy
                    for l=1:jy
                        for j=1:t_nclass
                            % in multi-class preprocessing we don't
                            % have a one-nested cell array as data
                            % container, e.g.
                            % mapY.Tr{CV1 perm, CV1 fold}{data shelves}
                            if multiproc
                                TR = mapY{i}.Tr{k,l};
                                CV = mapY{i}.CV{k,l};
                                TS = mapY{i}.Ts{k,l};
                                nZo = size(out.Tr{k,l},1);
                            else
                                % in binary preprocessing we have a
                                % two-nested cell arrays as data
                                % containers, e.g.:
                                % mapY.Tr{CV1 perm, CV1 fold}{binary classifier}{data shelves}
                                TR = mapY{i}.Tr{k,l}{j};
                                CV = mapY{i}.CV{k,l}{j};
                                TS = mapY{i}.Ts{k,l}{j};
                                nZo = size(out.Tr{k,l}{j},1);
                            end
                            % Create mixtures of data shelves if modality concatenation is activated
                            if isfield(paramfl{i},'PXfull') && ~isempty(paramfl{i}.PXopt{j})
                                cntPXopt = height(paramfl{i}.PXopt{j});
                                if i==1
                                    if multiproc
                                        out.Tr{k,l} = cell(cntPXopt,1);
                                        out.CV{k,l} = cell(cntPXopt,1);
                                        out.Ts{k,l} = cell(cntPXopt,1);
                                        out.VI{k,l} = cell(cntPXopt,1);
                                    else
                                        out.Tr{k,l}{j} = cell(cntPXopt,1);
                                        out.CV{k,l}{j} = cell(cntPXopt,1);
                                        out.Ts{k,l}{j} = cell(cntPXopt,1);
                                        out.VI{k,l}{j} = cell(cntPXopt,1);
                                    end
                                end
                                % Check if parameter columns consist only of one value
                                % and remove these columns
                                need_fill = ( ~isfield(paramfl{i},'P') ) ...
                                         || ( numel(paramfl{i}.P) < j ) ...
                                         || isempty(paramfl{i}.P{j}) ...
                                         || ~isfield(paramfl{i}.P{j},'opt') ...
                                         || isempty(paramfl{i}.P{j}.opt);
                                
                                if need_fill
                                    % Make P{j} a struct with an 'opt' field mirroring PXopt{j}
                                    paramfl{i}.P{j} = struct('opt', paramfl{i}.PXopt{j});
                                end
                                if width(paramfl{i}.P{j}.opt) ~= width(paramfl{i}.PXopt{j})
                                    % drop columns that are constant across all rows in PXopt{j}
                                    idx_rem = all(diff(paramfl{i}.PXopt{j}, 1, 1) == 0, 1);
                                    paramfl{i}.PXopt{j}(:, idx_rem) = [];
                                end
                                shelf_ind = find(ismember(paramfl{i}.P{j}.opt,paramfl{i}.PXopt{j},'rows'));
                                p_opt = paramfl{i}.P{j}.opt(shelf_ind,:);
                                cnt_p_opt = height(p_opt);
                                for zq = 1 : cnt_p_opt
                                    shelf_ind_zq = ismember(paramfl{i}.PXopt{j},p_opt(zq,:),'rows');
                                    if multiproc
                                        out.Tr{k,l}(shelf_ind_zq) = cellmat_mergecols(out.Tr{k,l}(shelf_ind_zq), repmat(TR(shelf_ind(zq)),numel(shelf_ind_zq),1) );
                                        out.CV{k,l}(shelf_ind_zq) = cellmat_mergecols(out.CV{k,l}(shelf_ind_zq), repmat(CV(shelf_ind(zq)),numel(shelf_ind_zq),1) );
                                        out.Ts{k,l}(shelf_ind_zq) = cellmat_mergecols(out.Ts{k,l}(shelf_ind_zq), repmat(TS(shelf_ind(zq)),numel(shelf_ind_zq),1) );
                                        out.VI{k,l}(shelf_ind_zq) = cellmat_mergerows(out.VI{k,l}(shelf_ind_zq), repmat({i*ones(size(TR{shelf_ind(zq)},2),1)},numel(shelf_ind_zq),1));

                                    else
                                        out.Tr{k,l}{j}(shelf_ind_zq) = cellmat_mergecols(out.Tr{k,l}{j}(shelf_ind_zq), repmat(TR(shelf_ind(zq)),numel(shelf_ind_zq),1) );
                                        out.CV{k,l}{j}(shelf_ind_zq) = cellmat_mergecols(out.CV{k,l}{j}(shelf_ind_zq), repmat(CV(shelf_ind(zq)),numel(shelf_ind_zq),1) );
                                        out.Ts{k,l}{j}(shelf_ind_zq) = cellmat_mergecols(out.Ts{k,l}{j}(shelf_ind_zq), repmat(TS(shelf_ind(zq)),numel(shelf_ind_zq),1) );
                                        out.VI{k,l}{j}(shelf_ind_zq) = cellmat_mergerows(out.VI{k,l}{j}(shelf_ind_zq), repmat({i*ones(size(TR{shelf_ind(zq)},2),1)},numel(shelf_ind_zq),1));
                                    end
                                end
                                Param{i}(k,l,j).data_ind = (1:cntPXopt)';
                            else
                                if i>1
                                    cnt = 1;
                                    nZp = size(TR,1);
                                    MixCount = nZo * nZp;
                                    tOut.Tr = cell(MixCount,1);
                                    tOut.CV = cell(MixCount,1);
                                    tOut.Ts = cell(MixCount,1);
                                    tOut.VI = cell(MixCount,1);
                                    for zp = 1:nZp
                                        for zo = 1:nZo
                                            if multiproc
                                                tOut.Tr{cnt} = [ out.Tr{k,l}{zo}, TR{zp} ];
                                                tOut.CV{cnt} = [ out.CV{k,l}{zo}, CV{zp} ];
                                                tOut.Ts{cnt} = [ out.Ts{k,l}{zo}, TS{zp} ];
                                                tOut.VI{cnt} = [ out.VI{k,l}{zo}; i*ones(size(TR{zp},2),1) ]; 
                                            else
                                                tOut.Tr{cnt} = [ out.Tr{k,l}{j}{zo}, TR{zp} ];
                                                tOut.CV{cnt} = [ out.CV{k,l}{j}{zo}, CV{zp} ];
                                                tOut.Ts{cnt} = [ out.Ts{k,l}{j}{zo}, TS{zp} ];
                                                tOut.VI{cnt} = [ out.VI{k,l}{j}{zo}; i*ones(size(TR{zp},2),1) ]; 
                                            end
                                            cnt = cnt+1;
                                        end
                                    end
                                    if multiproc
                                        out.Tr{k,l} = tOut.Tr;
                                        out.CV{k,l} = tOut.CV;
                                        out.Ts{k,l} = tOut.Ts;
                                        out.VI{k,l} = tOut.VI;
                                    else
                                        out.Tr{k,l}{j} = tOut.Tr;
                                        out.CV{k,l}{j} = tOut.CV;
                                        out.Ts{k,l}{j} = tOut.Ts;
                                        out.VI{k,l}{j} = tOut.VI;
                                    end
                                    clear tOut;
                                else
                                    if multiproc
                                        out.Tr{k,l} = TR;
                                        out.CV{k,l} = CV;
                                        out.Ts{k,l} = TS;
                                        for m=1:numel(TR)
                                            out.VI{k,l}{m} = ones(size(TR{m},2),1);
                                        end
                                    else
                                        out.Tr{k,l}{j} = TR;
                                        out.CV{k,l}{j} = CV;
                                        out.Ts{k,l}{j} = TS;
                                        for m=1:numel(TR)
                                            out.VI{k,l}{j}{m} = ones(size(TR{m},2),1);
                                        end
                                    end
                                end
                            end
                        end   
                    end
                 end
            end
        else
            for i=1:nvar
                if ~iscell(mapY{1}.Ts{1,1}{1})
                    t_nclass = 1;
                    multiproc = true;
                else
                    t_nclass = inp.nclass;
                    multiproc = false;
                end
                [iy,jy] = size(mapY{1}.Ts);
                if i==1
                    out.Ts = cell(iy,jy);
                    if ~multiproc, for k=1:iy, for l=1:jy, out.Ts{k,l} = cell(t_nclass,1); end; end; end
                end
                 fprintf('\nAdding OOCV data of modality #%g to single data matrix.',i);
                 for k=1:iy
                    for l=1:jy
                        for j=1:t_nclass
                            % in multi-class preprocessing we don't
                            % have a one-nested cell array as data
                            % container, e.g.
                            % mapY.Tr{CV1 perm, CV1 fold}{data shelves}
                            if multiproc
                                TS = mapY{i}.Ts{k,l};
                                nZo = size(out.Ts{k,l},1);
                            else
                                % in binary preprocessing we have a
                                % two-nested cell arrays as data
                                % containers, e.g.:
                                % mapY.Tr{CV1 perm, CV1 fold}{binary classifier}{data shelves}
                                TS = mapY{i}.Ts{k,l}{j};
                                nZo = size(out.Ts{k,l}{j},1);
                            end
                            % Create mixtures of data shelves if modality concatenation is activated
                            if isfield(paramfl{i},'PXfull') && ~isempty(paramfl{i}.PXopt{j})
                                cntPXopt = height(paramfl{i}.PXopt{j});
                                if i==1
                                    if multiproc, out.Ts{k,l} = cell(cntPXopt,1); else, out.Ts{k,l}{j} = cell(cntPXopt,1); end
                                end
                                % Check if parameter columns consist only one value
                                % and remove these columns
                                if width(paramfl{i}.P{j}.opt) ~= width(paramfl{i}.PXopt{j})
                                    idx_rem = all(diff(paramfl{i}.PXopt{j}) == 0, 1);
                                    paramfl{i}.PXopt{j}(:,idx_rem) = [];
                                end
                                shelf_ind = find(ismember(paramfl{i}.P{j}.opt,paramfl{i}.PXopt{j},'rows'));
                                p_opt = paramfl{i}.P{j}.opt(shelf_ind,:);
                                cnt_p_opt = height(p_opt);
                                for zq = 1 : cnt_p_opt
                                    shelf_ind_zq = ismember(paramfl{i}.PXopt{j},p_opt(zq,:),'rows');
                                    if multiproc
                                        out.Ts{k,l}(shelf_ind_zq) = cellmat_mergecols(out.Ts{k,l}(shelf_ind_zq), repmat(TS(shelf_ind(zq)),numel(shelf_ind_zq),1) );
                                    else
                                        out.Ts{k,l}{j}(shelf_ind_zq) = cellmat_mergecols(out.Ts{k,l}{j}(shelf_ind_zq), repmat(TS(shelf_ind(zq)),numel(shelf_ind_zq),1) );
                                    end
                                end
                            else
                                if i>1
                                    cnt = 1;
                                    nZp = size(TS,1);
                                    MixCount = nZo * nZp;
                                    tOut.Ts = cell(MixCount,1);
                                    for zp = 1:nZp
                                        for zo = 1:nZo
                                            if multiproc
                                                tOut.Ts{cnt} = [ out.Ts{k,l}{zo}, TS{zp} ];
                                            else
                                                tOut.Ts{cnt} = [ out.Ts{k,l}{j}{zo}, TS{zp} ];
                                            end
                                            cnt = cnt+1;
                                        end
                                    end
                                    if multiproc, out.Ts{k,l} = tOut.Ts; else, out.Ts{k,l}{j} = tOut.Ts; end
                                    clear tOut;
                                else
                                    if multiproc, out.Ts{k,l} = TS; else, out.Ts{k,l}{j} = TS; end
                                end
                            end
                        end   
                    end
                 end
            end
        end
end