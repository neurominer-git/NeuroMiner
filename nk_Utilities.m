function nk_Utilities
global CV NM

menustr = ['Set root paths of neuroimaging tools (SPM/Freesurfer)|' ...
           'Create PreprocData path master|' ...
           'Create CVdatamat path master|' ...
           'Create CVresults path master|' ...
           'Create VISdatamat path master|' ...
           'Create OptPreprocParam path master|' ...
           'Create OptModel path master|' ...
           'Update analyses'' paths to new root directory|' ...
           'Surface Reslicer (works only in Linux and requires Freesurfer)|' ...
           'Feature Relevance Plotting Tool|' ...
           'JuSpace resource manager'];
menuact = 2:12;

nk_PrintLogo
act = nk_input('Choose utility function',0,'mq', menustr, menuact, 1);
                 
switch act
    case 0
        return
    case 2
        neurominerpath = fileparts(which('neurominer.m'));
        imaging_init_path = fullfile(neurominerpath,'imaging_init.mat');
        nk_ImagingInit(neurominerpath, imaging_init_path, 1);
    case 3
        inp = []; inp = nk_GetAnalModalInfo_config(NM, inp);
        nk_GenPreprocMaster2(NM.id, CV(1), [], inp.rootdir, [], 1, inp.varind, inp.varstr, inp.concatfl);
    case 4
        inp = []; inp = nk_GetAnalModalInfo_config(NM, inp);
        nk_GenCVdataMaster2(NM.id, CV(1), [], inp.rootdir, [], 1, inp.varind, inp.varstr, inp.concatfl);
    case 5
        inp = []; inp = nk_GetAnalModalInfo_config(NM, inp);
        nk_GenCVresultsMaster(NM.id,[],inp.rootdir,[],1); 
    case 6
        inp = []; inp = nk_GetAnalModalInfo_config(NM, inp);
        nk_GenDataMaster(NM.id, 'VISdatamat', CV(1),[],inp.rootdir,[],1);
    case 7
        inp = []; inp = nk_GetAnalModalInfo_config(NM, inp);
        nk_GenDataMaster(NM.id, 'OptPreprocParam', CV(1),[],inp.rootdir,[],1);
    case 8
        inp = []; inp = nk_GetAnalModalInfo_config(NM, inp);
        nk_GenDataMaster(NM.id, 'OptModel', CV(1),[],inp.rootdir,[],1);
    case 9
        complvec = []; for z=1:numel(NM.analysis), if NM.analysis{z}.status, complvec = [ complvec z ]; end; end %#ok<AGROW>
        t_act = 1; brief = 1; analind = 1; showmodalvec = []; 
        while t_act>0 
            [t_act, analind, ~, showmodalvec , brief] = nk_SelectAnalysis(NM, 0, 'MAIN INTERFACE >> UPDATE ANALYSES ROOT DIRECTORIES ', analind, [], 0, showmodalvec, brief); 
        end
        if isempty(analind), analind = complvec; end
        newdir = nk_DirSelector('Update analyses'' root paths');
        NM = nk_UpdateRootPaths(NM, analind, newdir);
    case 10
        [P, Y] = nk_FSreslice();
        assignin('base','P',P);
        assignin('base','Y',Y);    
    case 11
        FeatureRelevanceGUI();
    case 12
        nk_JuSpaceResourceManager();
end

nk_Utilities

end

function nk_JuSpaceResourceManager()
% Centralized resource-management utility for JuSpace atlases and brain maps.
% The preprocessing configurator should only store paths and selections; this
% utility performs directory creation, downloads, and resource scans.

[rootDir, juSpaceRoot] = nk_JuSpaceRoot();
if isempty(rootDir)
    fprintf('\nCould not determine the NeuroMiner root directory. Add neurominer.m to the MATLAB path.\n');
    nk_input('Press any key to return',0,'sq');
    return
end

if ~exist(juSpaceRoot,'dir')
    fprintf('\nJuSpace directory does not yet exist: %s\n', juSpaceRoot);
end

menustr = ['Create/check JuSpace directory|' ...
           'Download atlases from JuSpace|' ...
           'Download or use brain maps from JuSpace|' ...
           'Download or use brain maps from neuromaps (Python)|' ...
           'Show JuSpace resource status|' ...
           'Back'];
act = nk_input('JuSpace resource manager',0,'mq',menustr,[1 2 3 4 5 0],1);

