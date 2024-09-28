function [ SPATIAL, PX ] = nk_Spatial_config(SPATIAL, PX, defaultsfl, parentstr,brainmask)
% Compute spatial consistency of discriminative effects

if ~exist('defaultsfl','var') || isempty(defaultsfl),  defaultsfl = 0; end;
if ~exist('PX','var'), PX =  []; end;
cubetype    = 1;
cubefwhm    = 8;
cubevoxres  = 3;

if ~defaultsfl
   
    if ~isempty(SPATIAL) && isfield(SPATIAL,'cubetype'), cubetype = SPATIAL.cubetype; else SPATIAL.cubetype = cubetype; end
    if ~isempty(SPATIAL) && isfield(SPATIAL,'cubefwhm'), cubefwhm = SPATIAL.cubefwhm; else SPATIAL.cubefwhm = cubefwhm; end
    if ~isempty(SPATIAL) && isfield(SPATIAL,'cubevoxres'), cubevoxres = SPATIAL.cubevoxres; else SPATIAL.cubevoxres = cubevoxres; end
    if exist('brainmask','var')
        if ~isempty(SPATIAL), SPATIAL.brainmask = brainmask; end
    end

    switch cubetype
        case 1
            cubetypestr = 'No filtering';
        case 2
            cubetypestr = 'Absolute difference filtering (6 neighbors)';
        case 3
            cubetypestr = 'Cube variance filtering (27 neighbors)';
        case 4
            cubetypestr = 'Gaussian smoothing';
            cubefwhmstr = nk_ConcatParamstr(cubefwhm);
        case 5
            cubetypestr = 'Neurotransmitter correlations';
        case 6
            cubetypestr = 'Resampling';
            cubevoxresstr = nk_ConcatParamstr(cubevoxres);
        case 7
            cubetypestr = 'ROI MEANS';
    end
   
    menustr = sprintf('Select spatial operation [ %s ]', cubetypestr ); menuact = 1;
    switch SPATIAL.cubetype 
        case 4
            menustr = sprintf('%s|Specify Gaussian filter width [ %s ]', menustr, cubefwhmstr ); menuact = [ menuact 2 ];
        case 5
            
            Atlas = [];
            AtlasDir = [];
            M_NT = [];
            YAtlas = [];
            CorType = 1;
            AutoCorCorrect = [];
            NTList = [];
            NTDir = [];
            NTind = [];
            NTROIs = [];
            TPMpath = [];
            TPMROIs = [];
            V_brainmask = [];
            indVol_brainmask = [];
            SPATIAL.JUSPACE.importflag = false;
            SPATIAL.JUSPACE.completeflag = false;

            if ~isfield(SPATIAL,'JUSPACE')
                SPATIAL.JUSPACE = [];
            end
            if isfield(SPATIAL.JUSPACE,'Atlas') && ~isempty(SPATIAL.JUSPACE.Atlas) 
                Atlas = SPATIAL.JUSPACE.Atlas; 
            end
            if isfield(SPATIAL.JUSPACE,'YAtlas') && ~isempty(SPATIAL.JUSPACE.YAtlas) 
                YAtlas = SPATIAL.JUSPACE.YAtlas; 
            end
            if isfield(SPATIAL.JUSPACE,'cortype') && ~isempty(SPATIAL.JUSPACE.cortype) 
                CorType = SPATIAL.JUSPACE.cortype; 
            end
            if isfield(SPATIAL.JUSPACE,'autocorcorrect') && ~isempty(SPATIAL.JUSPACE.autocorcorrect) 
                AutoCorCorrect = SPATIAL.JUSPACE.autocorcorrect; 
            end
            if isfield(SPATIAL.JUSPACE,'NTDir') && ~isempty(SPATIAL.JUSPACE.NTDir) 
                NTDir = SPATIAL.JUSPACE.NTDir; 
            end
            if isfield(SPATIAL.JUSPACE,'NTList') && ~isempty(SPATIAL.JUSPACE.NTList) 
                NTList = SPATIAL.JUSPACE.NTList; 
            end
            if isfield(SPATIAL.JUSPACE,'NTind') && ~isempty(SPATIAL.JUSPACE.NTind) 
                NTind = SPATIAL.JUSPACE.NTind; 
            end
            if isfield(SPATIAL.JUSPACE,'NTROIs') && ~isempty(SPATIAL.JUSPACE.NTROIs) 
                NTROIs = SPATIAL.JUSPACE.NTROIs; 
            end
            if isfield(SPATIAL.JUSPACE,'TPMpath') && ~isempty(SPATIAL.JUSPACE.TPMpath) 
                TPMpath = SPATIAL.JUSPACE.TPMpath; 
            end
            if isfield(SPATIAL.JUSPACE,'TPMROIs') && ~isempty(SPATIAL.JUSPACE.TPMROIs) 
                TPMROIs = SPATIAL.JUSPACE.TPMROIs; 
            end
            if isfield(SPATIAL.JUSPACE,'V_brainmask') && ~isempty(SPATIAL.JUSPACE.V_brainmask) 
                V_brainmask = SPATIAL.JUSPACE.V_brainmask; 
            end
            if isfield(SPATIAL.JUSPACE,'indVol_brainmask') && ~isempty(SPATIAL.JUSPACE.indVol_brainmask) 
                indVol_brainmask = SPATIAL.JUSPACE.indVol_brainmask; 
            end
            if ~isfield(SPATIAL.JUSPACE,'brainmask')
                SPATIAL.JUSPACE.brainmask = SPATIAL.brainmask;
                brainmask = SPATIAL.JUSPACE.brainmask;
            elseif isfield(SPATIAL.JUSPACE,'brainmask') && ~isempty(SPATIAL.JUSPACE.brainmask)
                brainmask = SPATIAL.JUSPACE.brainmask;
            end
            
            if ~isempty(Atlas)
                if size(Atlas,1) > 1
                    AtlasDef = 1;
                    for i = 1:size(Atlas,1)
                        if i == 1
                            ATLASSTR = [Atlas(i,:)];
                        else
                            ATLASSTR = [ATLASSTR,Atlas(i,:)];
                        end
                    end
                else
                    AtlasDef = 1;
                    ATLASSTR = Atlas;
                end
            else
                AtlasDef = 2;
                ATLASSTR = 'not defined';
            end
         
            if ~isempty(CorType) % correlation type
                switch CorType
                    case 1
                        CORTYPESTR = 'Spearman correlation';
                    case 2
                        CORTYPESTR = 'Pearson correlation';
                end
                CORTYPEDef = 1;
            else
                CORTYPESTR = 'not defined';
                CORTYPEDef = 2;
            end
        
            if ~isempty(AutoCorCorrect) % adjust for autocorrelations 1 = yes
                AUTOCORCORRECTSTR = num2str(AutoCorCorrect);
                if AutoCorCorrect == 1
                    AUTOCORCORRECTSTR = 'yes';
                else
                    AUTOCORCORRECTSTR = 'no';
                end
                AUTOCORCORRECTDef = 1;
            else
                AUTOCORCORRECTSTR = 'not defined';
                AUTOCORCORRECTDef = 2;
            end
        
            if ~isempty(NTDir)
                NTDirDef = 1;
                NTDIRSTR = NTDir;
            else
                NTDirDef = 2;
                NTDIRSTR = 'not defined';
            end
        
            if ~isempty(NTList)
                for i= 1:size(NTList,2)
                    if i == 1
                        NTLISTSTR = NTList{i}.id;
                    else 
                        NTLISTSTR = sprintf('%s, %s', NTLISTSTR, NTList{i}.id);
                    end
                end
                NTListDef = 1;
            else
                NTLISTSTR = 'No neurotransmitter selected';
                NTListDef = 2;
            end

            if AtlasDef == 1 && NTDirDef == 1 && NTListDef == 1 && CORTYPEDef == 1 && AUTOCORCORRECTDef == 1
                disallow = false;
                SPATIAL.JUSPACE.completeflag = true;
            else
                disallow = true;
            end

            python_available = pyenv;

             if ~isempty(python_available.Version)
                menustr = [menustr                                                                       '|'...
                           'Download atlases from JuSpace                                              ' '|' ...
                           'Download or use existing neurotransmitter maps from JuSpace or neuromaps   ' '|' ...
                           'Atlas                                                                       [' ATLASSTR ']|' ...
                           'Correlation type                                                            [' CORTYPESTR ']|' ...
                           'Adjust for spatial autocorrelations                                         [' AUTOCORCORRECTSTR ']|' ... 
                           'Neurotransmitter maps directory                                             [' NTDIRSTR ']|'];
                
            else
                menustr = [menustr                                                           '|'...
                           'Download atlases from JuSpace                                  ' '|' ...
                           'Download or use existing neurotransmitter maps from JuSpace    ' '|' ...
                           'Atlas                                                           [' ATLASSTR ']|' ...
                           'Correlation type                                                [' CORTYPESTR ']|' ...
                           'Adjust for spatial autocorrelations                             [' AUTOCORCORRECTSTR ']|' ... 
                           'Neurotransmitter maps directory                                 [' NTDIRSTR ']|'];
            end
            menuact = [menuact 4 5 6 7 8 9];

            if NTDirDef == 1
                mn_IO = sprintf(['Neurotransmitter selection                                [' NTLISTSTR ']']);
                menuact = [menuact 10] ; menustr = [menustr mn_IO];
            end
            if ~disallow
                mn_IO = sprintf('|Import neurotransmitter maps and atlas');
                menuact = [menuact 11] ; menustr = [menustr mn_IO];
            end
        case 6
            menustr = sprintf('%s|Specify voxel resolution [ %s ]', menustr, cubevoxresstr ); menuact = [ menuact 3 ];
        case 7
            Atlas = [];
            YAtlas = [];
            AtlasDir = [];
            AtlasROIs = {};
            AtlasLabels = [];
            V_brainmask = [];
            indVol_brainmask = [];
            SPATIAL.ROIMEANS.completeflag = false;

            if ~isfield(SPATIAL,'ROIMEANS')
                SPATIAL.ROIMEANS = [];
            end

            if ~isfield(SPATIAL.ROIMEANS,'brainmask')
                SPATIAL.ROIMEANS.brainmask = SPATIAL.brainmask;
                brainmask = SPATIAL.ROIMEANS.brainmask;
            elseif isfield(SPATIAL.ROIMEANS,'brainmask') && ~isempty(SPATIAL.ROIMEANS.brainmask)
                brainmask = SPATIAL.ROIMEANS.brainmask;
            end

            if isfield(SPATIAL.ROIMEANS,'indVol_brainmask') && ~isempty(SPATIAL.ROIMEANS.indVol_brainmask)
                indVol_brainmask = SPATIAL.ROIMEANS.indVol_brainmask;
            end

            if isfield(SPATIAL.ROIMEANS,'atlas') && ~isempty(SPATIAL.ROIMEANS.atlas)
                Atlas = SPATIAL.ROIMEANS.atlas;
            end

            if isfield(SPATIAL.ROIMEANS,'YAtlas') && ~isempty(SPATIAL.ROIMEANS.YAtlas) 
                YAtlas = SPATIAL.ROIMEANS.YAtlas; 
            end

            if isfield(SPATIAL.ROIMEANS,'AtlasROIs') && ~isempty(SPATIAL.ROIMEANS.AtlasROIs) 
                AtlasROIs = SPATIAL.ROIMEANS.AtlasROIs; 
            end
        
            if isfield(SPATIAL.ROIMEANS,'V_brainmask') && ~isempty(SPATIAL.ROIMEANS.V_brainmask) 
                V_brainmask = SPATIAL.ROIMEANS.V_brainmask; 
            end

            if isfield(SPATIAL.ROIMEANS,'AtlasLabels') && ~isempty(SPATIAL.ROIMEANS.AtlasLabels) 
                AtlasLabels = SPATIAL.ROIMEANS.AtlasLabels; 
            end

            if ~isempty(Atlas)
                if size(Atlas,1) > 1
                    for i = 1:size(Atlas,1)
                        if i == 1
                            ATLASSTR = [Atlas(i,:)];
                        else
                            ATLASSTR = [ATLASSTR,Atlas(i,:)];
                        end
                        SPATIAL.ROIMEANS.completeflag = true;
                    end
                else
                    ATLASSTR = Atlas;
                    SPATIAL.ROIMEANS.completeflag = true;
                end
            else
                AtlasDef = 2;
                ATLASSTR = 'not defined';
            end
            menustr = [menustr                           '|'...
                       'Download atlases from CAT12    ' '|' ...
                       'Atlas                            [ ' ATLASSTR ' ]|'];
            menuact = [menuact 12 13];
    end
    
    nk_PrintLogo

    mestr = 'Spatial operations'; navistr = [parentstr ' >>> ' mestr]; fprintf('\nYou are here: %s >>> ',parentstr); 
    act = nk_input(mestr,0,'mq', menustr, menuact);
    
    
    switch act
        case 1
            SPATIAL.cubetype = uint8(nk_input('Select spatial operation',0,'m',...
                ['No filtering|' ...
                'Absolute difference filtering (6 neighbors)|' ...
                'Cube variance filtering (27 neighbors)|' ...
                'Gaussian smoothing|' ...
                'Neurotransmitter correlations|' ...
                'ROI means computation|'],...%'Resampling (=>Voxel size)']
                [1:5,7],cubetype));
            switch SPATIAL.cubetype 
                case 4
                    SPATIAL.cubefwhm = 8;
                    PX = nk_AddParam(SPATIAL.cubefwhm, 'FWHM', 0, PX, 'replace');
                case 6
                    SPATIAL.cubevoxres = 3;
                    PX = nk_AddParam(SPATIAL.cubefwhm, 'VOX', 0, PX, 'replace');
                otherwise
                    PX = nk_AddParam(SPATIAL.cubefwhm, 'FWHM', 0, PX, 'reset');
            end
        case 2
            SPATIAL.cubefwhm = nk_input('Specify Gaussian filter width range [mm]',0,'e', cubefwhm);
            PX = nk_AddParam(SPATIAL.cubefwhm,'FWHM', 0, PX, 'replace');
        case 3
            SPATIAL.cubevoxres =  nk_input('Specify voxel resolution range [mm]',0,'e', cubevoxres);
            PX = nk_AddParam(SPATIAL.cubevoxres,'VOX', 0, PX, 'replace');
        case 4
            JUSPACE_act = 1;
            SPATIAL.JUSPACE = JuSpace_config_spatial(SPATIAL.JUSPACE,JUSPACE_act);
        case 5
            JUSPACE_act = 2;
            SPATIAL.JUSPACE = JuSpace_config_spatial(SPATIAL.JUSPACE,JUSPACE_act);
        case 6
            JUSPACE_act = 3;
            SPATIAL.JUSPACE = JuSpace_config_spatial(SPATIAL.JUSPACE,JUSPACE_act);
        case 7
            JUSPACE_act = 4;
            SPATIAL.JUSPACE = JuSpace_config_spatial(SPATIAL.JUSPACE,JUSPACE_act);
        case 8
            JUSPACE_act = 5;
            SPATIAL.JUSPACE = JuSpace_config_spatial(SPATIAL.JUSPACE,JUSPACE_act);
        case 9
            JUSPACE_act = 6;
            SPATIAL.JUSPACE = JuSpace_config_spatial(SPATIAL.JUSPACE,JUSPACE_act);
        case 10
            JUSPACE_act = 7;
            SPATIAL.JUSPACE = JuSpace_config_spatial(SPATIAL.JUSPACE,JUSPACE_act);
        case 11
            JUSPACE_act = 8;
            SPATIAL.JUSPACE = JuSpace_config_spatial(SPATIAL.JUSPACE,JUSPACE_act);
        case 12
            AtlasDownloadFlag = nk_input('Do you want to download atlas files from CAT12?',0, ...
                                            'yes|no',[1,0],1);

            if AtlasDownloadFlag
        
                SPMAVAIL = logical(exist('spm_select','file'));
    
                if AtlasDownloadFlag == 1
                    if SPMAVAIL
                        SaveDirAtlas = spm_select(1, 'dir', 'Select directory for saving atlases');
                    else
                        SaveDirAtlas = uigetdir(pwd, 'Select directory for saving atlases');
                    end
                end
    
                if AtlasDownloadFlag == 1
                    AtlasDir = download_atlas_cat12(SaveDirAtlas);
                else
                    AtlasDir = [];
                end
            end
            SPATIAL.ROIMEANS.AtlasDir = AtlasDir;
        case 13
             hdrstr = 'Select atlas'; 
            if isfield(SPATIAL.ROIMEANS,'AtlasDir') && ~isempty(SPATIAL.ROIMEANS.AtlasDir)
                Atlas = nk_FileSelector(Inf, 'nifti', hdrstr, '.*\.nii$', [], SPATIAL.ROIMEANS.AtlasDir);
            else
                Atlas = nk_FileSelector(Inf, 'nifti', hdrstr, '.*\.nii$', [], pwd);
            end

            V_brainmask = spm_vol(char(brainmask));

            if ~exist('label','var') || isempty(label), label = 0; end
            if ~exist('labelop','var') || isempty(labelop), labelop = 'gt'; end
            
            vox = sqrt(sum(V_brainmask.mat(1:3,1:3).^2));
            indVol_brainmask = [];
            
            for sl=1:V_brainmask.dim(3)
                % read mask
               
                M = spm_matrix([0 0 sl 0 0 0 1 1 1]);
               
                mask_slice = spm_slice_vol(V_brainmask,M,V_brainmask.dim(1:2),1);
                ind0 = find(feval(labelop, mask_slice,label));
                ind = ind0 + (sl - 1)*prod(V_brainmask.dim(1:2));
                indVol_brainmask = [indVol_brainmask; ind];
                clear mask_slice
            end

            YAtlas = zeros(size(Atlas,1),V_brainmask.dim(1)*V_brainmask.dim(2)*V_brainmask.dim(3));
            AtlasROIs = {};
            for sm = 1:size(Atlas,1)
                clear YAtlas_3D
                YAtlas_3D = resize_image_JuSpace(Atlas(sm,:),brainmask);
                YAtlas(sm,:) = reshape(YAtlas_3D,size(YAtlas_3D,1)*size(YAtlas_3D,2)*size(YAtlas_3D,3),1)';
                a = unique(YAtlas(sm,:));
                a = a(a~=0); 
                AtlasROIs{end+1,1} = a(~isnan(a));
                [AtlasLabels{sm},AtlasLabels_Num] = read_atlas_labels(Atlas(sm,:));
                if ~isempty(AtlasLabels{sm})
                    ind_labels = ismember(cell2mat(AtlasLabels_Num),cell2mat(AtlasROIs)');
                    AtlasLabels{sm} = AtlasLabels{sm}(ind_labels,1);
                else
                    AtlasLabels{sm} = cellstr([repmat('Label ',size(AtlasROIs{sm,1},2),1),num2str(AtlasROIs{sm}')]);
                end
            end

            SPATIAL.ROIMEANS.atlas = Atlas;
            SPATIAL.ROIMEANS.YAtlas = YAtlas;
            SPATIAL.ROIMEANS.AtlasROIs = AtlasROIs;
            SPATIAL.ROIMEANS.AtlasLabels = AtlasLabels;
            SPATIAL.ROIMEANS.V_brainmask = V_brainmask;
            SPATIAL.ROIMEANS.indVol_brainmask = indVol_brainmask;
    end
else
    act = 0;
end    

if act, [ SPATIAL, PX ] = nk_Spatial_config(SPATIAL, PX, [], parentstr); end

end

function JUSPACE = JuSpace_config_spatial(JUSPACE,JUSPACE_act)

Atlas = [];
AtlasDir = [];
M_NT = [];
YAtlas = [];
CorType = 1;
AutoCorCorrect = [];
NTList = [];
NTDir = [];
NTind = [];
NTROIs = [];
TPMpath = [];
TPMROIs = [];
V_brainmask = [];
indVol_brainmask = [];
importflag = false;
completeflag = false;
brainmask = [];

if ~exist('defaultsfl','var') || isempty(defaultsfl); defaultsfl = false; end

if ~defaultsfl

    if isfield(JUSPACE,'Atlas') && ~isempty(JUSPACE.Atlas) 
        Atlas = JUSPACE.Atlas; 
    end
    if isfield(JUSPACE,'YAtlas') && ~isempty(JUSPACE.YAtlas) 
        YAtlas = JUSPACE.YAtlas; 
    end
    if isfield(JUSPACE,'AtlasDir') && ~isempty(JUSPACE.AtlasDir) 
        AtlasDir = JUSPACE.AtlasDir; 
    end
    if isfield(JUSPACE,'NT_Table') && ~isempty(JUSPACE.NT_Table) 
        M_NT = JUSPACE.NT_Table; 
    end
    % correlation type
    if isfield(JUSPACE,'cortype') && ~isempty(JUSPACE.cortype) 
        CorType = JUSPACE.cortype; 
    end
    % adjust for spatial correlations
    if isfield(JUSPACE,'autocorcorrect') && ~isempty(JUSPACE.autocorcorrect) 
        AutoCorCorrect = JUSPACE.autocorcorrect; 
    end
    if isfield(JUSPACE,'NTDir') && ~isempty(JUSPACE.NTDir) 
        NTDir = JUSPACE.NTDir; 
    end
    if isfield(JUSPACE,'NTList') && ~isempty(JUSPACE.NTList) 
        NTList = JUSPACE.NTList; 
    end
    if isfield(JUSPACE,'NTind') && ~isempty(JUSPACE.NTind) 
        NTind = JUSPACE.NTind; 
    end
    if isfield(JUSPACE,'NTROIs') && ~isempty(JUSPACE.NTROIs) 
        NTROIs = JUSPACE.NTROIs; 
    end
    if isfield(JUSPACE,'TPMpath') && ~isempty(JUSPACE.TPMpath) 
        TPMpath = JUSPACE.TPMpath; 
    end
    if isfield(JUSPACE,'TPMROIs') && ~isempty(JUSPACE.TPMROIs) 
        TPMROIs = JUSPACE.TPMROIs; 
    end
    if isfield(JUSPACE,'brainmask') && ~isempty(JUSPACE.brainmask) 
        brainmask = JUSPACE.brainmask; 
    end
    if isfield(JUSPACE,'V_brainmask') && ~isempty(JUSPACE.V_brainmask) 
        V_brainmask = JUSPACE.V_brainmask; 
    end
    if isfield(JUSPACE,'indVol_brainmask') && ~isempty(JUSPACE.indVol_brainmask) 
        indVol_brainmask = JUSPACE.indVol_brainmask; 
    end
    if isfield(JUSPACE,'importflag') && ~isempty(JUSPACE.importflag) 
        importflag = JUSPACE.importflag; 
    end
    if isfield(JUSPACE,'completeflag') && ~isempty(JUSPACE.completeflag) 
        completeflag = JUSPACE.completeflag; 
    end

    switch JUSPACE_act
        case 1
            AtlasDownloadFlag = nk_input('Do you want to download atlas files from JuSpace?',0,...
                                            'yes|no',[1,0],1);

            if AtlasDownloadFlag
        
                SPMAVAIL = logical(exist('spm_select','file'));

                if SPMAVAIL
                    SaveDirAtlas = spm_select(1, 'dir', 'Select directory for saving atlases');
                else
                    SaveDirAtlas = uigetdir(pwd, 'Select directory for saving atlases');
                end
    
                AtlasDir = download_atlas_files(SaveDirAtlas);
            else
                AtlasDir = [];
            end
        case 2
            python_available = pyenv;

            if ~isempty(python_available.Version)
                NTDownloadFlag = nk_input('Do you want to download or use existing neurotransmitter maps from JuSpace or neuromaps?',0,'mq',...
                                         ['Download from JuSpace (MATLAB-based toolbox)|',...
                                          'Download from neuromaps (Python-based toolbox, provides more neurotransmitter maps)|',...
                                          'Use existing from JuSpace (MATLAB-based toolbox)|',...
                                          'Use existing from neuromaps (Python-based toolbox, provides more neurotransmitter maps)'], 1:4, 0);

                if NTDownloadFlag == 1
                    JuSpaceDownloadFlag = 1;
                    UseExistingFlag = 0;
                    neuromapsDownloadFlag = 0;
                elseif NTDownloadFlag == 2
                    neuromapsDownloadFlag = 1;
                    UseExistingFlag = 0;
                    JuSpaceDownloadFlag = 0;
                elseif NTDownloadFlag == 3
                    JuSpaceDownloadFlag = 1;
                    UseExistingFlag = 1;
                    neuromapsDownloadFlag = 0;
                elseif NTDownloadFlag == 4
                    neuromapsDownloadFlag = 1;
                    UseExistingFlag = 1;
                    JuSpaceDownloadFlag = 0;
                elseif NTDownloadFlag == 0
                    JuSpaceDownloadFlag = 0;
                    neuromapsDownloadFlag = 0;
                    UseExistingFlag = 0;
                end
            else
                neuromapsDownloadFlag = 0;
                JuSpaceDownloadFlag = nk_input('Do you want to download or use existing neurotransmitter maps from JuSpace?',0,'mq',...
                                         ['Download from JuSpace (MATLAB-based)|',...
                                          'Use existing from JuSpace (MATLAB-based)'],1:2, 0);
                if JuSpaceDownloadFlag == 1
                    UseExistingFlag = 0;
                elseif JuSpaceDownloadFlag == 2
                    UseExistingFlag = 1;
                else
                    UseExistingFlag = 0;
                end
            end

            SPMAVAIL = logical(exist('spm_select','file'));

            if (JuSpaceDownloadFlag || neuromapsDownloadFlag) && ~UseExistingFlag
                if SPMAVAIL
                    SaveDir = spm_select(1, 'dir', 'Select directory for saving neurotransmitter maps');
                else
                    SaveDir = uigetdir(pwd, 'Select directory for saving neurotransmitter maps');
                end
            elseif UseExistingFlag && (JuSpaceDownloadFlag || neuromapsDownloadFlag)
                if SPMAVAIL
                    SaveDir = spm_select(1, 'dir', 'Select existing neurotransmitter maps directory');
                else
                    SaveDir = uigetdir(pwd, 'Select existing neurotransmitter maps directory');
                end
            end

            if JuSpaceDownloadFlag
                M_NT = download_sort_images(SaveDir,'JuSpace',UseExistingFlag);
                if ~UseExistingFlag
                    NTDir = fullfile(SaveDir,'NT','JuSpace');
                else
                    NTDir = SaveDir;
                end
            elseif neuromapsDownloadFlag
                M_NT = download_sort_images(SaveDir,'neuromaps',UseExistingFlag);
                if ~UseExistingFlag
                    NTDir = fullfile(SaveDir,'NT','neuromaps');
                else
                    NTDir = SaveDir;
                end
            end
        case 3
            hdrstr = 'Select atlas';
            if isempty(AtlasDir)
                Atlas = nk_FileSelector(Inf, 'nifti', hdrstr, '.*\.nii$', [], pwd);
            else
                Atlas = nk_FileSelector(Inf, 'nifti', hdrstr, '.*\.nii$', [], AtlasDir);
            end
        case 4
            CorType = nk_input('Define the correlation type', 0, 'mq', ...
                ['Spearman correlation |', ...
                'Pearson correlation'], 1:2, 0);
        case 5
            AutoCorCorrect = nk_input('Adjust for spatial correlations',0,'mq',...
                ['Yes |',...
                 'No'], 1:2, 0);
            if AutoCorCorrect == 1
                spm_path = extractBefore(which('SPM'),[filesep,'spm.m']);
                TPMpath = fullfile(spm_path,'tpm','TPM.nii,1');
            else
                TPMpath = '';
            end
        case 6
            hdrstr = 'Select neurotransmitter maps directory';
            SPMAVAIL = logical(exist('spm_select','file'));
            if SPMAVAIL
                NTDir = spm_select(1, 'dir', 'Select neurotransmitter maps directory');
            else
                NTDir = uigetdir(pwd,'Select neurotransmitter maps directory');
            end
            NTind = [];
            NTList = [];
        case 7
            hdrstr = 'Select neurotransmitters';
            [NTind,NTList] = print_NTmaps_quickselector(M_NT,NTDir);
        case 8

            disp('Importing atlas and neurotransmitter information...');

            aa = dir(fullfile(NTDir,'*.nii'));
            NTFiles = {aa.name}';
            NTFiles = NTFiles(NTind');

%             Thresh.nVml = 0;
%             Thresh.Vml = 0;
%             Thresh.Lm{1} = 'Binary treshold: gt 0';
%             Thresh.threshop{1} = 'gt';
%         
%             tmpflg = false;
 
            V_brainmask = spm_vol(char(brainmask));

            if ~exist('label','var') || isempty(label), label = 0; end
            if ~exist('labelop','var') || isempty(labelop), labelop = 'gt'; end
            
            vox = sqrt(sum(V_brainmask.mat(1:3,1:3).^2));                
            Y   = [];
            indVol_brainmask = [];
            
            for sl=1:V_brainmask.dim(3)
                % read mask
               
                M = spm_matrix([0 0 sl 0 0 0 1 1 1]);
               
                mask_slice = spm_slice_vol(V_brainmask,M,V_brainmask.dim(1:2),1);
                ind0 = find(feval(labelop, mask_slice,label));
                ind = ind0 + (sl - 1)*prod(V_brainmask.dim(1:2));
                indVol_brainmask = [indVol_brainmask; ind];
                clear mask_slice
            end

%             Vmvol = spm_read_vols(V_brainmask);
        
%             [V_brainmask, tmpflg] = WriteTempVol(V_brainmask, Vmvol, tmpflg);
        
            YAtlas = zeros(size(Atlas,1),V_brainmask.dim(1)*V_brainmask.dim(2)*V_brainmask.dim(3));
            for i = 1:size(Atlas,1)
                clear YAtlas_3D
                YAtlas_3D = resize_image_JuSpace(Atlas(i,:),brainmask);
                YAtlas(i,:) = reshape(YAtlas_3D,size(YAtlas_3D,1)*size(YAtlas_3D,2)*size(YAtlas_3D,3),1)';
            end
%             VAtlas = spm_vol(Atlas);
%             YAtlas = nk_ReturnSubSpaces(VAtlas, V_brainmask, 1, size(Atlas,1), Thresh);
            if AutoCorCorrect == 1
                YTPM_3D = resize_image_JuSpace(TPMpath,brainmask);
                YTPM = reshape(YTPM_3D,size(YTPM_3D,1)*size(YTPM_3D,2)*size(YTPM_3D,3),1)';
            end
%             VTPM = spm_vol(char(TPMpath));
%             YTPM = nk_ReturnSubSpaces(VTPM, V_brainmask, 1, 1, Thresh);

            YNT = zeros(size(NTFiles,1),V_brainmask.dim(1)*V_brainmask.dim(2)*V_brainmask.dim(3));
            for i = 1:size(NTFiles,1)
                clear YNT_3D
                YNT_3D = resize_image_JuSpace(fullfile(NTDir,NTFiles{i,1}),brainmask);
                YNT(i,:) = reshape(YNT_3D,size(YNT_3D,1)*size(YNT_3D,2)*size(YNT_3D,3),1)';
            end
%             VNT = spm_vol(char(fullfile(NTDir,NTFiles)));
%             YNT = nk_ReturnSubSpaces(VNT, V_brainmask, 1, size(NTFiles,1), Thresh);

            if AutoCorCorrect == 1
                TPMROIs = cell(size(Atlas,1),1);
            else
                TPMROIs = [];
            end

            NTROIs = cell(size(Atlas,1),1);
            for k = 1:size(YAtlas,1)
                a = unique(YAtlas(k,:));
                a = a(a~=0);
                AtlasROIs = a(~isnan(a));
                
                for i = 1:numel(AtlasROIs)
                    indVec = round(YAtlas(k,:)) == round(AtlasROIs(i));
                    if AutoCorCorrect == 1
                        TPMROIs{k,1}(:,i) = mean(removenan_my(YTPM(1,indVec)'),1);
                    end
                    for j = 1:size(YNT,1)
                        NTROIs{k,1}(j,i) = mean(removenan_my(YNT(j,indVec)'),1);
                    end
                end
            end
            importflag = true;
    end
else
    JUSPACE_act = 0;
end

JUSPACE.Atlas = Atlas;
JUSPACE.AtlasDir = AtlasDir;
JUSPACE.NT_Table = M_NT;
JUSPACE.YAtlas = YAtlas;
JUSPACE.NTDir = NTDir;
JUSPACE.NTind = NTind;
JUSPACE.NTList = NTList;
JUSPACE.NTROIs = NTROIs;
JUSPACE.cortype = CorType;
JUSPACE.autocorcorrect = AutoCorCorrect;
JUSPACE.TPMpath = TPMpath;
JUSPACE.TPMROIs = TPMROIs;
JUSPACE.V_brainmask = V_brainmask;
JUSPACE.indVol_brainmask = indVol_brainmask;
JUSPACE.completeflag = completeflag;
JUSPACE.importflag = importflag;

end

function AtlasDir = download_atlas_files(NTDir)

fprintf('Preparing to download image files...\n');

api_url_start = 'https://api.github.com/repos/juryxy/JuSpace/contents';

data_start = webread(api_url_start);

ind_dir = strcmp({data_start.type}','dir');

dir_name = data_start(ind_dir).name;

api_url = ['https://api.github.com/repos/juryxy/JuSpace/contents/',dir_name,'/atlas?ref=',dir_name];

data = webread(api_url);

AtlasDir = fullfile(NTDir,'Atlas_NT');
if ~exist(AtlasDir, 'dir')
    mkdir(AtlasDir);
end

for i = 1:length(data)
    if strcmp(data(i).type, 'file')
        file_name = data(i).name;
        download_url = data(i).download_url;
        
        local_file = fullfile(AtlasDir, file_name);

        websave(local_file, download_url);
        
        fprintf('Downloaded: %s\n', file_name);
    else
        fprintf('Error: Unable to fetch folder contents. Please download the files manually from the JuSpace Github page: https://github.com/juryxy/JuSpace": %s\n', data(i).name);
    end
end

end


function M_NT = download_sort_images(NTDir,software,UseExistingFlag)    

if strcmp(software,'neuromaps')

    if ~UseExistingFlag
        fprintf('Preparing to download image files...\n');
    else
        fprintf('Gathering file information...\n');
    end

    GOOGLE_SHEET_ID = '1oZecOsvtQEh5pQkIf8cB6CyhPKVrQuko';
    SHEET_GID = '1162991686';
    
    csv_url = ['https://docs.google.com/spreadsheets/d/',GOOGLE_SHEET_ID,'/export?format=csv&gid=',SHEET_GID];
    
    M_NT = [];
    attempt = 0;
    delayBetweenAttempts = 10;
    success = false;

    while attempt < 11 && ~success
        try
            M_NT = readtable(csv_url);
            success = true; 
        catch
            attempt = attempt + 1;
            pause(delayBetweenAttempts);
        end
        if attempt == 10 && isempty(M_NT)
            disp('Could not load table.')
        end
    end

    if ~UseExistingFlag

%         get_images_OSF(NTDir);
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

        if ~UseExistingFlag
            fprintf('Preparing to download image files...\n');
        else
            fprintf('Gathering file information...\n');
        end

        aa = dir(fullfile(NTDir,'*.nii'));
        if ~isempty(aa)
            NTfiles = fullfile({aa.folder}',{aa.name}');
        else
            error('No neurotransmitter image files were found in this directory: %s', NTDir);
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
    
        if UseExistingFlag
            ind_available = ismember(NTfiles_docs,{aa.name}');
        else
            ind_available = ismember(NTfiles_docs,extractBefore({aa.name}','.gz'));
        end
    
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

        api_url_start = 'https://api.github.com/repos/juryxy/JuSpace/contents';
    
        data_start = webread(api_url_start);
    
        ind_dir = strcmp({data_start.type}','dir');
    
        dir_name = data_start(ind_dir).name;
    
        api_url = ['https://api.github.com/repos/juryxy/JuSpace/contents/',dir_name,'/PETatlas?ref=',dir_name];
        
        data = webread(api_url);
        
        NT_folder = fullfile(NTDir,'NT','JuSpace');
        if ~exist(NT_folder, 'dir')
            mkdir(NT_folder);
        end
        
        for i = 1:length(data)
            if strcmp(data(i).type, 'file')
                file_name = data(i).name;
    
                download_url = data(i).download_url;
                
                local_file = fullfile(NT_folder, file_name);
                
                websave(local_file, download_url);
                
                fprintf('Downloaded: %s\n', file_name);
            else
                fprintf('Error: Unable to fetch folder contents. Please download the files manually from the JuSpace Github page: https://github.com/juryxy/JuSpace": %s\n', data(i).name);
            end
        end
    
        aa = dir(fullfile(NT_folder,'*.nii'));
        NTfiles = fullfile({aa.folder}',{aa.name}');
    else
        aa = dir(fullfile(NTDir,'*.nii'));
        if ~isempty(aa)
            NTfiles = fullfile({aa.folder}',{aa.name}');
        else
            error('No neurotransmitter image files were found in this directory: %s', NTDir);
        end
    end

    M_NT = extractFilePartsMultiple({aa.name}');
end

function M_NT = extractFilePartsMultiple(filenames)
    filePartsArray = struct('NT', {}, 'tracer', {}, 'N', {}, 'source', {});
    
    for j = 1:length(filenames)
        [~, fileWithoutExtension, ~] = fileparts(filenames{j});
        
        parts = regexp(fileWithoutExtension, '_', 'split');
        
        fileParts.NT = 'NA';
        fileParts.tracer = 'NA';
        fileParts.N = 'NA';
        fileParts.source = 'NA';
        
        if length(parts) >= 1
            fileParts.NT = parts{1};
        end
        if length(parts) >= 2
            fileParts.tracer = parts{2};
        end
        if length(parts) >= 3
            if contains(parts{3},caseInsensitivePattern('hc'))
                part3 = extractAfter(parts{3},caseInsensitivePattern('hc'));
                if isempty(part3)
                    part3 = extractBefore(parts{3},caseInsensitivePattern('hc'));
                end
            elseif contains(parts{3},caseInsensitivePattern('c'))
                part3 = extractAfter(parts{3},caseInsensitivePattern('c'));
            else
                part3 = 'NA';
            end
            fileParts.N = part3;
        end
        if length(parts) >= 4
            fileParts.source = parts{4};
        end
        
        filePartsArray(j) = fileParts;
    end
    M_NT = struct2table(filePartsArray);
end

end

function [NTind,neurotransmitterSel] = print_NTmaps_quickselector(M_NT,NTDir)

nk_PrintLogo
fprintf('\n\t'); fprintf('============================================= ');
fprintf('\n\t'); fprintf('***        Neurotransmitter Selector        *** ');
fprintf('\n\t'); fprintf('============================================= ');

if isempty(M_NT) && ~isempty(NTDir)
    aa = dir(fullfile(NTDir,'*.nii'));
    NTFiles = extractBefore({aa.name}','.nii');

    if ~isempty(NTFiles)    
        for i = 1:size(NTFiles,1)
            neurotransmitter{i}.id = char(NTFiles{i});
            neurotransmitter{i}.listidx = i;
        end
    
        for i=1:numel(neurotransmitter)
            fprintf('\n\t** [ %2g ]: NT : %s', i, neurotransmitter{i}.id);
        end
        fprintf('\n');
        NTind = nk_input('Type sequence of neurotransmitters to include (1d-vector)',0,'e');
    
        zeroIDX = NTind == 0; 
        NTind = NTind(~zeroIDX);
        greaterIDX = NTind > numel(neurotransmitter); 
        NTind = NTind(~greaterIDX);
        
        neurotransmitterSel = [];
        for i = 1:numel(NTind)
            neurotransmitterSel{i}.id = neurotransmitter{NTind(i)}.id;
            neurotransmitterSel{i}.listidx = neurotransmitter{NTind(i)}.listidx;
            NTnames{i} = neurotransmitter{NTind(i)}.id;
        end
    else
        fprintf(['\n\nWARNING: The directory ',NTDir,' does not contain any neurotransmitter maps.\n        n Please select the folder directly including the images.']);
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
    end

    for i = 1:numel(neurotransmitter)
        fprintf('\n\t** [ %2g ]: NT: %-10s Tracer: %-20s N: %-5s Source: %s', ...
            i, neurotransmitter{i}.NT, neurotransmitter{i}.Tracer, neurotransmitter{i}.N, neurotransmitter{i}.Source);
    end
    fprintf('\n');
    NTind = nk_input('Type sequence of neurotransmitters to include (1d-vector)',0,'e');

    % remove invalid numbers
    zeroIDX = NTind == 0; 
    NTind = NTind(~zeroIDX);
    greaterIDX = NTind > numel(neurotransmitter); 
    NTind = NTind(~greaterIDX);
    
    neurotransmitterSel = [];
    for i = 1:numel(NTind)
        neurotransmitterSel{i}.id = neurotransmitter{NTind(i)}.NT;
        neurotransmitterSel{i}.listidx = neurotransmitter{NTind(i)}.listidx;
        NTnames{i} = neurotransmitter{NTind(i)}.NT;
    end
end
end

function Atlas_folder = download_atlas_cat12(AtlasDir)

fprintf('Preparing to download atlas files...\n');
    
api_url = 'https://api.github.com/repos/ChristianGaser/cat12/contents/templates_MNI152NLin2009cAsym?ref=main';

data = webread(api_url);

ind_atlas = contains({data.name}','.csv');

data_atlas_csv = extractBefore({data(ind_atlas).name}','.csv');

ind_atlas_all = contains({data.name}',data_atlas_csv);

data = data(ind_atlas_all);

Atlas_folder = fullfile(AtlasDir,'Atlas');
if ~exist(Atlas_folder, 'dir')
    mkdir(Atlas_folder);
end

for m = 1:length(data)
    if strcmp(data(m).type, 'file')
        file_name = data(m).name;

        download_url = data(m).download_url;
        
        local_file = fullfile(Atlas_folder, file_name);
        
        websave(local_file, download_url);
        
        fprintf('Downloaded: %s\n', file_name);
    else
        fprintf('Error: Unable to fetch folder contents. Please download the files manually from the JuSpace Github page: https://github.com/juryxy/JuSpace": %s\n', data(i).name);
    end
end
end

function [AtlasLabels,AtlasLabels_Num] = read_atlas_labels(atlas)

descfile_xml  = spm_file(atlas,'ext','xml');
if ~spm_existfile(descfile_xml)
    [pathstr, name, ext] = fileparts(descfile_xml);
    descfile_xml = fullfile(pathstr,['labels_',name,ext]);
end
descfile_csv = spm_file(atlas,'ext','csv');
if ~spm_existfile(descfile_csv)
    [pathstr, name, ext] = fileparts(descfile_csv);
    descfile_csv = fullfile(pathstr,['labels_',name,ext]);
end

if spm_existfile(descfile_xml)
    xA    = spm_atlas('load',descfile_xml);
    AtlasLabels_Num = {xA.labels.index}';
    AtlasLabels = {xA.labels.name}';
elseif spm_existfile(descfile_csv)

  opt.delimiter       = ',';
  opt.komma           = '.'; 
  opt.linedelimiter   = '\n'; 
  opt.format          = '%0.4f';
  opt.finaldelimiter  = 0;  

  pos   = ''; 
  opt_csv = detectImportOptions(descfile_csv);
  opt.delimiter = opt_csv.Delimiter{1};
  if opt.delimiter == ',', opt.komma = ','; end

  xA = readcsv(descfile_csv,pos,opt);
  xA = cell2table(xA(2:end,:),'VariableNames',xA(1,:));
  AtlasLabels = xA.ROIname;
  if ~iscell(xA.ROIid)
    AtlasLabels_Num = num2cell(xA.ROIid);
  elseif ~isnumeric(xA.ROIid)
    AtlasLabels_Num = {str2double(xA.ROIid)};
  end
else
    AtlasLabels = [];
    AtlasLabels_Num = [];
end
end

function C = readcsv(filename,pos,opt)

fid = fopen(filename);
mv = version; mvi = strfind(mv,'R');

C1  = textscan(fid,'%q','delimiter',opt.linedelimiter); C1=C1{1};
fclose(fid);

for j=1:size(C1,1)
    Quote=strfind(C1{j},'"'); 
    for qi=numel(Quote):-1:1
        Delim=strfind(C1{j}(Quote(qi):end),opt.delimiter) + Quote(qi) - 1;
        if ~isempty(Delim) && strcmp(C1{j}(1:Delim(1)-1),'"')
            C1{j}=[C1{j}(1:Delim(1)-1) '"' C1{j}(Delim(1):end)];
        end
    end
end

C1  = strrep(C1,'Ã¤','ä');
C1  = strrep(C1,'Ã¼','ü');
C1  = strrep(C1,'Ã¶','ö');

for j=1:size(C1,1)
    try
      if isempty(C1{j})
        C2{j} = '';
      else
          C2{j}=textscan(C1{j},'%q','delimiter',opt.delimiter)'; C2{j}=C2{j}{1}';
      end
    catch
      fprintf('WARNING:cat_io_csv:readcsv: Can''t read line %d!\n',j); C2{j}=cell(1,numel(C2{1}));
    end
end
C3=cell(size(C2,2),max(cellfun('size',C2,1)));
for j=1:size(C2,2)
    for k=1:size(C2{j},2)
      C3{j,k}=C2{j}{k};
    end
end

if isempty(pos), C=C3; else C=readC(C3,pos); end

for j=1:numel(C), if ~isnan(str2double(C{j})), id=strfind(C{j},','); C{j}(id)='.'; C{j} = str2double(C{j}); end; end

end
