% Save the current directory
original_dir = pwd;

% Get the root directory (main directory)
rootDir = '/Users/claravetter/local/Code/NeuroMiner/NeuroMiner_Current'; % Replace with your main directory

% Generate include paths for all subdirectories
includePaths = genpath(rootDir);
includePathStr = strjoin(strsplit(includePaths, ':'), ' -I'); % For macOS and Linux
% includePathStr = strjoin(strsplit(includePaths, ';'), ' -I'); % For Windows

% List all C and CPP files
nm_cfiles = dir(fullfile(rootDir, '**/*.c'));
nm_cppfiles = dir(fullfile(rootDir, '**/*.cpp'));

% Initialize error tracking
error_count_nm_cfiles = 0;
errors_nm_cfiles = {};

% Compile C files
for i = 1:length(nm_cfiles)
    cur_c = nm_cfiles(i);
    fullpath = fullfile(cur_c.folder, cur_c.name);
    
    try
        % Compile the C file with include paths
        eval(sprintf('mex CFLAGS=''$CFLAGS -std=c99'' -I%s -largeArrayDims %s', includePathStr, fullpath));
    catch ME
        % Display and log the error
        disp(['Error compiling: ', fullpath]);
        disp(ME.message);
        error_count_nm_cfiles = error_count_nm_cfiles + 1;
        errors_nm_cfiles{error_count_nm_cfiles} = fullpath;
    end
end

% Initialize error tracking for CPP files
error_count_nm_cppfiles = 0;
errors_nm_cppfiles = {};

% Compile CPP files
for i = 1:length(nm_cppfiles)
    cur_cpp = nm_cppfiles(i);
    fullpath = fullfile(cur_cpp.folder, cur_cpp.name);
    
    try
        % Compile the CPP file with include paths
        eval(sprintf('mex CFLAGS=''$CFLAGS -std=c99'' -I%s -largeArrayDims %s', includePathStr, fullpath));
    catch ME
        % Display and log the error
        disp(['Error compiling: ', fullpath]);
        disp(ME.message);
        error_count_nm_cppfiles = error_count_nm_cppfiles + 1;
        errors_nm_cppfiles{error_count_nm_cppfiles} = fullpath;
    end
end

% Display a summary of the errors
disp(['Number of C files with errors: ', num2str(error_count_nm_cfiles)]);
disp('C files with errors:');
disp(errors_nm_cfiles);

disp(['Number of CPP files with errors: ', num2str(error_count_nm_cppfiles)]);
disp('CPP files with errors:');
disp(errors_nm_cppfiles);
