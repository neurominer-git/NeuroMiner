classdef NMDataIOCodeExportTools
% NMDataIOCodeExportTools
% -------------------------------------------------------------------------
% Export committed browser DataIO provenance to a flat MATLAB function that
% re-runs the corresponding public NMDataIOAPITools import calls.  The
% generated function loads bulky or fragile import specifications from a MAT
% sidecar and does not assign directly into NM data fields.
% -------------------------------------------------------------------------

    methods (Static)
        function out = writeImportFunction(NM, outputDir, opts)
            % writeImportFunction  Export committed DataIO provenance as a public API recipe.
            %
            %   out = NMDataIOCodeExportTools.writeImportFunction(NM,outputDir,opts)
            %   writes one MATLAB function plus a MAT sidecar that replays the
            %   committed training import through NMDataIOAPITools. It does not
            %   assign directly into NM.Y, NM.cases or NM.datadescriptor.
            %
            %   opts.ModalityIndex: scalar training-modality index or ''all''; empty also exports all committed training modalities.
            %   out contains paths, function name, modality indices and warnings.

            if nargin < 3 || isempty(opts), opts = struct(); end
            if nargin < 2 || isempty(outputDir)
                error('NMDataIOCodeExportTools:missingOutputDir', 'An output directory is required for DataIO API recipe export.');
            end
            outputDir = char(string(outputDir));
            if ~exist(outputDir, 'dir')
                [ok,msg] = mkdir(outputDir);
                if ~ok
                    error('NMDataIOCodeExportTools:mkdirFailed', 'Could not create DataIO recipe output directory %s. %s', outputDir, msg);
                end
            end

            modalityIndex = NMDataIOCodeExportTools.getOpt(opts, 'ModalityIndex', []);
            exportAll = isempty(modalityIndex) || (ischar(modalityIndex) && strcmpi(strtrim(modalityIndex), 'all')) || ...
                (isstring(modalityIndex) && isscalar(modalityIndex) && strcmpi(strtrim(char(modalityIndex)), 'all'));
            indices = NMDataIOCodeExportTools.resolveTrainingIndices(NM, modalityIndex, exportAll);
            if isempty(indices)
                error('NMDataIOCodeExportTools:noModalities', 'No completed training modalities are available. Import and Commit at least one training modality before exporting an import recipe.');
            end

            [recipes, warnings] = NMDataIOCodeExportTools.recipesFromNM(NM, indices, exportAll);
            stamp = datestr(now, 'yyyymmdd_HHMMSS');
            if exportAll
                baseName = ['nm_dataio_full_import_' stamp];
            else
                baseName = sprintf('nm_dataio_modality_%02d_import_%s', indices(1), stamp);
            end
            functionName = matlab.lang.makeValidName(baseName);
            sidecarName = [functionName '_sidecar.mat'];
            functionFile = fullfile(outputDir, [functionName '.m']);
            sidecarFile = fullfile(outputDir, sidecarName);

            recipe = struct();
            recipe.schemaVersion = 1;
            recipe.createdBy = 'NMDataIOCodeExportTools';
            recipe.generatedAt = datestr(now, 30);
            recipe.scope = 'training';
            recipe.exportAll = exportAll;
            recipe.modalityIndices = indices;
            recipe.modalities = recipes;
            recipe.importSpecs = {recipes.spec};
            recipe.apiFunctions = {recipes.apiFunction};
            recipe.warnings = warnings;
            save(sidecarFile, 'recipe', '-v7');

            code = NMDataIOCodeExportTools.functionCode(functionName, sidecarName, recipes);
            fid = fopen(functionFile, 'w');
            if fid < 0
                error('NMDataIOCodeExportTools:writeFailed', 'Could not write generated DataIO API import function: %s', functionFile);
            end
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, '%s', code);

            out = struct('ok', true, 'functionFile', functionFile, 'sidecarFile', sidecarFile, ...
                'functionName', functionName, 'nModalities', numel(recipes), 'modalityIndices', indices, ...
                'warnings', {warnings}, 'message', sprintf('Exported DataIO API recipe function for %d modality/modalities.', numel(recipes)));
        end

        function tf = canExportModality(NM, varind)
            % canExportModality  Test whether a committed training modality has exportable DataIO provenance.
            %
            %   tf = NMDataIOCodeExportTools.canExportModality(NM,varind)
            %   returns true when recipe extraction succeeds for the selected
            %   modality. The method is read-only and suppresses extraction
            %   errors into a logical result for UI enable/disable logic.

            tf = false;
            try
                NMDataIOCodeExportTools.recipeFromNM(NM, varind, false);
                tf = true;
            catch
                tf = false;
            end
        end
    end

    methods (Static, Access = private)
        function indices = resolveTrainingIndices(NM, modalityIndex, exportAll)
            n = 0;
            if isstruct(NM) && isfield(NM,'datadescriptor') && iscell(NM.datadescriptor)
                n = numel(NM.datadescriptor);
            elseif isstruct(NM) && isfield(NM,'Y') && iscell(NM.Y)
                n = numel(NM.Y);
            end
            if exportAll
                indices = 1:n;
            else
                if isempty(modalityIndex) || ~isnumeric(modalityIndex) || ~isscalar(modalityIndex) || ~isfinite(double(modalityIndex))
                    error('NMDataIOCodeExportTools:badModalityIndex', 'A valid scalar modality index is required for selected-modality recipe export.');
                end
                indices = max(1, round(double(modalityIndex)));
                if indices > n
                    error('NMDataIOCodeExportTools:badModalityIndex', 'Modality %d is outside the available training modality range 1..%d.', indices, n);
                end
            end
        end

        function [recipes, warnings] = recipesFromNM(NM, indices, exportAll)
            warnings = {};
            recipes = repmat(NMDataIOCodeExportTools.emptyRecipe(), 1, 0);
            for i = 1:numel(indices)
                try
                    r = NMDataIOCodeExportTools.recipeFromNM(NM, indices(i), exportAll);
                    recipes(end+1) = r; %#ok<AGROW>
                    warnings = [warnings, r.warnings]; %#ok<AGROW>
                catch ME
                    if exportAll
                        error('NMDataIOCodeExportTools:fullExportFailed', 'Cannot export full DataIO API recipe. Modality %d is not exportable: %s', indices(i), ME.message);
                    else
                        rethrow(ME);
                    end
                end
            end
        end

        function r = emptyRecipe()
            r = struct('modalityIndex', NaN, 'description', '', 'sourceFamily', '', ...
                'apiFunction', '', 'apiLabel', '', 'spec', struct(), 'warnings', {{}});
        end

        function r = recipeFromNM(NM, varind, exportAll)
            if nargin < 3, exportAll = false; end
            r = NMDataIOCodeExportTools.emptyRecipe();
            if ~isstruct(NM) || ~isfield(NM,'datadescriptor') || numel(NM.datadescriptor) < varind || ...
                    ~isstruct(NM.datadescriptor{varind})
                error('NMDataIOCodeExportTools:missingDescriptor', 'Modality %d has no saved import information.', varind);
            end
            dd = NM.datadescriptor{varind};
            if ~isfield(dd,'input_settings') || ~isstruct(dd.input_settings)
                error('NMDataIOCodeExportTools:missingInputSettings', 'Modality %d has no saved import settings that can be exported.', varind, varind);
            end
            input = dd.input_settings;
            if NMDataIOCodeExportTools.isIncompleteInputSettings(input)
                error('NMDataIOCodeExportTools:incompleteInputSettings', 'Modality %d is incomplete. Finish the import and Commit it before exporting an import recipe.', varind);
            end
            if ~exportAll && NMDataIOCodeExportTools.isROISplitInput(input)
                error('NMDataIOCodeExportTools:roiSplitSelectedExport', ['Modality %d appears to originate from an ROI-split image import. ', ...
                    'Export the full import recipe instead; a selected atlas-split output may not contain all settings needed to reproduce the original import.'], varind);
            end

            sourceFamily = NMDataIOCodeExportTools.inferSourceFamily(dd, input);
            spec = NMDataIOCodeExportTools.specFromInput(input, sourceFamily);
            spec.varind = varind;
            if ~isfield(spec,'scope') || isempty(spec.scope), spec.scope = 'training'; end
            if ~isfield(spec,'targetMode') || isempty(spec.targetMode), spec.targetMode = 'add'; end
            if ~isfield(spec,'finalizeTrainingImport') || isempty(spec.finalizeTrainingImport), spec.finalizeTrainingImport = false; end

            r.modalityIndex = varind;
            r.description = NMDataIOCodeExportTools.asChar(NMDataIOCodeExportTools.fieldOr(input, 'desc_data', NMDataIOCodeExportTools.fieldOr(dd, 'desc', sprintf('Modality %d', varind))));
            r.sourceFamily = sourceFamily;
            r.spec = spec;
            switch sourceFamily
                case 'connectivity'
                    r.apiFunction = 'importTrainingConnectivity';
                    r.apiLabel = 'connectivity training import';
                case 'image'
                    r.apiFunction = 'importTrainingImages';
                    if isfield(spec,'datasource') && strcmpi(char(string(spec.datasource)), 'surf')
                        r.apiLabel = 'surface training import';
                    else
                        r.apiLabel = 'image training import';
                    end
                otherwise
                    r.apiFunction = 'importTrainingMatrix';
                    r.apiLabel = 'matrix/table training import';
            end
            r.warnings = NMDataIOCodeExportTools.recipeWarnings(input, sourceFamily, varind, exportAll);
        end

        function tf = isIncompleteInputSettings(input)
            tf = false;
            if isfield(input,'incomplete') && isequal(input.incomplete, true), tf = true; return; end
            if isfield(input,'status') && any(strcmpi(char(string(input.status)), {'incomplete','draft'})), tf = true; return; end
            if isfield(input,'draftDirty') && isequal(input.draftDirty, true), tf = true; return; end
        end

        function tf = isROISplitInput(input)
            tf = false;
            if isfield(input,'spaceDefType') && strcmpi(char(string(input.spaceDefType)), 'atlas') && ...
                    isfield(input,'atlasImportMode') && any(strcmpi(char(string(input.atlasImportMode)), {'split','roi_split'}))
                tf = true;
            end
        end

        function sourceFamily = inferSourceFamily(dd, input)
            srcFam = lower(strtrim(NMDataIOCodeExportTools.asChar(NMDataIOCodeExportTools.fieldOr(input, 'sourceFamily', ''))));
            srcType = lower(strtrim(NMDataIOCodeExportTools.asChar(NMDataIOCodeExportTools.fieldOr(input, 'sourceType', ''))));
            datasource = lower(strtrim(NMDataIOCodeExportTools.asChar(NMDataIOCodeExportTools.fieldOr(input, 'datasource', ''))));
            ddSource = lower(strtrim(NMDataIOCodeExportTools.asChar(NMDataIOCodeExportTools.fieldOr(dd, 'source', ''))));
            if strcmp(srcFam,'connectivity') || strcmp(srcType,'connectivity') || isfield(input,'connectivitySpec') || strcmp(ddSource,'connectivity')
                sourceFamily = 'connectivity';
            elseif any(strcmp(datasource, {'nifti','spm','image','surf'})) || any(strcmp(srcType, {'image-list','surface-list'})) || ...
                    (isfield(input,'groupmode') && isequal(double(input.groupmode), -2)) || isfield(input,'imageFiles') || isfield(input,'spaceDefType')
                sourceFamily = 'image';
            else
                sourceFamily = 'matrix';
            end
        end

        function spec = specFromInput(input, sourceFamily)
            switch sourceFamily
                case 'connectivity'
                    if isfield(input,'connectivitySpec') && isstruct(input.connectivitySpec)
                        spec = input.connectivitySpec;
                    else
                        spec = input;
                    end
                    spec.sourceType = 'connectivity';
                case 'image'
                    spec = input;
                    if ~isfield(spec,'datasource') || isempty(spec.datasource)
                        spec.datasource = 'nifti';
                    end
                otherwise
                    spec = input;
                    if ~isfield(spec,'sourceType') || isempty(spec.sourceType)
                        spec.sourceType = NMDataIOCodeExportTools.asChar(NMDataIOCodeExportTools.fieldOr(input, 'sourceType', 'workspace'));
                    end
            end
            spec = NMDataIOCodeExportTools.stripReportOnlyFields(spec);
            if isfield(spec,'databaseConnector') || isfield(spec,'databaseUrl') || isfield(spec,'databaseFile')
                dbInfo = NMDataIODatabaseTools.connectionInfo(spec); % Reject legacy credential-bearing connection strings before recipe export. Normalize connector hierarchy afterward.
                spec.databaseConnector = dbInfo.connector;
                spec.databaseUrl = dbInfo.url;
                spec.databaseFile = dbInfo.file;
                spec.databaseUser = dbInfo.user;
                spec.databaseName = dbInfo.database;
                spec.databaseSchema = dbInfo.schema;
                spec.databaseTable = dbInfo.table;
                spec.databaseUseQuery = dbInfo.useQuery;
                spec.databaseQuery = dbInfo.query;
            end
        end

        function S = stripReportOnlyFields(S)
            if ~isstruct(S), return; end
            fields = {'modalityInfo','featureStats','importReport','externalDataInfo','connectivityProvenance','atlasInfo','atlasCollapseProvenance', ...
                'databasePassword','password','passwd'};
            for k = 1:numel(fields)
                if isfield(S, fields{k}), S = rmfield(S, fields{k}); end
            end
        end

        function warnings = recipeWarnings(input, sourceFamily, varind, exportAll)
            warnings = {};
            if strcmp(sourceFamily,'matrix')
                src = lower(strtrim(NMDataIOCodeExportTools.asChar(NMDataIOCodeExportTools.fieldOr(input,'sourceType',''))));
                if any(strcmp(src, {'workspace','variable'}))
                    warnings{end+1} = sprintf('Modality %d uses workspace-variable style matrix settings; the generated function requires the same variables to be resolvable by the DataIO API at runtime or the spec to be edited.', varind); %#ok<AGROW>
                elseif strcmp(src,'database')
                    warnings{end+1} = sprintf('Modality %d database credentials are intentionally excluded from exported recipes; provide databasePassword only as a transient runtime API field when the connector requires authentication.', varind); %#ok<AGROW>
                end
            end
            if NMDataIOCodeExportTools.isROISplitInput(input) && exportAll
                warnings{end+1} = sprintf('Modality %d was exported as part of a full ROI-split modality-space recipe. Use the full exported function rather than selected-modality fragments for this import.', varind); %#ok<AGROW>
            end
        end

        function code = functionCode(functionName, sidecarName, recipes)
            lines = {};
            lines{end+1} = sprintf('function [NM, report] = %s(NM)', functionName);
            lines{end+1} = sprintf('%%%s Import NeuroMiner data using DataIO API calls.', upper(functionName));
            lines{end+1} = '%';
            lines{end+1} = '% Each section loads the corresponding import specification from the';
            lines{end+1} = '% sidecar MAT file and executes the matching NMDataIOAPITools call.';
            lines{end+1} = 'if nargin < 1 || isempty(NM), NM = struct(); end';
            lines{end+1} = 'report = struct();';
            lines{end+1} = 'thisFile = mfilename(''fullpath'');';
            lines{end+1} = sprintf('sidecarFile = fullfile(fileparts(thisFile), ''%s'');', sidecarName);
            lines{end+1} = 'S = load(sidecarFile, ''recipe'');';
            lines{end+1} = 'recipe = S.recipe;';
            lines{end+1} = 'report.sidecarFile = sidecarFile;';
            lines{end+1} = 'report.recipe = rmfield(recipe, ''importSpecs'');';
            lines{end+1} = '';
            for k = 1:numel(recipes)
                r = recipes(k);
                lines{end+1} = sprintf('%% Modality %d: %s.', r.modalityIndex, r.apiLabel);
                switch r.apiFunction
                    case 'importTrainingImages'
                        lines{end+1} = '% Defines the image or surface source files, case matching, labels, covariates, and spatial settings.';
                    case 'importTrainingConnectivity'
                        lines{end+1} = '% Defines the connectivity matrices, node/edge metadata, case matching, labels, and edge-space settings.';
                    otherwise
                        lines{end+1} = '% Defines the matrix/table source, case matching, feature names, labels, and covariates.';
                end
                lines{end+1} = sprintf('spec = recipe.importSpecs{%d};', k);
                lines{end+1} = sprintf('spec.varind = %d;', r.modalityIndex);
                lines{end+1} = 'spec.finalizeTrainingImport = false;';
                lines{end+1} = sprintf('[NM, report.modality(%d)] = NMDataIOAPITools.%s(NM, spec);', k, r.apiFunction);
                lines{end+1} = sprintf('if ~isstruct(report.modality(%d)) || ~isfield(report.modality(%d), ''ok'') || ~isequal(report.modality(%d).ok, true)', k, k, k);
                lines{end+1} = '    msg = ''DataIO API import failed.'';';
                lines{end+1} = sprintf('    if isstruct(report.modality(%d)) && isfield(report.modality(%d), ''message'') && ~isempty(report.modality(%d).message)', k, k, k);
                lines{end+1} = sprintf('        msg = report.modality(%d).message;', k);
                lines{end+1} = '    end';
                lines{end+1} = sprintf('    error(''NMDataIORecipe:importFailed'', ''Modality %d %s: %%s'', msg);', r.modalityIndex, r.apiLabel);
                lines{end+1} = 'end';
                lines{end+1} = '';
            end
            lines{end+1} = 'end';
            code = strjoin(lines, newline);
            code = char(code);
        end

        function v = getOpt(opts, name, defaultValue)
            if nargin < 3, defaultValue = []; end
            if isstruct(opts) && isfield(opts,name) && ~isempty(opts.(name))
                v = opts.(name);
            else
                v = defaultValue;
            end
        end

        function v = fieldOr(S, name, defaultValue)
            if isstruct(S) && isfield(S,name) && ~isempty(S.(name))
                v = S.(name);
            else
                v = defaultValue;
            end
        end

        function c = asChar(v)
            if isempty(v), c = ''; return; end
            if ischar(v), c = v; return; end
            if isstring(v), c = char(v(1)); return; end
            if isnumeric(v) || islogical(v), c = char(string(v(1))); return; end
            c = char(string(v));
        end
    end
end
