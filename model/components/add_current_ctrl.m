function add_current_ctrl(mdl, pos)
%ADD_CURRENT_CTRL  Add the CurrentCtrl subsystem (REQ-INV-020..023).
%
%   Inputs : 1 IdRef_A, 2 IqRef_A, 3 Id_A, 4 Iq_A, 5 DcLinkVolt_V, 6 PwmEnable
%   Outputs: 1 Vd_V, 2 Vq_V
%
%   Two discrete PI controllers (parallel form, forward Euler) with clamping
%   anti-windup. Voltage vector limit Vmax = Udc/sqrt(3) with d-axis priority:
%   Vd is limited to +/-Vmax, Vq to +/-sqrt(Vmax^2 - Vd^2). While PwmEnable is
%   FALSE the integrators are reset and both outputs are 0.

    sys = [mdl '/CurrentCtrl'];
    mbd_add('built-in/Subsystem', sys, pos, 'TreatAsAtomicUnit', 'on', 'Description', ...
            'd/q PI current control, clamping anti-windup, voltage vector limit with d-axis priority (REQ-INV-020..023).');

    ins = {'IdRef_A', 'IqRef_A', 'Id_A', 'Iq_A', 'DcLinkVolt_V', 'PwmEnable'};
    for k = 1:numel(ins)
        mbd_add('built-in/Inport', [sys '/' ins{k}], mbd_pos(1, 2 * k - 1, 30, 14), 'Port', num2str(k));
    end
    mbd_add('built-in/Outport', [sys '/Vd_V'], mbd_pos(11, 2, 30, 14), 'Port', '1');
    mbd_add('built-in/Outport', [sys '/Vq_V'], mbd_pos(11, 8, 30, 14), 'Port', '2');

    % ---- voltage limit
    mbd_add('built-in/Gain', [sys '/VmaxCalc'], mbd_pos(3, 9),  'Gain', 'InvCtrl_CurCtrl_VmaxFactor');
    mbd_add('built-in/Gain', [sys '/NegVmax'],  mbd_pos(4, 10), 'Gain', '-1');
    mbd_line(sys, 'DcLinkVolt_V/1', 'VmaxCalc/1', 'DcLinkVolt_V');
    mbd_line(sys, 'VmaxCalc/1',     'NegVmax/1', 'Vmax_V');

    % ---- d axis: full voltage range
    addPiAxis(sys, 'PI_d', mbd_pos(6, 1, 90, 110));
    mbd_line(sys, 'IdRef_A/1',   'PI_d/1', 'IdRef_A');
    mbd_line(sys, 'Id_A/1',      'PI_d/2', 'Id_A');
    mbd_line(sys, 'VmaxCalc/1',  'PI_d/3');
    mbd_line(sys, 'NegVmax/1',   'PI_d/4');
    mbd_line(sys, 'PwmEnable/1', 'PI_d/5', 'PwmEnable');
    mbd_line(sys, 'PI_d/1',      'Vd_V/1', 'Vd_V');

    % ---- q axis: remaining headroom sqrt(Vmax^2 - Vd^2)
    mbd_add('built-in/Product',  [sys '/VmaxSq'],       mbd_pos(5, 9),  'Inputs', '**');
    mbd_add('built-in/Product',  [sys '/VdSq'],         mbd_pos(7, 4),  'Inputs', '**');
    mbd_add('built-in/Sum',      [sys '/HeadroomSq'],   mbd_pos(8, 5),  'Inputs', '+-');
    mbd_add('built-in/Constant', [sys '/ZeroSq'],       mbd_pos(8, 6),  'Value', '0', 'OutDataTypeStr', 'single');
    mbd_add('built-in/MinMax',   [sys '/HeadroomPos'],  mbd_pos(9, 5),  'Function', 'max', 'Inputs', '2');
    mbd_add('simulink/Math Operations/Sqrt', [sys '/VqLimCalc'], mbd_pos(9, 7));
    mbd_add('built-in/Gain',     [sys '/NegVqLim'],     mbd_pos(9, 9),  'Gain', '-1');
    mbd_line(sys, 'VmaxCalc/1',    'VmaxSq/1');
    mbd_line(sys, 'VmaxCalc/1',    'VmaxSq/2');
    mbd_line(sys, 'PI_d/1',        'VdSq/1');
    mbd_line(sys, 'PI_d/1',        'VdSq/2');
    mbd_line(sys, 'VmaxSq/1',      'HeadroomSq/1');
    mbd_line(sys, 'VdSq/1',        'HeadroomSq/2');
    mbd_line(sys, 'HeadroomSq/1',  'HeadroomPos/1');
    mbd_line(sys, 'ZeroSq/1',      'HeadroomPos/2');
    mbd_line(sys, 'HeadroomPos/1', 'VqLimCalc/1');
    mbd_line(sys, 'VqLimCalc/1',   'NegVqLim/1', 'VqLim_V');

    addPiAxis(sys, 'PI_q', mbd_pos(10, 7, 90, 110));
    mbd_line(sys, 'IqRef_A/1',   'PI_q/1', 'IqRef_A');
    mbd_line(sys, 'Iq_A/1',      'PI_q/2', 'Iq_A');
    mbd_line(sys, 'VqLimCalc/1', 'PI_q/3');
    mbd_line(sys, 'NegVqLim/1',  'PI_q/4');
    mbd_line(sys, 'PwmEnable/1', 'PI_q/5');
    mbd_line(sys, 'PI_q/1',      'Vq_V/1', 'Vq_V');
end

