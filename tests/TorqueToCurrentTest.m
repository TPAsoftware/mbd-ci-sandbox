classdef (SharedTestFixtures = {InvCtrlModelFixture}) TorqueToCurrentTest < InvCtrlTestCase
    %TORQUETOCURRENTTEST  MIL tests of TorqueToCurrent (REQ-INV-018, 019).

    properties (Constant)
        Kt_NmpA = 0.5                                   % REQ-INV-018
        FwBp    = [0 400 500 600 700 800 1000 1200]     % REQ-INV-019
        FwTbl   = [0 0 0 -80 -160 -240 -360 -450]
    end

    methods (Test, TestTags = {'REQ-INV-018'})
        function testIqRefScaling(tc)
            scn = tc.scenario(0.30);
            scn.step('TrqReq_Nm', 0.090, 100);
            scn.step('TrqReq_Nm', 0.140, -150);
            scn.step('TrqReq_Nm', 0.200, 300);
            r = tc.simulate(scn);
            tc.savePlot(r, {{'TrqCmd_Nm'}, 'torque [N*m]'; {'IqRef_A'}, 'current [A]'}, ...
                'torque command 100 -> -150 -> 300 N*m');

            expected = r.TrqCmd_Nm / tc.Kt_NmpA;
            [eMax, k] = max(abs(r.IqRef_A - expected));
            tc.verifyLessThanOrEqual(eMax, 0.1, sprintf( ...
                'REQ-INV-018: IqRef_A = %.3f A at TrqCmd_Nm = %.3f N*m (t = %.1f ms), expected %.3f A.', ...
                r.IqRef_A(k), r.TrqCmd_Nm(k), 1e3 * r.t(k), expected(k)));
            tc.verifyEqual(r.IqRef_A(tc.idx(0.130)), 200, 'AbsTol', 0.1, ...
                'REQ-INV-018: IqRef_A must be 200 A at 100 N*m.');
            tc.verifyEqual(r.IqRef_A(end), 600, 'AbsTol', 0.1, ...
                'REQ-INV-018: IqRef_A must be 600 A at 300 N*m.');
        end
    end

    methods (Test, TestTags = {'REQ-INV-019'})
        function testFieldWeakeningIdRef(tc)
            scn = tc.scenario(0.90);
            scn.ramp('MotSpd_radps', 0.050, 0.850, -1300, 1300);
            r = tc.simulate(scn);
            tc.savePlot(r, {{'In_MotSpd_radps'}, 'speed [rad/s]'; {'IdRef_A'}, 'current [A]'}, ...
                'speed ramp -1300 -> 1300 rad/s');

            spd = abs(r.In_MotSpd_radps);
            expected = interp1(tc.FwBp, tc.FwTbl, min(max(spd, tc.FwBp(1)), tc.FwBp(end)), 'linear');
            [eMax, k] = max(abs(r.IdRef_A - expected));
            tc.verifyLessThanOrEqual(eMax, 0.5, sprintf( ...
                'REQ-INV-019: IdRef_A = %.2f A at MotSpd_radps = %.1f rad/s (t = %.1f ms), expected %.2f A.', ...
                r.IdRef_A(k), r.In_MotSpd_radps(k), 1e3 * r.t(k), expected(k)));
        end
    end
end
