function [PREPROC, ...
            RFE, ...
            GRD, ...
            SVM, ...
            LIBSVMTRAIN, ...
            LIBSVMPREDICT, ...
            RVM, ...
            MKLRVM, ...
            CMDSTR, ...
            MULTI, ...
            VIS, ...
            TENSORFLOW, paramstr] = nk_CompatParams2(TrainParam, varind, paramstr)

global MODEFL
        
PREPROC             = [];
RFE                 = []; 
GRD                 = [];
LIBSVMTRAIN         = [];
LIBSVMPREDICT       = [];
RVM                 = [];
MKLRVM              = [];
CMDSTR              = [];
VIS                 = [];
MULTI               = [];
TENSORFLOW          = [];

if ~exist('paramstr','var'), paramstr = []; end

if ~isempty(TrainParam.FUSION) && TrainParam.FUSION.flag == 3
   TrainParam = TrainParam.STRAT{varind};
end

if isfield(TrainParam,'PREPROC')
    if iscell(TrainParam.PREPROC) 
        if varind > numel(TrainParam.PREPROC)
            warning('VARIND out of bounds. Resetting to VARIND = 1 !!!')
            varind = 1;
        end
        if numel(varind)>1
            PREPROC  = TrainParam.PREPROC(varind);
        else
            PREPROC  = TrainParam.PREPROC{varind}; 
        end
    else
        PREPROC  = TrainParam.PREPROC; 
    end
end

if isfield(TrainParam,'VIS')
    if iscell(TrainParam.VIS) 
        if varind > numel(TrainParam.VIS)
            warning('VARIND out of bounds. Resetting to VARIND = 1 !!!')
            varind = 1;
        end
        if numel(varind)>1
            VIS= TrainParam.VIS(varind);
        else
            VIS = TrainParam.VIS{varind}; 
        end
    else
        VIS = TrainParam.VIS; 
    end
end

SVM = TrainParam.SVM;
SVM.RVMflag = false; if isfield(SVM,'BBQ') && SVM.BBQ.flag; SVM.RVMflag = true; end
            
switch SVM.prog
    
    case 'LIBSVM'
        try
            CMDSTR  = nk_DefineCmdStr(SVM, MODEFL);
            if SVM.LIBSVM.Optimization.b, SVM.RVMflag = true; end
            switch SVM.LIBSVM.LIBSVMver
                case 0
                    LIBSVMTRAIN = '312'; LIBSVMPREDICT = '312';
                case 2
                    LIBSVMTRAIN = '289'; LIBSVMPREDICT = '289';
                case 1
                    LIBSVMTRAIN = '291'; LIBSVMPREDICT = '291';
                case 3
                    LIBSVMTRAIN = '289PLUS'; LIBSVMPREDICT = '289PLUS';
            end
            LIBSVMTRAIN = ['svmtrain' LIBSVMTRAIN]; LIBSVMPREDICT = ['svmpredict' LIBSVMPREDICT];
        catch
            paramstr = sprintf('%s\n%s',paramstr,'Parameters for LIBSVM');
        end
        
    case 'LIBLIN'
        try
            CMDSTR  = nk_DefineCmdStr(SVM, MODEFL);
            if SVM.LIBLIN.b, SVM.RVMflag = true; end
        catch
            paramstr = sprintf('%s\n%s',paramstr,'Parameters for LIBLINEAR');
        end
        
    case 'MikRVM'
        try
            RVM.UserOpt = TrainParam.SVM.RVM.UserOpt;
            RVM.ParamSet = TrainParam.SVM.RVM.ParamSet;
            RVM.LikelihoodModel = TrainParam.SVM.RVM.LikelihoodModel;
        catch
            paramstr = sprintf('%s\n%s',paramstr,'Parameters for Mike Tipping RVM');
        end
        SVM.RVMflag = true;
        
    case 'MKLRVM'
        try
            MKLRVM  = TrainParam.SVM.MKLRVM;
        catch
            paramstr = sprintf('%s\n%s',paramstr,'Multiple Kernel Learning parameters for RVM');
        end
        SVM.RVMflag = true;
        
    case {'BLOREG', 'IMRELF', 'kNNMEX','GLMFIT','GLMNET'}
        SVM.RVMflag = true;
        
    case 'RNDFOR'
        CMDSTR  = nk_DefineCmdStr(SVM, MODEFL);
        SVM.RVMflag = true;

    case 'MLPERC'
        SVM.RVMflag = true;

    case 'BAYLIN'
        SVM.RVMflag = true;

    case 'TFDEEP'
        SVM.RVMflag = true;

        %Python needs access to NM paths; 
        % Add each to the Python sys.path if not already present
        all_paths = strsplit(path, pathsep);
        for j = 1:length(all_paths)
            this_path = all_paths{j};
            if count(py.sys.path, this_path) == 0
                insert(py.sys.path, int32(0), this_path);
            end
        end

        %Loading the python modules into GRD, and the folders into Python env.
        if ~strcmp(TrainParam.GRD.(SVM.prog).Params(end).range, 'none')
            TENSORFLOW.modules = cell(size(TrainParam.GRD.(SVM.prog).Params(end).range, 1), 1);
            for j=1:size(TrainParam.GRD.(SVM.prog).Params(end).range, 1)
                % ================= Get file path of model =================
                file_path = strtrim(TrainParam.GRD.(SVM.prog).Params(end).range(j, :));
                %Convert to absolute if relative
                file_path = fullfile(cd, file_path);
                %Get file name and dir.
                [dir, name, ~] = fileparts(file_path);
    
                % ================= Add folder to Python path if needed ====
                if count(py.sys.path, dir) == 0
                    insert(py.sys.path, int32(0), dir);
                end
    
                % ================= Load model module ====================== 
                TENSORFLOW.modules{j} = py.importlib.import_module(name);
                %Force reload in case file has changed. 
                TENSORFLOW.modules{j} = py.importlib.reload(TENSORFLOW.modules{j});
            end
        else
            %Default mode with default python function
            TENSORFLOW.modules{1} = py.importlib.import_module("train_tf_model");
            %Force reload in case file has changed. 
            TENSORFLOW.modules{1} = py.importlib.reload(TENSORFLOW.modules{1});
        end
        
    otherwise
        CMDSTR  = nk_DefineCmdStr(SVM);

end

if isfield(TrainParam,'GRD'),            GRD      = TrainParam.GRD; end
if isfield(TrainParam,'RFE'),            RFE      = TrainParam.RFE; end
if isfield(TrainParam,'MULTI'),          MULTI    = TrainParam.MULTI; end