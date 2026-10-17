classdef (SharedTestFixtures = {InvCtrlModelFixture}) FaultMonitorTest < InvCtrlTestCase
    %FAULTMONITORTEST  MIL tests of FaultMonitor (REQ-INV-024..029) and the fault reaction.

    methods (Test, TestTags = {'REQ-INV-024'})
        function testNoSpuriousFaultAtStartup(tc)
            scn = tc.scenario(0.15);
            scn.step('TrqReq_Nm', 0.090, 50);
            r = tc.simulate(scn);
            tc.savePlot(r, {{'InvState'}, 'state'; {'FaultWord'}, 'FaultWord'}, 'nominal power-up, no fault expected');

            k = tc.firstAt(r.FaultWord ~= 0);
            if ~isempty(k)
                tc.verifyFail(sprintf('REQ-INV-024: FaultWord = 0x%04X at t = %.1f ms with nominal inputs.', ...
                    r.FaultWord(k), 1e3 * r.t(k)));
            end
            tc.verifyFalse(any(r.InvState == tc.S.FAULT), 'REQ-INV-024: InvState must never be FAULT with nominal inputs.');
        end
    end

    methods (Test, TestTags = {'REQ-INV-025', 'REQ-INV-029', 'REQ-INV-008'})
        function testOvercurrentDetection(tc)
            scn = tc.scenario(0.14);
            % 3 tasks above the threshold: too short
            scn.step('PhaseCurr_A', 0.1000, [1000 -500 -500]);
            scn.step('PhaseCurr_A', 0.1003, [0 0 0]);
            % 5 ms just below the threshold
            scn.step('PhaseCurr_A', 0.105, [890 -445 -445]);
            scn.step('PhaseCurr_A', 0.110, [0 0 0]);
            % 2 ms of negative overcurrent on phase b
            scn.step('PhaseCurr_A', 0.120, [500 -1000 500]);
            scn.step('PhaseCurr_A', 0.122, [0 0 0]);
            r = tc.simulate(scn);
            tc.savePlot(r, {{'In_PhaseCurr_A'}, 'phase currents [A]'; {'FaultWord'}, 'FaultWord'; {'InvState'}, 'state'}, ...
                'short pulse, sub-threshold, then -1000 A on phase b for 2 ms');

            oc = tc.bit(r.FaultWord, 0);
            tc.verifyFalse(any(oc(1:tc.idx(0.1199))), ...
                'REQ-INV-025: OC must not be set by a 3-task pulse or by 890 A.');
            k = tc.firstAt(oc);
            tc.assertNotEmpty(k, 'REQ-INV-025: OC (FaultWord bit 0) was not set by -1000 A on phase b for 2 ms.');
            tc.verifyLessThanOrEqual(abs(r.t(k) - 0.1204), tc.Ts + 1e-9, sprintf( ...
                'REQ-INV-025: OC set at t = %.1f ms, expected after 5 tasks at t = 120.4 ms.', 1e3 * r.t(k)));
            kClr = tc.firstAt(~oc, k);
            tc.assertNotEmpty(kClr, 'REQ-INV-029: OC bit never cleared.');
            tc.verifyLessThanOrEqual(abs(r.t(kClr) - 0.122), tc.Ts + 1e-9, sprintf( ...
                'REQ-INV-029: OC cleared at t = %.1f ms, expected t = 122.0 ms.', 1e3 * r.t(kClr)));
            tc.verifyEntryTime(r, 'FAULT', 0.1204, 1, 'REQ-INV-008');
        end
    end

    methods (Test, TestTags = {'REQ-INV-026', 'REQ-INV-029'})
        function testOvervoltageDebounce(tc)
            scn = tc.scenario(0.14);
            scn.step('DcLinkVolt_V', 0.1000, 950);     % 5 tasks: too short
            scn.step('DcLinkVolt_V', 0.1005, 800);
            scn.step('DcLinkVolt_V', 0.1200, 950);     % 5 ms
            scn.step('DcLinkVolt_V', 0.1250, 800);
            r = tc.simulate(scn);
            tc.savePlot(r, {{'In_DcLinkVolt_V'}, 'DC link [V]'; {'FaultWord'}, 'FaultWord'}, 'overvoltage 0.5 ms, then 5 ms');

            ov = tc.bit(r.FaultWord, 1);
            tc.verifyFalse(any(ov(1:tc.idx(0.1199))), 'REQ-INV-026: OV must not be set by a 0.5 ms overvoltage.');
            k = tc.firstAt(ov);
            tc.assertNotEmpty(k, 'REQ-INV-026: OV (FaultWord bit 1) was not set by 950 V for 5 ms.');
            tc.verifyLessThanOrEqual(abs(r.t(k) - 0.1209), tc.Ts + 1e-9, sprintf( ...
                'REQ-INV-026: OV set at t = %.1f ms, expected after 10 tasks at t = 120.9 ms.', 1e3 * r.t(k)));
            kClr = tc.firstAt(~ov, k);
            tc.assertNotEmpty(kClr, 'REQ-INV-029: OV bit never cleared.');
            tc.verifyLessThanOrEqual(abs(r.t(kClr) - 0.125), tc.Ts + 1e-9, sprintf( ...
                'REQ-INV-029: OV cleared at t = %.1f ms, expected t = 125.0 ms.', 1e3 * r.t(kClr)));
        end
    end

    methods (Test, TestTags = {'REQ-INV-027'})
        function testUndervoltageOnlyWhenHvActive(tc)
            % the DC link is below 420 V during the whole power-up (not monitored),
            % then drops to 380 V in RUN
            scn = tc.scenario(0.13);
            scn.step('DcLinkVolt_V', 0.100, 380);
            r = tc.simulate(scn);
            tc.savePlot(r, {{'In_DcLinkVolt_V'}, 'DC link [V]'; {'FaultWord'}, 'FaultWord'; {'InvState'}, 'state'}, ...
                'undervoltage during power-up (not monitored) and in RUN');

            uv = tc.bit(r.FaultWord, 2);
            tc.verifyFalse(any(uv(1:tc.idx(0.0999))), ...
                'REQ-INV-027: UV must not be reported before READY (DC link not yet charged).');
            k = tc.firstAt(uv);
            tc.assertNotEmpty(k, 'REQ-INV-027: UV (FaultWord bit 2) was not set by 380 V in RUN.');
            tc.verifyLessThanOrEqual(abs(r.t(k) - 0.1019), tc.Ts + 1e-9, sprintf( ...
                'REQ-INV-027: UV set at t = %.1f ms, expected after 20 tasks at t = 101.9 ms.', 1e3 * r.t(k)));
            tc.verifyEntryTime(r, 'FAULT', 0.1019, 1, 'REQ-INV-008');
        end
    end

    methods (Test, TestTags = {'REQ-INV-028'})
        function testOverTemperatureDebounce(tc)
            scn = tc.scenario(0.27);
            scn.step('InvTemp_degC', 0.100, 130);
            scn.step('MotTemp_degC', 0.150, 195);
            r = tc.simulate(scn);
            tc.savePlot(r, {{'In_InvTemp_degC', 'In_MotTemp_degC'}, 'temperature [degC]'; {'FaultWord'}, 'FaultWord'}, ...
                'inverter 130 degC from 100 ms, motor 195 degC from 150 ms');

            otInv = tc.bit(r.FaultWord, 3);
            otMot = tc.bit(r.FaultWord, 4);
            k3 = tc.firstAt(otInv);
            k4 = tc.firstAt(otMot);
            tc.assertNotEmpty(k3, 'REQ-INV-028: OT_INV (bit 3) was not set by 130 degC for 170 ms.');
            tc.assertNotEmpty(k4, 'REQ-INV-028: OT_MOT (bit 4) was not set by 195 degC for 120 ms.');
            tc.verifyLessThanOrEqual(abs(r.t(k3) - 0.1999), tc.Ts + 1e-9, sprintf( ...
                'REQ-INV-028: OT_INV set at t = %.1f ms, expected after 100 ms at t = 199.9 ms.', 1e3 * r.t(k3)));
            tc.verifyLessThanOrEqual(abs(r.t(k4) - 0.2499), tc.Ts + 1e-9, sprintf( ...
                'REQ-INV-028: OT_MOT set at t = %.1f ms, expected after 100 ms at t = 249.9 ms.', 1e3 * r.t(k4)));
        end
    end
end
