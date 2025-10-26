function rp = nk_RelPath(target, base)
    % nk_RelPath  Compute the relative path from a base directory to a target file or folder.
    %
    %   rp = nk_RelPath(target, base) returns the relative path from the folder
    %   specified by 'base' to the file or directory specified by 'target'.
    %
    %   Both 'target' and 'base' must be valid file or directory paths. The
    %   function resolves both paths to their absolute (canonical) forms before
    %   computing the relative path. It handles platform-specific path separators.
    %
    %   Inputs:
    %   -------
    %   target : char or string
    %       Absolute or relative path to the target file or folder.
    %
    %   base   : char or string
    %       Absolute or relative path to the base folder from which the relative
    %       path to 'target' will be computed.
    %
    %   Output:
    %   -------
    %   rp : char
    %       Relative path from 'base' to 'target', using platform-specific file
    %       separators (e.g., '\' on Windows, '/' on Unix). If the computed path
    %       does not already begin with '.' or a file separator, the function
    %       prepends './' or '.\' to clearly indicate that the path is relative.
    %
    %   Example:
    %   --------
    %       target = 'C:\Users\sergi\project\data\file.txt';
    %       base   = 'C:\Users\sergi\project';
    %       rp = nk_RelPath(target, base)
    %       % Returns: '.\data\file.txt'
    %
    %   Notes:
    %   ------
    %   - This function relies on Java's canonical path and NIO path libraries.
    %   - The function works on both Windows and Unix-based systems.
    %   - Symbolic links are resolved when calling getCanonicalPath().
    %
    %   See also: fullfile, fileparts, relpath (R2020b+), java.io.File, java.nio.file.Paths
    
    % Author: Sergio Mena
    % Date: August 2025

    % Convert to absolute canonical paths
    targetFile = java.io.File(target).getCanonicalFile();
    baseFile   = java.io.File(base).getCanonicalFile();

    % Break into path components
    targetParts = strsplit(char(targetFile.getPath()), filesep);
    baseParts   = strsplit(char(baseFile.getPath()), filesep);

    % Find common prefix length
    minLen = min(length(targetParts), length(baseParts));
    common = find(~strcmp(targetParts(1:minLen), baseParts(1:minLen)), 1) - 1;
    if isempty(common)
        common = minLen;
    end

    % Construct relative path
    upDirs = repmat({'..'}, 1, length(baseParts) - common);
    downDirs = targetParts(common+1:end);
    allParts = [upDirs, downDirs];

    if isempty(allParts)
        rp = '.';  % same directory
    else
        rp = strjoin(allParts, filesep);
    end

    % Prepend ./ for relative paths that don't start with . or ..
    if ~startsWith(rp, '.') && ~startsWith(rp, filesep)
        rp = ['.' filesep rp];
    end
end