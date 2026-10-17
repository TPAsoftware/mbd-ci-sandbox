function mdl = build_inv_ctrl(outFolder)
%BUILD_INV_CTRL  Build the InvCtrl Simulink model from its scripted definition.
%
%   mdl = build_inv_ctrl()            build InvCtrl and save it as work/InvCtrl.slx
%   mdl = build_inv_ctrl(outFolder)   save it into outFolder instead
%
%   The scripts in model/ are the single source of truth of the model:
%   InvCtrl.slx is a build artefact and is not version controlled. Every
%   design change is a change of these scripts, reviewed as a normal diff.
%   Parameters come from params/inv_ctrl_params.m and are stored in the
%   model workspace.
%
%   Structure (single rate, Ts = 100 us, discrete fixed-step solver):
%     FaultMonitor     debounced OC/OV/UV/OT detection   -> FaultWord, FaultActive
%     InvStateMachine  Stateflow operating state machine -> InvState, PwmEnable, UvMonEna
%     Derating         torque limit and rate limiter     -> TrqLim_Nm, TrqCmd_Nm
%     TorqueToCurrent  current references                -> IqRef_A, IdRef_A
%     CurrentCtrl      d/q PI current control            -> Vd_V, Vq_V
%
%   See docs/REQUIREMENTS.md for the interface and the requirements.

    root = fileparts(fileparts(mfilename('fullpath')));
    if nargin < 1 || isempty(outFolder)
        outFolder = fullfile(root, 'work');
    end
    if ~isfolder(outFolder)
        mkdir(outFolder);
    end

    mdl = 'InvCtrl';
    slxFile = fullfile(outFolder, [mdl '.slx']);
    if bdIsLoaded(mdl)
        close_system(mdl, 0);
    end
    if isfile(slxFile)
        delete(slxFile);
    end

    P = inv_ctrl_params();

    new_system(mdl);
    configureModel(mdl, P.InvCtrl_Ts_s);

    % all parameters live in the model workspace
    hws = get_param(mdl, 'ModelWorkspace');
    names = fieldnames(P);
    for k = 1:numel(names)
        assignin(hws, names{k}, P.(names{k}));
    end

    addRootPorts(mdl, P.InvCtrl_Ts_s);
    add_fault_monitor(mdl, mbd_pos(3, 9, 140, 170));
    add_state_machine(mdl, mbd_pos(5, 2, 170, 200));
    add_derating(mdl, mbd_pos(7, 5, 150, 150));
    add_torque_to_current(mdl, mbd_pos(9, 5, 150, 90));
    add_current_ctrl(mdl, mbd_pos(11, 4, 150, 190));
    connectTopLevel(mdl);

    try
        Simulink.BlockDiagram.arrangeSystem(mdl);
    catch
        % layout only; the model is complete without it
    end

    save_system(mdl, slxFile);
    fprintf('build_inv_ctrl: saved %s\n', slxFile);
end

% =====================================================================================
function configureModel(mdl, Ts)
    set_param(mdl, 'SolverType', 'Fixed-step');
    set_param(mdl, 'Solver', 'FixedStepDiscrete');
    set_param(mdl, 'FixedStep', sprintf('%.10g', Ts));
    set_param(mdl, 'StartTime', '0', 'StopTime', '1');
    set_param(mdl, 'SaveOutput', 'on', 'OutputSaveName', 'yout', 'SaveFormat', 'Dataset');
    set_param(mdl, 'SaveTime', 'on', 'TimeSaveName', 'tout', 'SaveState', 'off');
    set_param(mdl, 'LimitDataPoints', 'off', 'ReturnWorkspaceOutputs', 'on');
    set_param(mdl, 'AlgebraicLoopMsg', 'error');
    set_param(mdl, 'ParameterPrecisionLossMsg', 'none');   % double parameters used as single
    set_param(mdl, 'UnconnectedInputMsg', 'error');
    set_param(mdl, 'UnconnectedOutputMsg', 'error');
    set_param(mdl, 'UnconnectedLineMsg', 'error');
    set_param(mdl, 'Description', sprintf([ ...
        'InvCtrl - inverter control application for a PMSM traction drive, single rate 100 us.\n' ...
        'Built by model/build_inv_ctrl.m (do not edit the .slx). Parameters: params/inv_ctrl_params.m.\n' ...
        'Requirements: docs/REQUIREMENTS.md.']));
end

% =====================================================================================
function addRootPorts(mdl, Ts)
    ts = sprintf('%.10g', Ts);
    % name, data type, dimension (the port number is the row number)
    ins = {
        'EnableReq',     'boolean', '1'
        'TrqEnableReq',  'boolean', '1'
        'FaultReset',    'boolean', '1'
        'PrechargeDone', 'boolean', '1'
        'TrqReq_Nm',     'single',  '1'
        'MotSpd_radps',  'single',  '1'
        'DcLinkVolt_V',  'single',  '1'
        'InvTemp_degC',  'single',  '1'
        'MotTemp_degC',  'single',  '1'
        'PhaseCurr_A',   'single',  '3'
        'Id_A',          'single',  '1'
        'Iq_A',          'single',  '1'};
    for k = 1:size(ins, 1)
        mbd_add('built-in/Inport', [mdl '/' ins{k, 1}], mbd_pos(1, k, 30, 14), ...
                'Port', num2str(k), 'OutDataTypeStr', ins{k, 2}, ...
                'PortDimensions', ins{k, 3}, 'SampleTime', ts, 'Interpolate', 'off');
    end

    outs = {'InvState', 'PwmEnable', 'TrqCmd_Nm', 'TrqLim_Nm', 'IdRef_A', 'IqRef_A', ...
            'Vd_V', 'Vq_V', 'FaultWord'};
    for k = 1:numel(outs)
        mbd_add('built-in/Outport', [mdl '/' outs{k}], mbd_pos(13, k, 30, 14), 'Port', num2str(k));
    end