switch act
    case 0
        return
    case 1
        if ~exist(juSpaceRoot,'dir'), mkdir(juSpaceRoot); end
        dirs = {fullfile(juSpaceRoot,'Atlases'), fullfile(juSpaceRoot,'NT'), fullfile(juSpaceRoot,'NT','JuSpace'), fullfile(juSpaceRoot,'NT','neuromaps')};
        for i=1:numel(dirs), if ~exist(dirs{i},'dir'), mkdir(dirs{i}); end; end
        fprintf('\nJuSpace directory prepared: %s\n', juSpaceRoot);
    case 2
        if ~exist(juSpaceRoot,'dir'), mkdir(juSpaceRoot); end
        saveDir = nk_JuSpaceSelectDir('Select directory for saving JuSpace atlases', fullfile(juSpaceRoot,'Atlases'));
        if ~isempty(saveDir)
            AtlasDir = nk_JuSpaceDownloadAtlases(saveDir); %#ok<NASGU>
            fprintf('\nAtlas download/scan completed. Atlas directory: %s\n', saveDir);
        end
    case 3
        if ~exist(juSpaceRoot,'dir'), mkdir(juSpaceRoot); end
        useExisting = nk_input('Download new maps or use existing files?',0,'mq','Download from JuSpace|Use existing JuSpace directory',[0 1],0);
        if useExisting
            mapDir = nk_JuSpaceSelectDir('Select existing JuSpace brain maps directory', fullfile(juSpaceRoot,'NT','JuSpace'));
        else
            mapDir = nk_JuSpaceSelectDir('Select parent directory for saving JuSpace brain maps', juSpaceRoot);
        end
        if ~isempty(mapDir)
            M_NT = nk_JuSpaceDownloadSortImages(mapDir,'JuSpace',logical(useExisting)); %#ok<NASGU>
            outDir = mapDir;
            if ~logical(useExisting), outDir = fullfile(mapDir,'NT','JuSpace'); end
            save(fullfile(outDir,'NT_Table.mat'),'M_NT');
            fprintf('\nBrain-map resource table saved: %s\n', fullfile(outDir,'NT_Table.mat'));
        end
    case 4
        if ~exist(juSpaceRoot,'dir'), mkdir(juSpaceRoot); end
        py = pyenv;
        if isempty(py.Version)
            fprintf('\nPython is not configured in MATLAB. Configure pyenv before using neuromaps downloads.\n');
            nk_input('Press any key to return',0,'sq');
            return
        end
        useExisting = nk_input('Download new maps or use existing files?',0,'mq','Download from neuromaps|Use existing neuromaps directory',[0 1],0);
        if useExisting
            mapDir = nk_JuSpaceSelectDir('Select existing neuromaps brain maps directory', fullfile(juSpaceRoot,'NT','neuromaps'));
        else
            mapDir = nk_JuSpaceSelectDir('Select parent directory for saving neuromaps brain maps', juSpaceRoot);
        end
        if ~isempty(mapDir)
            M_NT = nk_JuSpaceDownloadSortImages(mapDir,'neuromaps',logical(useExisting)); %#ok<NASGU>
            outDir = mapDir;
            if ~logical(useExisting), outDir = fullfile(mapDir,'NT','neuromaps'); end
            save(fullfile(outDir,'NT_Table.mat'),'M_NT');
            fprintf('\nBrain-map resource table saved: %s\n', fullfile(outDir,'NT_Table.mat'));
        end
    case 5
        nk_JuSpacePrintStatus(juSpaceRoot);
end

nk_JuSpaceResourceManager();
end

function [rootDir, juSpaceRoot] = nk_JuSpaceRoot()
rootDir = '';
try
    p = which('neurominer.m');
    if ~isempty(p), rootDir = fileparts(p); end
catch
end
if isempty(rootDir)
    try
        p = which('nk_Utilities.m');
        if ~isempty(p), rootDir = fileparts(p); end
    catch
    end
end
if isempty(rootDir), juSpaceRoot = ''; else, juSpaceRoot = fullfile(rootDir,'JuSpace'); end
end

function d = nk_JuSpaceSelectDir(titleStr, defaultDir)
if nargin < 2 || isempty(defaultDir), defaultDir = pwd; end
if ~exist(defaultDir,'dir'), mkdir(defaultDir); end
if exist('spm_select','file') == 2
    d = spm_select(1,'dir',titleStr,{},defaultDir);
else
    d = uigetdir(defaultDir,titleStr);
    if isnumeric(d) && d == 0, d = ''; end
end
if iscell(d), d = d{1}; end
if isstring(d), d = char(d); end
end

