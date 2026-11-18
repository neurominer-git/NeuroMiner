classdef NMResultsViewer3DVideoTools
% NMResultsViewer3DVideoTools
% Deterministic browser-frame spooling and MATLAB VideoWriter finalization
% for the shared NM Results Viewer 3-D Video Maker.

    methods (Static)
        function out = capabilities()
            profiles = {};
            if exist('VideoWriter','class') == 8 || exist('VideoWriter','file') == 2
                profiles = {'Motion JPEG AVI'};
                try
                    probe = VideoWriter([tempname '.mp4'],'MPEG-4'); %#ok<NASGU>
                    profiles{end+1} = 'MPEG-4';
                catch
                end
            end
            out = struct('ok',true,'operation','results_viewer_alpha_video_capabilities', ...
                'videoWriterAvailable',~isempty(profiles), ...
                'mp4',any(strcmp(profiles,'MPEG-4')), ...
                'avi',any(strcmp(profiles,'Motion JPEG AVI')), ...
                'profiles',{profiles},'contractVersion','G7B');
        end

        function out = prepare(tmpDir, req)
            spec = NMResultsViewer3DVideoTools.requestStruct(req,'videoSpec');
            outputPath = NMResultsViewer3DVideoTools.requestText(req,'outputPath','');
            if isempty(outputPath), error('NMResultsViewer3DVideoTools:OutputPath','A video output path is required.'); end
            frameCount = NMResultsViewer3DVideoTools.positiveInteger(spec,'frameCount',0,1e7);
            width = NMResultsViewer3DVideoTools.positiveInteger(spec,'width',0,16384);
            height = NMResultsViewer3DVideoTools.positiveInteger(spec,'height',0,16384);
            fps = NMResultsViewer3DVideoTools.positiveInteger(spec,'fps',30,120);
            format = lower(NMResultsViewer3DVideoTools.structText(spec,'format','mp4'));
            if ~any(strcmp(format,{'mp4','avi'})), error('NMResultsViewer3DVideoTools:Format','Unsupported video format: %s',format); end
            [folder,base,ext] = fileparts(outputPath);
            if isempty(folder), folder = pwd; outputPath = fullfile(folder,[base ext]); end
            if exist(folder,'dir') ~= 7, error('NMResultsViewer3DVideoTools:Folder','Output directory does not exist: %s',folder); end
            expectedExt = ['.' format];
            if isempty(ext), outputPath = [outputPath expectedExt]; elseif ~strcmpi(ext,expectedExt), error('NMResultsViewer3DVideoTools:Extension','Output extension must be %s.',expectedExt); end
            caps = NMResultsViewer3DVideoTools.capabilities();
            if strcmp(format,'mp4') && ~caps.mp4, error('NMResultsViewer3DVideoTools:Codec','MPEG-4 VideoWriter is unavailable in this MATLAB installation.'); end
            if strcmp(format,'avi') && ~caps.avi, error('NMResultsViewer3DVideoTools:Codec','Motion JPEG AVI VideoWriter is unavailable.'); end
            token = ['nmvideo_' lower(dec2hex(randi([0 2^31-1]),8)) '_' datestr(now,'yyyymmddTHHMMSSFFF')];
            token = regexprep(token,'[^A-Za-z0-9_-]','');
            spoolDir = fullfile(tmpDir,['video_' token]);
            if exist(spoolDir,'dir') == 7, rmdir(spoolDir,'s'); end
            mkdir(spoolDir);
            manifest = struct('kind','NMResultsViewer3DVideoSpool','schemaVersion',1,'contractVersion','G7B', ...
                'token',token,'frameCount',frameCount,'width',width,'height',height,'fps',fps,'format',format, ...
                'outputPath',outputPath,'maxFrameBytes',max(1048576,min(100*1024*1024,width*height*4)), ...
                'createdUtc',datestr(datetime('now','TimeZone','UTC'),'yyyy-mm-ddTHH:MM:SS.FFFZ'), ...
                'videoSpec',spec);
            NMSerializationTools.writeTextFile(fullfile(spoolDir,'manifest.json'), ...
                NMConfigTools.encodeJson(manifest,'imaging video spool manifest'), ...
                'NMResultsViewer3DVideoTools:Manifest','Could not write %s','fwrite-input-char');
            out = struct('ok',true,'operation','results_viewer_alpha_video_prepare','token',token, ...
                'frameCount',frameCount,'width',width,'height',height,'fps',fps,'format',format, ...
                'outputPath',outputPath,'uploadBase',['/api/results-viewer-video/' token '/frame/']);
        end

        function out = finalize(tmpDir, req)
            token = NMResultsViewer3DVideoTools.safeToken(NMResultsViewer3DVideoTools.requestText(req,'token',''));
            [spoolDir, manifest] = NMResultsViewer3DVideoTools.loadManifest(tmpDir,token);
            format = manifest.format;
            if strcmp(format,'mp4'), profile = 'MPEG-4'; else, profile = 'Motion JPEG AVI'; end
            writer = VideoWriter(char(manifest.outputPath),profile);
            writer.FrameRate = manifest.fps;
            open(writer);
            writerCleanup = onCleanup(@() NMResultsViewer3DVideoTools.closeWriterQuiet(writer)); %#ok<NASGU>
            for i = 0:manifest.frameCount-1
                framePath = fullfile(spoolDir,sprintf('frame_%08d.png',i));
                if exist(framePath,'file') ~= 2
                    error('NMResultsViewer3DVideoTools:MissingFrame','Missing video frame %d of %d.',i+1,manifest.frameCount);
                end
                rgb = imread(framePath);
                if size(rgb,1) ~= manifest.height || size(rgb,2) ~= manifest.width
                    error('NMResultsViewer3DVideoTools:FrameSize','Frame %d has size %dx%d; expected %dx%d.',i+1,size(rgb,2),size(rgb,1),manifest.width,manifest.height);
                end
                if size(rgb,3) == 4, rgb = rgb(:,:,1:3); end
                writeVideo(writer,rgb);
            end
            close(writer); clear writerCleanup;
            sidecar = manifest; sidecar.kind='NMResultsViewer3DVideoSpecification';sidecar.schemaVersion=1;sidecar.contractVersion='G7B';sidecar.completedUtc=datestr(datetime('now','TimeZone','UTC'),'yyyy-mm-ddTHH:MM:SS.FFFZ');
            [folder,base] = fileparts(char(manifest.outputPath)); sidecarPath = fullfile(folder,[base '.nm3dvideo.json']);
            NMSerializationTools.writeTextFile(sidecarPath,NMConfigTools.encodeJson(sidecar,'3-D video sidecar'), ...
                'NMResultsViewer3DVideoTools:Sidecar','Could not write %s','fwrite-input-char');
            roiSequencePath = '';
            if isfield(manifest.videoSpec,'roiSequence') && isstruct(manifest.videoSpec.roiSequence)
                roiSequencePath = fullfile(folder,[base '_roi_sequence.csv']);
                NMResultsViewer3DVideoTools.writeRoiSequenceCsv(roiSequencePath,manifest.videoSpec.roiSequence);
            end
            rmdir(spoolDir,'s');
            out = struct('ok',true,'operation','results_viewer_alpha_video_finalize', ...
                'message','3-D video encoded successfully.','outputPath',char(manifest.outputPath), ...
                'sidecarPath',sidecarPath,'roiSequencePath',roiSequencePath,'frameCount',manifest.frameCount,'fps',manifest.fps);
        end

        function out = cancel(tmpDir, req)
            token = NMResultsViewer3DVideoTools.safeToken(NMResultsViewer3DVideoTools.requestText(req,'token',''));
            spoolDir = fullfile(tmpDir,['video_' token]);
            if ~isempty(token) && exist(spoolDir,'dir') == 7, rmdir(spoolDir,'s'); end
            out = struct('ok',true,'operation','results_viewer_alpha_video_cancel','message','Video task cancelled and temporary frames removed.','token',token);
        end
    end

    methods (Static, Access=private)
        function [spoolDir, manifest] = loadManifest(tmpDir,token)
            if isempty(token), error('NMResultsViewer3DVideoTools:Token','A valid video task token is required.'); end
            spoolDir = fullfile(tmpDir,['video_' token]); root = char(java.io.File(tmpDir).getCanonicalPath()); candidate = char(java.io.File(spoolDir).getCanonicalPath());
            if ~startsWith([candidate filesep],[root filesep]) || exist(spoolDir,'dir') ~= 7
                error('NMResultsViewer3DVideoTools:Spool','Video spool does not exist.');
            end
            manifest = NMConfigTools.decodeJson(fileread(fullfile(spoolDir,'manifest.json')));
            if ~isstruct(manifest) || ~isfield(manifest,'kind') || ~strcmp(manifest.kind,'NMResultsViewer3DVideoSpool') || ~strcmp(char(manifest.token),token)
                error('NMResultsViewer3DVideoTools:Manifest','Invalid video spool manifest.');
            end
        end
        function token = safeToken(value), token = regexprep(char(value),'[^A-Za-z0-9_-]',''); end
        function value = requestText(req,name,default), value=default;if isstruct(req)&&isfield(req,name)&&~isempty(req.(name)),value=char(req.(name));end,end
        function value = requestStruct(req,name), value=struct();if isstruct(req)&&isfield(req,name)&&isstruct(req.(name))&&isscalar(req.(name)),value=req.(name);end,end
        function value = structText(s,name,default), value=default;if isstruct(s)&&isfield(s,name)&&~isempty(s.(name)),value=char(s.(name));end,end
        function n = positiveInteger(s,name,default,maxValue), n=default;if isstruct(s)&&isfield(s,name),n=double(s.(name));end;if ~isscalar(n)||~isfinite(n)||n<1||n>maxValue,error('NMResultsViewer3DVideoTools:Numeric','Invalid %s.',name);end;n=round(n);end

        function writeRoiSequenceCsv(pathValue, sequence)
            rows = struct([]);
            if isfield(sequence,'rois') && isstruct(sequence.rois), rows = sequence.rois; end
            fid = fopen(pathValue,'w');
            if fid < 0, error('NMResultsViewer3DVideoTools:ROICsv','Could not open ROI sequence CSV for writing: %s',pathValue); end
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid,'rank,roiId,roiName,rankingScore,elementCount,centroidX,centroidY,centroidZ,extentX,extentY,extentZ\n');
            for i = 1:numel(rows)
                row = rows(i);
                centroid = row.centroidWorldMm;
                extent = nan(1,3);
                if ~isempty(row.extentMm), extent = row.extentMm; end
                fprintf(fid,'%g,%s,%s,%.17g,%g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g\n', ...
                    row.rank, ...
                    NMResultsViewer3DVideoTools.csvText(row.roiId), ...
                    NMResultsViewer3DVideoTools.csvText(row.roiName), ...
                    row.rankingScore, ...
                    row.elementCount, ...
                    centroid(1),centroid(2),centroid(3),extent(1),extent(2),extent(3));
            end
        end
        function out = csvText(value)
            out = char(value);
            out = strrep(out,'"','""');
            out = ['"' out '"'];
        end
        function closeWriterQuiet(writer), try, close(writer); catch, end, end
    end
end
