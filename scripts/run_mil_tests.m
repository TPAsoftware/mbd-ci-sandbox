function results = run_mil_tests()
%RUN_MIL_TESTS  Build InvCtrl from its scripted definition and run the MIL test suite.
%
%   results = run_mil_tests()
%
%   Output in results/:
%     junit_mil.xml   JUnit XML for CI tooling
%     SUMMARY.md      result per test with requirement IDs and the first failure
%                     message (also appended to the GitHub Actions job summary
%                     when GITHUB_STEP_SUMMARY is set)
%     plots/*.png     signal plots, one per test
%   Throws an error when a test fails, so the CI job fails.

    root = inv_ctrl_setup();
    addpath(fullfile(root, 'tests'));
    resultsDir = fullfile(root, 'results');
    if ~isfolder(resultsDir)
        mkdir(resultsDir);
    end
    printVersions();

    import matlab.unittest.TestSuite
    import matlab.unittest.TestRunner
    import matlab.unittest.Verbosity
    import matlab.unittest.plugins.TestRunProgressPlugin
    import matlab.unittest.plugins.DiagnosticsOutputPlugin
    import matlab.unittest.plugins.DiagnosticsRecordingPlugin
    import matlab.unittest.plugins.XMLPlugin

    suite = TestSuite.fromFolder(fullfile(root, 'tests'));
    runner = TestRunner.withNoPlugins;
    runner.addPlugin(TestRunProgressPlugin.withVerbosity(Verbosity.Detailed));
    runner.addPlugin(DiagnosticsOutputPlugin);
    runner.addPlugin(DiagnosticsRecordingPlugin);
    runner.addPlugin(XMLPlugin.producingJUnitFormat(fullfile(resultsDir, 'junit_mil.xml')));

    t0 = tic;
    results = runner.run(suite);
    elapsed = toc(t0);

    writeSummary(suite, results, resultsDir, elapsed);

    bad = [results.Failed] | [results.Incomplete];
    if any(bad)
        error('run_mil_tests:failed', '%d of %d MIL tests failed: %s', nnz(bad), numel(results), ...
              strjoin({results(bad).Name}, ', '));
    end
    fprintf('All %d MIL tests passed.\n', numel(results));
end

% =====================================================================================
function printVersions()
    v = ver;
    fprintf('MATLAB release %s\n', version('-release'));
    for k = 1:numel(v)
        fprintf('  %-28s %s\n', v(k).Name, v(k).Version);
    end
end

% =====================================================================================
function writeSummary(suite, results, resultsDir, elapsed)
    nPassed = nnz([results.Passed]);
    nFailed = nnz([results.Failed] | [results.Incomplete]);
    lines = {};
    if nFailed == 0
        verdict = 'PASSED';
    else
        verdict = 'FAILED';
    end
    lines{end + 1} = sprintf('## MIL tests %s: %d passed, %d failed (%d tests, MATLAB %s, %.0f s)', ...
        verdict, nPassed, nFailed, numel(results), version('-release'), elapsed);
    lines{end + 1} = '';
    lines{end + 1} = '| Result | Test | Requirements | Time [s] | Details |';
    lines{end + 1} = '|---|---|---|---|---|';
    order = [find(~[results.Passed]), find([results.Passed])];
    for i = order
        res = results(i);
        if res.Passed
            status = 'passed';
            details = '';
        else
            status = '**FAILED**';
            details = firstFailure(res);
        end
        tags = '';
        try
            tags = strjoin(suite(i).Tags, ', ');
        catch
        end
        lines{end + 1} = sprintf('| %s | %s | %s | %.1f | %s |', status, res.Name, tags, ...
            res.Duration, mdCell(details)); %#ok<AGROW>
    end
    txt = strjoin(lines, newline);

    fid = fopen(fullfile(resultsDir, 'SUMMARY.md'), 'w');
    fprintf(fid, '%s\n', txt);
    fclose(fid);

    stepSummary = getenv('GITHUB_STEP_SUMMARY');
    if ~isempty(stepSummary)
        fid = fopen(stepSummary, 'a');
        fprintf(fid, '%s\n', txt);
        fclose(fid);
    end
    fprintf('\n%s\n\n', txt);
end

function msg = firstFailure(res)
    msg = 'see the job log';
    try
        recs = res.Details.DiagnosticRecord;
    catch
        return
    end
    failEvents = {'VerificationFailed', 'AssertionFailed', 'FatalAssertionFailed', 'AssumptionFailed', 'ExceptionThrown'};
    for j = 1:numel(recs)
        rec = recs(j);
        if ~any(strcmp(rec.Event, failEvents))
            continue
        end
        txt = '';
        try
            tdr = rec.TestDiagnosticResults;
            if ~isempty(tdr)
                txt = char(tdr(1).DiagnosticText);
            end
        catch
        end
        if isempty(txt)
            try
                txt = rec.Exception.message;
            catch
            end
        end
        if isempty(txt)
            try
                txt = char(rec.Report);
            catch
            end
        end
        if ~isempty(txt)
            msg = txt;
        end
        return
    end
end

function s = mdCell(s)
    s = regexprep(char(s), '\s+', ' ');
    s = strrep(s, '|', '\|');
    if numel(s) > 600
        s = [s(1:597) '...'];
    end
end
