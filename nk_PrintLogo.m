function nk_PrintLogo(maindlg)
global NMinfo EXPERT SPMAVAIL DEV

clc
if ~SPMAVAIL
    %cl = [0.1,0.5,0]; 
    mode = 'non-imaging mode';
else
    %cl = NMinfo.cllogo; 
    mode = [];
end
if exist('maindlg','var') && maindlg
    fprintf('\n  _   _                      __  __ _                 ');
    fprintf('\n | \\ | | ___ _   _ _ __ ___ |  \\/  (_)_ __   ___ _ __ ');
    fprintf('\n |  \\| |/ _ | | | | ''__/ _ \\| |\\/| | | ''_ \\ / _ | ''__|');
    fprintf('\n | |\\  |  __| |_| | | | (_) | |  | | | | | |  __| |   ');
    fprintf('\n |_| \\_|\\___|\\__,_|_|  \\___/|_|  |_|_|_| |_|\\___|_|   ');
    fprintf('\n  ___________________________________________________');
    fprintf('\n |  >>> Machine Learning for Precision Medicine <<<  |');
    fprintf('\n  ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾');                                                     
    if ~isempty(mode),fprintf('\n%s',mode);end
else
    fprintf('\t~~~~~~~~~~~~~~~~~~~~~~~ \n');
    fprintf('\t  N e u r o M i n e r \n');
    fprintf('\t~~~~~~~~~~~~~~~~~~~~~~~ ');
end
if EXPERT
    fprintf('\n  >>> EXPERT MODE <<< ')
end
if DEV
    fprintf('\n  >>> DEVELOPMENT MODE <<<')
end
fprintf('\n  %s', NMinfo.info.ver); fprintf('\n')
if exist('maindlg','var') && maindlg
    fprintf('\n  (c) %s | %s ', NMinfo.info.author, NMinfo.info.datever)
    fprintf('\n  nm@pronia.eu \n')
end