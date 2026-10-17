classdef (SharedTestFixtures = {InvCtrlModelFixture}) StateMachineTest < InvCtrlTestCase
    %STATEMACHINETEST  MIL tests of InvStateMachine (REQ-INV-001..011).

    methods (Test, TestTags = {'REQ-INV-001', 'REQ-INV-002', 'REQ-INV-003', 'REQ-INV-004', 'REQ-INV-005', 'REQ-INV-011'})
        function testNominalStartupSequence(tc)
            scn = tc.scenario(0.12);
            r = tc.simulate(scn);
            tc.savePlot(r, {{'InvState'}, 'state'; {'PwmEnable', 'In_EnableReq', 'In_PrechargeDone', 'In_TrqEnableReq'}, 'flags'}, ...
                'standard power-up OFF -> STANDBY -> PRECHARGE -> READY -> RUN');

            tc.verifyEqual(r.InvState(1), tc.S.OFF, 'REQ-INV-001: InvState after power-up must be OFF.');
            tc.verifyFalse(r.PwmEnable(1), 'REQ-INV-001: PwmEnable after power-up must be FALSE.');
            expected = [tc.S.OFF tc.S.STANDBY tc.S.PRECHARGE tc.S.READY tc.S.RUN];
            seq = tc.stateSequence(r.InvState);
            tc.verifyEqual(seq, expected, sprintf('State sequence is %s, expected %s.', ...
                tc.stateList(seq), tc.stateList(expected)));
            tc.verifyEntryTime(r, 'STANDBY',   scn.T_ENABLE,          1, 'REQ-INV-002');
            tc.verifyEntryTime(r, 'PRECHARGE', scn.T_ENABLE + 0.010,  2, 'REQ-INV-003');
            tc.verifyEntryTime(r, 'READY',     scn.T_PRECH_DONE,      1, 'REQ-INV-004');
            tc.verifyEntryTime(r, 'RUN',       scn.T_RUN,             1, 'REQ-INV-005');
            tc.verifyEqual(r.PwmEnable, r.InvState == tc.S.RUN, ...
                'REQ-INV-011: PwmEnable must be TRUE if and only if InvState is RUN.');
        end
    end

    methods (Test, TestTags = {'REQ-INV-005', 'REQ-INV-011'})
        function testTorqueDisableReturnsToReady(tc)
            scn = tc.scenario(0.15);
            scn.step('TrqEnableReq', 0.100, 0);
            r = tc.simulate(scn);
            tc.savePlot(r, {{'InvState'}, 'state'; {'PwmEnable', 'In_TrqEnableReq'}, 'flags'}, ...
                'TrqEnableReq FALSE at 100 ms: RUN -> READY');

            tc.verifyStateAt(r, 0.0995, 'RUN', 'REQ-INV-005');
            tc.verifyStateAt(r, 0.1002, 'READY', 'REQ-INV-005');
            tc.verifyStateAt(r, 0.1500, 'READY', 'REQ-INV-005');
            k = tc.idx(0.1002);
            tc.verifyFalse(any(r.PwmEnable(k:end)), 'REQ-INV-011: PwmEnable must be FALSE in READY.');
        end
    end

    methods (Test, TestTags = {'REQ-INV-006', 'REQ-INV-007'})
        function testDisableDischargesThenOff(tc)
            scn = tc.scenario(0.20);
            scn.step('EnableReq', 0.100, 0);
            scn.ramp('DcLinkVolt_V', 0.100, 0.150, 800, 0);
            r = tc.simulate(scn);
            tc.savePlot(r, {{'InvState'}, 'state'; {'In_DcLinkVolt_V'}, 'DC link [V]'}, ...
                'EnableReq FALSE at 100 ms: RUN -> SAFE_DISCHARGE -> OFF below 60 V');

            tc.verifyEntryTime(r, 'SAFE_DISCHARGE', 0.100, 1, 'REQ-INV-006');
            kLow = tc.firstAt(r.In_DcLinkVolt_V < 60, tc.idx(0.100));
            kOff = tc.firstAt(r.InvState == tc.S.OFF, tc.idx(0.100));
            tc.assertNotEmpty(kOff, 'REQ-INV-007: InvState never returned to OFF.');
            tc.verifyLessThanOrEqual(abs(kOff - kLow), 1, sprintf( ...
                'REQ-INV-007: OFF entered at t = %.1f ms, DC link below 60 V from t = %.1f ms.', 1e3 * r.t(kOff), 1e3 * r.t(kLow)));
            tc.verifyTrue(all(r.InvState(tc.idx(0.1002):kOff - 1) == tc.S.SAFE_DISCHARGE), ...
                'REQ-INV-006: InvState must stay SAFE_DISCHARGE until the DC link is discharged.');
            tc.verifyFalse(any(r.PwmEnable(tc.idx(0.1002):end)), 'PwmEnable must be FALSE after the disable request.');
        end
    end

    methods (Test, TestTags = {'REQ-INV-008', 'REQ-INV-009', 'REQ-INV-010'})
        function testFaultLatchedUntilReset(tc)
            % overcurrent on phase a in RUN, a FaultReset pulse while the fault is
            % still active (ignored), then a FaultReset pulse with no active fault
            scn = tc.scenario(0.18);
            scn.step('PhaseCurr_A', 0.100, [1000 -500 -500]);
            scn.step('PhaseCurr_A', 0.110, [0 0 0]);
            scn.step('FaultReset',  0.105, 1);
            scn.step('FaultReset',  0.108, 0);
            scn.step('FaultReset',  0.150, 1);
            scn.step('FaultReset',  0.155, 0);
            r = tc.simulate(scn);
            tc.savePlot(r, {{'InvState'}, 'state'; {'FaultWord'}, 'FaultWord'; {'In_FaultReset', 'PwmEnable'}, 'flags'}, ...
                'overcurrent 100..110 ms, FaultReset pulses at 105 ms (fault active) and 150 ms');

            tc.verifyEntryTime(r, 'FAULT', 0.1004, 1, 'REQ-INV-008');
            kFault = tc.firstAt(r.InvState == tc.S.FAULT);
            kReset = tc.idx(0.150);
            tc.assertNotEmpty(kFault, 'REQ-INV-008: InvState never entered FAULT.');
            held = r.InvState(kFault:kReset - 1);
            kLeft = find(held ~= tc.S.FAULT, 1);
            tc.verifyEmpty(kLeft, sprintf( ...
                'REQ-INV-009: InvState left FAULT at t = %.1f ms before the fault reset at t = 150 ms.', ...
                1e3 * r.t(kFault + max([kLeft 1]) - 1)));
            tc.verifyStateAt(r, 0.1501, 'STANDBY', 'REQ-INV-010 (FaultReset pulse with no active fault)');
        end
    end

    methods (Test, TestTags = {'REQ-INV-010'})
        function testFaultResetRequiresRisingEdge(tc)
            % overcurrent on phase a in RUN; FaultReset rises at 105 ms while the
            % fault is still active and is held TRUE; the fault disappears at 110 ms.
            % Only the new rising edge at 220 ms may release FAULT.
            scn = tc.scenario(0.26);
            scn.step('TrqReq_Nm',   0.085, 100);
            scn.step('PhaseCurr_A', 0.100, [1000 -500 -500]);
            scn.step('PhaseCurr_A', 0.110, [0 0 0]);
            scn.step('FaultReset',  0.105, 1);
            scn.step('FaultReset',  0.200, 0);
            scn.step('FaultReset',  0.220, 1);
            r = tc.simulate(scn);
            tc.savePlot(r, {{'InvState'}, 'state'; {'FaultWord'}, 'FaultWord'; ...
                            {'In_FaultReset', 'PwmEnable'}, 'flags'; {'TrqCmd_Nm'}, 'torque [N*m]'}, ...
                'FaultReset held TRUE from 105 ms (fault still active), new rising edge at 220 ms');

            kFault = tc.firstAt(r.InvState == tc.S.FAULT);
            tc.assertNotEmpty(kFault, 'REQ-INV-008: InvState never entered FAULT.');
            kEdge = tc.idx(0.220);
            window = kFault:kEdge - 1;
            kLeft = find(r.InvState(window) ~= tc.S.FAULT, 1);
            if isempty(kLeft)
                tc.verifyTrue(true);
            else
                k = window(kLeft);
                tc.verifyFail(sprintf([ ...
                    'REQ-INV-010: InvState left FAULT at t = %.1f ms (FAULT -> %s) without a rising edge of FaultReset. ' ...
                    'FaultReset has been TRUE since t = 105 ms (it rose while the overcurrent was still active); ' ...
                    'the overcurrent disappeared at t = 110 ms. Expected: FAULT until the next rising edge of ' ...
                    'FaultReset at t = 220 ms.'], 1e3 * r.t(k), tc.stateName(r.InvState(k))));
            end
            tc.verifyFalse(any(r.PwmEnable(window)), sprintf( ...
                'REQ-INV-010: PwmEnable became TRUE again at t = %.1f ms without a new fault reset request.', ...
                1e3 * r.t(window(max([1, find(r.PwmEnable(window), 1)])))));
            tc.verifyEqual(max(abs(r.TrqCmd_Nm(window))), 0, sprintf( ...
                'REQ-INV-010: torque was commanded again (max |TrqCmd_Nm| = %.1f N*m) without a new fault reset request.', ...
                max(abs(r.TrqCmd_Nm(window)))));
            tc.verifyStateAt(r, 0.2201, 'STANDBY', 'REQ-INV-010 (rising edge of FaultReset with no active fault)');
        end
    end
end
