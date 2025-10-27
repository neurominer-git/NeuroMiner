function get_images_OSF(SaveDir)

json_url = 'https://raw.githubusercontent.com/netneurolab/neuromaps/main/neuromaps/datasets/data/osf.json';

list_annotations = {};
ind_annotations = [];

try
    json_data = webread(json_url);
    data = jsondecode(json_data);

    for i = 1:numel(data.annotations)
        if isfield(data.annotations{i},'tags') && any(strcmp(data.annotations{i}.tags, 'PET')) && isfield(data.annotations{i},'space') && any(strcmp(data.annotations{i}.space, 'MNI152'))
            list_annotations{end+1,1} = data.annotations{i}.fname;
            ind_annotations(end+1,1) = i;
        end
    end
end

for i = 1:size(ind_annotations,1)
    ind_curr = ind_annotations(i,1);
    if isfield(data.annotations{ind_curr}, 'url')
        project_id = data.annotations{ind_curr}.url{1};
        file_id = data.annotations{ind_curr}.url{2};
        download_url = strcat('https://files.osf.io/v1/resources/', project_id, '/providers/osfstorage/', file_id);

        if isfield(data.annotations{ind_curr}, 'fname')
            output_filename = fullfile(SaveDir,data.annotations{ind_curr}.fname);
        end

        try
            websave(output_filename, download_url);
            disp(['Downloaded ', data.annotations{ind_curr}.fname,'.']);
        catch ME
            disp(ME.message);
        end
    end
end
end