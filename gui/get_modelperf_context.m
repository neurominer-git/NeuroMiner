function [handles, ctx] = get_modelperf_context(handles)
% Returns everything needed to render *any* view without plotting the full grid.

predind = get(handles.popupmenu1,'Value');
predstr = get(handles.popupmenu1,'String');
h_list  = get(handles.selModelMeasures,'String');
h_val   = get(handles.selModelMeasures,'Value');
grd     = handles.grid;
meastype= h_list{h_val};
ctx = struct('meastype',meastype,'multfl',false,'ylb','', ...
             'P',[],'SEM',[],'lgstr',{{}},'pardesc','','ct',[],'h',predind);

if strcmpi(predstr{predind},'Multi-group classifier')
    ctx.h = 1; ctx.multfl = true;
    switch meastype
        case 'Multi-class cross-validation performance'
            pardesc = nk_GetParamDescription2([],handles.params.TrainParam,'GridParam');
            ctx.P   = [grd.MultiCVPerf grd.MultiTSPerf];
            ctx.SEM = [grd.seMultiCVPerf grd.seMultiTSPerf];
            perfstr = strcmpi(pardesc.GridParam,'BAC') * "Average Binary BAC [%]" + ...
                      ~strcmpi(pardesc.GridParam,'BAC') * "Multi-class Accuracy [%]";
            ctx.ylb = ['Multi-class CV1/CV2-test performance [' char(perfstr) ' ]'];
            ctx.lgstr = {'Multi-class CV1 test performance','Multi-class CV2 test performance'};
            ctx.pardesc = pardesc.GridParam;

        case 'Multi-class generalization error'
            pardesc = nk_GetParamDescription2([],handles.params.TrainParam,'GridParam');
            ctx.P   = grd.MultiERR_CVTSPerf; ctx.SEM = [];
            ctx.ylb = ['Multi-group generalization error [CV1-test - CV2-test] [' pardesc.GridParam ' ]'];
            ctx.pardesc = pardesc.GridParam;

        case 'Multi-class ensemble diversity'
            ctx.P   = [grd.MultiCVDiversity grd.MultiTsDiversity]; ctx.SEM = [];
            ctx.ylb = 'Multi-class ensemble entropy';

        case 'Multi-class complexity'
            ctx.P   = grd.MultiComplexity; ctx.SEM = [];
            ctx.ylb = 'Average model complexity [%]';

        case 'Multi-class model selection frequency'
            ctx.P   = grd.MultiSelNodeFreq*100; ctx.SEM = [];
            ctx.ylb = 'Multi-class parameter selection frequency [%]';
    end
else
    h = predind; ctx.h = h;
    switch meastype
        case 'Cross-validation performances'
            pardesc = nk_GetParamDescription2([],handles.params.TrainParam,'GridParam');
            ctx.P   = [grd.mean_CVPerf(:,h,:,handles.curlabel) grd.mean_TSPerf(:,h,:,handles.curlabel)];
            ctx.SEM = [grd.se_CVPerf(:,h,:,handles.curlabel)  grd.se_TSPerf(:,h,:,handles.curlabel)];
            ctx.ylb = ['CV1/CV2-test performance [' pardesc.GridParam ' ]'];
            ctx.lgstr = {'CV1 test performance','CV2 test performance'};
            ctx.pardesc = pardesc.GridParam;

        case 'Generalization error'
            pardesc = nk_GetParamDescription2([],handles.params.TrainParam,'GridParam');
            ctx.P   = grd.mean_Err_CVTSPerf(:,h,:,handles.curlabel); ctx.SEM = grd.se_Err_CVTSPerf(:,h,:,handles.curlabel);
            ctx.ylb = ['Generalization error [CV1-test - CV2-test] [' pardesc.GridParam ' ]'];
            ctx.pardesc = pardesc.GridParam;

        case 'Model complexity'
            ctx.P   = grd.mean_Complexity(:,h,:,handles.curlabel); ctx.SEM = grd.se_Complexity(:,h,:,handles.curlabel);
            ctx.ylb = 'Model complexity';

        case 'Ensemble diversity'
            ctx.P   = [grd.mean_CVDiversity(:,h,:,handles.curlabel) grd.mean_TsDiversity(:,h,:,handles.curlabel)]; ctx.SEM = [];
            ctx.ylb = 'Binary ensemble entropy';

        case 'Model selection frequency'
            ctx.P   = grd.SelNodeFreq(:,h,:,handles.curlabel); ctx.SEM = [];
            ctx.ylb = 'Parameter selection frequency [%]';

        case 'Overall sequence gain'
            perf = nk_GetParamDescription2([],handles.params.TrainParam,'GridParam');
            ctx.P   = grd.mean_SeqGain(:,h,:,handles.curlabel); ctx.SEM = grd.se_SeqGain(:,h,:,handles.curlabel);
            ctx.ylb = ['CV1-test performance gain [ ' perf.GridParam ' ]'];

        case 'Examination frequencies'
            nE = size(handles.params.TrainParam.SVM.SEQOPT.C,2);
            ctx.P   = grd.mean_SeqExamFreq(:,:,h,:,handles.curlabel); ctx.SEM = grd.se_SeqExamFreq(:,:,h,:,handles.curlabel);
            ctx.ylb = 'Examination frequencies [%]';
            ctx.lgstr = cellstr([repmat('Examination frequency: model #', nE ,1) num2str((1:nE)')]);

        case 'Case propagation thresholds'
            nE = size(handles.params.TrainParam.SVM.SEQOPT.C,2)-1;
            ctx.P   = [grd.mean_SeqPercUpper(:,:,h,:,handles.curlabel) -1*grd.mean_SeqPercLower(:,:,h,:,handles.curlabel)];
            ctx.SEM = [grd.se_SeqPercUpper(:,:,h,:,handles.curlabel)  -1*grd.se_SeqPercLower(:,:,h,:,handles.curlabel)];
            ctx.ylb = 'Case propagation thresholds';
            lg1 = [repmat('+1 * Upper propagation threshold: model #', nE ,1) num2str((1:nE)')];
            lg2 = [repmat('-1 * Lower propagation threshold: model #', nE ,1) num2str((1:nE)')];
            ctx.lgstr = cellstr([lg1; lg2]);
    end
end

handles.currmeas     = ctx.P;
handles.currmeasdesc = ctx.pardesc;
end
