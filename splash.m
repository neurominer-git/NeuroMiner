function varargout = splash(varargin)
%SPLASH  Creates a splash screen without using im2java.
%   SPLASH(FILENAME,FMT,TIME) creates a splash screen using the image from the
%   file specified by the string FILENAME, where the string FMT specifies
%   the format of the file and TIME is the duration time of the splash
%   screen in millisecond.
%   SPLASH(FILENAME,FMT) uses default TIME=3s.
%   HSPLASH = SPLASH(...) returns the javax.swing.JWindow handle.
%   SPLASH(HSPLASH,'off') closes the splash screen.

% Parse inputs and handle 'off' call
if nargout >= 2
    error('MATLAB:splash','Too many output arguments.');
end
[filename, format, time, handle, msg] = parse_inputs(varargin{:});
if ~isempty(msg)
    error('MATLAB:splash:inputParsing','%s',msg);
end
if ~isempty(handle)
    handle.dispose();
    return;
end

% Load image
try
    fullName = filename;
    if ~isempty(format)
        fullName = strcat(filename, '.', format);
    end
    I = imread(fullName);
catch ME
    error('MATLAB:splash:imread','%s', ME.message);
end

% Ensure uint8 RGB data
if size(I,3)==1
    I = repmat(I, [1 1 3]);
end
if ~isa(I,'uint8')
    I = im2uint8(I);
end

% Build a Java BufferedImage using TYPE_INT_RGB and setRGB
[h, w, ~] = size(I);
BI = java.awt.image.BufferedImage(w, h, java.awt.image.BufferedImage.TYPE_INT_RGB);
% Pack R, G, B into single int: (R << 16) | (G << 8) | B
R = uint32(I(:,:,1));
G = uint32(I(:,:,2));
B = uint32(I(:,:,3));
pixelData = bitshift(R,16) + bitshift(G,8) + B;
% Transpose to row-major order for setRGB
pixelData = pixelData';
intArr = int32(pixelData(:));
BI.setRGB(0, 0, w, h, intArr, 0, w);

% Create splash screen window
win = javax.swing.JWindow;
icon = javax.swing.ImageIcon(BI);
label = javax.swing.JLabel(icon);
win.getContentPane.add(label);
win.setAlwaysOnTop(true);
win.pack();

% Center on screen
screenSize = win.getToolkit.getScreenSize();
sWidth = screenSize.width;
sHeight = screenSize.height;
iWidth = icon.getIconWidth();
iHeight = icon.getIconHeight();
win.setLocation((sWidth - iWidth)/2, (sHeight - iHeight)/2);

% Show window
win.setVisible(true);

% Return handle if requested
if nargout == 1
    varargout{1} = win;
    warning('MATLAB:splash','Input duration time is discarded. Use SPLASH(handle,''off'') to close it');
    time = [];
end

% Control duration and fade out
if ~isempty(time)
    pause(time/1000);
    fadeout(win, 2500, false);
end
end

%% Helper: input parsing
function [filename, format, time, handle, msg] = parse_inputs(varargin)
filename = '';
format   = '';
time     = 3000;
handle   = [];
msg      = '';
switch numel(varargin)
    case 1
        filename = varargin{1};
    case 2
        in1 = varargin{1}; in2 = varargin{2};
        if ischar(in1) && ischar(in2)
            filename = in1; format = in2;
        elseif ischar(in1) && isnumeric(in2)
            filename = in1; time = in2;
        elseif isjava(in1) && isequal(in2,'off')
            handle = in1;
        else
            msg = 'Input type mismatch.';
        end
    case 3
        in1 = varargin{1}; in2 = varargin{2}; in3 = varargin{3};
        if ischar(in1) && ischar(in2) && isnumeric(in3)
            filename = in1; format = in2; time = in3;
        else
            msg = 'Input type mismatch.';
        end
    otherwise
        msg = 'Invalid number of inputs.';
end
end

%% Helper: fade out effect (unchanged)
function fadeout(jWindow, fadeDuration, blockingFlag)
oldAlpha = com.sun.awt.AWTUtilities.getWindowOpacity(jWindow);
newAlpha = 0.0;
delta   = newAlpha - oldAlpha;
maxStep = 0.03;
steps   = fix(abs(delta)/maxStep) + 1;
stepA   = delta/steps;
stepD   = fadeDuration/(steps-1);
if blockingFlag || steps==1
    for k=1:steps
        alpha = oldAlpha + k*stepA;
        com.sun.awt.AWTUtilities.setWindowOpacity(jWindow, alpha);
        jWindow.repaint();
        if k<steps, pause(stepD); end
    end
else
    t = timer('ExecutionMode','fixedRate','Period',0.02,'TasksToExecute',steps,...
        'TimerFcn', {@timerFcn, jWindow, oldAlpha, stepA});
    start(t);
end
end

function timerFcn(hTimer, ~, jFrame, current, stepA)
k = hTimer.TasksExecuted;
alpha = current + k*stepA;
try
    com.sun.awt.AWTUtilities.setWindowOpacity(jFrame, alpha);
catch
    stop(hTimer); delete(hTimer); jFrame.dispose(); return;
end
jFrame.repaint();
if k == hTimer.TasksToExecute
    stop(hTimer); delete(hTimer); jFrame.dispose();
end
end
