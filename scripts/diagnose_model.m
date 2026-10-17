function diagnose_model()
% sandbox diagnostics: compiled sample times of delays and switches
inv_ctrl_setup();
mdl = build_inv_ctrl();
feval(mdl, [], [], [], 'compile');
c = onCleanup(@() feval(mdl, [], [], [], 'term'));
types = {'UnitDelay', 'Switch', 'Sum', 'Constant', 'Inport'};
for t = 1:numel(types)
    blks = find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'BlockType', types{t});
    for k = 1:numel(blks)
        ts = get_param(blks{k}, 'CompiledSampleTime');
        if iscell(ts), ts = cell2mat(ts(:)); end
        fprintf('DIAG %-10s %-70s Ts=%s\n', types{t}, blks{k}, mat2str(ts));
    end
end
end
