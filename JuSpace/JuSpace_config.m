function [JUSPACE, act, menuact, menustr] = JuSpace_config(JUSPACE, brainmask, Thresh, parentstr, act, returnmenu)

if ~exist('parentstr','var') || isempty(parentstr), parentstr = 'Neuromaps co-localization'; end
if ~exist('returnmenu','var') || isempty(returnmenu), returnmenu = false; end

Atlas = []; AtlasDir = []; AtlasNames = [];
M_NT = []; YAtlas = []; CorType = 1; AutoCorCorrect = 1;
NTList = []; NTNames = []; NTDir = []; NTind = [];
YNT = []; TPMpath = []; YTPM = [];
importflag = false; completeflag = false;

if isfield(JUSPACE,'Atlas') && ~isempty(JUSPACE.Atlas),           Atlas = JUSPACE.Atlas; end
if isfield(JUSPACE,'YAtlas') && ~isempty(JUSPACE.YAtlas),         YAtlas = JUSPACE.YAtlas; end
if isfield(JUSPACE,'AtlasNames') && ~isempty(JUSPACE.AtlasNames), AtlasNames = JUSPACE.AtlasNames; end
if isfield(JUSPACE,'AtlasDir') && ~isempty(JUSPACE.AtlasDir),     AtlasDir = JUSPACE.AtlasDir; end
if isfield(JUSPACE,'NT_Table') && ~isempty(JUSPACE.NT_Table),     M_NT = JUSPACE.NT_Table; end
if isfield(JUSPACE,'cortype') && ~isempty(JUSPACE.cortype),       CorType = JUSPACE.cortype; end
if isfield(JUSPACE,'autocorcorrect') && ~isempty(JUSPACE.autocorcorrect), AutoCorCorrect = JUSPACE.autocorcorrect; end
if isfield(JUSPACE,'NTDir') && ~isempty(JUSPACE.NTDir),           NTDir = JUSPACE.NTDir; end
if isfield(JUSPACE,'NTList') && ~isempty(JUSPACE.NTList),         NTList = JUSPACE.NTList; end
if isfield(JUSPACE,'NTind') && ~isempty(JUSPACE.NTind),           NTind = JUSPACE.NTind; end
if isfield(JUSPACE,'NTNames') && ~isempty(JUSPACE.NTNames),       NTNames = JUSPACE.NTNames; end
if isfield(JUSPACE,'YNT') && ~isempty(JUSPACE.YNT),               YNT = JUSPACE.YNT; end
if isfield(JUSPACE,'TPMpath') && ~isempty(JUSPACE.TPMpath)
    TPMpath = JUSPACE.TPMpath;
end
if isfield(JUSPACE,'YTPM') && ~isempty(JUSPACE.YTPM),             YTPM = JUSPACE.YTPM; end
if isfield(JUSPACE,'brainmask') && ~isempty(JUSPACE.brainmask),   brainmask = JUSPACE.brainmask; end
if isfield(JUSPACE,'Thresh') && ~isempty(JUSPACE.Thresh),         Thresh = JUSPACE.Thresh; end
if isfield(JUSPACE,'importflag') && ~isempty(JUSPACE.importflag), importflag = JUSPACE.importflag; end
if isfield(JUSPACE,'completeflag') && ~isempty(JUSPACE.completeflag), completeflag = JUSPACE.completeflag; end

if ~isempty(Atlas)
    AtlasDef = 1;
    if size(Atlas,1) > 1
        for i = 1:size(Atlas,1)
            if i == 1, ATLASSTR = Atlas(i,:);
            else,       ATLASSTR = sprintf('%s, %s', ATLASSTR, Atlas(i,:));
            end
        end
    else
        ATLASSTR = Atlas;
    end
else
    AtlasDef = 2; ATLASSTR = 'not defined';
end

% Correlation type
if ~isempty(CorType)
    switch CorType
        case 1, CORTYPESTR = 'Spearman correlation';
        case 2, CORTYPESTR = 'Pearson correlation';
    end
    CORTYPEDef = 1;
else
    CORTYPESTR = 'not defined'; CORTYPEDef = 2;
end

% Autocorrelation correction (+ ensure TPM when yes)
if ~isempty(AutoCorCorrect)
    if AutoCorCorrect == 1
        AUTOCORCORRECTSTR = 'yes';
        if isempty(TPMpath)
            spm_path = extractBefore(which('SPM'),[filesep,'spm.m']);
            TPMpath  = fullfile(spm_path,'tpm','TPM.nii,1');
        end
    else
        AUTOCORCORRECTSTR = 'no';
        TPMpath = '';
    end
    AutoCorDef = 1;
