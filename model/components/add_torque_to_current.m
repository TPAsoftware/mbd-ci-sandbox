function add_torque_to_current(mdl, pos)
%ADD_TORQUE_TO_CURRENT  Add the TorqueToCurrent subsystem (REQ-INV-018, 019).
%
%   Inputs : 1 TrqCmd_Nm, 2 MotSpd_radps
%   Outputs: 1 IqRef_A, 2 IdRef_A
%
%   IqRef_A = TrqCmd_Nm * (1/Kt)
%   IdRef_A = f_FieldWeakening(|MotSpd_radps|)   (1-D table, clipped)

    sys = [mdl '/TorqueToCurrent'];
    mbd_add('built-in/Subsystem', sys, pos, 'TreatAsAtomicUnit', 'on', 'Description', ...
            'q-axis current reference from the torque command, d-axis reference from the field-weakening table (REQ-INV-018, 019).');

    mbd_add('built-in/Inport',  [sys '/TrqCmd_Nm'],    mbd_pos(1, 1, 30, 14), 'Port', '1');
    mbd_add('built-in/Inport',  [sys '/MotSpd_radps'], mbd_pos(1, 3, 30, 14), 'Port', '2');
    mbd_add('built-in/Outport', [sys '/IqRef_A'],      mbd_pos(5, 1, 30, 14), 'Port', '1');
    mbd_add('built-in/Outport', [sys '/IdRef_A'],      mbd_pos(5, 3, 30, 14), 'Port', '2');

    % ---- q axis
    mbd_add('built-in/Gain', [sys '/InvKt'], mbd_pos(3, 1), 'Gain', 'InvCtrl_InvKt_ApNm');
    mbd_line(sys, 'TrqCmd_Nm/1', 'InvKt/1', 'TrqCmd_Nm');
    mbd_line(sys, 'InvKt/1',     'IqRef_A/1', 'IqRef_A');

    % ---- d axis (field weakening)
    mbd_add('built-in/Abs', [sys '/SpdAbs'], mbd_pos(2, 3));
    mbd_add('simulink/Lookup Tables/1-D Lookup Table', [sys '/FieldWeakeningIdRef'], mbd_pos(3, 3), ...
            'Table', 'InvCtrl_FwId_Tbl_A', 'BreakpointsForDimension1', 'InvCtrl_FwId_Bp_radps', ...
            'ExtrapMethod', 'Clip', 'OutDataTypeStr', 'single');
    mbd_line(sys, 'MotSpd_radps/1',        'SpdAbs/1', 'MotSpd_radps');
    mbd_line(sys, 'SpdAbs/1',              'FieldWeakeningIdRef/1', 'MotSpdAbs_radps');
    mbd_line(sys, 'FieldWeakeningIdRef/1', 'IdRef_A/1', 'IdRef_A');
end
