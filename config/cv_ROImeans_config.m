function [ROIMEANS, act ] = cv_ROImeans_config(ROIMEANS, brainmask, Thresh, parentstr, defaultsfl)

Atlas = [];
YAtlas = [];
AtlasDir = [];
AtlasROIs = {};
AtlasLabels = [];
completeflag = false;

if ~exist('defaultsfl','var') || isempty(defaultsfl); defaultsfl = false; end

if ~defaultsfl
    if isfield(ROIMEANS,'atlas') && ~isempty(ROIMEANS.atlas)
        Atlas = ROIMEANS.atlas;
    end

    if isfield(ROIMEANS,'AtlasDir') && ~isempty(ROIMEANS.AtlasDir)
        AtlasDir = ROIMEANS.AtlasDir;
    end

    if isfield(ROIMEANS,'YAtlas') && ~isempty(ROIMEANS.YAtlas) 
        YAtlas = ROIMEANS.YAtlas; 
    end

    if isfield(ROIMEANS,'AtlasROIs') && ~isempty(ROIMEANS.AtlasROIs) 
        AtlasROIs = ROIMEANS.AtlasROIs; 
    end

    if isfield(ROIMEANS,'AtlasLabels') && ~isempty(ROIMEANS.AtlasLabels) 
        AtlasLabels = ROIMEANS.AtlasLabels; 
    end

    if isfield(ROIMEANS,'completeflag') && ~isempty(ROIMEANS.completeflag) 
        completeflag = ROIMEANS.completeflag;
    end

    if ~isempty(Atlas)
        if size(Atlas,1) > 1
            for mn = 1:size(Atlas,1)
                if mn == 1
                    ATLASSTR = [Atlas(mn,:)];
                else
                    ATLASSTR = [ATLASSTR,Atlas(mn,:)];
                end
            end
            completeflag = true;
        else
            ATLASSTR = Atlas;
            completeflag = true;
        end
    else
        ATLASSTR = 'not defined';
        completeflag = true;
    end

    menustr = ['Download atlases from CAT12    ' '|' ...
               'Atlas                         [' ATLASSTR ']'];
    menuact = [1,2];
    nk_PrintLogo
    mestr = 'ROIMEANS Toolbox step setup'; navistr = [parentstr ' >>> ' mestr]; fprintf('\nYou are here: %s >>> ',parentstr);
    act = nk_input(mestr,0,'mq', menustr, menuact);

    switch act
        case 1
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
        case 2
            hdrstr = 'Select atlas';
            if ~isempty(AtlasDir)
                Atlas = nk_FileSelector(Inf, 'nifti', hdrstr, '.*\.nii$', [], AtlasDir);
            else
                Atlas = nk_FileSelector(Inf, 'nifti', hdrstr, '.*\.nii$', [], pwd);
            end

            V_brainmask = spm_vol(char(brainmask));

            VAtlas = spm_vol(Atlas);

            YAtlas = [];
            for mn = 1:size(VAtlas,1)
                YAtlas(mn,:) = nk_ReturnSubSpaces_JuSpace(VAtlas(mn), V_brainmask, 1, 1, Thresh, 0);
            end

            AtlasROIs = cell(size(Atlas,1),1);
            for sm = 1:size(YAtlas,1)
                a = unique(YAtlas(sm,:));
                a = a(a~=0);
                AtlasROIs{sm,1} = a(~isnan(a));
                [AtlasLabels{sm,1},AtlasLabels_Num] = read_atlas_labels(Atlas(sm,:));
                if ~isempty(AtlasLabels{sm,1})
                    ind_labels = ismember(cell2mat(AtlasLabels_Num),cell2mat(AtlasROIs)');
                    AtlasLabels{sm,1} = AtlasLabels{sm,1}(ind_labels,1);
                else
                    AtlasLabels{sm,1} = cellstr([repmat('Label ',size(AtlasROIs{sm,1},2),1),num2str(AtlasROIs{sm}')]);
                end
            end
    end
else
    act = 0;
end

ROIMEANS.AtlasDir = AtlasDir;
ROIMEANS.atlas = Atlas;
ROIMEANS.YAtlas = YAtlas;
ROIMEANS.AtlasROIs = AtlasROIs;
ROIMEANS.AtlasLabels = AtlasLabels;
ROIMEANS.completeflag = completeflag;


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
end

%             if ~exist('label','var') || isempty(label), label = 0; end
%             if ~exist('labelop','var') || isempty(labelop), labelop = 'gt'; end
%             
%             vox = sqrt(sum(V_brainmask.mat(1:3,1:3).^2));
%             indVol_brainmask = [];
%             
%             for sl=1:V_brainmask.dim(3)
%                 % read mask
%                
%                 M = spm_matrix([0 0 sl 0 0 0 1 1 1]);
%                
%                 mask_slice = spm_slice_vol(V_brainmask,M,V_brainmask.dim(1:2),1);
%                 ind0 = find(feval(labelop, mask_slice,label));
%                 ind = ind0 + (sl - 1)*prod(V_brainmask.dim(1:2));
%                 indVol_brainmask = [indVol_brainmask; ind];
%                 clear mask_slice
%             end


%             YAtlas = zeros(size(Atlas,1),V_brainmask.dim(1)*V_brainmask.dim(2)*V_brainmask.dim(3));
%             AtlasROIs = {};
%             for sm = 1:size(Atlas,1)
%                 clear YAtlas_3D
%                 YAtlas_3D = resize_image_JuSpace(Atlas(sm,:),brainmask);
%                 YAtlas(sm,:) = reshape(YAtlas_3D,size(YAtlas_3D,1)*size(YAtlas_3D,2)*size(YAtlas_3D,3),1)';
%                 a = unique(YAtlas(sm,:));
%                 a = a(a~=0); 
%                 AtlasROIs{end+1,1} = a(~isnan(a));
%                 [AtlasLabels{sm},AtlasLabels_Num] = read_atlas_labels(Atlas(sm,:));
%                 if ~isempty(AtlasLabels{sm})
%                     ind_labels = ismember(cell2mat(AtlasLabels_Num),cell2mat(AtlasROIs)');
%                     AtlasLabels{sm} = AtlasLabels{sm}(ind_labels,1);
%                 else
%                     AtlasLabels{sm} = cellstr([repmat('Label ',size(AtlasROIs{sm,1},2),1),num2str(AtlasROIs{sm}')]);
%                 end
%             end