else
    AUTOCORCORRECTSTR = 'not defined'; AutoCorDef = 2;
end

% NT directory
if ~isempty(NTDir), NTDirDef = 1; NTDIRSTR = NTDir;
else,               NTDirDef = 2; NTDIRSTR = 'not defined';
end

% NT list
if ~isempty(NTList)
    NTLISTSTR = NTList{1}.id;
    for i = 2:numel(NTList), NTLISTSTR = sprintf('%s, %s', NTLISTSTR, NTList{i}.id); end
    NTListDef = 1;
else
    NTLISTSTR = 'No neuromap selected'; NTListDef = 2;
end

% Pretty NT name list (optional)
if ~isempty(NTList) && ~isempty(NTNames)
    if ischar(NTNames)
        NTLISTNAME = NTNames;
    else
        NTLISTNAME = NTNames{1};
        for i=2:numel(NTNames), NTLISTNAME = sprintf('%s, %s', NTLISTNAME, NTNames{i}); end
    end
else
    NTLISTNAME = NTLISTSTR;
end

% Atlas names for "Alternative atlas name"
if ~isempty(Atlas)
    if ~isempty(AtlasNames)
        ATLASLISTSTR = AtlasNames{1};
        for i=2:numel(AtlasNames), ATLASLISTSTR = sprintf('%s, %s', ATLASLISTSTR, AtlasNames{i}); end
    else
        [~, names, ~] = cellfun(@fileparts, cellstr(Atlas), 'UniformOutput', false);
        ATLASLISTSTR = names{1};
        for i=2:numel(names), ATLASLISTSTR = sprintf('%s, %s', ATLASLISTSTR, names{i}); end
    end
end

disallow = ~(AtlasDef==1 && NTDirDef==1 && NTListDef==1 && CORTYPEDef==1 && AutoCorDef==1);

python_available = pyenv;

if ~isempty(python_available.Version)
    menustr = ['Download atlases from JuSpace                                              |' ...
               'Download or use existing neuromaps from JuSpace or neuromaps   |' ...
               'Atlas                                                                       [' ATLASSTR ']|' ...
               'Correlation type                                                            [' CORTYPESTR ']|' ...
               'Adjust for spatial autocorrelations                                         [' AUTOCORCORRECTSTR ']|' ...
               'Neuromaps directory                                             [' NTDIRSTR ']|'];
else
    menustr = ['Download atlases from JuSpace                                  |' ...
               'Download or use existing neuromaps from JuSpace    |' ...
               'Atlas                                                           [' ATLASSTR ']|' ...
               'Correlation type                                                [' CORTYPESTR ']|' ...
               'Adjust for spatial autocorrelations                             [' AUTOCORCORRECTSTR ']|' ...
               'Neuromaps directory                                 [' NTDIRSTR ']|'];
end

menuact = [1 2 3 5 6 7];

if AtlasDef == 1
    mn = sprintf('Alternative atlas name                                    [%s]', ATLASLISTSTR);
    parts = strsplit(menustr,'|');
    parts = [parts(1:3), {mn}, parts(4:end)];
    menustr = strjoin(parts,'|');
    menuact  = [menuact(1:3) 4 menuact(4:end)];
end

if NTDirDef == 1
    menustr = [menustr sprintf('Neuromaps selection                                [%s]|', NTLISTSTR)];
    menuact = [menuact 8];
end

if NTListDef == 1
    menustr = [menustr sprintf('Alternative neuromap names                         [%s]|', NTLISTNAME)];
    menuact = [menuact 9];
end

if ~disallow
    menustr = [menustr '|Import neuromaps and atlas'];
    menuact = [menuact 10];
end

if ~returnmenu
    nk_PrintLogo
    if ~disallow
        fprintf('\n'); mestr = 'Neuromaps co-localization setup';
        navistr = [parentstr ' >>> ' mestr];
        fprintf('\nYou are here: %s >>> ',parentstr);
        act = char(nk_input(mestr,0,'mq', menustr, menuact));
        completeflag = true;
    else
        mestr = 'Neuromaps co-localization step setup';
        navistr = [parentstr ' >>> ' mestr];
        fprintf('\nYou are here: %s >>> ',parentstr);
        act = nk_input(mestr,0,'mq', menustr, menuact);
    end
end