% =====================================================================================
function addPiAxis(parent, name, pos)
%ADDPIAXIS  One PI current controller with clamping anti-windup.
%   e     = Ref - Meas
%   u     = Kp*e + I(k-1)
%   V     = Active ? sat(u, LoLim, UpLim) : 0
%   clamp = (u is limited) AND (e*u > 0)          the error drives further into the limit
%   I(k)  = Active ? (clamp ? I(k-1) : I(k-1) + KiTs*e) : 0

    sys = [parent '/' name];
    mbd_add('built-in/Subsystem', sys, pos, 'Description', ...
            'PI controller, parallel form, forward Euler, clamping anti-windup, reset while Active is FALSE.');
    ins = {'Ref', 'Meas', 'UpLim', 'LoLim', 'Active'};
    for k = 1:numel(ins)
        mbd_add('built-in/Inport', [sys '/' ins{k}], mbd_pos(1, 2 * k - 1, 30, 14), 'Port', num2str(k));
    end
    mbd_add('built-in/Outport', [sys '/V'], mbd_pos(9, 3, 30, 14), 'Port', '1');

    mbd_add('built-in/Sum',       [sys '/Err'],       mbd_pos(2, 1), 'Inputs', '+-', 'OutDataTypeStr', 'single');
    mbd_add('built-in/Gain',      [sys '/Kp'],        mbd_pos(3, 1), 'Gain', 'InvCtrl_CurCtrl_Kp_VpA');
    mbd_add('built-in/Gain',      [sys '/KiTs'],      mbd_pos(3, 3), 'Gain', 'InvCtrl_CurCtrl_KiTs_VpA');
    mbd_add('built-in/UnitDelay', [sys '/IntPrev'],   mbd_pos(3, 5), 'InitialCondition', '0');
    mbd_add('built-in/Sum',       [sys '/USum'],      mbd_pos(4, 1), 'Inputs', '++', 'OutDataTypeStr', 'single');
    mbd_add('simulink/Discontinuities/Saturation Dynamic', [sys '/USat'], mbd_pos(5, 1, 70, 60));
    mbd_add('built-in/RelationalOperator', [sys '/SatActive'], mbd_pos(6, 2), ...
            'Operator', '~=', 'OutDataTypeStr', 'boolean');
    mbd_add('built-in/Product',   [sys '/ErrTimesU'], mbd_pos(5, 4), 'Inputs', '**');
    mbd_add('built-in/Constant',  [sys '/ZeroS'],     mbd_pos(5, 6), 'Value', '0', 'OutDataTypeStr', 'single');
    mbd_add('built-in/RelationalOperator', [sys '/SameSign'], mbd_pos(6, 4), ...
            'Operator', '>', 'OutDataTypeStr', 'boolean');
    mbd_add('built-in/Logic',     [sys '/Clamp'],     mbd_pos(7, 3), 'Operator', 'AND', 'Inputs', '2', ...
            'OutDataTypeStr', 'boolean');
    mbd_add('built-in/Sum',       [sys '/IntCand'],   mbd_pos(4, 4), 'Inputs', '++', 'OutDataTypeStr', 'single');
    mbd_add('built-in/Switch',    [sys '/IntHold'],   mbd_pos(8, 4), 'Criteria', 'u2 ~= 0', 'OutDataTypeStr', 'single');
    mbd_add('built-in/Switch',    [sys '/IntNext'],   mbd_pos(8, 6), 'Criteria', 'u2 ~= 0', 'OutDataTypeStr', 'single');
    mbd_add('built-in/Switch',    [sys '/VOut'],      mbd_pos(8, 2), 'Criteria', 'u2 ~= 0', 'OutDataTypeStr', 'single');

    mbd_line(sys, 'Ref/1',       'Err/1');
    mbd_line(sys, 'Meas/1',      'Err/2');
    mbd_line(sys, 'Err/1',       'Kp/1', 'e');
    mbd_line(sys, 'Err/1',       'KiTs/1');
    mbd_line(sys, 'Err/1',       'ErrTimesU/1');
    mbd_line(sys, 'Kp/1',        'USum/1');
    mbd_line(sys, 'IntPrev/1',   'USum/2', 'IntPrev');
    mbd_line(sys, 'UpLim/1',     'USat/1');
    mbd_line(sys, 'USum/1',      'USat/2', 'u');
    mbd_line(sys, 'LoLim/1',     'USat/3');
    mbd_line(sys, 'USum/1',      'SatActive/1');
    mbd_line(sys, 'USat/1',      'SatActive/2', 'uSat');
    mbd_line(sys, 'USum/1',      'ErrTimesU/2');
    mbd_line(sys, 'ErrTimesU/1', 'SameSign/1');
    mbd_line(sys, 'ZeroS/1',     'SameSign/2');
    mbd_line(sys, 'SatActive/1', 'Clamp/1');
    mbd_line(sys, 'SameSign/1',  'Clamp/2');
    mbd_line(sys, 'IntPrev/1',   'IntCand/1');
    mbd_line(sys, 'KiTs/1',      'IntCand/2');
    mbd_line(sys, 'IntPrev/1',   'IntHold/1');
    mbd_line(sys, 'Clamp/1',     'IntHold/2', 'clamp');
    mbd_line(sys, 'IntCand/1',   'IntHold/3');
    mbd_line(sys, 'IntHold/1',   'IntNext/1');
    mbd_line(sys, 'Active/1',    'IntNext/2', 'Active');
    mbd_line(sys, 'ZeroS/1',     'IntNext/3');
    mbd_line(sys, 'IntNext/1',   'IntPrev/1', 'IntNext');
    mbd_line(sys, 'USat/1',      'VOut/1');
    mbd_line(sys, 'Active/1',    'VOut/2');
    mbd_line(sys, 'ZeroS/1',     'VOut/3');
    mbd_line(sys, 'VOut/1',      'V/1');
end
