function add_fault_monitor(mdl, pos)
%ADD_FAULT_MONITOR  Add the FaultMonitor subsystem (REQ-INV-024..029).
%
%   Inputs : 1 PhaseCurr_A [3], 2 DcLinkVolt_V, 3 InvTemp_degC, 4 MotTemp_degC,
%            5 UvMonEna (state machine output of the previous task)
%   Outputs: 1 FaultWord (uint16), 2 FaultActive (boolean)
%
%   Every fault condition is qualified by its own debounce counter: the counter
%   counts the consecutive tasks in which the raw condition is TRUE (saturating
%   at N) and is cleared in the first task in which it is FALSE. The fault is
%   qualified while the counter is at N. FaultWord bits:
%     0 OC (overcurrent), 1 OV (DC-link overvoltage), 2 UV (DC-link undervoltage),
%     3 OT_INV (inverter over-temperature), 4 OT_MOT (motor over-temperature).
%   Bits are not latched here; InvStateMachine latches the FAULT state.

    sys = [mdl '/FaultMonitor'];
    mbd_add('built-in/Subsystem', sys, pos, 'TreatAsAtomicUnit', 'on', 'Description', ...
            'Debounced fault detection; FaultWord bit 0 OC, 1 OV, 2 UV, 3 OT_INV, 4 OT_MOT (REQ-INV-024..029).');

    ins = {'PhaseCurr_A', 'DcLinkVolt_V', 'InvTemp_degC', 'MotTemp_degC', 'UvMonEna'};
    for k = 1:numel(ins)
        mbd_add('built-in/Inport', [sys '/' ins{k}], mbd_pos(1, 2 * k - 1, 30, 14), 'Port', num2str(k));
    end
    mbd_add('built-in/Outport', [sys '/FaultWord'],   mbd_pos(11, 4, 30, 14), 'Port', '1');
    mbd_add('built-in/Outport', [sys '/FaultActive'], mbd_pos(11, 7, 30, 14), 'Port', '2');

    % ---- overcurrent: max |i_a|, |i_b|, |i_c| above the threshold
    mbd_add('built-in/Abs',                [sys '/PhaseAbs'], mbd_pos(2, 1));
    mbd_add('built-in/MinMax',             [sys '/PhaseMax'], mbd_pos(3, 1), 'Function', 'max', 'Inputs', '1');
    mbd_add('built-in/Constant',           [sys '/OcThresh'], mbd_pos(3, 2), ...
            'Value', 'InvCtrl_OcThresh_A', 'OutDataTypeStr', 'single');
    mbd_add('built-in/RelationalOperator', [sys '/OcCheck'],  mbd_pos(4, 1), ...
            'Operator', '>', 'OutDataTypeStr', 'boolean');
    addDebounce(sys, 'OcDebounce', 'InvCtrl_OcDebounce_tk', mbd_pos(5, 1, 90, 40));
    mbd_line(sys, 'PhaseCurr_A/1', 'PhaseAbs/1', 'PhaseCurr_A');
    mbd_line(sys, 'PhaseAbs/1',    'PhaseMax/1');
    mbd_line(sys, 'PhaseMax/1',    'OcCheck/1', 'PhaseCurrMax_A');
    mbd_line(sys, 'OcThresh/1',    'OcCheck/2');
    mbd_line(sys, 'OcCheck/1',     'OcDebounce/1', 'OcRaw');

    % ---- DC-link overvoltage
    mbd_add('built-in/Constant',           [sys '/OvThresh'], mbd_pos(3, 4), ...
            'Value', 'InvCtrl_OvThresh_V', 'OutDataTypeStr', 'single');
    mbd_add('built-in/RelationalOperator', [sys '/OvCheck'],  mbd_pos(4, 3), ...
            'Operator', '>', 'OutDataTypeStr', 'boolean');
    addDebounce(sys, 'OvDebounce', 'InvCtrl_OvDebounce_tk', mbd_pos(5, 3, 90, 40));
    mbd_line(sys, 'DcLinkVolt_V/1', 'OvCheck/1', 'DcLinkVolt_V');
    mbd_line(sys, 'OvThresh/1',     'OvCheck/2');
    mbd_line(sys, 'OvCheck/1',      'OvDebounce/1', 'OvRaw');

    % ---- DC-link undervoltage, monitored only while UvMonEna (READY, RUN)
    mbd_add('built-in/Constant',           [sys '/UvThresh'],  mbd_pos(3, 6), ...
            'Value', 'InvCtrl_UvThresh_V', 'OutDataTypeStr', 'single');
    mbd_add('built-in/RelationalOperator', [sys '/UvCheck'],   mbd_pos(4, 5), ...
            'Operator', '<', 'OutDataTypeStr', 'boolean');
    mbd_add('built-in/Logic',              [sys '/UvMonGate'], mbd_pos(5, 6), ...
            'Operator', 'AND', 'Inputs', '2', 'OutDataTypeStr', 'boolean');
    addDebounce(sys, 'UvDebounce', 'InvCtrl_UvDebounce_tk', mbd_pos(6, 5, 90, 40));
    mbd_line(sys, 'DcLinkVolt_V/1', 'UvCheck/1');
    mbd_line(sys, 'UvThresh/1',     'UvCheck/2');
    mbd_line(sys, 'UvCheck/1',      'UvMonGate/1');
    mbd_line(sys, 'UvMonEna/1',     'UvMonGate/2', 'UvMonEna');
    mbd_line(sys, 'UvMonGate/1',    'UvDebounce/1', 'UvRaw');

    % ---- inverter over-temperature
    mbd_add('built-in/Constant',           [sys '/OtInvThresh'], mbd_pos(3, 8), ...
            'Value', 'InvCtrl_OtInvThresh_degC', 'OutDataTypeStr', 'single');
    mbd_add('built-in/RelationalOperator', [sys '/OtInvCheck'],  mbd_pos(4, 7), ...
            'Operator', '>', 'OutDataTypeStr', 'boolean');
    addDebounce(sys, 'OtInvDebounce', 'InvCtrl_OtInvDebounce_tk', mbd_pos(5, 7, 90, 40));
    mbd_line(sys, 'InvTemp_degC/1', 'OtInvCheck/1', 'InvTemp_degC');
    mbd_line(sys, 'OtInvThresh/1',  'OtInvCheck/2');
    mbd_line(sys, 'OtInvCheck/1',   'OtInvDebounce/1', 'OtInvRaw');

    % ---- motor over-temperature
    mbd_add('built-in/Constant',           [sys '/OtMotThresh'], mbd_pos(3, 10), ...
            'Value', 'InvCtrl_OtMotThresh_degC', 'OutDataTypeStr', 'single');
    mbd_add('built-in/RelationalOperator', [sys '/OtMotCheck'],  mbd_pos(4, 9), ...
            'Operator', '>', 'OutDataTypeStr', 'boolean');
    addDebounce(sys, 'OtMotDebounce', 'InvCtrl_OtMotDebounce_tk', mbd_pos(5, 9, 90, 40));
    mbd_line(sys, 'MotTemp_degC/1', 'OtMotCheck/1', 'MotTemp_degC');
    mbd_line(sys, 'OtMotThresh/1',  'OtMotCheck/2');
    mbd_line(sys, 'OtMotCheck/1',   'OtMotDebounce/1', 'OtMotRaw');

    % ---- FaultWord: bit b = fault * 2^b (uint16)
    bits = {'Oc',    'OcDebounce',    0, 'FaultOc'
            'Ov',    'OvDebounce',    1, 'FaultOv'
            'Uv',    'UvDebounce',    2, 'FaultUv'
            'OtInv', 'OtInvDebounce', 3, 'FaultOtInv'
            'OtMot', 'OtMotDebounce', 4, 'FaultOtMot'};
    mbd_add('built-in/Sum', [sys '/FaultWordSum'], mbd_pos(9, 4, 40, 130), ...
            'Inputs', '+++++', 'IconShape', 'rectangular', 'OutDataTypeStr', 'uint16');
    for k = 1:size(bits, 1)
        nm = bits{k, 1};
        mbd_add('built-in/DataTypeConversion', [sys '/' nm 'ToU16'], mbd_pos(7, 2 * k - 1), ...
                'OutDataTypeStr', 'uint16');
        mbd_add('built-in/Gain', [sys '/' nm 'Bit'], mbd_pos(8, 2 * k - 1), ...
                'Gain', num2str(2 ^ bits{k, 3}), 'ParamDataTypeStr', 'uint16', 'OutDataTypeStr', 'uint16');
        mbd_line(sys, [bits{k, 2} '/1'], [nm 'ToU16/1'], bits{k, 4});
        mbd_line(sys, [nm 'ToU16/1'], [nm 'Bit/1']);
        mbd_line(sys, [nm 'Bit/1'], sprintf('FaultWordSum/%d', k));
    end
    mbd_add('built-in/Constant',           [sys '/NoFault'],  mbd_pos(9, 8), 'Value', '0', 'OutDataTypeStr', 'uint16');
    mbd_add('built-in/RelationalOperator', [sys '/AnyFault'], mbd_pos(10, 7), ...
            'Operator', '~=', 'OutDataTypeStr', 'boolean');
    mbd_line(sys, 'FaultWordSum/1', 'FaultWord/1', 'FaultWord');
    mbd_line(sys, 'FaultWordSum/1', 'AnyFault/1');
    mbd_line(sys, 'NoFault/1',      'AnyFault/2');
    mbd_line(sys, 'AnyFault/1',     'FaultActive/1', 'FaultActive');
