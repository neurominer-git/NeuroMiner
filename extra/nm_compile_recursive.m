function nm_compile_recursive(rootDir)
% =========================================================================
% function nm_compile_recursive(rootDir)
% -------------------------------------------------------------------------
% Description:
%   Recursively finds and compiles all .c and .cpp files within rootDir
%   for use with NeuroMiner. This is an automated version of the
%   original nk_make.
%
% Inputs:
%   rootDir     :   The root directory of the NeuroMiner project.
%                   If not provided, the current directory is used.
%
% =========================================================================
% (c) Nikolaos Koutsouleris 01/2017
% (updated by Gemini 2025)
% =========================================================================

    if nargin < 1
        rootDir = pwd;
        fprintf('No rootDir provided, using current directory: %s\n', rootDir);
    else
        if ~isfolder(rootDir)
            error('Specified rootDir does not exist: %s', rootDir);
        end
    end

    % --- 1. Generate Include Paths ---
    fprintf('Generating include paths from: %s\n', rootDir);
    allPaths = genpath(rootDir);
    pathList = strsplit(allPaths, pathsep);
    
    % Remove empty strings (e.g., from trailing pathsep)
    pathList = pathList(~cellfun('isempty', pathList)); 
    
    % Format as '-I<path>' arguments for mex
    includeArgs = cellfun(@(p) ['-I' p], pathList, 'UniformOutput', false);
    fprintf('Found %d directories to include.\n', numel(includeArgs));

    % --- 2. Find C and CPP Files ---
    fprintf('Searching for C/CPP files...\n');
    c_files = dir(fullfile(rootDir, '**', '*.c'));
    cpp_files = dir(fullfile(rootDir, '**', '*.cpp'));
    fprintf('Found %d .c files and %d .cpp files.\n', length(c_files), length(cpp_files));
    
    % --- 3. Compile C Files ---
    error_count_c = 0;
    errors_c = {};
    fprintf('\n--- Compiling C Files ---\n');
    for i = 1:length(c_files)
        cur_c = c_files(i);
        fullpath = fullfile(cur_c.folder, cur_c.name);
        fprintf('Compiling C: %s\n', fullpath);
        
        try
            % Get existing CFLAGS from environment and append C99 standard
            % This avoids mex interpreting '$CFLAGS' as a literal string
            cflags_env = getenv('CFLAGS');
            if isempty(cflags_env)
                cflags_arg = 'CFLAGS=-std=c99';
            else
                % Append new flag to existing ones
                cflags_arg = ['CFLAGS=' cflags_env ' -std=c99'];
            end
            
            % Compile C file with C99 standard and include paths
            % The CFLAGS="...flags..." part must be a single argument
            mex(cflags_arg, '-largeArrayDims', includeArgs{:}, fullpath);
            
        catch ME
            % Display and log the error
            warning('Error compiling: %s\n%s', fullpath, ME.message);
            error_count_c = error_count_c + 1;
            errors_c{end+1} = fullpath;
        end
    end

    % --- 4. Compile CPP Files ---
    error_count_cpp = 0;
    errors_cpp = {};
    fprintf('\n--- Compiling CPP Files ---\n');
    for i = 1:length(cpp_files)
        cur_cpp = cpp_files(i);
        fullpath = fullfile(cur_cpp.folder, cur_cpp.name);
        fprintf('Compiling CPP: %s\n', fullpath);
        
        try
            % Get existing CXXFLAGS from environment and append C++11 standard
            % This avoids mex interpreting '$CXXFLAGS' as a literal string
            cxxflags_env = getenv('CXXFLAGS');
            if isempty(cxxflags_env)
                cxxflags_arg = 'CXXFLAGS=-std=c++11';
            else
                % Append new flag to existing ones
                cxxflags_arg = ['CXXFLAGS=' cxxflags_env ' -std=c++11'];
            end
            
            % Compile CPP file with C++11 standard and include paths
            % The CXXFLAGS="...flags..." part must be a single argument
            mex(cxxflags_arg, '-largeArrayDims', includeArgs{:}, fullpath);
        catch ME
            % Display and log the error
            warning('Error compiling: %s\n%s', fullpath, ME.message);
            error_count_cpp = error_count_cpp + 1;
            errors_cpp{end+1} = fullpath;
        end
    end

    % --- 5. Display Summary ---
    fprintf('\n--- Compilation Summary ---\n');
    if error_count_c == 0
        fprintf('Successfully compiled all %d C files.\n', length(c_files));
    else
        fprintf('Number of C files with errors: %d\n', error_count_c);
        fprintf('C files with errors:\n');
        for k = 1:length(errors_c), fprintf('  %s\n', errors_c{k}); end
    end
    
    if error_count_cpp == 0
        fprintf('Successfully compiled all %d CPP files.\n', length(cpp_files));
    else
        fprintf('Number of CPP files with errors: %d\n', error_count_cpp);
        fprintf('CPP files with errors:\n');
        for k = 1:length(errors_cpp), fprintf('  %s\n', errors_cpp{k}); end
    end
    fprintf('-----------------------------\n');

end

