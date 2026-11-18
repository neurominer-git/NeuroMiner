function installed = nm2_install_chromium_shell(nmRoot, downloadSource, expectedSHA256)
%NM2_INSTALL_CHROMIUM_SHELL Optional PDF-renderer installer for this MATLAB host.
%   nm2_install_chromium_shell              % installer placed in the NM2 root
%   nm2_install_chromium_shell(nmRoot)       % automatic official download
%   nm2_install_chromium_shell(nmRoot, 'https://.../shell.zip')
%   nm2_install_chromium_shell(nmRoot, '/path/to/shell.zip')
%   nm2_install_chromium_shell(nmRoot, source, trustedSHA256)
%
% The optional downloadSource accepts an HTTPS URL or a local ZIP file.
% expectedSHA256, when supplied independently from a trusted source, checks
% archive integrity. Neither a version string nor a matching ZIP layout
% authenticates a custom source without a trusted checksum.
% Nothing downloads automatically during NM2 report export.

if nargin < 1 || isempty(nmRoot)
    nmRoot = fileparts(mfilename('fullpath'));
end
if nargin < 2, downloadSource = ''; end
if nargin < 3, expectedSHA256 = ''; end
nmRoot = char(nmRoot);
downloadSource = char(downloadSource);
expectedSHA256 = lower(char(expectedSHA256));
if ~isempty(expectedSHA256) && isempty(regexp(expectedSHA256,'^[0-9a-f]{64}$','once'))
    error('NM2:ChromiumInstall:Checksum','Expected SHA-256 must contain exactly 64 hexadecimal characters.');
end
if ~isfile(fullfile(nmRoot,'core','NMResultsViewerReportTools.m'))
    error('NM2:ChromiumInstall:Root', ...
        'Select the NM2 root containing core/NMResultsViewerReportTools.m.');
end
switch computer('arch')
    case 'win64',       platform = 'win64';
    case 'win32',       platform = 'win32';
    case 'maci64',      platform = 'mac-x64';
    case 'maca64',      platform = 'mac-arm64';
    case 'glnxa64',     platform = 'linux64';
    case 'glnxaarch64', platform = 'linux-arm64';
    otherwise
        error('NM2:ChromiumInstall:Platform', ...
            'No Headless Shell package for MATLAB architecture %s.', computer('arch'));
end
version = '157.0.8103.50';
bundle = ['chrome-headless-shell-' platform];
exeName = 'chrome-headless-shell';
if ispc, exeName = [exeName '.exe']; end
assetRoot = fullfile(nmRoot,'thirdparty','chrome-headless-shell',platform);
finalDir = fullfile(assetRoot,bundle);
executable = fullfile(finalDir,exeName);
if isfile(executable)
    [status,out] = system(['"' executable '" --version']);
    if status ~= 0 || ~contains(out,version)
        error('NM2:ChromiumInstall:ExistingInvalid', ...
            'An existing renderer is incompatible or cannot execute: %s. Inspect it before replacing.',strtrim(out));
    end
    fprintf('Chrome Headless Shell %s is already installed: %s\n',version,executable);
    installed = struct('platform',platform,'version',version,'executable',executable,'alreadyInstalled',true);
    return;
end
if isfolder(finalDir)
    error('NM2:ChromiumInstall:PartialInstall', ...
        'A partial package already exists at %s. Inspect/remove it before installation.',finalDir);
end
if ~isfolder(assetRoot), mkdir(assetRoot); end
stage = tempname(assetRoot);
mkdir(stage);
cleanup = onCleanup(@() rmdir(stage,'s')); %#ok<NASGU>
archive = fullfile(stage,[bundle '.zip']);
if isempty(downloadSource)
    % Resolve the PINNED version from the official, versioned download manifest.
    manifestURL = 'https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json';
    try
        manifest = webread(manifestURL,weboptions('Timeout',60));
        versions = manifest.versions;
        versionIndex = find(strcmp({versions.version},version),1);
        if isempty(versionIndex)
            error('NM2:ChromiumInstall:VersionNotListed','Pinned version %s is absent from the official manifest.',version);
        end
        key = matlab.lang.makeValidName('chrome-headless-shell');
        downloads = versions(versionIndex).downloads.(key);
        platformIndex = find(strcmp({downloads.platform},platform),1);
        if isempty(platformIndex)
            error('NM2:ChromiumInstall:PlatformNotListed','The official manifest has no %s package for %s.',platform,version);
        end
        downloadSource = downloads(platformIndex).url;
        if ~startsWith(downloadSource,'https://')
            error('NM2:ChromiumInstall:ManifestURL','The official manifest returned a non-HTTPS URL.');
        end
    catch cause
        error('NM2:ChromiumInstall:Manifest', ...
            ['Could not resolve the official Chromium download: %s\n' ...
             'Retry with nm2_install_chromium_shell(nmRoot, alternateHttpsURL) or a local ZIP.'],cause.message);
    end