end

% =====================================================================================
function addDebounce(parent, name, nParam, pos)
%ADDDEBOUNCE  Debounce counter subsystem: Qualified = (counter == N).
%   count(k) = Raw(k) ? min(count(k-1) + 1, N) : 0      (uint16, count(-1) = 0)
%   Qualified(k) = count(k) >= N

    sys = [parent '/' name];
    mbd_add('built-in/Subsystem', sys, pos, 'Description', ...
            sprintf('Debounce: Qualified after %s consecutive tasks with Raw = TRUE.', nParam));
    mbd_add('built-in/Inport',  [sys '/Raw'],       mbd_pos(1, 2, 30, 14), 'Port', '1');
    mbd_add('built-in/Outport', [sys '/Qualified'], mbd_pos(7, 2, 30, 14), 'Port', '1');

    mbd_add('built-in/Constant',  [sys '/N'],         mbd_pos(2, 4), 'Value', nParam, 'OutDataTypeStr', 'uint16');
    mbd_add('built-in/Constant',  [sys '/One'],       mbd_pos(2, 3), 'Value', '1', 'OutDataTypeStr', 'uint16');
    mbd_add('built-in/Constant',  [sys '/Zero'],      mbd_pos(3, 4), 'Value', '0', 'OutDataTypeStr', 'uint16');
    mbd_add('built-in/UnitDelay', [sys '/CountPrev'], mbd_pos(2, 1), 'InitialCondition', '0');
    mbd_add('built-in/Sum',       [sys '/CountInc'],  mbd_pos(3, 1), 'Inputs', '++', 'OutDataTypeStr', 'uint16');
    mbd_add('built-in/MinMax',    [sys '/CountSat'],  mbd_pos(4, 1), 'Function', 'min', 'Inputs', '2', ...
            'OutDataTypeStr', 'uint16');
    mbd_add('built-in/Switch',    [sys '/CountNext'], mbd_pos(5, 2), 'Criteria', 'u2 ~= 0', 'OutDataTypeStr', 'uint16');
    mbd_add('built-in/RelationalOperator', [sys '/AtLimit'], mbd_pos(6, 2), ...
            'Operator', '>=', 'OutDataTypeStr', 'boolean');

    mbd_line(sys, 'CountPrev/1', 'CountInc/1');
    mbd_line(sys, 'One/1',       'CountInc/2');
    mbd_line(sys, 'CountInc/1',  'CountSat/1');
    mbd_line(sys, 'N/1',         'CountSat/2');
    mbd_line(sys, 'CountSat/1',  'CountNext/1');
    mbd_line(sys, 'Raw/1',       'CountNext/2');
    mbd_line(sys, 'Zero/1',      'CountNext/3');
    mbd_line(sys, 'CountNext/1', 'CountPrev/1', 'Count');
    mbd_line(sys, 'CountNext/1', 'AtLimit/1');
    mbd_line(sys, 'N/1',         'AtLimit/2');
    mbd_line(sys, 'AtLimit/1',   'Qualified/1');
end
