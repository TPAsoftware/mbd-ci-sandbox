classdef (SharedTestFixtures = {InvCtrlModelFixture}) DeratingTest < InvCtrlTestCase
    %DERATINGTEST  MIL tests of Derating (REQ-INV-012..017).
    %   Expected tables are taken from docs/REQUIREMENTS.md, not from the
    %   parameter file, so a wrong calibration is detected.

    properties (Constant)
        InvTempBp  = [-40 80 90 100 110 120]       % REQ-INV-013
        InvTempTbl = [350 350 300 200 100 0]
        MotTempBp  = [-40 140 150 160 170 180]     % REQ-INV-014
        MotTempTbl = [350 350 300 200 100 0]
        UdcBp      = [400 450 550 850 900 950]     % REQ-INV-015
        UdcTbl     = [0 0 350 350 0 0]
        TolNm      = 1
    end

    methods (Test, TestTags = {'REQ-INV-012', 'REQ-INV-013'})
        function testInverterTempDerating(tc)
            scn = tc.scenario(0.80);
            scn.step('TrqReq_Nm', 0.085, 400);
            scn.ramp('InvTemp_degC', 0.100, 0.750, 60, 125);
            r = tc.simulate(scn);
            tc.savePlot(r, {{'In_InvTemp_degC'}, 'temperature [degC]'; {'TrqLim_Nm', 'TrqCmd_Nm'}, 'torque [N*m]'}, ...
                'inverter temperature ramp 60 -> 125 degC, request 400 N*m');

            k = tc.idx(0.065):numel(r.t);      % DC link charged: only the temperature limit is active
            tc.verifyLimit(r, tc.expectedLimit(r), 'REQ-INV-013', 'InvTemp_degC', r.In_InvTemp_degC, k);
            tc.verifyTableUsed(r, k, 'REQ-INV-013');
            tc.verifyCommandWithinLimit(r);
        end
    end

    methods (Test, TestTags = {'REQ-INV-012', 'REQ-INV-014'})
        function testMotorTempDerating(tc)
            scn = tc.scenario(0.70);
            scn.step('TrqReq_Nm', 0.085, 400);
            scn.ramp('MotTemp_degC', 0.100, 0.650, 130, 185);
            r = tc.simulate(scn);
            tc.savePlot(r, {{'In_MotTemp_degC'}, 'temperature [degC]'; {'TrqLim_Nm', 'TrqCmd_Nm'}, 'torque [N*m]'}, ...
                'motor temperature ramp 130 -> 185 degC, request 400 N*m');

            k = tc.idx(0.065):numel(r.t);      % DC link charged: only the temperature limit is active
            tc.verifyLimit(r, tc.expectedLimit(r), 'REQ-INV-014', 'MotTemp_degC', r.In_MotTemp_degC, k);
            tc.verifyTableUsed(r, k, 'REQ-INV-014');
            tc.verifyCommandWithinLimit(r);
        end
    end

    methods (Test, TestTags = {'REQ-INV-012', 'REQ-INV-015'})
        function testDcLinkVoltageDerating(tc)
            scn = tc.scenario(0.65);
            scn.step('TrqReq_Nm', 0.085, -400);
            scn.ramp('DcLinkVolt_V', 0.100, 0.200, 800, 915);
            scn.ramp('DcLinkVolt_V', 0.250, 0.600, 915, 430);
            r = tc.simulate(scn);
            tc.savePlot(r, {{'In_DcLinkVolt_V'}, 'DC link [V]'; {'TrqLim_Nm', 'TrqCmd_Nm'}, 'torque [N*m]'}, ...
                'DC-link voltage 800 -> 915 -> 430 V, request -400 N*m');

            k = 1:numel(r.t);                  % including the power-up with the DC link at 0 V
            tc.verifyLimit(r, tc.expectedLimit(r), 'REQ-INV-015', 'DcLinkVolt_V', r.In_DcLinkVolt_V, k);
            tc.verifyTableUsed(r, tc.idx(0.065):numel(r.t), 'REQ-INV-015');
            tc.verifyCommandWithinLimit(r);
        end
    end

    methods (Test, TestTags = {'REQ-INV-016'})
        function testTorqueRateLimit(tc)
            scn = tc.scenario(0.20);
            scn.step('TrqReq_Nm', 0.100, 200);
            scn.step('TrqReq_Nm', 0.150, -150);
            r = tc.simulate(scn);
            tc.savePlot(r, {{'TrqCmd_Nm'}, 'torque [N*m]'}, 'torque request steps 0 -> 200 -> -150 N*m in RUN');

            d = abs(diff(r.TrqCmd_Nm));
            [dMax, kMax] = max(d);
            tc.verifyLessThanOrEqual(dMax, 1 + 1e-4, sprintf( ...
                'REQ-INV-016: TrqCmd_Nm changed by %.3f N*m in one task at t = %.1f ms (max 1 N*m).', dMax, 1e3 * r.t(kMax + 1)));
            tc.verifyEqual(r.TrqCmd_Nm(tc.idx(0.110)), 101, 'AbsTol', 1.01, ...
                'REQ-INV-016: TrqCmd_Nm 10 ms after the step must be 101 N*m (1 N*m per task).');
            tc.verifyEqual(r.TrqCmd_Nm(tc.idx(0.1205):tc.idx(0.1499)), 200 * ones(numel(tc.idx(0.1205):tc.idx(0.1499)), 1), ...
                'AbsTol', 0.01, 'REQ-INV-016: TrqCmd_Nm must settle at the request of 200 N*m.');
            tc.verifyEqual(r.TrqCmd_Nm(end), -150, 'AbsTol', 0.01, ...
                'REQ-INV-016: TrqCmd_Nm must settle at the request of -150 N*m.');
        end
    end

    methods (Test, TestTags = {'REQ-INV-017'})
        function testTorqueZeroOutsideRun(tc)
            scn = tc.scenario(0.20);
            scn.step('TrqReq_Nm', 0, 120);              % requested from power-up on
            scn.step('TrqEnableReq', 0.150, 0);         % RUN -> READY
            scn.step('TrqEnableReq', 0.170, 1);         % READY -> RUN
            r = tc.simulate(scn);
            tc.savePlot(r, {{'InvState'}, 'state'; {'TrqCmd_Nm', 'In_TrqReq_Nm'}, 'torque [N*m]'}, ...
                'torque requested before RUN, RUN left at 150 ms and re-entered at 170 ms');

            notRun = r.InvState ~= tc.S.RUN;
            tc.verifyEqual(max(abs(r.TrqCmd_Nm(notRun))), 0, ...
                'REQ-INV-017: TrqCmd_Nm must be 0 whenever InvState is not RUN.');
            entries = find(diff(double(r.InvState == tc.S.RUN)) == 1) + 1;
            tc.assertNumElements(entries, 2, 'RUN must be entered twice in this scenario.');
            for k = reshape(entries, 1, [])
                tc.verifyLessThanOrEqual(abs(r.TrqCmd_Nm(k)), 1 + 1e-4, sprintf( ...
                    'REQ-INV-017: TrqCmd_Nm = %.2f N*m in the first RUN task at t = %.1f ms (must start from 0).', ...
                    r.TrqCmd_Nm(k), 1e3 * r.t(k)));
            end
        end
    end

    methods (Access = private)
        function y = interpTable(~, bp, tbl, x)
            %INTERPTABLE  Linear interpolation, clipped outside the breakpoints.
            y = interp1(bp, tbl, min(max(x, bp(1)), bp(end)), 'linear');
        end

        function y = expectedLimit(tc, r)
            %EXPECTEDLIMIT  REQ-INV-012: min(350 N*m, f_InvTemp, f_MotTemp, f_Udc).
            y = min([350 * ones(numel(r.t), 1), ...
                     tc.interpTable(tc.InvTempBp, tc.InvTempTbl, r.In_InvTemp_degC), ...
                     tc.interpTable(tc.MotTempBp, tc.MotTempTbl, r.In_MotTemp_degC), ...
                     tc.interpTable(tc.UdcBp, tc.UdcTbl, r.In_DcLinkVolt_V)], [], 2);
        end

        function verifyTableUsed(tc, r, k, req)
            %VERIFYTABLEUSED  The scenario must drive the limit through the whole table (350 -> 0 N*m).
            tc.verifyGreaterThanOrEqual(max(r.TrqLim_Nm(k)), 349, sprintf( ...
                '%s: precondition: the scenario must start at the full limit of 350 N*m.', req));
            tc.verifyLessThanOrEqual(min(r.TrqLim_Nm(k)), 1, sprintf( ...
                '%s: precondition: the scenario must reach the end of the table (0 N*m).', req));
        end

        function verifyLimit(tc, r, expected, req, inputName, inputValues, k)
            if nargin < 7
                k = 1:numel(r.t);
            end
            err = abs(r.TrqLim_Nm(k) - expected(k));
            [eMax, i] = max(err);
            kk = k(i);
            tc.verifyLessThanOrEqual(eMax, tc.TolNm, sprintf( ...
                '%s: TrqLim_Nm = %.2f N*m at %s = %.2f (t = %.1f ms), expected %.2f N*m (tolerance %g N*m).', ...
                req, r.TrqLim_Nm(kk), inputName, inputValues(kk), 1e3 * r.t(kk), expected(kk), tc.TolNm));
        end

        function verifyCommandWithinLimit(tc, r)
            excess = abs(r.TrqCmd_Nm) - r.TrqLim_Nm;
            [eMax, k] = max(excess);
            tc.verifyLessThanOrEqual(eMax, 1e-3, sprintf( ...
                'REQ-INV-012: |TrqCmd_Nm| = %.2f N*m exceeds TrqLim_Nm = %.2f N*m at t = %.1f ms.', ...
                abs(r.TrqCmd_Nm(k)), r.TrqLim_Nm(k), 1e3 * r.t(k)));
        end
    end
end
