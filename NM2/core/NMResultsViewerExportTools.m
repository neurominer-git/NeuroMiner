classdef NMResultsViewerExportTools
% NMResultsViewerExportTools
% -------------------------------------------------------------------------
% Generic Results Viewer artifact validation and export utilities.
% Every viewer/reporter/exporter path consumes the same versioned browser
% artifact. MATLAB validates and writes it; it never reconstructs a view.
% -------------------------------------------------------------------------

    methods (Static)
        function out = exportArtifactRequest(req, tmpDir) %#ok<INUSD>
            % EXPORTARTIFACTREQUEST  Write one versioned browser artifact.
            [artifact, exportSpec] = NMResultsViewerExportTools.requestArtifact(req);
            [ok, message, artifact] = NMResultsViewerExportTools.validateArtifact(artifact);
            if ~ok
                out = struct('ok',false,'message',message,'format','','path','');
                return;
            end
            fmt = lower(strtrim(NMSerializationTools.textField(exportSpec, 'format', '')));
            if strcmp(artifact.kind,'table')
                out = NMResultsViewerTableExportTools.writeArtifact(artifact, exportSpec);
                return;
            end
            if ~ismember(fmt, {'svg','png','pdf'})
                out = struct('ok',false,'message','Visual artifact export requires SVG, PNG, or PDF format.', ...
                    'format',fmt,'path','');
                return;
            end
            outDir = NMSerializationTools.textField(exportSpec, 'outputDirectory', '');
            if isempty(outDir) || exist(outDir, 'dir') ~= 7
                out = struct('ok',false,'message','No valid export directory was provided by the browser path dialog.', ...
                    'format',fmt,'path','');
                return;
            end
            panelKind = NMSerializationTools.sanitizeToken(NMSerializationTools.textField(artifact, 'representationId', 'view'), 'plot');
            resultKind = NMSerializationTools.sanitizeToken(NMSerializationTools.textField(exportSpec, 'resultKind', 'results'), 'plot');
            analysisIndex = NMSerializationTools.textField(exportSpec, 'analysisIndex', '0');
            analysisText = NMSerializationTools.sanitizeToken(['A' regexprep(analysisIndex, '^A', '')], 'plot');
            stamp = datestr(now, 'yyyymmdd_HHMMSS');
            defaultBase = sprintf('NM_%s_%s_%s_%s', analysisText, resultKind, panelKind, stamp);
            outPath = NMSerializationTools.uniqueOutputPath(outDir, defaultBase, fmt);
            if strcmp(fmt,'svg')
                svgText = NMSerializationTools.textField(artifact, 'svgText', '');
                if isempty(strtrim(svgText))
                    out = struct('ok',false,'message','The artifact does not contain serialized SVG output.', ...
                        'format',fmt,'path','');
                    return;
                end
                NMSerializationTools.writeTextUtf8(outPath, svgText);
            else
                dataUrl = NMSerializationTools.textField(artifact, 'dataUrl', '');
                if isempty(dataUrl)
                    out = struct('ok',false,'message','The artifact does not contain rendered image bytes.', ...
                        'format',fmt,'path','');
                    return;
                end

                [bytes, mime] = NMSerializationTools.decodeDataUrl(dataUrl);
                if isempty(bytes)
                    out = struct('ok',false,'message','The browser export payload did not contain decodable image bytes.', ...
                        'format',fmt,'path','');
                    return;
                end

                if strcmp(fmt,'png')
                    if ~contains(lower(mime), 'png')
                        out = struct('ok',false,'message','PNG export received a non-PNG browser payload.', ...
                            'format',fmt,'path','');
                        return;
                    end
                    NMSerializationTools.writeBytes(outPath, bytes);
                else
                    if ~contains(lower(mime), 'jpeg') && ~contains(lower(mime), 'jpg')
                        out = struct('ok',false,'message','PDF export requires the browser-rendered JPEG payload.', ...
                            'format',fmt,'path','');
                        return;
                    end
                    w = NMSerializationTools.numericField(artifact, 'width', 0);
                    h = NMSerializationTools.numericField(artifact, 'height', 0);
                    if ~(isfinite(w) && isfinite(h) && w > 0 && h > 0)
                        out = struct('ok',false,'message','PDF export received invalid image dimensions.', ...
                            'format',fmt,'path','');
                        return;
                    end
                    NMResultsViewerExportTools.writeJpegPdf(bytes, round(w), round(h), outPath);
                end
            end

            out = struct('ok',true,'message',sprintf('Results Viewer artifact exported to %s.', outPath), ...
                'format',fmt,'path',outPath);
        end

        function [artifact, exportSpec] = requestArtifact(req)
            % REQUESTARTIFACT  Extract the only accepted public export request.
            artifact = struct(); exportSpec = struct();
            if ~isstruct(req), return; end
            if isfield(req,'artifact') && isstruct(req.artifact), artifact = req.artifact; end
            if isfield(req,'export') && isstruct(req.export), exportSpec = req.export; end
        end

        function [ok, message, artifact] = validateArtifact(artifact)
            % VALIDATEARTIFACT  Validate the cross-viewer artifact envelope.
            ok = false; message = '';
            if ~isstruct(artifact) || ~isscalar(artifact)
                message = 'A scalar NMResultsViewerArtifact is required.'; return;
            end
            if ~strcmp(NMSerializationTools.textField(artifact,'schema',''),'NMResultsViewerArtifact') || ...
                    NMSerializationTools.numericField(artifact,'schemaVersion',0) ~= 1
                message = 'Unsupported Results Viewer artifact schema or version.'; return;
            end
            kind = lower(NMSerializationTools.textField(artifact,'kind',''));
            if ~ismember(kind, {'visual','table'})
                message = 'Results Viewer artifact kind must be visual or table.'; return;
            end
            if isempty(NMSerializationTools.textField(artifact,'representationId',''))
                message = 'Results Viewer artifact representationId is required.'; return;
            end
            if strcmp(kind,'visual')
                mime = lower(NMSerializationTools.textField(artifact,'mediaType',''));
                if ~ismember(mime, {'image/png','image/jpeg','image/svg+xml'})
                    message = 'Unsupported Results Viewer visual artifact media type.'; return;
                end
                if strcmp(mime,'image/svg+xml')
                    svg = NMSerializationTools.textField(artifact,'svgText','');
                    if isempty(regexp(svg, '^\s*<svg[\s>]', 'once')) || ~isempty(regexpi(svg, '<script|\son\w+\s*=', 'once'))
                        message = 'Results Viewer SVG artifact is empty or contains active content.'; return;
                    end
                else
                    dataUrl = NMSerializationTools.textField(artifact,'dataUrl','');
                    expected = ['^data:' regexptranslate('escape',mime) ';base64,'];
                    if isempty(regexp(dataUrl,expected,'once'))
                        message = 'Results Viewer image artifact has no matching base64 data URL.'; return;
                    end
                end
            end
            artifact.kind = kind;
            ok = true;
        end

        function html = artifactHtml(artifact)
            % ARTIFACTHTML  Embed an already-rendered artifact in report HTML.
            [ok, message, artifact] = NMResultsViewerExportTools.validateArtifact(artifact);
            if ~ok, error('NMResultsViewerExportTools:invalidArtifact','%s',message); end
            if ~strcmp(artifact.kind,'visual')
                error('NMResultsViewerExportTools:nonVisualArtifact','Report figure output requires a visual artifact.');
            end
            title = NMSerializationTools.textField(artifact,'title','Results Viewer output');
            title = strrep(strrep(strrep(title,'&','&amp;'),'<','&lt;'),'>','&gt;');
            if strcmp(NMSerializationTools.textField(artifact,'mediaType',''),'image/svg+xml')
                bytes = unicode2native(NMSerializationTools.textField(artifact,'svgText',''),'UTF-8');
                src = ['data:image/svg+xml;base64,' char(matlab.net.base64encode(bytes(:)))];
            else
                src = NMSerializationTools.textField(artifact,'dataUrl','');
            end
            metadataHtml = '';
            if isfield(artifact,'metadata') && isstruct(artifact.metadata) && isfield(artifact.metadata,'presentation') && isstruct(artifact.metadata.presentation) && isfield(artifact.metadata.presentation,'lines')
                rawLines = artifact.metadata.presentation.lines;
                if ischar(rawLines), rawLines = {rawLines}; elseif isstring(rawLines), rawLines = cellstr(rawLines(:)); end
                if iscell(rawLines)
                    lineHtml = {};
                    for ii = 1:numel(rawLines)
                        line = char(string(rawLines{ii}));
                        if isempty(strtrim(line)) || strcmp(line, title), continue; end
                        line = strrep(strrep(strrep(line,'&','&amp;'),'<','&lt;'),'>','&gt;');
                        lineHtml{end+1} = ['<span>' line '</span>']; %#ok<AGROW>
                    end
                    if ~isempty(lineHtml)
                        metadataHtml = ['<div class="rvReportViewerMetadata">' strjoin(lineHtml,'') '</div>'];
                    end
                end
            end
            html = sprintf('<figure class="rvReportViewerArtifact"><img src="%s" alt="%s"><figcaption>%s</figcaption></figure>%s',src,title,title,metadataHtml);
        end

        function writeJpegPdf(jpegBytes, w, h, pdfPath)
            % WRITEJPEGPDF  Embed a browser-rendered JPEG into a single-page PDF.
            %
            %   NMResultsViewerExportTools.writeJpegPdf(jpegBytes, w, h, pdfPath)
            %   writes a minimal PDF containing one JPEG image scaled to an A4
            %   page. The browser supplies rasterization; MATLAB only packages
            %   the already-rendered JPEG bytes.
            if isempty(jpegBytes)
                error('NMResultsViewerExportTools:emptyJpeg', 'Cannot write an empty JPEG payload to PDF.');
            end
            if w >= h
                pageW = 842; pageH = 595; % A4 landscape in points
            else
                pageW = 595; pageH = 842; % A4 portrait in points
            end
            margin = 24;
            sc = min((pageW - 2*margin) / double(w), (pageH - 2*margin) / double(h));
            drawW = double(w) * sc; drawH = double(h) * sc;
            x0 = (pageW - drawW) / 2; y0 = (pageH - drawH) / 2;
            content = sprintf('q %.4f 0 0 %.4f %.4f %.4f cm /Im1 Do Q\n', drawW, drawH, x0, y0);

            objects = cell(1,5);
            objects{1} = uint8(sprintf('1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'));
            objects{2} = uint8(sprintf('2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'));
            objects{3} = uint8(sprintf(['3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.4f %.4f] ', ...
                '/Resources << /XObject << /Im1 4 0 R >> >> /Contents 5 0 R >>\nendobj\n'], pageW, pageH));
            header4 = uint8(sprintf(['4 0 obj\n<< /Type /XObject /Subtype /Image /Width %d /Height %d ', ...
                '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length %d >>\nstream\n'], w, h, numel(jpegBytes)));
            objects{4} = [header4 uint8(jpegBytes(:)') uint8(sprintf('\nendstream\nendobj\n'))];
            cbytes = uint8(content);
            objects{5} = uint8(sprintf('5 0 obj\n<< /Length %d >>\nstream\n%s\nendstream\nendobj\n', numel(cbytes), content));

            pdf = uint8(sprintf('%%PDF-1.4\n%%'));
            pdf = [pdf uint8([226 227 207 211]) uint8(newline)]; %#ok<AGROW>
            offsets = zeros(1, numel(objects));
            for i = 1:numel(objects)
                offsets(i) = numel(pdf);
                pdf = [pdf objects{i}]; %#ok<AGROW>
            end
            xrefStart = numel(pdf);
            xref = sprintf('xref\n0 %d\n0000000000 65535 f \n', numel(objects)+1);
            for i = 1:numel(objects)
                xref = [xref sprintf('%010d 00000 n \n', offsets(i))]; %#ok<AGROW>
            end
            trailer = sprintf('trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n', numel(objects)+1, xrefStart);
            pdf = [pdf uint8(xref) uint8(trailer)];
            NMSerializationTools.writeBytes(pdfPath, pdf);
        end
    end
end
