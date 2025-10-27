function cv_visualize_samlesize_estimation_results(samplesize_results)
if isfield(samplesize_results, 'resplotfilename_fig') && exist(samplesize_results.resplotfilename_fig, 'file')
    openfig(samplesize_results.resplotfilename_fig)
else
    plot(samplesize_results.R)
end
end
