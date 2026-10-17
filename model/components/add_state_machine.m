function add_state_machine(mdl, pos)
%ADD_STATE_MACHINE  Add the InvStateMachine Stateflow chart (REQ-INV-001..011).
%
%   Inputs : 1 EnableReq, 2 TrqEnableReq, 3 PrechargeDone, 4 FaultReset,
%            5 FaultActive, 6 DcLinkDischarged            (all boolean)
%   Outputs: 1 InvState (InvState_T), 2 PwmEnable, 3 UvMonEna (boolean)
%   Parameter: InvCtrl_StbyDwell_tk (model workspace)
%
%   States and outputs (entry actions):
%     state            PwmEnable  UvMonEna
%     OFF              false      false
%     STANDBY          false      false     self-test, InvCtrl_StbyDwell_tk tasks
%     PRECHARGE        false      false     DC link is being charged
%     READY            false      true
%     RUN              true       true      torque producing
%     SAFE_DISCHARGE   false      false     DC link is being discharged
%     FAULT            false      false     latched
%
%   Transitions are listed per source state in execution order (1 = highest
%   priority). The fault reaction always has priority 1.

    chartPath = [mdl '/InvStateMachine'];
    add_block('sflib/Chart', chartPath, 'Position', pos);
    rt = sfroot;
    ch = rt.find('-isa', 'Stateflow.Chart', 'Path', chartPath);
    if numel(ch) ~= 1
        error('add_state_machine:chart', 'Stateflow chart %s not found after add_block.', chartPath);
    end
    ch.ActionLanguage = 'C';
    ch.ChartUpdate = 'INHERITED';
    try
        ch.UserSpecifiedStateTransitionExecutionOrder = true;
    catch
        % explicit ordering is the only mode in newer releases
    end
    ch.Description = 'Inverter operating state machine (REQ-INV-001..011).';

    % ---- data; ports are numbered in creation order (checked at the end)
    in  = {'EnableReq', 'TrqEnableReq', 'PrechargeDone', 'FaultReset', 'FaultActive', 'DcLinkDischarged'};
    out = {'InvState', 'Enum: InvState_T'
           'PwmEnable', 'boolean'
           'UvMonEna', 'boolean'};
    for k = 1:numel(in)
        addData(ch, in{k}, 'Input', 'boolean');
    end
    for k = 1:size(out, 1)
        addData(ch, out{k, 1}, 'Output', out{k, 2});
    end
    addData(ch, 'InvCtrl_StbyDwell_tk', 'Parameter', 'Inherit: Same as Simulink');

    % ---- states: name, PwmEnable, UvMonEna, position [x y w h]
    W = 190; H = 95;
    sOff   = addState(ch, 'OFF',            false, false, [ 40  40 W H]);
    sStby  = addState(ch, 'STANDBY',        false, false, [330  40 W H]);
    sPre   = addState(ch, 'PRECHARGE',      false, false, [620  40 W H]);
    sDis   = addState(ch, 'SAFE_DISCHARGE', false, false, [ 40 270 W H]);
    sRun   = addState(ch, 'RUN',            true,  true,  [330 270 W H]);
    sRdy   = addState(ch, 'READY',          false, true,  [620 270 W H]);
    sFault = addState(ch, 'FAULT',          false, false, [330 500 W H]);

    % ---- default transition -> OFF (REQ-INV-001)
    t0 = Stateflow.Transition(ch);
    t0.Destination = sOff;
    t0.DestinationOClock = 0;
    x0 = sOff.Position(1) + sOff.Position(3) / 2;
    y0 = sOff.Position(2);
    t0.SourceEndpoint = [x0, y0 - 30];
    t0.Midpoint = [x0, y0 - 15];

    % ---- transitions: source, destination, label, execution order, source/destination o'clock
    fault = '[FaultActive]';
    T = {
        sOff,   sStby,  '[EnableReq]',                       1, 3, 9    % REQ-INV-002
        sStby,  sFault, fault,                               1, 6, 0    % REQ-INV-008
        sStby,  sOff,   '[!EnableReq]',                      2, 8, 4    % REQ-INV-003
        sStby,  sPre,   'after(InvCtrl_StbyDwell_tk, tick)', 3, 3, 9    % REQ-INV-003
        sPre,   sFault, fault,                               1, 7, 2    % REQ-INV-008
        sPre,   sDis,   '[!EnableReq]',                      2, 8, 1    % REQ-INV-006
        sPre,   sRdy,   '[PrechargeDone]',                   3, 6, 0    % REQ-INV-004
        sRdy,   sFault, fault,                               1, 7, 3    % REQ-INV-008
        sRdy,   sDis,   '[!EnableReq]',                      2, 5, 5    % REQ-INV-006
        sRdy,   sRun,   '[TrqEnableReq]',                    3, 9, 3    % REQ-INV-005
        sRun,   sFault, fault,                               1, 6, 0    % REQ-INV-008
        sRun,   sDis,   '[!EnableReq]',                      2, 9, 3    % REQ-INV-006
        sRun,   sRdy,   '[!TrqEnableReq]',                   3, 2, 10   % REQ-INV-005
        sDis,   sFault, fault,                               1, 6, 9    % REQ-INV-008
        sDis,   sOff,   '[DcLinkDischarged]',                2, 0, 6    % REQ-INV-007
        % FAULT -> STANDBY on fault reset once no fault is active (REQ-INV-009, REQ-INV-010)
        sFault, sStby,  '[FaultReset && !FaultActive]',      1, 1, 5
        };
    for k = 1:size(T, 1)
        addTransition(ch, T{k, :});
    end

    checkPorts(ch, in, out(:, 1));
    checkExecutionOrder(ch, T);
