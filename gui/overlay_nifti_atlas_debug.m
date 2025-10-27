function overlay_nifti_atlas_debug(structFile, atlasFile, lutFile)
% overlay_nifti_atlas_debug: Overlay atlas on structural and clickable region lookup
%   overlay_nifti_atlas_debug(structFile, atlasFile, lutFile)
%   - Reslices atlas → structural space (nearest-neighbour)
%   - Displays axial, sagittal, coronal mid-slices with 50% atlas α
%   - Adds click callback: print region name/code at clicked voxel
%   - Requires: SPM12 and a LUT text file (tab-delimited: index\tname)

    % 1) Reslice atlas to structural grid
    [pAT,nAT,eAT] = fileparts(atlasFile);
    rAtlas = fullfile(pAT, ['r' nAT eAT]);
    if ~exist(rAtlas,'file')
        flags = struct('interp',0,'which',1,'mean',0);
        spm_reslice(char(structFile, atlasFile), flags);
    end

    % 2) Load volumes
    Vs = spm_vol(structFile); S = spm_read_vols(Vs);
    Vt = spm_vol(rAtlas);      T0 = spm_read_vols(Vt);
    T  = T0 * Vt.pinfo(1) + Vt.pinfo(2);

    % 3) Mid-slices & dims
    dims   = Vs.dim;
    si_ax  = round(dims(3)/2);
    si_sag = round(dims(1)/2);
    si_cor = round(dims(2)/2);

    % 4) Load LUT if provided
    useLUT = nargin>=3 && exist(lutFile,'file');
    if useLUT
        TT = readtable(lutFile,'Delimiter','\t','ReadVariableNames',false,'Format','%f%s');
        lut = containers.Map(TT.Var1, TT.Var2);
    else
        lut = []; % no LUT
    end

    % 5) Setup figure
    fig = figure('Name','Debug Overlay','NumberTitle','off','Color','w');
    colormap gray;
    views = {'axial','sagittal','coronal'};
    sliceIdxs = [si_ax, si_sag, si_cor];
    hAxes = gobjects(1,3);

    for v=1:3
        ax = subplot(1,3,v);
        hold(ax,'on'); axis(ax,'image','off');
        switch v
            case 1 % axial
                A = squeeze(S(:,:,si_ax)); B = squeeze(T(:,:,si_ax));
            case 2 % sagittal
                A = squeeze(S(si_sag,:,:))'; B = squeeze(T(si_sag,:,:))';
            case 3 % coronal
                A = squeeze(S(:,si_cor,:))'; B = squeeze(T(:,si_cor,:))';
        end
        hA = imagesc(A,'Parent',ax); % background
        set(hA,'HitTest','off','PickableParts','none');
        hB = imagesc(B,'Parent',ax); set(hB,'AlphaData',0.5);
        set(hB,'HitTest','off','PickableParts','none');
        title(ax,sprintf('%s slice %d',views{v}, sliceIdxs(v)),'FontWeight','bold');
        % attach click callback to axes
        set(ax,'ButtonDownFcn',{@onClick,views{v},sliceIdxs(v),dims,T,useLUT,lut});
        hAxes(v) = ax;
    end
    % now set a single global click handler on the figure
    fig.WindowButtonDownFcn = @(~,~)onGlobalClick();

    % … later, nested in your function …
    function onGlobalClick()
        % find the object under the mouse
        h = hittest(fig);
        % if it’s one of our axes (or a child of it), handle it
        ax = ancestor(h,'axes');
        [tf, idx] = ismember(ax, hAxes);   % tf = true if ax is in hAxes
        if ~tf, return; end                % click wasn’t in one of our subplots
    
        % get view & slice idx
        view     = views{idx};
        sliceIdx = sliceIdxs(idx);
    
        % pixel coords in that axes
        pt = ax.CurrentPoint; 
        row = round(pt(1,2)); 
        col = round(pt(1,1));
        if row<1||col<1, return; end
    
        % map pixel → voxel (exactly as before)
        switch view
          case 'axial'
            i = col;    j = row;            k = sliceIdx;
          case 'sagittal'
            i = sliceIdx; j = col;          k = dims(3)-row+1;
          case 'coronal'
            i = col;     j = sliceIdx;      k = dims(3)-row+1;
        end
        if any([i j k]<1) || i>dims(1)||j>dims(2)||k>dims(3), return; end
    
        % read atlas code directly from T
        code = round(T(i,j,k));
        if code==0
            fprintf('Clicked outside atlas region.\n');
            return;
        end
    
        % look up name
        if lut.isKey(code)
          name = lut(code);
        else
          name = sprintf('Code %d',code);
        end
    
        fprintf('Clicked %s: region %s (code=%d) at voxel [%d %d %d]\\n', ...
                view, name, code, i, j, k);
    end
end
