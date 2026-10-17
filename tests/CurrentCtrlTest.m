classdef (SharedTestFixtures = {InvCtrlModelFixture}) CurrentCtrlTest < InvCtrlTestCase
    %CURRENTCTRLTEST  Open-loop MIL tests of CurrentCtrl (REQ-INV-020..023).
    %   The measured currents Id_A / Iq_A are test inputs, so the controller
    %   response to a defined error can be checked exactly.

    properties (Constant)
        Kp   = 0.6283       % REQ-INV-020 [V/A]
        KiTs = 0.003016     % REQ-INV-020 [V/A per task]
    end

    methods (Test, TestTags = {'REQ-INV-020'})
        function testPiResponseOpenLoop(tc)
            % IdRef = 0 at standstill, Id = -10 A  ->  constant d-axis error of +10 A
            scn = tc.scenario(0.12);
            scn.step('Id_A', 0, -10);
            r = tc.simulate(scn);
            tc.savePlot(r, {{'Vd_V', 'Vq_V'}, 'voltage [V]'; {'PwmEnable'}, 'PWM'}, ...
                'constant d-axis error of 10 A from RUN entry on');

            k0 = tc.firstAt(r.PwmEnable);
            tc.assertNotEmpty(k0, 'PwmEnable never became TRUE.');
            tc.verifyEqual(r.Vd_V(k0), tc.Kp * 10, 'AbsTol', 1e-3, sprintf( ...
                'REQ-INV-020: first Vd_V in RUN is %.4f V, expected Kp * 10 A = %.4f V.', r.Vd_V(k0), tc.Kp * 10));
            slope = (r.Vd_V(k0 + 200) - r.Vd_V(k0)) / 200;
            tc.verifyEqual(slope, tc.KiTs * 10, 'AbsTol', 1e-5, sprintf( ...
                'REQ-INV-020: Vd_V rises by %.6f V per task, expected KiTs * 10 A = %.6f V.', slope, tc.KiTs * 10));
            tc.verifyEqual(max(abs(r.Vq_V)), 0, 'AbsTol', 1e-6, 'REQ-INV-020: Vq_V must stay 0 without a q-axis error.');
        end
    end

    methods (Test, TestTags = {'REQ-INV-021'})
        function testAntiWindupRecovery(tc)
            % q axis driven into the voltage limit for about 95 ms (open loop, Iq = 0),
            % then the error changes sign (Iq = 700 A > IqRef = 600 A)
            scn = tc.scenario(0.25);
            scn.step('TrqReq_Nm', 0.085, 300);
            scn.step('Iq_A', 0.200, 700);
            r = tc.simulate(scn);
            tc.savePlot(r, {{'Vq_V'}, 'voltage [V]'; {'IqRef_A', 'In_Iq_A'}, 'current [A]'}, ...
                'q axis in the voltage limit, error reverses at 200 ms');

            vmax = 800 / sqrt(3);
            kRev = tc.idx(0.200);
            tc.verifyEqual(r.Vq_V(kRev - 1), vmax, 'RelTol', 1e-3, sprintf( ...
                'Precondition: Vq_V must be in the voltage limit (%.1f V) before the error reverses; it is %.1f V.', ...
                vmax, r.Vq_V(kRev - 1)));
            kOut = tc.firstAt(r.Vq_V < vmax - 1, kRev);
            if isempty(kOut)
                tc.verifyFail(sprintf(['REQ-INV-021: Vq_V stayed in the voltage limit (%.1f V) until the end of the ' ...
                    'test after the error became negative at t = 200 ms: integrator wind-up.'], vmax));
                return
            end
            tc.verifyLessThanOrEqual(kOut - kRev, 1, sprintf( ...
                'REQ-INV-021: Vq_V left the voltage limit %.1f ms after the error became negative (max 1 task): integrator wind-up.', ...
                (kOut - kRev) * tc.Ts * 1e3));
            seg = r.Vq_V(kOut:kOut + 100);
            tc.verifyTrue(all(diff(seg) < 0), ...
                'REQ-INV-021: Vq_V must decrease in every task after the error became negative.');
        end
    end

    methods (Test, TestTags = {'REQ-INV-022'})
        function testVoltageVectorLimit(tc)
            scn = tc.scenario(0.50);
            scn.step('TrqReq_Nm', 0.085, 300);        % q axis into the limit (open loop)
            scn.step('Id_A', 0.200, 100);             % d-axis error -100 A
            scn.step('DcLinkVolt_V', 0.400, 600);     % lower DC link
            r = tc.simulate(scn);
            tc.savePlot(r, {{'Vd_V', 'Vq_V'}, 'voltage [V]'; {'In_DcLinkVolt_V'}, 'DC link [V]'}, ...
                'q axis saturated, then d-axis demand, then DC link 800 -> 600 V');

            vabs = hypot(r.Vd_V, r.Vq_V);
            vmax = r.In_DcLinkVolt_V / sqrt(3);
            [excess, k] = max(vabs - vmax .* (1 + 1e-5));
            tc.verifyLessThanOrEqual(excess, 1e-3, sprintf( ...
                'REQ-INV-022: |V| = %.2f V exceeds Udc/sqrt(3) = %.2f V at t = %.1f ms.', vabs(k), vmax(k), 1e3 * r.t(k)));
            k1 = tc.idx(0.150);
            tc.verifyEqual(vabs(k1), vmax(k1), 'RelTol', 1e-3, sprintf( ...
                'REQ-INV-022: the voltage limit must be used: |V| = %.1f V, Udc/sqrt(3) = %.1f V at t = 150 ms.', ...
                vabs(k1), vmax(k1)));
            k2 = tc.idx(0.450);
            tc.verifyEqual(r.Vd_V(k2), -vmax(k2), 'RelTol', 1e-3, sprintf( ...
                'REQ-INV-022: d-axis priority: Vd_V = %.1f V, expected %.1f V at t = 450 ms.', r.Vd_V(k2), -vmax(k2)));
            tc.verifyEqual(r.Vq_V(k2), 0, 'AbsTol', 1e-2, sprintf( ...
                'REQ-INV-022: d-axis priority: Vq_V = %.2f V, expected 0 V when Vd_V uses the full limit.', r.Vq_V(k2)));
        end
    end

    methods (Test, TestTags = {'REQ-INV-023'})
        function testOutputsZeroWhenPwmDisabled(tc)
            scn = tc.scenario(0.20);
            scn.step('Id_A', 0, 50);
            scn.step('Iq_A', 0, -40);
            scn.step('TrqEnableReq', 0.150, 0);       % RUN -> READY
            scn.step('TrqEnableReq', 0.170, 1);       % READY -> RUN
            r = tc.simulate(scn);
            tc.savePlot(r, {{'Vd_V', 'Vq_V'}, 'voltage [V]'; {'PwmEnable'}, 'PWM'}, ...
                'current errors present while PWM is off');

            off = ~r.PwmEnable;
            tc.verifyEqual(max(abs([r.Vd_V(off); r.Vq_V(off)])), 0, ...
                'REQ-INV-023: Vd_V and Vq_V must be 0 while PwmEnable is FALSE.');
            k = tc.firstAt(r.PwmEnable, tc.idx(0.160));
            tc.assertNotEmpty(k, 'Precondition: RUN must be re-entered at t = 170 ms.');
            tc.verifyEqual(r.Vd_V(k), tc.Kp * -50, 'AbsTol', 1e-3, sprintf( ...
                'REQ-INV-023: Vd_V = %.3f V in the first task after re-entering RUN, expected %.3f V (integrator reset).', ...
                r.Vd_V(k), tc.Kp * -50));
        end
    end
end
