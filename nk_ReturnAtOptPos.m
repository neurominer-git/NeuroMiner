function [ Tr, CV, Ts, Ocv, TrainedParam ] = nk_ReturnAtOptPos(oTr, oCV, oTs, oOcv, Pnt, z, oocvonly, paramonly)

if ~exist("paramonly",'var') || isempty(paramonly), paramonly = false; end
if ~exist("oocvonly",'var') || isempty(oocvonly), oocvonly = false; end
Ocv = []; Tr = []; CV = []; Ts = []; 

if ~paramonly
if ~isempty(Pnt.data_ind)
    Ix = Pnt.data_ind(z);
else
    Ix = 1;
end
if ~isempty(oTr) && iscell(oTr)
    Tr = oTr{Ix}; 
    if ~oocvonly
        CV = oCV{Ix}; Ts = oTs{Ix};   
    end
    if ~isempty(oOcv)
        if size(oOcv,2)>1
            Ocv = oOcv(Ix,:);
        else
            Ocv = oOcv{Ix}; 
        end
    end
elseif ~isempty(oTr)
    Tr = oTr; 
    if ~oocvonly
        CV = oCV; Ts = oTs;   
    end
    if ~isempty(oOcv), Ocv = oOcv; end
else
    Tr = [];
    CV = [];
    Ts = [];
    Ocv= [];
end

end


if ischar(Pnt.TrainedParam) 
    if exist(Pnt.TrainedParam,'file')
        fprintf('\tLoading parameter file.')
        load( Pnt.TrainedParam );
    else
        error('Parameter file %s could not be found.',Pnt.TrainedParam );
    end
else
    oTrainedParam = Pnt.TrainedParam;
end

if ~isempty(Pnt.nA) && isfield(Pnt,'TrainedParam') && ~isempty(Pnt.TrainedParam)
    TrainedParam = cell(1,Pnt.nA);
    for a = 1:Pnt.nA
        if isstruct(Pnt.TrainedParam{a})
            TrainedParam{a} = oTrainedParam{a};
        else
            TrainedParam{a} = oTrainedParam{a}{Pnt.train_ind(z,a)};
        end
    end
else
    TrainedParam = oTrainedParam;
end
