function handles = load_modal(handles, GDdims)
% Build base list from GDdims
nM = numel(GDdims);
popuplist = cell(nM,1);
for i = 1:nM
    desc = '';
    if i <= nM && isfield(GDdims{i}, 'datadescriptor') && isfield(GDdims{i}.datadescriptor, 'desc')
        desc = GDdims{i}.datadescriptor.desc;
    end
    popuplist{i} = sprintf('Modality #%g: %s', i, desc);
end
handles.selModal.String = popuplist;