function nk_JuSpacePrintStatus(juSpaceRoot)
fprintf('\nJuSpace root: %s\n', juSpaceRoot);
fprintf('  Exists: %d\n', exist(juSpaceRoot,'dir') == 7);
subdirs = {fullfile(juSpaceRoot,'Atlases'), fullfile(juSpaceRoot,'NT','JuSpace'), fullfile(juSpaceRoot,'NT','neuromaps')};
for i=1:numel(subdirs)
    d = subdirs{i};
    n = numel(dir(fullfile(d,'*.nii'))) + numel(dir(fullfile(d,'*.nii.gz')));
    fprintf('  %-60s %5d NIfTI files\n', d, n);
end
nk_input('Press any key to return',0,'sq');
end

function AtlasDir = nk_JuSpaceDownloadAtlases(SaveDirAtlas)
if ~exist(SaveDirAtlas,'dir'), mkdir(SaveDirAtlas); end
if exist('download_atlas_files','file') == 2
    AtlasDir = download_atlas_files(SaveDirAtlas);
    return
end

fprintf('\nNo download_atlas_files helper found. Trying direct JuSpace GitHub atlas download.\n');
repo_url = 'https://api.github.com/repos/juryxy/JuSpace';
opts = weboptions('ContentType','json','UserAgent','MATLAB');
repo_info = webread(repo_url, opts);
branch = repo_info.default_branch;
tree_url = sprintf('https://api.github.com/repos/juryxy/JuSpace/git/trees/%s?recursive=1', branch);
tree_info = webread(tree_url, opts);
AtlasDir = SaveDirAtlas;
if ~isfield(tree_info,'tree') || isempty(tree_info.tree)
    warning('Could not read JuSpace GitHub tree. Please download atlases manually.');
    return
end
n = 0;
for i=1:numel(tree_info.tree)
    item = tree_info.tree(i);
    if ~isfield(item,'type') || ~strcmp(item.type,'blob') || ~isfield(item,'path'), continue; end
    pth = item.path; low = lower(pth);
    if ~(endsWith(low,'.nii') || endsWith(low,'.nii.gz')), continue; end
    if ~contains(low,'atlas') || contains(low,'petatlas'), continue; end
    url = sprintf('https://raw.githubusercontent.com/juryxy/JuSpace/%s/%s', branch, pth);
    [~,name,ext] = fileparts(pth);
    if endsWith(lower(pth),'.nii.gz')
        [~,name2] = fileparts(name); name = [name2 '.nii']; ext = '.gz';
    end
    websave(fullfile(SaveDirAtlas,[name ext]), url);
    n = n + 1;
end
fprintf('Downloaded %d atlas image(s) to %s\n', n, SaveDirAtlas);
end

function M_NT = nk_JuSpaceDownloadSortImages(NTDir,software,UseExistingFlag)
if nargin < 3 || isempty(UseExistingFlag), UseExistingFlag = false; end
software = char(software);