else
    if isempty(expectedSHA256)
        warning('NM2:ChromiumInstall:CustomSourceUnverified', ...
            ['A custom download source has no independently verified SHA-256. ' ...
             'Only use a source you trust; ZIP layout and --version are not authenticity checks.']);
    end
end
if startsWith(lower(downloadSource),'https://')
    fprintf('Downloading Chrome Headless Shell %s (%s):\n%s\n',version,platform,downloadSource);
    try
        websave(archive,downloadSource,weboptions('Timeout',900));
    catch cause
        error('NM2:ChromiumInstall:Download', ...
            ['Download failed: %s\n' ...
             'Retry with nm2_install_chromium_shell(nmRoot, alternateHttpsURL) or a local ZIP.'],cause.message);
    end
elseif contains(downloadSource,'://')
    error('NM2:ChromiumInstall:Transport','Only HTTPS download URLs or local ZIP paths are supported.');
elseif isfile(downloadSource)
    archive = downloadSource;
else
    error('NM2:ChromiumInstall:Archive','Download source is not an HTTPS URL or readable local ZIP: %s',downloadSource);
end
if ~isempty(expectedSHA256)
    actualSHA256 = localSHA256(archive);
    if ~strcmp(actualSHA256,expectedSHA256)
        error('NM2:ChromiumInstall:ChecksumMismatch', ...
            'Archive SHA-256 differs from the expected trusted checksum. Aborting installation.');
    end
end
localCheckZipEntries(archive,bundle);
unzip(archive,stage);
stagedExe = fullfile(stage,bundle,exeName);
if ~isfile(stagedExe)
    error('NM2:ChromiumInstall:Content','Expected executable is absent: %s',stagedExe);
end
if ~ispc
    [ok,msg] = fileattrib(stagedExe,'+x','a');
    if ~ok
        error('NM2:ChromiumInstall:Permission','Unable to set executable permission: %s',msg);
    end
end
[status,out] = system(['"' stagedExe '" --version']);
if status ~= 0 || ~contains(out,version)
    error('NM2:ChromiumInstall:SmokeTest', ...
        'This host cannot execute the expected Chromium %s binary: %s',version,strtrim(out));
end
[ok,msg] = movefile(fullfile(stage,bundle),finalDir);
if ~ok
    error('NM2:ChromiumInstall:Move','Could not install Chromium: %s',msg);
end
fprintf('Installed Chrome Headless Shell %s for %s:\n%s\nRetry PDF export in NM2.\n',version,platform,executable);
installed = struct('platform',platform,'version',version,'executable',executable,'alreadyInstalled',false);
end

function localCheckZipEntries(archive,bundle)
% Reject unexpected folders, traversal and oversized archives before unzip.
z = java.util.zip.ZipFile(java.io.File(archive));
cleanup = onCleanup(@() z.close()); %#ok<NASGU>
entries = z.entries();
bytes = 0;
count = 0;
while entries.hasMoreElements()
    e = entries.nextElement();
    name = char(e.getName());
    count = count + 1;
    sizeBytes = double(e.getSize());
    if ~startsWith(name,[bundle '/']) || contains(name,'\') || ...
            ~isempty(regexp(name,'(^|/)\.\.(/|$)','once')) || sizeBytes < 0
        error('NM2:ChromiumInstall:UnsafeArchive','Invalid ZIP member: %s',name);
    end
    bytes = bytes + sizeBytes;
    if bytes > 2e9 || count > 100000
        error('NM2:ChromiumInstall:UnsafeArchive','ZIP expanded size or entry count exceeds the installation limit.');
    end
end
if count == 0
    error('NM2:ChromiumInstall:EmptyArchive','ZIP contains no package files.');
end
end

function digest = localSHA256(archive)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(archive,'rb');
if fid < 0
    error('NM2:ChromiumInstall:ArchiveRead','Cannot read ZIP for checksum: %s',archive);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
while true
    block = fread(fid,1048576,'*int8');
    if isempty(block), break; end
    md.update(block);
end
bytes = typecast(int8(md.digest()),'uint8');
digest = lower(reshape(dec2hex(bytes,2).',1,[]));
end