end

% =====================================================================================
function connectTopLevel(mdl)
    % UvMonEna of the previous task (breaks the FaultMonitor <-> state machine loop)
    mbd_add('built-in/UnitDelay', [mdl '/UvMonEnaPrev'], mbd_pos(4, 13), 'InitialCondition', '0', ...
            'SampleTime', 'InvCtrl_Ts_s');
    % DC-link discharged flag for SAFE_DISCHARGE -> OFF
    mbd_add('built-in/Constant', [mdl '/DischargedVolt'], mbd_pos(3, 2), ...
            'Value', 'InvCtrl_DischargedVolt_V', 'OutDataTypeStr', 'single');
    mbd_add('built-in/RelationalOperator', [mdl '/DcLinkDischargedCheck'], mbd_pos(4, 2), ...
            'Operator', '<', 'OutDataTypeStr', 'boolean');

    % fault monitor
    mbd_line(mdl, 'PhaseCurr_A/1',   'FaultMonitor/1', 'PhaseCurr_A');
    mbd_line(mdl, 'DcLinkVolt_V/1',  'FaultMonitor/2', 'DcLinkVolt_V');
    mbd_line(mdl, 'InvTemp_degC/1',  'FaultMonitor/3', 'InvTemp_degC');
    mbd_line(mdl, 'MotTemp_degC/1',  'FaultMonitor/4', 'MotTemp_degC');
    mbd_line(mdl, 'UvMonEnaPrev/1',  'FaultMonitor/5', 'UvMonEnaPrev');
    mbd_line(mdl, 'FaultMonitor/1',  'FaultWord/1', 'FaultWord');

    % state machine
    mbd_line(mdl, 'DcLinkVolt_V/1',          'DcLinkDischargedCheck/1');
    mbd_line(mdl, 'DischargedVolt/1',        'DcLinkDischargedCheck/2');
    mbd_line(mdl, 'EnableReq/1',             'InvStateMachine/1', 'EnableReq');
    mbd_line(mdl, 'TrqEnableReq/1',          'InvStateMachine/2', 'TrqEnableReq');
    mbd_line(mdl, 'PrechargeDone/1',         'InvStateMachine/3', 'PrechargeDone');
    mbd_line(mdl, 'FaultReset/1',            'InvStateMachine/4', 'FaultReset');
    mbd_line(mdl, 'FaultMonitor/2',          'InvStateMachine/5', 'FaultActive');
    mbd_line(mdl, 'DcLinkDischargedCheck/1', 'InvStateMachine/6', 'DcLinkDischarged');
    mbd_line(mdl, 'InvStateMachine/1',       'InvState/1', 'InvState');
    mbd_line(mdl, 'InvStateMachine/2',       'PwmEnable/1', 'PwmEnable');
    mbd_line(mdl, 'InvStateMachine/3',       'UvMonEnaPrev/1', 'UvMonEna');

    % derating
    mbd_line(mdl, 'TrqReq_Nm/1',       'Derating/1', 'TrqReq_Nm');
    mbd_line(mdl, 'InvTemp_degC/1',    'Derating/2');
    mbd_line(mdl, 'MotTemp_degC/1',    'Derating/3');
    mbd_line(mdl, 'DcLinkVolt_V/1',    'Derating/4');
    mbd_line(mdl, 'InvStateMachine/2', 'Derating/5');
    mbd_line(mdl, 'Derating/1',        'TrqCmd_Nm/1', 'TrqCmd_Nm');
    mbd_line(mdl, 'Derating/2',        'TrqLim_Nm/1', 'TrqLim_Nm');

    % torque to current
    mbd_line(mdl, 'Derating/1',        'TorqueToCurrent/1');
    mbd_line(mdl, 'MotSpd_radps/1',    'TorqueToCurrent/2', 'MotSpd_radps');
    mbd_line(mdl, 'TorqueToCurrent/1', 'IqRef_A/1', 'IqRef_A');
    mbd_line(mdl, 'TorqueToCurrent/2', 'IdRef_A/1', 'IdRef_A');

    % current control
    mbd_line(mdl, 'TorqueToCurrent/2', 'CurrentCtrl/1');
    mbd_line(mdl, 'TorqueToCurrent/1', 'CurrentCtrl/2');
    mbd_line(mdl, 'Id_A/1',            'CurrentCtrl/3', 'Id_A');
    mbd_line(mdl, 'Iq_A/1',            'CurrentCtrl/4', 'Iq_A');
    mbd_line(mdl, 'DcLinkVolt_V/1',    'CurrentCtrl/5');
    mbd_line(mdl, 'InvStateMachine/2', 'CurrentCtrl/6');
    mbd_line(mdl, 'CurrentCtrl/1',     'Vd_V/1', 'Vd_V');
    mbd_line(mdl, 'CurrentCtrl/2',     'Vq_V/1', 'Vq_V');
end
