function niiViewer = imagingMLI(casenum, APPstMLI, atlas_path, stats_path, brainmask, badcoords, datadescriptor)

y = MLIcont.Y_mapped(casenum,:)';
parent = APPstMLI.fig;
nk_WriteVol(y,'tempMLI', 2, brainmask, badcoords, datadescriptor.threshval, char(datadescriptor.threshop),[],[],false);
niiViewer = overlay_nifti_gui(atlas_path, 'tempMLI.nii', parent, 0.5);

end