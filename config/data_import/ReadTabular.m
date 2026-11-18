function [IO, mess] = ReadTabular(IO, fileflg, mess)

if ~exist('mess','var'), mess=[];end

switch fileflg
    case 1
        IO.Y = evalin('base',IO.M_edit);
        if istable(IO.Y)
            mess = GenerateMessageEntry(mess, sprintf('ERROR during data import: Workspace feature variable ''%s'' is a MATLAB table. Use the MATLAB table variable source instead.', IO.M_edit));
            return
        end
        if isfield(IO,'col_edit') && ~strcmp(IO.col_edit,'?')
            IO.s_featnames = evalin('base',IO.col_edit);
            if isa(IO.s_featnames,'string') || ischar(IO.s_featnames)
                IO.s_featnames = cellstr(IO.s_featnames);
            end
            if ~iscell(IO.s_featnames) || ~all(cellfun(@(x) ischar(x) || isa(x,'string'), IO.s_featnames(:)))
                mess = GenerateMessageEntry(mess, sprintf('ERROR during data import: Feature-name variable ''%s'' must be a cell array, string array, or char array.', IO.col_edit));
                return
            end
            IO.s_featnames = cellfun(@char, IO.s_featnames(:)', 'UniformOutput', false);
        elseif isfield(IO,'requireFeatureNames') && IO.requireFeatureNames
            mess = GenerateMessageEntry(mess, 'ERROR during data import: Workspace-variable import requires an assigned feature-name variable.');
            return
        else
            IO.s_featnames = arrayfun(@(j) sprintf('F%g',j), 1:size(IO.Y,2), 'UniformOutput', false);
        end
        IO.s_ID = evalin('base',IO.case_edit);
        if ~isfield(IO,'oocvflag') || ~IO.oocvflag || IO.labels_known
            IO.s_label = evalin('base',IO.label_edit);
        end
        if isfield(IO,'covar_edit') && ~isempty(IO.covar_edit)
            covars = [];
            for c=1:numel(IO.covar_edit)
                cv = evalin('base',IO.covar_edit{c});
                if istable(cv), cv = table2array(cv); end
                if ~(isnumeric(cv) || islogical(cv))
                    mess = GenerateMessageEntry(mess, sprintf('ERROR during data import: Covariate variable ''%s'' must be numeric. Found class ''%s''.', IO.covar_edit{c}, class(cv)));
                    return
                end
                covars = [covars double(cv)]; %#ok<AGROW>
            end
            if isfield(IO,'covnames_edit') && ~strcmp(IO.covnames_edit,'?')
                covnames = evalin('base', IO.covnames_edit);
                if isa(covnames,'string') || ischar(covnames)
                    covnames = cellstr(covnames);
                end
                if ~iscell(covnames) || ~all(cellfun(@(x) ischar(x) || isa(x,'string'), covnames(:)))
                    mess = GenerateMessageEntry(mess, sprintf('ERROR during data import: Covariate-name variable ''%s'' must be a cell array, string array, or char array.', IO.covnames_edit));
                    return
                end
                covnames = cellfun(@char, covnames(:)', 'UniformOutput', false);
                if numel(covnames) ~= size(covars,2)
                    mess = GenerateMessageEntry(mess, sprintf('ERROR during data import: Covariate-name variable ''%s'' contains %g name(s), but %g covariate column(s) were assigned.', IO.covnames_edit, numel(covnames), size(covars,2)));
                    return
                end
            elseif isfield(IO,'requireCovariateNames') && IO.requireCovariateNames
                mess = GenerateMessageEntry(mess, 'ERROR during data import: Workspace-variable import with covariates requires an assigned covariate-name variable.');
                return
            else
                covnames = {};
                for c=1:numel(IO.covar_edit)
                    cv = evalin('base',IO.covar_edit{c});
                    if istable(cv), cv = table2array(cv); end
                    if size(cv,2) == 1
                        covnames = [covnames IO.covar_edit(c)]; %#ok<AGROW>
                    else
                        covnames = [covnames arrayfun(@(j) sprintf('%s_%g', IO.covar_edit{c}, j), 1:size(cv,2), 'UniformOutput', false)]; %#ok<AGROW>
                    end
                end
            end
            IO.covars = covars; IO.covnames = covnames;
        end
    case 2
        load(IO.M_edit);
        IO.Y = eval(IO.matrix_edit);
        if istable(IO.Y)
            mess = GenerateMessageEntry(mess, sprintf('ERROR during data import: MAT-file feature variable ''%s'' is a MATLAB table. Use the MATLAB table variable source after loading the table into the workspace.', IO.matrix_edit));
            return
        end
        if isfield(IO,'col_edit') && ~strcmp(IO.col_edit,'?')
            IO.s_featnames = eval(IO.col_edit);
            if isa(IO.s_featnames,'string') || ischar(IO.s_featnames)
                IO.s_featnames = cellstr(IO.s_featnames);
            end
            if ~iscell(IO.s_featnames) || ~all(cellfun(@(x) ischar(x) || isa(x,'string'), IO.s_featnames(:)))
                mess = GenerateMessageEntry(mess, sprintf('ERROR during data import: Feature-name variable ''%s'' must be a cell array, string array, or char array.', IO.col_edit));
                return
            end
            IO.s_featnames = cellfun(@char, IO.s_featnames(:)', 'UniformOutput', false);
        elseif isfield(IO,'requireFeatureNames') && IO.requireFeatureNames
            mess = GenerateMessageEntry(mess, 'ERROR during data import: MAT-file import requires an assigned feature-name variable.');
            return
        else
            IO.s_featnames = arrayfun(@(j) sprintf('F%g',j), 1:size(IO.Y,2), 'UniformOutput', false);
        end
        IO.s_ID = eval(IO.case_edit);
        if ~isfield(IO,'oocvflag') || ~IO.oocvflag || IO.labels_known
            IO.s_label = eval(IO.label_edit);
        end
        if isfield(IO,'covar_edit') && ~isempty(IO.covar_edit)
            covars = [];
            for c=1:numel(IO.covar_edit)
                cv = eval(IO.covar_edit{c});
                if istable(cv), cv = table2array(cv); end
                if ~(isnumeric(cv) || islogical(cv))
                    mess = GenerateMessageEntry(mess, sprintf('ERROR during data import: Covariate variable ''%s'' must be numeric. Found class ''%s''.', IO.covar_edit{c}, class(cv)));
                    return
                end
                covars = [covars double(cv)]; %#ok<AGROW>
            end
            if isfield(IO,'covnames_edit') && ~strcmp(IO.covnames_edit,'?')
                covnames = eval(IO.covnames_edit);
                if isa(covnames,'string') || ischar(covnames)
                    covnames = cellstr(covnames);
                end
                if ~iscell(covnames) || ~all(cellfun(@(x) ischar(x) || isa(x,'string'), covnames(:)))
                    mess = GenerateMessageEntry(mess, sprintf('ERROR during data import: Covariate-name variable ''%s'' must be a cell array, string array, or char array.', IO.covnames_edit));
                    return
                end
                covnames = cellfun(@char, covnames(:)', 'UniformOutput', false);
                if numel(covnames) ~= size(covars,2)
                    mess = GenerateMessageEntry(mess, sprintf('ERROR during data import: Covariate-name variable ''%s'' contains %g name(s), but %g covariate column(s) were assigned.', IO.covnames_edit, numel(covnames), size(covars,2)));
                    return
                end
            elseif isfield(IO,'requireCovariateNames') && IO.requireCovariateNames
                mess = GenerateMessageEntry(mess, 'ERROR during data import: MAT-file import with covariates requires an assigned covariate-name variable.');
                return
            else
                covnames = {};
                for c=1:numel(IO.covar_edit)
                    cv = eval(IO.covar_edit{c});
                    if istable(cv), cv = table2array(cv); end
                    if size(cv,2) == 1
                        covnames = [covnames IO.covar_edit(c)]; %#ok<AGROW>
                    else
                        covnames = [covnames arrayfun(@(j) sprintf('%s_%g', IO.covar_edit{c}, j), 1:size(cv,2), 'UniformOutput', false)]; %#ok<AGROW>
                    end
                end
            end
            IO.covars = covars; IO.covnames = covnames;
        end
    case {3,4,5}
        if (exist('NMDataIOTableReadTools','class') == 8 || exist('NMDataIOTableReadTools','file') == 2) && ...
                (isfield(IO,'headerRow') || isfield(IO,'headerAutoDetect'))
            IO.Y = NMDataIOTableReadTools.readTableFromIO(IO);
        else
            switch fileflg
                case 3
                    delimRead = IO.delimit;
                    if ischar(delimRead) || isa(delimRead,'string')
                        switch lower(strtrim(char(delimRead)))
                            case {'tab','\\t'}
                                delimRead = sprintf('\t');
                            case {'comma'}
                                delimRead = ',';
                            case {'semicolon'}
                                delimRead = ';';
                            case {'space'}
                                delimRead = ' ';
                        end
                    end
                    IO.Y = readtable(IO.M_edit, 'FileType', 'text', 'Delimiter', delimRead);
                case 4
                    IO.Y = readtable(IO.M_edit, 'Sheet', IO.sheet);
                case 5
                    IO.Y = evalin('base', char(IO.M_edit));
                    if ~istable(IO.Y)
                        mess = GenerateMessageEntry(mess, sprintf('ERROR during data import: Workspace variable ''%s'' is not a MATLAB table.', IO.M_edit));
                        return
                    end
            end
        end
        if exist('NMDataIOTableRoleTools','class') == 8 || exist('NMDataIOTableRoleTools','file') == 2
            [IO, featureTable, mess] = NMDataIOTableRoleTools.prepareReadTabular(IO, IO.Y, mess);
            if exist('CheckReadyStatus','file') == 2 && CheckReadyStatus(mess)
                return
            end
            [~,IO.cellcols, IO.cellcolsinfo] = nk_ScopeCellRetDummyFromTable('scope', featureTable);
            if isfield(IO,'cellcols') && any(IO.cellcols)
                featureTable = nk_ScopeCellRetDummyFromTable('replace', featureTable, IO.uniquelim);
            end
            IO.s_featnames = featureTable.Properties.VariableNames;
            IO.featnames = IO.s_featnames;
            IO.Y = table2array(featureTable);
        else
            IO.s_featnames = IO.Y.Properties.VariableNames;
            col_cases = strcmp(IO.s_featnames,IO.case_edit);
            col_label = RetCellInCellsIndex(IO.s_featnames, IO.label_edit);
            if isnumeric(IO.Y{:,col_cases})
                IO.s_ID = cellstr(num2str(IO.Y{:,col_cases}));
            else
                IO.s_ID = table2cell(IO.Y(:,col_cases));
            end
            if ~isfield(IO,'oocvflag') || ~IO.oocvflag || IO.labels_known
                IO.s_label = table2array(IO.Y(:,col_label));
            end
            if isfield(IO,'feature_edit') && ~isempty(IO.feature_edit)
                col_feature = RetCellInCellsIndex(IO.s_featnames, IO.feature_edit);
            else
                col_feature = ~(col_cases | col_label);
            end
            col_cov = false(size(IO.s_featnames));
            if isfield(IO,'covar_edit') && ~isempty(IO.covar_edit)
                col_cov = RetCellInCellsIndex(IO.s_featnames, IO.covar_edit);
                if any(col_cov)
                    IO.covars = table2array(IO.Y(:, col_cov));
                    IO.covnames = IO.s_featnames(col_cov);
                end
            end
            if isfield(IO,'ignore_edit') && ~isempty(IO.ignore_edit)
                col_ignore = RetCellInCellsIndex(IO.s_featnames, IO.ignore_edit);
            else
                col_ignore = false(size(IO.s_featnames));
            end
            keep_cols = col_feature & ~(col_cases | col_label | col_ignore | col_cov);
            IO.Y = IO.Y(:, keep_cols); 
            [~,IO.cellcols, IO.cellcolsinfo] = nk_ScopeCellRetDummyFromTable('scope', IO.Y);
            if isfield(IO,'cellcols') && any(IO.cellcols)
                IO.Y = nk_ScopeCellRetDummyFromTable('replace',IO.Y, IO.uniquelim);
                col_cases = strcmp(IO.Y.Properties.VariableNames, IO.case_edit);
                col_label = RetCellInCellsIndex(IO.Y.Properties.VariableNames, IO.label_edit);
                IO.s_featnames = IO.Y.Properties.VariableNames;
            end
            IO.s_featnames = IO.Y.Properties.VariableNames;
            IO.Y = table2array(IO.Y);
        end
end

if strcmp(IO.modeflag,'classification') && isfield(IO,'s_label') && (isnumeric(IO.s_label) || islogical(IO.s_label))
    if size(IO.s_label,2) > 1
        mess = GenerateMessageEntry(mess, 'ERROR during data import: Numeric classification labels must be a vector, not a multi-column matrix.');
        return
    end
    num_label = double(IO.s_label(:));
    IO.s_label = arrayfun(@(x) sprintf('%g', x), num_label, 'UniformOutput', false);
    IO.s_label(~isfinite(num_label)) = {''};
end

% Check format of ID variable
if sum(cellfun(@isnumeric,IO.s_ID)) == numel(IO.s_ID)
    IO.s_ID = cellfun(@num2str,IO.s_ID,'UniformOutput',0);
    mess = GenerateMessageEntry(mess, '* Convert IDs: numbers => strings.',0,'blue');
end
if sum(cellfun(@ischar,IO.s_ID)) ~= numel(IO.s_ID)
    mess = GenerateMessageEntry(mess, 'ERROR during data import: The ID variable should contain only alpha(numeric) strings or numbers.');
    return 
end

% Check whether previous feature names exists and make sure that the order
% of features in the new modality matches the order of features in previous modalities
if isfield(IO,'oocvflag') && IO.oocvflag && isfield(IO,'featnames')
    if ~isfield(IO,'feat_reordered') || ~IO.feat_reordered
        ind = zeros(1,numel(IO.featnames)); flg = false;
        for i=1:numel(IO.featnames)
            ii = strcmp(IO.s_featnames,IO.featnames{i});
            if ~any(ii)
                mess = GenerateMessageEntry(mess, 'Error during import of new matrix-based modality data.\n\tCould not find feature ''%s'' among the features of the new modality!');
                flg = true;
                continue;
            end
            ind(i) = find(ii);
        end
        if flg, return; end
        if ~isequal(ind,1:numel(IO.featnames))
            IO.Y = IO.Y(:,ind);
            IO.features_reordered = ind;
            mess = GenerateMessageEntry(mess, sprintf('Data (%s) reordered during import to match previous feature order!',IO.desc_data), 0, 'blue'); 
        end
    end
else
    IO.featnames = IO.s_featnames;
end

% Check whether previous label exists and make sure that the order of cases
% in the new modality matches the order of cases in previous modalities

if isfield(IO,'ID') 
    ind = zeros(numel(IO.ID),1); flg = false; 
    for i=1:numel(IO.ID)
        ii = find(strcmp(IO.s_ID,IO.ID{i}));
        if ~any(ii)
            mess = GenerateMessageEntry(mess, sprintf('Error during import of new matrix-based modality data. Could not find case ''%s'' in the IDs of the new modality!',IO.ID{i}));
            flg = true;
            continue
        elseif numel(ii)>1
            mess = GenerateMessageEntry(mess, sprintf('Error during import of new matrix-based modality data. Found %g instances of case ''%s'' in the IDs of the new modality!', numel(ii), IO.ID{i}));
            flg = true; 
            continue
        end
        ind(i) = ii; 
    end
    if flg, return; end
    if ~isequal(ind,1:numel(IO.ID))
        IO.Y = IO.Y(uint16(ind),:);
        if isfield(IO,'covars') && ~isempty(IO.covars), IO.covars = IO.covars(uint16(ind),:); end
        IO.cases_reordered=ind;
        IO.ID = IO.s_ID(ind);
        mess = GenerateMessageEntry(mess, sprintf('Data (%s) reordered during import to match previous case order!',IO.desc_data),0,'blue'); 
    end

else
    IO.ID = IO.s_ID;
    if ~isfield(IO,'oocvflag') || ~IO.oocvflag || IO.labels_known
        switch IO.modeflag
            case 'classification'           
                nL = size(IO.s_label,2);
                IO.label = nan(size(IO.s_label));     
                if iscell(IO.s_label)
                    IO.nonnan_label = ~(isnanincell(IO.s_label) | strcmp(IO.s_label,'') | cellfun(@isempty,IO.s_label));
                else
                    IO.nonnan_label = ~isnan(IO.s_label);
                end
                if nL>1
                    IO.n_subjects = cell(nL,1);
                else
                    IO.n_subjects = zeros(1,numel(unique(IO.s_label(IO.nonnan_label),'stable'))); 
                end
                
                tdesc_groups = IO.desc_groups;
                for j=1:nL
                    if isfield(IO, 'oocvflag') && IO.oocvflag && IO.labels_known
                        desc_groups = IO.desc_groups; 
                    else
                        desc_groups = unique(IO.s_label(IO.nonnan_label(:,j),j),'stable');
                    end
                    IO.n_samples(j) = numel(desc_groups);
                    if nL>1
                        IO.desc_groups{j} = desc_groups;
                    else
                        IO.desc_groups = desc_groups;
                    end
                    for i=1:numel(tdesc_groups)
                        if isfield(IO,'selCases') && ~isempty(IO.selCases)
                            selCases = IO.selCases;
                        else
                            selCases = true(size(IO.s_label,1),1);
                        end
                        ind = strcmp(IO.s_label(:,j),tdesc_groups{i}) & selCases;
                        IO.label(ind,j) = i;
                        if nL>1
                            IO.n_subjects{j}(i) = sum(ind); 
                        else
                            IO.n_subjects(i) = sum(ind); 
                        end
                    end
                end
            case 'regression'
                IO.desc_labels = IO.label_edit;
                if isfield(IO,'selCases') && ~isempty(IO.selCases)
                    selCases = IO.selCases;
                else
                    selCases = true(size(IO.s_label,1),1);
                end
                IO.label = IO.s_label(selCases,:);
                IO.n_subjects = size(IO.label,1);
        end
    end
end

IO.n_subjects_all = sum(IO.n_subjects);