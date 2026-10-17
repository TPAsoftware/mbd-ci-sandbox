classdef (Abstract) InvCtrlTestCase < matlab.unittest.TestCase
    %INVCTRLTESTCASE  Common helpers for the InvCtrl MIL tests.
    %
    %   Every test builds an InvCtrlScenario, simulates InvCtrl (built once per
    %   run by InvCtrlModelFixture) with Simulink.SimulationInput, checks the
    %   requirement with explicit tolerances and saves a plot of the relevant
    %   signals to results/plots. Test methods carry requirement IDs as TestTags.

    properties (Constant)
        ModelName = 'InvCtrl'
        Ts = 1e-4
        S = struct('OFF', 0, 'STANDBY', 1, 'PRECHARGE', 2, 'READY', 3, 'RUN', 4, ...
                   'SAFE_DISCHARGE', 5, 'FAULT', 6)
        StateNames = {'OFF', 'STANDBY', 'PRECHARGE', 'READY', 'RUN', 'SAFE_DISCHARGE', 'FAULT'}
        OutputNames = {'InvState', 'PwmEnable', 'TrqCmd_Nm', 'TrqLim_Nm', 'IdRef_A', 'IqRef_A', ...
                       'Vd_V', 'Vq_V', 'FaultWord'}
    end

    methods (Access = protected)
        % ------------------------------------------------------------------ simulation
        function scn = scenario(~, stopTime, varargin)
            scn = InvCtrlScenario(stopTime, varargin{:});
        end

        function r = simulate(tc, scn)
            %SIMULATE  Run InvCtrl with the scenario; returns a struct of double column vectors.
            %   r.t (time), one field per output, and In_<signal> for every input.
            in = Simulink.SimulationInput(tc.ModelName);
            in = in.setExternalInput(scn.toDataset());
            in = in.setModelParameter('StopTime', sprintf('%.10g', scn.StopTime));
            out = sim(in);
            if ~isempty(out.ErrorMessage)
                error('InvCtrlTestCase:sim', 'Simulation failed: %s', out.ErrorMessage);
            end
            ds = out.get('yout');
            r = struct();
            for i = 1:numel(tc.OutputNames)
                nm = tc.OutputNames{i};
                el = tc.findOutput(ds, nm);
                r.(nm) = double(el.Values.Data(:));
                if i == 1
                    r.t = el.Values.Time(:);
                end
            end
            r.PwmEnable = r.PwmEnable > 0.5;
            n = numel(r.t);
            for i = 1:numel(scn.Signals)
                v = scn.sample(scn.Signals{i});
                if size(v, 1) < n
                    error('InvCtrlTestCase:length', 'Scenario shorter than the simulation.');
                end
                r.(['In_' scn.Signals{i}]) = v(1:n, :);
            end
        end

        function el = findOutput(~, ds, name)
            %FINDOUTPUT  Logged root output by outport block name.
            for k = 1:ds.numElements
                e = ds.get(k);
                bp = e.BlockPath.getBlock(1);
                if endsWith(bp, ['/' name])
                    el = e;
                    return
                end
            end
            error('InvCtrlTestCase:output', 'Output %s not found in yout.', name);
        end

        % ------------------------------------------------------------------ indexing helpers
        function k = idx(tc, t)
            %IDX  Sample index (1-based) of time t.
            k = round(t / tc.Ts) + 1;
        end

        function k = firstAt(~, mask, fromIdx)
            %FIRSTAT  First index >= fromIdx where mask is TRUE ([] if none).
            if nargin < 3
                fromIdx = 1;
            end
            k = find(mask(fromIdx:end), 1) + fromIdx - 1;
        end

        function txt = stateName(tc, code)
            txt = tc.StateNames{code + 1};
        end

        function txt = stateList(tc, codes)
            txt = strjoin(arrayfun(@(c) tc.stateName(c), codes, 'UniformOutput', false), ' -> ');
        end

        function seq = stateSequence(~, st)
            %STATESEQUENCE  Visited state codes in order (consecutive duplicates removed).
            st = st(:);
            seq = st([true; diff(st) ~= 0])';
        end

        function b = bit(~, word, n)
            %BIT  Logical array: bit n (0-based) of FaultWord.
            b = bitand(uint16(word), uint16(2 ^ n)) > 0;
        end

        function verifyStateAt(tc, r, t, expected, context)
            %VERIFYSTATEAT  InvState at time t equals the expected state.
            k = tc.idx(t);
            actual = r.InvState(k);
            tc.verifyEqual(actual, tc.S.(expected), sprintf( ...
                '%s: InvState at t = %.1f ms is %s, expected %s.', context, 1e3 * t, tc.stateName(actual), expected));
        end

        function verifyEntryTime(tc, r, state, tExpected, tolTasks, context)
            %VERIFYENTRYTIME  First entry into a state happens at tExpected +/- tolTasks tasks.
            k = tc.firstAt(r.InvState == tc.S.(state));
            if isempty(k)
                tc.verifyFail(sprintf('%s: InvState never entered %s (visited: %s).', ...
                    context, state, tc.stateList(tc.stateSequence(r.InvState))));
                return
            end
            tc.verifyLessThanOrEqual(abs(r.t(k) - tExpected), tolTasks * tc.Ts + 1e-9, sprintf( ...
                '%s: InvState entered %s at t = %.1f ms, expected t = %.1f ms (+/- %d tasks).', ...
                context, state, 1e3 * r.t(k), 1e3 * tExpected, tolTasks));
        end

        % ------------------------------------------------------------------ evidence
        function savePlot(tc, r, panels, titleText)
            %SAVEPLOT  Stacked plot of signals, PNG in results/plots (named after the test).
            %   panels: N x 2 cell {signal names (cell), y label}. Never fails the test.
            try
                st = dbstack(1);
                testName = strrep(st(1).name, '.', '__');
                root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
                plotDir = fullfile(root, 'results', 'plots');
                if ~isfolder(plotDir)
                    mkdir(plotDir);
                end
                f = figure('Visible', 'off', 'Position', [100 100 1100 210 * size(panels, 1) + 90]);
                cleanup = onCleanup(@() close(f));
                tl = tiledlayout(f, size(panels, 1), 1, 'TileSpacing', 'compact', 'Padding', 'compact');
                for p = 1:size(panels, 1)
                    ax = nexttile(tl);
                    hold(ax, 'on');
                    grid(ax, 'on');
                    names = panels{p, 1};
                    for s = 1:numel(names)
                        nm = names{s};
                        y = r.(nm);
                        if strcmp(nm, 'InvState')
                            stairs(ax, r.t, y, 'LineWidth', 1.4, 'DisplayName', nm);
                            yticks(ax, 0:6);
                            yticklabels(ax, tc.StateNames);
                            ylim(ax, [-0.5 6.5]);
                        elseif size(y, 2) > 1
                            for c = 1:size(y, 2)
                                plot(ax, r.t, y(:, c), 'DisplayName', sprintf('%s(%d)', nm, c));
                            end
                        else
                            stairs(ax, r.t, double(y), 'LineWidth', 1.2, 'DisplayName', nm);
                        end
                    end
                    ylabel(ax, panels{p, 2}, 'Interpreter', 'none');
                    legend(ax, 'Location', 'best', 'Interpreter', 'none');
                    if p == size(panels, 1)
                        xlabel(ax, 'time [s]');
                    end
                end
                title(tl, sprintf('%s\n%s', strrep(testName, '__', '/'), titleText), 'Interpreter', 'none');
                exportgraphics(f, fullfile(plotDir, [testName '.png']), 'Resolution', 110);
                clear cleanup
            catch err
                tc.log(1, sprintf('plot not saved: %s', err.message));
            end
        end
    end
end
