function file = export_test_plot(outDir)
%EXPORT_TEST_PLOT  Signal plot of the REQ-INV-010 scenario, one clean picture for the review.
%
%   file = export_test_plot()          write into results/diagrams/
%   file = export_test_plot(outDir)    write into outDir
%
%   Builds InvCtrl, simulates the stimulus of StateMachineTest/testFaultResetRequiresRisingEdge
%   (overcurrent in RUN, FaultReset rises while the fault is still active and is held TRUE,
%   the fault disappears, a new rising edge of FaultReset follows) and plots state, fault
%   word, FaultReset / PwmEnable and torque command. The title states whether InvState left
%   FAULT before the new rising edge, so the same script describes a model with and without
%   the fix. Writes FaultReset_test_plot.png.

    root = inv_ctrl_setup();
    if nargin < 1 || isempty(outDir)
        outDir = fullfile(root, 'results', 'diagrams');
    end
    if ~isfolder(outDir)
        mkdir(outDir);
    end
    build_inv_ctrl();

    % stimulus of the test (times in s)
    tOvercurrent = 0.100;
    tResetRises  = 0.105;
    tFaultGone   = 0.110;
    tResetLow    = 0.200;
    tNewEdge     = 0.220;
    scn = InvCtrlScenario(0.26);
    scn.step('TrqReq_Nm',   0.085, 100);
    scn.step('PhaseCurr_A', tOvercurrent, [1000 -500 -500]);
    scn.step('PhaseCurr_A', tFaultGone, [0 0 0]);
    scn.step('FaultReset',  tResetRises, 1);
    scn.step('FaultReset',  tResetLow, 0);
    scn.step('FaultReset',  tNewEdge, 1);

    in = Simulink.SimulationInput('InvCtrl');
    in = in.setExternalInput(scn.toDataset());
    in = in.setModelParameter('StopTime', '0.26');
    out = sim(in);
    if ~isempty(out.ErrorMessage)
        error('export_test_plot:sim', 'Simulation failed: %s', out.ErrorMessage);
    end

    ds = out.get('yout');
    el = findOutput(ds, 'InvState');
    t = el.Values.Time(:);
    state = double(el.Values.Data(:));
    faultWord = double(findOutput(ds, 'FaultWord').Values.Data(:));
    pwm = double(findOutput(ds, 'PwmEnable').Values.Data(:));
    torque = double(findOutput(ds, 'TrqCmd_Nm').Values.Data(:));
    reset = scn.sample('FaultReset');
    reset = double(reset(1:numel(t)));
    tm = 1e3 * t;

    % verdict: did InvState leave FAULT before the new rising edge?
    sFault = 6;
    met = false;
    kFault = find(state == sFault, 1);
    if isempty(kFault)
        verdict = 'InvState never entered FAULT';
    else
        window = kFault:find(t >= tNewEdge, 1) - 1;
        kLeft = find(state(window) ~= sFault, 1);
        if isempty(kLeft)
            met = true;
            verdict = sprintf('InvState stays in FAULT until the new rising edge of FaultReset at %.0f ms: REQ-INV-010 met', 1e3 * tNewEdge);
        else
            verdict = sprintf('InvState leaves FAULT at %.0f ms without a new rising edge of FaultReset: REQ-INV-010 violated', tm(window(kLeft)));
        end
    end

    stateNames = {'OFF', 'STANDBY', 'PRECHARGE', 'READY', 'RUN', 'SAFE_DISCHARGE', 'FAULT'};
    marks = 1e3 * [tOvercurrent, tResetRises, tFaultGone, tNewEdge];
    f = figure('Visible', 'off', 'Position', [100 100 1200 900], 'Color', 'w');
    cleanup = onCleanup(@() close(f));
    tl = tiledlayout(f, 4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    ax = nexttile(tl);
    stairs(ax, tm, state, 'LineWidth', 1.8);
    yticks(ax, 0:6);
    yticklabels(ax, stateNames);
    ax.TickLabelInterpreter = 'none';
    ylim(ax, [-0.5 6.5]);
    ylabel(ax, 'InvState');
    decorate(ax, marks);

    ax = nexttile(tl);
    stairs(ax, tm, faultWord, 'LineWidth', 1.6);
    ylim(ax, [-0.1 1.1]);
    ylabel(ax, 'FaultWord');
    decorate(ax, marks);

    ax = nexttile(tl);
    hold(ax, 'on');
    h1 = stairs(ax, tm, reset, 'LineWidth', 1.6);
    h2 = stairs(ax, tm, pwm, 'LineWidth', 1.6);
    ylim(ax, [-0.1 1.1]);
    ylabel(ax, 'flags');
    decorate(ax, marks);
    legend(ax, [h1 h2], {'FaultReset (input)', 'PwmEnable'}, 'Location', 'west', 'Interpreter', 'none', ...
           'AutoUpdate', 'off');

    ax = nexttile(tl);
    plot(ax, tm, torque, 'LineWidth', 1.6);
    ylabel(ax, 'TrqCmd [N*m]');
    xlabel(ax, 'time [ms]');
    decorate(ax, marks);

    header = sprintf(['Overcurrent %.0f-%.0f ms | FaultReset rises at %.0f ms (fault still active), held TRUE until %.0f ms | ' ...
                      'new rising edge at %.0f ms'], 1e3 * tOvercurrent, 1e3 * tFaultGone, 1e3 * tResetRises, ...
                     1e3 * tResetLow, 1e3 * tNewEdge);
    if met
        verdictColor = [0 0.45 0];
    else
        verdictColor = [0.75 0 0];
    end
    title(tl, {header, verdict}, 'Interpreter', 'none', 'FontWeight', 'bold', 'FontSize', 11, 'Color', verdictColor);

    file = fullfile(outDir, 'FaultReset_test_plot.png');
    exportgraphics(f, file, 'Resolution', 150);
    close_system('InvCtrl', 0);
    fprintf('%s\n%s\n', verdict, file);
end

function decorate(ax, marks)
    grid(ax, 'on');
    xlim(ax, [0 260]);
    for m = marks
        xline(ax, m, ':', 'Color', [0.45 0.45 0.45]);
    end
end

function el = findOutput(ds, name)
    % logged root output by outport block name
    for k = 1:ds.numElements
        e = ds.get(k);
        bp = e.BlockPath.getBlock(1);
        if endsWith(bp, ['/' name])
            el = e;
            return
        end
    end
    error('export_test_plot:output', 'Output %s not found in yout.', name);
end