end

% =====================================================================================
function d = addData(ch, name, scope, dataType)
    d = Stateflow.Data(ch);
    d.Name = name;
    d.Scope = scope;
    d.DataType = dataType;
end

function s = addState(ch, name, pwm, uvMon, pos)
    s = Stateflow.State(ch);
    s.LabelString = sprintf('%s\nen:\nInvState = InvState_T.%s;\nPwmEnable = %s;\nUvMonEna = %s;', ...
        name, name, boolText(pwm), boolText(uvMon));
    s.Position = pos;
end

function t = addTransition(ch, src, dst, label, order, srcClock, dstClock)
    t = Stateflow.Transition(ch);
    t.Source = src;
    t.Destination = dst;
    t.SourceOClock = srcClock;
    t.DestinationOClock = dstClock;
    t.LabelString = label;
    if t.ExecutionOrder ~= order
        t.ExecutionOrder = order;
    end
end

function txt = boolText(b)
    if b
        txt = 'true';
    else
        txt = 'false';
    end
end

% =====================================================================================
function checkPorts(ch, in, out)
    % the top-level wiring in build_inv_ctrl.m relies on this port order
    for k = 1:numel(in)
        d = ch.find('-isa', 'Stateflow.Data', 'Name', in{k});
        if d.Port ~= k
            error('add_state_machine:port', 'Chart input %s has port %d, expected %d.', in{k}, d.Port, k);
        end
    end
    for k = 1:numel(out)
        d = ch.find('-isa', 'Stateflow.Data', 'Name', out{k});
        if d.Port ~= k
            error('add_state_machine:port', 'Chart output %s has port %d, expected %d.', out{k}, d.Port, k);
        end
    end
end

function checkExecutionOrder(ch, T)
    % every transition must carry the execution order of the table above
    trans = ch.find('-isa', 'Stateflow.Transition');
    for k = 1:size(T, 1)
        found = false;
        for j = 1:numel(trans)
            t = trans(j);
            if ~isempty(t.Source) && isequal(t.Source, T{k, 1}) && isequal(t.Destination, T{k, 2}) ...
                    && strcmp(t.LabelString, T{k, 3})
                found = true;
                if t.ExecutionOrder ~= T{k, 4}
                    error('add_state_machine:order', 'Transition %s -> %s "%s" has execution order %d, expected %d.', ...
                          T{k, 1}.Name, T{k, 2}.Name, T{k, 3}, t.ExecutionOrder, T{k, 4});
                end
            end
        end
        if ~found
            error('add_state_machine:transition', 'Transition %s -> %s "%s" not found.', ...
                  T{k, 1}.Name, T{k, 2}.Name, T{k, 3});
        end
    end
end
