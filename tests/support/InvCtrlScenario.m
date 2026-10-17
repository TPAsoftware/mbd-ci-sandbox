classdef InvCtrlScenario < handle
    %INVCTRLSCENARIO  Time-based stimulus for the root inputs of InvCtrl.
    %
    %   s = InvCtrlScenario(stopTime)               standard power-up, Udc 800 V, speed 0
    %   s = InvCtrlScenario(stopTime, 'Udc', 600)
    %   s.step('TrqReq_Nm', 0.100, 250);            value 250 from t = 100 ms on
    %   s.ramp('InvTemp_degC', 0.1, 0.6, 70, 120);  linear ramp, then hold the end value
    %   ds = s.toDataset();                         external input for Simulink.SimulationInput
    %
    %   Standard power-up (every scenario starts with it):
    %     t = 0      EnableReq 0, TrqEnableReq 0, FaultReset 0, PrechargeDone 0, TrqReq 0,
    %                speed 0, Udc 0 V, InvTemp 40 degC, MotTemp 60 degC, phase currents 0,
    %                Id 0, Iq 0
    %     t = 10 ms  EnableReq 1                  -> STANDBY
    %     t = 20 ms  self-test done               -> PRECHARGE; Udc ramps 0 -> Udc in 40 ms
    %     t = 65 ms  PrechargeDone 1              -> READY
    %     t = 80 ms  TrqEnableReq 1               -> RUN
    %
    %   Per signal, the event with the latest start time at or before t defines the
    %   value (equal start times: the event added last wins). Values are sampled at
    %   every task (Ts = 100 us) and held between samples.

    properties (Constant)
        % root inputs in port order
        Signals = {'EnableReq', 'TrqEnableReq', 'FaultReset', 'PrechargeDone', 'TrqReq_Nm', ...
                   'MotSpd_radps', 'DcLinkVolt_V', 'InvTemp_degC', 'MotTemp_degC', ...
                   'PhaseCurr_A', 'Id_A', 'Iq_A'}
        Types   = {'boolean', 'boolean', 'boolean', 'boolean', 'single', ...
                   'single', 'single', 'single', 'single', ...
                   'single', 'single', 'single'}
        Widths  = [1 1 1 1 1 1 1 1 1 3 1 1]
        T_ENABLE     = 0.010
        T_PRECHARGE  = 0.020
        T_PRECH_END  = 0.060
        T_PRECH_DONE = 0.065
        T_RUN        = 0.080
    end

    properties
        StopTime (1, 1) double
        Ts       (1, 1) double = 1e-4
        UdcNom   (1, 1) double = 800
        Events   struct = struct('Signal', {}, 'Kind', {}, 't0', {}, 't1', {}, 'v0', {}, 'v1', {}, 'Seq', {})
    end

    methods
        function obj = InvCtrlScenario(stopTime, varargin)
            ip = inputParser;
            ip.addParameter('Udc', 800);
            ip.addParameter('Spd', 0);
            ip.parse(varargin{:});
            obj.StopTime = stopTime;
            obj.UdcNom   = ip.Results.Udc;

            obj.step('EnableReq',     0, 0);
            obj.step('EnableReq',     obj.T_ENABLE, 1);
            obj.step('TrqEnableReq',  0, 0);
            obj.step('TrqEnableReq',  obj.T_RUN, 1);
            obj.step('FaultReset',    0, 0);
            obj.step('PrechargeDone', 0, 0);
            obj.step('PrechargeDone', obj.T_PRECH_DONE, 1);
            obj.step('TrqReq_Nm',     0, 0);
            obj.step('MotSpd_radps',  0, ip.Results.Spd);
            obj.step('DcLinkVolt_V',  0, 0);
            obj.ramp('DcLinkVolt_V',  obj.T_PRECHARGE, obj.T_PRECH_END, 0, obj.UdcNom);
            obj.step('InvTemp_degC',  0, 40);
            obj.step('MotTemp_degC',  0, 60);
            obj.step('PhaseCurr_A',   0, [0 0 0]);
            obj.step('Id_A',          0, 0);
            obj.step('Iq_A',          0, 0);
        end

        function obj = step(obj, sig, t, v)
            obj.addEvent(sig, 'step', t, t, v, v);
        end

        function obj = ramp(obj, sig, t0, t1, v0, v1)
            if t1 <= t0
                error('InvCtrlScenario:ramp', 'Ramp end time must be after its start time.');
            end
            obj.addEvent(sig, 'ramp', t0, t1, v0, v1);
        end

        function t = time(obj)
            n = round(obj.StopTime / obj.Ts) + 1;
            t = (0:n - 1)' * obj.Ts;
        end

        function v = sample(obj, sig)
            %SAMPLE  Values of one signal at every task (N x width, double).
            t = obj.time();
            w = obj.Widths(strcmp(obj.Signals, sig));
            v = zeros(numel(t), w);
            ev = obj.Events(strcmp({obj.Events.Signal}, sig));
            if isempty(ev)
                return
            end
            [~, order] = sortrows([[ev.t0]' [ev.Seq]']);
            ev = ev(order);
            for i = 1:numel(ev)
                e = ev(i);
                k0 = round(e.t0 / obj.Ts) + 1;
                if k0 > numel(t)
                    continue
                end
                kk = (k0:numel(t))';
                if strcmp(e.Kind, 'step')
                    v(kk, :) = repmat(e.v0(:)', numel(kk), 1);
                else
                    a = min(max((t(kk) - e.t0) / (e.t1 - e.t0), 0), 1);
                    v(kk, :) = e.v0(:)' + a .* (e.v1(:)' - e.v0(:)');
                end
            end
        end

        function ds = toDataset(obj)
            %TODATASET  Root-level external input (one element per input port, in port order).
            t = obj.time();
            ds = Simulink.SimulationData.Dataset;
            for i = 1:numel(obj.Signals)
                v = obj.sample(obj.Signals{i});
                switch obj.Types{i}
                    case 'boolean'
                        v = logical(v);
                    case 'single'
                        v = single(v);
                end
                ts = timeseries(v, t, 'Name', obj.Signals{i});
                ds = ds.addElement(ts, obj.Signals{i});
            end
        end
    end

    methods (Access = private)
        function addEvent(obj, sig, kind, t0, t1, v0, v1)
            k = find(strcmp(obj.Signals, sig), 1);
            if isempty(k)
                error('InvCtrlScenario:signal', 'Unknown input signal %s.', sig);
            end
            if numel(v0) ~= obj.Widths(k) || numel(v1) ~= obj.Widths(k)
                error('InvCtrlScenario:width', 'Signal %s needs %d value(s).', sig, obj.Widths(k));
            end
            e = struct('Signal', sig, 'Kind', kind, 't0', t0, 't1', t1, ...
                       'v0', double(v0), 'v1', double(v1), 'Seq', numel(obj.Events) + 1);
            obj.Events(end + 1) = e;
        end
    end
end
