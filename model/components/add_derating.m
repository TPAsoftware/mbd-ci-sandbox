function add_derating(mdl, pos)
%ADD_DERATING  Add the Derating subsystem (REQ-INV-012..017).
%
%   Inputs : 1 TrqReq_Nm, 2 InvTemp_degC, 3 MotTemp_degC, 4 DcLinkVolt_V, 5 PwmEnable
%   Outputs: 1 TrqCmd_Nm, 2 TrqLim_Nm
%
%   TrqLim_Nm = min(TrqMax, f_InvTemp, f_MotTemp, f_Udc)   (1-D tables, clipped)
%   TrqCmd_Nm = rate-limited TrqReq_Nm, saturated to +/-TrqLim_Nm before and after
%               the rate limiter; 0 (and rate limiter reset) while PwmEnable is FALSE.

    sys = [mdl '/Derating'];
    mbd_add('built-in/Subsystem', sys, pos, 'TreatAsAtomicUnit', 'on', 'Description', ...
            'Torque limit from temperatures and DC-link voltage, saturation and rate limiter (REQ-INV-012..017).');

    ins = {'TrqReq_Nm', 'InvTemp_degC', 'MotTemp_degC', 'DcLinkVolt_V', 'PwmEnable'};
    for k = 1:numel(ins)
        mbd_add('built-in/Inport', [sys '/' ins{k}], mbd_pos(1, 2 * k - 1, 30, 14), 'Port', num2str(k));
    end
    mbd_add('built-in/Outport', [sys '/TrqCmd_Nm'], mbd_pos(13, 1, 30, 14), 'Port', '1');
    mbd_add('built-in/Outport', [sys '/TrqLim_Nm'], mbd_pos(13, 5, 30, 14), 'Port', '2');

    % ---- torque limit
    lut = 'simulink/Lookup Tables/1-D Lookup Table';
    mbd_add('built-in/Constant', [sys '/TrqMax'], mbd_pos(3, 2), ...
            'Value', 'InvCtrl_TrqMax_Nm', 'OutDataTypeStr', 'single');
    mbd_add(lut, [sys '/InvTempDerating'], mbd_pos(3, 3), 'Table', 'InvCtrl_InvTempDrt_Tbl_Nm', ...
            'BreakpointsForDimension1', 'InvCtrl_InvTempDrt_Bp_degC', 'ExtrapMethod', 'Clip', 'OutDataTypeStr', 'single');
    mbd_add(lut, [sys '/MotTempDerating'], mbd_pos(3, 5), 'Table', 'InvCtrl_MotTempDrt_Tbl_Nm', ...
            'BreakpointsForDimension1', 'InvCtrl_MotTempDrt_Bp_degC', 'ExtrapMethod', 'Clip', 'OutDataTypeStr', 'single');
    mbd_add(lut, [sys '/DcLinkDerating'], mbd_pos(3, 7), 'Table', 'InvCtrl_UdcDrt_Tbl_Nm', ...
            'BreakpointsForDimension1', 'InvCtrl_UdcDrt_Bp_V', 'ExtrapMethod', 'Clip', 'OutDataTypeStr', 'single');
    mbd_add('built-in/MinMax', [sys '/TrqLimMin'], mbd_pos(5, 3, 40, 120), 'Function', 'min', 'Inputs', '4', ...
            'OutDataTypeStr', 'single');
    mbd_add('built-in/Gain',   [sys '/NegTrqLim'], mbd_pos(6, 6), 'Gain', '-1');
    mbd_line(sys, 'TrqMax/1',          'TrqLimMin/1');
    mbd_line(sys, 'InvTemp_degC/1',    'InvTempDerating/1', 'InvTemp_degC');
    mbd_line(sys, 'InvTempDerating/1', 'TrqLimMin/2', 'TrqLimInvTemp_Nm');
    mbd_line(sys, 'MotTemp_degC/1',    'MotTempDerating/1', 'MotTemp_degC');
    mbd_line(sys, 'MotTempDerating/1', 'TrqLimMin/3', 'TrqLimMotTemp_Nm');
    mbd_line(sys, 'DcLinkVolt_V/1',    'DcLinkDerating/1', 'DcLinkVolt_V');
    mbd_line(sys, 'DcLinkDerating/1',  'TrqLimMin/4', 'TrqLimUdc_Nm');
    mbd_line(sys, 'TrqLimMin/1',       'TrqLim_Nm/1', 'TrqLim_Nm');
    mbd_line(sys, 'TrqLimMin/1',       'NegTrqLim/1');

    % ---- request saturation, zero target outside RUN
    sat = 'simulink/Discontinuities/Saturation Dynamic';   % inputs: 1 up, 2 u, 3 lo
    mbd_add(sat, [sys '/TrqReqSat'], mbd_pos(7, 1, 70, 60));
    mbd_add('built-in/Constant', [sys '/ZeroTrq'], mbd_pos(7, 4), 'Value', '0', 'OutDataTypeStr', 'single');
    mbd_add('built-in/Switch',   [sys '/TrqTarget'], mbd_pos(8, 1), 'Criteria', 'u2 ~= 0', 'OutDataTypeStr', 'single');
    mbd_line(sys, 'TrqLimMin/1', 'TrqReqSat/1');
    mbd_line(sys, 'TrqReq_Nm/1', 'TrqReqSat/2', 'TrqReq_Nm');
    mbd_line(sys, 'NegTrqLim/1', 'TrqReqSat/3', 'TrqLimNeg_Nm');
    mbd_line(sys, 'TrqReqSat/1', 'TrqTarget/1', 'TrqReqLim_Nm');
    mbd_line(sys, 'PwmEnable/1', 'TrqTarget/2', 'PwmEnable');
    mbd_line(sys, 'ZeroTrq/1',   'TrqTarget/3');

    % ---- rate limiter (max InvCtrl_TrqSlewStep_Nm per task), final saturation, gate
    mbd_add('built-in/UnitDelay', [sys '/TrqCmdPrev'], mbd_pos(9, 4), 'InitialCondition', '0', ...
            'SampleTime', 'InvCtrl_Ts_s');
    mbd_add('built-in/Sum',       [sys '/TrqDelta'],   mbd_pos(9, 1), 'Inputs', '+-', 'OutDataTypeStr', 'single');
    mbd_add('built-in/Saturate',  [sys '/SlewLimit'],  mbd_pos(10, 1), ...
            'UpperLimit', 'InvCtrl_TrqSlewStep_Nm', 'LowerLimit', '-InvCtrl_TrqSlewStep_Nm');
    mbd_add('built-in/Sum',       [sys '/TrqRamp'],    mbd_pos(11, 1), 'Inputs', '++', 'OutDataTypeStr', 'single');
    mbd_add(sat,                  [sys '/TrqCmdSat'],  mbd_pos(11, 3, 70, 60));
    mbd_add('built-in/Switch',    [sys '/TrqCmdGate'], mbd_pos(12, 1), 'Criteria', 'u2 ~= 0', 'OutDataTypeStr', 'single');
    mbd_line(sys, 'TrqTarget/1',  'TrqDelta/1', 'TrqTarget_Nm');
    mbd_line(sys, 'TrqCmdPrev/1', 'TrqDelta/2', 'TrqCmdPrev_Nm');
    mbd_line(sys, 'TrqDelta/1',   'SlewLimit/1');
    mbd_line(sys, 'SlewLimit/1',  'TrqRamp/1');
    mbd_line(sys, 'TrqCmdPrev/1', 'TrqRamp/2');
    mbd_line(sys, 'TrqLimMin/1',  'TrqCmdSat/1');
    mbd_line(sys, 'TrqRamp/1',    'TrqCmdSat/2', 'TrqRamp_Nm');
    mbd_line(sys, 'NegTrqLim/1',  'TrqCmdSat/3');
    mbd_line(sys, 'TrqCmdSat/1',  'TrqCmdGate/1');
    mbd_line(sys, 'PwmEnable/1',  'TrqCmdGate/2');
    mbd_line(sys, 'ZeroTrq/1',    'TrqCmdGate/3');
    mbd_line(sys, 'TrqCmdGate/1', 'TrqCmd_Nm/1', 'TrqCmd_Nm');
    mbd_line(sys, 'TrqCmdGate/1', 'TrqCmdPrev/1');
end
