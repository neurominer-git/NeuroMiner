classdef NMAppSessionState < handle
% NMAppSessionState
% Mutable app-level state shared by the browser bridge handler closure.

    properties
        NM = struct()
        Context = struct()
        InitialPage = 'landing'
        TrainTemplateOrch = []
    end
end
