function tf = nm_preproc_scaffold_needs_labels(orch)
% nm_preproc_scaffold_needs_labels  Report whether the preprocessing scaffold contains steps that require labels.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

tf = false;
seqs = {orch.SubjectSequence, orch.CVSequence};
for s = 1:numel(seqs)
    seq = seqs{s};
    for i = 1:numel(seq.Steps)
        st = seq.Steps{i};
        try
            m = seq.Registry.get(st.moduleId); info = m.info(); cap = info.capabilities;
            if (isfield(cap,'requiresLabels') && cap.requiresLabels) || (isfield(cap,'usesLabels') && cap.usesLabels)
                tf = true; return;
            end
        catch
        end
        id = lower(char(st.moduleId));
        if any(strcmp(id, {'labelimpute','rankfeat','remvarcomp','correctnuis','devmap','discsym'}))
            % Conservative: these modules may be label-dependent depending on config.
            tf = true; return;
        end
    end
end
end