switch act
    case 1 % Download atlases (JuSpace)
        AtlasDownloadFlag = nk_input('Do you want to download atlas files from JuSpace?',0,'yes|no',[1,0],1);
        if AtlasDownloadFlag
            SPMAVAIL = logical(exist('spm_select','file'));
            if SPMAVAIL, SaveDirAtlas = spm_select(1,'dir','Select directory for saving atlases');
            else,        SaveDirAtlas = uigetdir(pwd,'Select directory for saving atlases'); end
            AtlasDir = download_atlas_files(SaveDirAtlas);          % your existing helper
        else
            AtlasDir = [];
        end

    case 2 % Download/use NT maps (JuSpace or neuromaps)
        if ~isempty(python_available.Version)
            NTDownloadFlag = nk_input('Do you want to download or use existing neuromaps from JuSpace or neuromaps?',0,'mq',...
                ['Download from JuSpace (MATLAB-based toolbox)|',...
                 'Download from neuromaps (Python-based toolbox, provides more neuromaps)|',...
                 'Use existing from JuSpace (MATLAB-based toolbox)|',...
                 'Use existing from neuromaps (Python-based toolbox, provides more neuromaps)'], 1:4, 0);
            if     NTDownloadFlag == 1, JuSpaceDownloadFlag = 1; UseExistingFlag = 0; neuromapsDownloadFlag = 0;
            elseif NTDownloadFlag == 2, neuromapsDownloadFlag = 1; UseExistingFlag = 0; JuSpaceDownloadFlag = 0;
            elseif NTDownloadFlag == 3, JuSpaceDownloadFlag = 1; UseExistingFlag = 1; neuromapsDownloadFlag = 0;
            elseif NTDownloadFlag == 4, neuromapsDownloadFlag = 1; UseExistingFlag = 1; JuSpaceDownloadFlag = 0;
            else,  JuSpaceDownloadFlag = 0; neuromapsDownloadFlag = 0; UseExistingFlag = 0;
            end
        else
            neuromapsDownloadFlag = 0;
            J = nk_input('Do you want to download or use existing neuromaps from JuSpace?',0,'mq',...
                ['Download from JuSpace (MATLAB-based)|','Use existing from JuSpace (MATLAB-based)'],1:2, 0);
            JuSpaceDownloadFlag = any(J == [1,2]); UseExistingFlag = (J == 2);
        end

        SPMAVAIL = logical(exist('spm_select','file'));
        if (JuSpaceDownloadFlag || neuromapsDownloadFlag) && ~UseExistingFlag
            if SPMAVAIL, SaveDir = spm_select(1,'dir','Select directory for saving neuromaps');
            else,        SaveDir = uigetdir(pwd,'Select directory for saving neuromaps'); end
        elseif UseExistingFlag && (JuSpaceDownloadFlag || neuromapsDownloadFlag)
            if SPMAVAIL, SaveDir = spm_select(1,'dir','Select existing neuromaps directory');
            else,        SaveDir = uigetdir(pwd,'Select existing neuromaps directory'); end
        end

        if JuSpaceDownloadFlag
            M_NT = download_sort_images(SaveDir,'JuSpace',UseExistingFlag);
            if ~UseExistingFlag, NTDir = fullfile(SaveDir,'NT','JuSpace'); else, NTDir = SaveDir; end
        elseif neuromapsDownloadFlag
            M_NT = download_sort_images(SaveDir,'neuromaps',UseExistingFlag);
            if ~UseExistingFlag, NTDir = fullfile(SaveDir,'NT','neuromaps'); else, NTDir = SaveDir; end
        end

    case 3 % Select atlas (+ optional precompute later)
        hdrstr = 'Select atlas';
        if isempty(AtlasDir)
            Atlas = nk_FileSelector(Inf, 'nifti', hdrstr, '.*\.nii$', [], pwd);
        else
            Atlas = nk_FileSelector(Inf, 'nifti', hdrstr, '.*\.nii$', [], AtlasDir);
        end

    case 4 % Alternative atlas name(s)
        AtlasNames = nk_input('Provide alternative name[s] for atlas[es]',0,'e',[],[size(Atlas,1),1]);

    case 5 % Correlation type
        CorType = nk_input('Define the correlation type', 0, 'mq', ...
            ['Spearman correlation |','Pearson correlation'], 1:2, 0);

    case 6 % Autocorrelation correction
        AutoCorCorrect = nk_input('Adjust for spatial correlations',0,'mq', ['Yes |','No'], 1:2, 0);
        if AutoCorCorrect == 1
            spm_path = extractBefore(which('SPM'),[filesep,'spm.m']);
            TPMpath  = fullfile(spm_path,'tpm','TPM.nii,1');
        else
            TPMpath = '';
        end

    case 7 % NT maps directory
        hdrstr = 'Select neuromaps directory';
        SPMAVAIL = logical(exist('spm_select','file'));
        if SPMAVAIL, NTDir = spm_select(1,'dir',hdrstr);
        else,        NTDir = uigetdir(pwd,hdrstr); end
        NTind = []; NTList = []; NTNames = [];

    case 8 % NT selection
        [NTind,NTList] = print_NTmaps_quickselector(M_NT,NTDir);

    case 9 % Alternative neurotransmitter name(s)
        NTNames = nk_input('Provide alternative names for neuromaps',0,'e',[],[numel(NTList),1]);

    case 10 % Import atlas/NT (+TPM)
        disp('Importing atlas and neuromap data.');

        % Precompute YAtlas
        V_brainmask = spm_vol(char(brainmask));
        VAtlas = spm_vol(Atlas);
        YAtlas = [];
        for i = 1:size(VAtlas,1)
            YAtlas(i,:) = nk_ReturnSubSpaces_JuSpace(VAtlas(i), V_brainmask, 1, 1, Thresh, 0);
        end

        % TPM (if autocor == yes)
        if AutoCorCorrect == 1
            VTPM  = spm_vol(char(TPMpath));
            YTPM  = nk_ReturnSubSpaces_JuSpace(VTPM, V_brainmask, 1, 1, Thresh, 1);
        else
            YTPM = [];
        end

        % NT maps
        NTFiles = cellfun(@(x) x.file, NTList(1, 1:size(NTList,2)), 'UniformOutput', false)';
        VNT = spm_vol(char(fullfile(NTDir,NTFiles)));
        YNT = [];
        for i = 1:size(VNT,1)
            YNT(i,:) = nk_ReturnSubSpaces_JuSpace(VNT(i), V_brainmask, 1, 1, Thresh, 0);
        end
        importflag = true; completeflag = true;
