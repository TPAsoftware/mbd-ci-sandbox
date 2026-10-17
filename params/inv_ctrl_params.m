function P = inv_ctrl_params()
%INV_CTRL_PARAMS  Design and calibration parameters of the InvCtrl model.
%
%   P = inv_ctrl_params() returns a struct with one field per parameter.
%   model/build_inv_ctrl.m stores every field in the model workspace of
%   InvCtrl, where blocks and the Stateflow chart reference them by name.
%
%   This file is the single source of truth for all values. The unit is part
%   of every name (_s, _Nm, _A, _V, _degC, _radps, _tk = task cycles).
%   Requirements: docs/REQUIREMENTS.md.

P = struct();

% ---------------------------------------------------------------- general
P.InvCtrl_Ts_s               = 1e-4;     % task period (single rate, 100 us = 10 kHz)

% ---------------------------------------------------------------- state machine (REQ-INV-001..011)
P.InvCtrl_StbyDwell_tk       = 100;      % STANDBY self-test time before PRECHARGE (100 tasks = 10 ms)
P.InvCtrl_DischargedVolt_V   = 60;       % SAFE_DISCHARGE -> OFF below this DC-link voltage

% ---------------------------------------------------------------- derating (REQ-INV-012..017)
P.InvCtrl_TrqMax_Nm          = 350;      % peak torque limit
P.InvCtrl_TrqSlewStep_Nm     = 1;        % max torque command change per task (10 kN*m/s)
P.InvCtrl_InvTempDrt_Bp_degC = [-40 80 90 100 110 120];     % inverter temperature derating: breakpoints
P.InvCtrl_InvTempDrt_Tbl_Nm  = [350 350 300 200 100 0];     % inverter temperature derating: torque limit
P.InvCtrl_MotTempDrt_Bp_degC = [-40 140 150 160 170 180];   % motor winding temperature derating: breakpoints
P.InvCtrl_MotTempDrt_Tbl_Nm  = [350 350 300 200 100 0];     % motor winding temperature derating: torque limit
P.InvCtrl_UdcDrt_Bp_V        = [400 450 550 850 900 950];   % DC-link voltage derating: breakpoints
P.InvCtrl_UdcDrt_Tbl_Nm      = [0 0 350 350 0 0];           % DC-link voltage derating: torque limit

% ---------------------------------------------------------------- torque to current (REQ-INV-018, 019)
P.InvCtrl_InvKt_ApNm         = 2;        % inverse torque constant 1/Kt (Kt = 0.5 N*m/A)
P.InvCtrl_FwId_Bp_radps      = [0 400 500 600 700 800 1000 1200];   % field weakening: |speed| breakpoints
P.InvCtrl_FwId_Tbl_A         = [0 0 0 -80 -160 -240 -360 -450];     % field weakening: d-axis current reference

% ---------------------------------------------------------------- current control (REQ-INV-020..023)
P.InvCtrl_CurCtrl_Kp_VpA     = 0.6283;   % PI proportional gain, L*wc (L = 0.25 mH, wc = 2*pi*400 rad/s)
P.InvCtrl_CurCtrl_KiTs_VpA   = 0.003016; % PI integral gain per task, R*wc*Ts (R = 12 mOhm)
P.InvCtrl_CurCtrl_VmaxFactor = 0.57735;  % voltage vector limit Vmax = Udc/sqrt(3)

% ---------------------------------------------------------------- fault monitor (REQ-INV-024..029)
P.InvCtrl_OcThresh_A         = 900;      % overcurrent threshold, max |phase current|
P.InvCtrl_OcDebounce_tk      = 5;        % overcurrent debounce (0.5 ms)
P.InvCtrl_OvThresh_V         = 920;      % DC-link overvoltage threshold
P.InvCtrl_OvDebounce_tk      = 10;       % overvoltage debounce (1 ms)
P.InvCtrl_UvThresh_V         = 420;      % DC-link undervoltage threshold (monitored in READY and RUN)
P.InvCtrl_UvDebounce_tk      = 20;       % undervoltage debounce (2 ms)
P.InvCtrl_OtInvThresh_degC   = 125;      % inverter over-temperature threshold
P.InvCtrl_OtInvDebounce_tk   = 1000;     % inverter over-temperature debounce (100 ms)
P.InvCtrl_OtMotThresh_degC   = 190;      % motor over-temperature threshold
P.InvCtrl_OtMotDebounce_tk   = 1000;     % motor over-temperature debounce (100 ms)

end