if strcmpi(software,'neuromaps')
    GOOGLE_SHEET_ID = '1oZecOsvtQEh5pQkIf8cB6CyhPKVrQuko';
    SHEET_GID = '1162991686';
    csv_url = ['https://docs.google.com/spreadsheets/d/',GOOGLE_SHEET_ID,'/export?format=csv&gid=',SHEET_GID];

    M_NT = [];
    attempt = 0; delayBetweenAttempts = 10; success = false;
    while attempt < 11 && ~success
        try
            M_NT = readtable(csv_url); success = true;
        catch
            attempt = attempt + 1; pause(delayBetweenAttempts);
        end
        if attempt == 10 && isempty(M_NT), disp('Could not load neuromaps table.'); end
    end

    if ~UseExistingFlag
        scriptPath = which('download_images_neuromaps.py');
        if isempty(scriptPath), error('download_images_neuromaps.py was not found on the MATLAB/Python path.'); end
        pyrunfile(scriptPath,'data_dir',NTDir);
        aa = dir(fullfile(NTDir,'NT','neuromaps','**','*.nii.gz'));
        NTfiles = fullfile({aa.folder}',{aa.name}');
        if ~isempty(NTfiles)
            gunzip(NTfiles);
            NTfiles = extractBefore(NTfiles,'.gz');
            for i = 1:length(NTfiles)
                copyfile(NTfiles{i}, fullfile(NTDir,'NT','neuromaps'));
            end
            annDir = fullfile(NTDir,'NT','neuromaps','annotations');
            if exist(annDir,'dir'), rmdir(annDir,'s'); end
        end
        aa = dir(fullfile(NTDir,'NT','neuromaps','*.nii'));
    else
        aa = dir(fullfile(NTDir,'*.nii'));
        if isempty(aa), error('No neuromap image files were found in this directory: %s', NTDir); end
    end

    if size(M_NT,1) > 0
        ind_NT_MNI = contains(M_NT.tags,'PET') & contains(M_NT.annotation,'MNI');
        M_NT = M_NT(ind_NT_MNI,:);
        NT_fileparts = extractBetween(M_NT.annotation,'(', ')');
        NT_fileparts_split = cellfun(@(x) split(x, ','), NT_fileparts, 'UniformOutput', false);
        NT_fileparts_reshaped = cellfun(@(x) reshape(x, 1, []), NT_fileparts_split, 'UniformOutput', false);
        NT_fileparts_flat = strtrim(strrep(vertcat(NT_fileparts_reshaped{:}), '''', ''));
        NTfiles_docs = strcat('source-',NT_fileparts_flat(:,1),'_desc-',NT_fileparts_flat(:,2),'_space-',NT_fileparts_flat(:,3),'_res-',NT_fileparts_flat(:,4),'_feature.nii');
        if UseExistingFlag, ind_available = ismember(NTfiles_docs,{aa.name}');
        else,               ind_available = ismember(NTfiles_docs,{aa.name}'); end
        M_NT = M_NT(ind_available,:);
        M_NT.filenames = NTfiles_docs(ind_available,1);
        M_NT.NT = repmat({''},size(M_NT,1),1);
        ind_GABA = contains(M_NT.description, 'GABA') & ~contains(M_NT.description,' to ');
        M_NT.NT(ind_GABA,1) = {'GABA'};
        M_NT.NT(~ind_GABA,1) = extractBetween(M_NT.description(~ind_GABA,1),'to ',' (');
        M_NT.tracer = NT_fileparts_flat(ind_available,2);
        M_NT.source = NT_fileparts_flat(ind_available,1);
        M_NT.N = extractBefore(M_NT.N_males_,' (');
    else
        M_NT = [];
    end

elseif strcmpi(software,'JuSpace')
    if ~UseExistingFlag
        repo_url = 'https://api.github.com/repos/juryxy/JuSpace';
        opts = weboptions('ContentType','json','UserAgent','MATLAB');
        repo_info = webread(repo_url, opts);
        branch = repo_info.default_branch;
        api_url_start = 'https://api.github.com/repos/juryxy/JuSpace/contents';
        data_start = webread(api_url_start);
        ind_dir = strcmp({data_start.type}','dir');
        dir_name = data_start(ind_dir).name;
        api_url = ['https://api.github.com/repos/juryxy/JuSpace/contents/',dir_name,'/PETatlas?ref=',branch];
        data = webread(api_url);
        NT_folder = fullfile(NTDir,'NT','JuSpace'); if ~exist(NT_folder, 'dir'), mkdir(NT_folder); end
        for i = 1:length(data)
            if strcmp(data(i).type, 'file')
                file_name = data(i).name;
                download_url = data(i).download_url;
                local_file = fullfile(NT_folder, file_name);
                websave(local_file, download_url);
                fprintf('Downloaded: %s\n', file_name);
            else
                fprintf('Error: Unable to fetch folder contents. Please download manually from JuSpace GitHub: %s\n', data(i).name);
            end
        end
        aa = dir(fullfile(NT_folder,'*.nii'));
    else
        aa = dir(fullfile(NTDir,'*.nii'));
        if isempty(aa), error('No JuSpace image files were found in this directory: %s', NTDir); end
    end
    M_NT = nk_JuSpaceExtractFilePartsMultiple({aa.name}');
else
    error('Unknown JuSpace resource source: %s', software);
end
end

function M = nk_JuSpaceExtractFilePartsMultiple(filenames)
M = struct('NT', {}, 'tracer', {}, 'N', {}, 'source', {}, 'file', {}, 'filenames', {});
for j = 1:length(filenames)
    [~, fileWithoutExtension, ext] = fileparts(filenames{j});
    if strcmpi(ext,'.gz')
        [~, fileWithoutExtension] = fileparts(fileWithoutExtension);
    end
    parts = regexp(fileWithoutExtension, '_', 'split');
    fileParts.NT = 'NA'; fileParts.tracer = 'NA'; fileParts.N = 'NA'; fileParts.source = 'NA';
    if length(parts) >= 1, fileParts.NT = parts{1}; end
    if length(parts) >= 2, fileParts.tracer = parts{2}; end
    if length(parts) >= 3
        low3 = lower(parts{3});
        idx = regexp(low3,'h?c(\d*)','tokens','once');
        if ~isempty(idx) && ~isempty(idx{1}), fileParts.N = idx{1}; else, fileParts.N = 'NA'; end
    end
    if length(parts) >= 4, fileParts.source = parts{4}; end
    fileParts.file = [fileWithoutExtension '.nii'];
    fileParts.filenames = fileParts.file;
    M(end+1,1) = fileParts; %#ok<AGROW>
end
M = struct2table(M);
end