end

JUSPACE.Atlas          = Atlas;
JUSPACE.AtlasDir       = AtlasDir;
JUSPACE.AtlasNames     = AtlasNames;
JUSPACE.NT_Table       = M_NT;
JUSPACE.YAtlas         = YAtlas;
JUSPACE.NTDir          = NTDir;
JUSPACE.NTind          = NTind;
JUSPACE.NTList         = NTList;
JUSPACE.NTNames        = NTNames;
JUSPACE.YNT            = YNT;
JUSPACE.cortype        = CorType;
JUSPACE.autocorcorrect = AutoCorCorrect;
JUSPACE.TPMpath        = TPMpath;
JUSPACE.YTPM           = YTPM;
JUSPACE.importflag     = importflag;
JUSPACE.completeflag   = completeflag;

end

function M_NT = download_sort_images(NTDir,software,UseExistingFlag)    

    if strcmp(software,'neuromaps')
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
            if attempt == 10 && isempty(M_NT), disp('Could not load table.'); end
        end
    
        if ~UseExistingFlag
            pyrunfile('download_images_neuromaps.py','data_dir',NTDir);
            aa = dir(fullfile(NTDir,'NT','neuromaps','**','*.nii.gz'));
            NTfiles = fullfile({aa.folder}',{aa.name}');
            if ~isempty(NTfiles)
                gunzip(NTfiles);
                NTfiles = extractBefore(NTfiles,'.gz');
                for i = 1:length(NTfiles)
                    copyfile(NTfiles{i}, fullfile(NTDir,'NT','neuromaps'));
                end
                rmdir(fullfile(NTDir,'NT','neuromaps','annotations'),'s');
            end
        else
            aa = dir(fullfile(NTDir,'*.nii'));
            if ~isempty(aa)
                NTfiles = fullfile({aa.folder}',{aa.name}');
            else
                error('No neuromap image files were found in this directory: %s', NTDir);
            end
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
            else,               ind_available = ismember(NTfiles_docs,extractBefore({aa.name}','.gz')); end
    
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
    
    elseif strcmp(software,'JuSpace')
    
        if ~UseExistingFlag
            fprintf('Preparing to download image files...\n');
        else
            fprintf('Gathering file information...\n');
        end
    
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
            NTfiles = fullfile({aa.folder}',{aa.name}');
        else
            aa = dir(fullfile(NTDir,'*.nii'));
            if ~isempty(aa)
                NTfiles = fullfile({aa.folder}',{aa.name}');
            else
                error(['No neuromap image files were found in this directory: %s'], NTDir);
            end
        end
    
        M_NT = extractFilePartsMultiple({aa.name}');
    end
end

function M = extractFilePartsMultiple(filenames)
    M = struct('NT', {}, 'tracer', {}, 'N', {}, 'source', {}, 'file', {});
    for j = 1:length(filenames)
        [~, fileWithoutExtension, ~] = fileparts(filenames{j});
        parts = regexp(fileWithoutExtension, '_', 'split');
        fileParts.NT = 'NA'; fileParts.tracer = 'NA'; fileParts.N = 'NA'; fileParts.source = 'NA';
        if length(parts) >= 1, fileParts.NT = parts{1}; end
        if length(parts) >= 2, fileParts.tracer = parts{2}; end
        if length(parts) >= 3
            if contains(parts{3},caseInsensitivePattern('hc'))
                part3 = extractAfter(parts{3},caseInsensitivePattern('hc')); if isempty(part3), part3 = extractBefore(parts{3},caseInsensitivePattern('hc')); end
            elseif contains(parts{3},caseInsensitivePattern('c'))
                part3 = extractAfter(parts{3},caseInsensitivePattern('c'));
            else
                part3 = 'NA';
            end
            fileParts.N = part3;
        end
        if length(parts) >= 4, fileParts.source = parts{4}; end
        fileParts.file = [fileWithoutExtension '.nii'];
        M(end+1,1) = fileParts;
    end
    M = struct2table(M);
end


function [NTind,neurotransmitterSel] = print_NTmaps_quickselector(M_NT,NTDir)

nk_PrintLogo
fprintf('\n\t'); fprintf('============================================= ');
fprintf('\n\t'); fprintf('***        Neuromap Selector        *** ');
fprintf('\n\t'); fprintf('============================================= ');

if isempty(M_NT) && ~isempty(NTDir)
    aa = dir(fullfile(NTDir,'*.nii'));
    NTFiles = {aa.name}';
    NTNames = extractBefore({aa.name}','.nii');

    if ~isempty(NTFiles)       
        for i = 1:size(NTFiles,1)
            neurotransmitter{i}.id = char(NTNames{i});
            neurotransmitter{i}.listidx = i;
            neurotransmitter{i}.file = NTFiles{i};
        end
    
        for i=1:numel(neurotransmitter)
            fprintf('\n\t** [ %2g ]: NT : %s', i, neurotransmitter{i}.id);
        end
        fprintf('\n');
        NTind = nk_input('Type sequence of neuromaps to include (1d-vector)',0,'e');
    
        zeroIDX = NTind == 0; 
        NTind = NTind(~zeroIDX);
        greaterIDX = NTind > numel(neurotransmitter); 
        NTind = NTind(~greaterIDX);
        
        neurotransmitterSel = [];
        for i = 1:numel(NTind)
            neurotransmitterSel{i}.id = neurotransmitter{NTind(i)}.id;
            neurotransmitterSel{i}.listidx = neurotransmitter{NTind(i)}.listidx;
            neurotransmitterSel{i}.file = neurotransmitter{NTind(i)}.file;
            NTnames{i} = neurotransmitter{NTind(i)}.id;
        end
    else
        fprintf(['\n\nWARNING: The directory ',NTDir,' does not contain any neuromaps.\n        n Please select the folder directly including the images.']);
        nk_input('Press any key to return',0,'sq')
        NTind = [];
        neurotransmitterSel = [];
    end
elseif ~isempty(M_NT)
    for i = 1:size(M_NT,1)
        neurotransmitter{i}.NT = char(M_NT.NT{i});
        neurotransmitter{i}.Tracer = char(M_NT.tracer{i});
        neurotransmitter{i}.N = char(M_NT.N{i});
        neurotransmitter{i}.Source = char(M_NT.source{i});
        neurotransmitter{i}.listidx = i;
        neurotransmitter{i}.file = M_NT.filenames{i};
    end

    for i = 1:numel(neurotransmitter)
        fprintf('\n\t** [ %2g ]: NT: %-10s Tracer: %-20s N: %-5s Source: %s', ...
            i, neurotransmitter{i}.NT, neurotransmitter{i}.Tracer, neurotransmitter{i}.N, neurotransmitter{i}.Source);
    end
    fprintf('\n');
    NTind = nk_input('Type sequence of neuromaps to include (1d-vector)',0,'e');

    % remove invalid numbers
    zeroIDX = NTind == 0; 
    NTind = NTind(~zeroIDX);
    greaterIDX = NTind > numel(neurotransmitter); 
    NTind = NTind(~greaterIDX);
    
    neurotransmitterSel = [];
    for i = 1:numel(NTind)
        neurotransmitterSel{i}.id = neurotransmitter{NTind(i)}.NT;
        neurotransmitterSel{i}.listidx = neurotransmitter{NTind(i)}.listidx;
        neurotransmitterSel{i}.file = neurotransmitter{NTind(i)}.file;
        NTnames{i} = neurotransmitter{NTind(i)}.NT;
    end
end

end
