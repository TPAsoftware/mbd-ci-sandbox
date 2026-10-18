function files = export_diagrams(outDir)
%EXPORT_DIAGRAMS  Render pictures of the InvCtrl model with MATLAB.
%
%   files = export_diagrams()          write into results/diagrams/
%   files = export_diagrams(outDir)    write into outDir
%
%   Builds InvCtrl exactly as the MIL tests do (inv_ctrl_setup, build_inv_ctrl), loads
%   the saved work/InvCtrl.slx and exports one picture per diagram:
%
%     01_InvCtrl_top_level   top level of the model
%     02_TorqueToCurrent     subsystem: torque command to current references
%     03_CurrentCtrl         subsystem: d/q PI current control
%     04_Derating            subsystem: torque limit and rate limiter
%     05_FaultMonitor        subsystem: debounced fault detection
%     06_StateMachine        Stateflow chart InvStateMachine, all states and transitions
%
%   The set is exported twice, in two folders of outDir:
%     native/   the layout exactly as model/build_inv_ctrl.m creates it
%     tidy/     layout only tidied for reading (Simulink.BlockDiagram.arrangeSystem for the
%               block diagrams, states on a grid with every label next to its transition for
%               the chart); blocks, states, transitions and their text are not touched
%
%   Every picture is written as PNG, SVG and PDF. The methods are tried in this order and
%   the first one that leaves a usable file wins: print -s<system>, saveas and, for the
%   chart, sfprint. print and saveas of a chart block only draw the block symbol (174 x 222
%   px), so for the chart sfprint is tried first.
%
%   Simulink does not print in the no-display mode of MATLAB, so on a headless Linux
%   machine MATLAB has to run under a virtual display (see .github/workflows/diagrams.yml).
%
%   Also written to outDir:
%     EXPORT_LOG.txt                          every attempt with its result or error message
%     StateMachine_transitions.txt            data, states and transitions of the chart as text
%   Throws an error when a PNG is missing, so the CI job fails.

    files = {};
    root = inv_ctrl_setup();
    if nargin < 1 || isempty(outDir)
        outDir = fullfile(root, 'results', 'diagrams');
    end
    if ~isfolder(outDir)
        mkdir(outDir);
    end
    logFile = fullfile(outDir, 'EXPORT_LOG.txt');
    if isfile(logFile)
        delete(logFile);
    end
    logEnvironment(logFile);

    % build the model exactly as the MIL tests do, then work on the saved file
    build_inv_ctrl();
    if bdIsLoaded('InvCtrl')
        close_system('InvCtrl', 0);
    end
    load_system(fullfile(root, 'work', 'InvCtrl.slx'));

    chartPath = 'InvCtrl/InvStateMachine';
    writeChartText(logFile, fullfile(outDir, 'StateMachine_transitions.txt'), chartPath);

    % name, system, is it a Stateflow chart?
    targets = {
        '01_InvCtrl_top_level', 'InvCtrl',                 false
        '02_TorqueToCurrent',   'InvCtrl/TorqueToCurrent', false
        '03_CurrentCtrl',       'InvCtrl/CurrentCtrl',     false
        '04_Derating',          'InvCtrl/Derating',        false
        '05_FaultMonitor',      'InvCtrl/FaultMonitor',    false
        '06_StateMachine',      chartPath,                 true};

    missing = {};

    say(logFile, '=== native layout');
    [f, m] = exportAll(logFile, fullfile(outDir, 'native'), targets);
    files = [files, f];
    missing = [missing, m];

    say(logFile, '=== tidy layout');
    tidyLayout(logFile, chartPath);
    [f, m] = exportAll(logFile, fullfile(outDir, 'tidy'), targets);
    files = [files, f];
    missing = [missing, m];

    close_system('InvCtrl', 0);

    say(logFile, '%d files in %s', numel(files), outDir);
    if ~isempty(missing)
        error('export_diagrams:missing', 'No PNG exported for: %s (see EXPORT_LOG.txt).', ...
              strjoin(missing, ', '));
    end
end

% =====================================================================================
function [files, missing] = exportAll(logFile, outDir, targets)
    if ~isfolder(outDir)
        mkdir(outDir);
    end
    files = {};
    missing = {};
    formats = {'png', 'svg', 'pdf'};
    for k = 1:size(targets, 1)
        name = targets{k, 1};
        sys = targets{k, 2};
        isChart = targets{k, 3};
        say(logFile, '--- %s (%s)', name, sys);
        for f = 1:numel(formats)
            file = fullfile(outDir, [name '.' formats{f}]);
            if exportImage(logFile, sys, isChart, formats{f}, file)
                files{end + 1} = file; %#ok<AGROW>
            elseif strcmp(formats{f}, 'png')
                missing{end + 1} = [name ' (' outDir ')']; %#ok<AGROW>
            end
        end
    end
end

function ok = exportImage(logFile, sys, isChart, fmt, file)
    % print -s first, then saveas; for a chart sfprint first (print only draws the block symbol)
    tries = {'print', 'saveas'};
    if isChart
        tries = {'sfprint'};
        if strcmp(fmt, 'png')
            tries = {'sfprint', 'print', 'saveas'};
        end
    end
    ok = false;
    for i = 1:numel(tries)
        if isfile(file)
            delete(file);
        end
        [good, why] = runMethod(tries{i}, sys, fmt, file);
        if good
            tag = 'ok';
        else
            tag = 'FAILED';
        end
        say(logFile, '  %-8s %-4s %-7s %s', tries{i}, fmt, tag, why);
        if good
            ok = true;
            return
        end
    end
end

function [good, why] = runMethod(method, sys, fmt, file)
    good = false;
    why = '';
    try
        switch method
            case 'print'
                print(['-s' sys], ['-d' fmt], file);
            case 'saveas'
                saveas(get_param(sys, 'Handle'), file);
            case 'sfprint'
                sfprint(sys, fmt, file, 1);
        end
        adoptStrayFile(file, sys, fmt);
        [good, why] = checkFile(file, fmt);
    catch err
        why = strrep(strtrim(err.message), newline, ' ');
    end
end

function adoptStrayFile(file, sys, fmt)
    % sfprint may ignore the destination name and name the file after the chart
    if isfile(file)
        return
    end
    folder = fileparts(file);
    [~, chart] = fileparts(sys);
    stem = strrep(sys, '/', '_');
    candidates = {[file '.' fmt], fullfile(folder, [stem '.' fmt]), fullfile(folder, [chart '.' fmt]), ...
                  fullfile(pwd, [stem '.' fmt]), fullfile(pwd, [chart '.' fmt])};
    for i = 1:numel(candidates)
        if isfile(candidates{i})
            movefile(candidates{i}, file);
            return
        end
    end
end

function [good, why] = checkFile(file, fmt)
    % a usable file exists, is not tiny and (PNG) is not blank
    good = false;
    if ~isfile(file)
        why = 'no file written';
        return
    end
    d = dir(file);
    why = sprintf('%d bytes', d.bytes);
    if d.bytes < 1000
        why = [why ', too small'];
        return
    end
    if ~strcmp(fmt, 'png')
        good = true;
        return
    end
    info = imfinfo(file);
    img = imread(file);
    why = sprintf('%d x %d px, %s', info.Width, info.Height, why);
    good = info.Width >= 200 && info.Height >= 100 && any(img(:) ~= img(1));
    if ~good
        why = [why ', blank or too small'];
    end
end

% =====================================================================================
function tidyLayout(logFile, chartPath)
    % layout only: nothing of the logic is touched
    systems = {'InvCtrl', 'InvCtrl/TorqueToCurrent', 'InvCtrl/CurrentCtrl', ...
               'InvCtrl/Derating', 'InvCtrl/FaultMonitor'};
    for k = 1:numel(systems)
        try
            Simulink.BlockDiagram.arrangeSystem(systems{k}, 'FullLayout', 'true');
            say(logFile, 'arranged %s', systems{k});
        catch err
            say(logFile, 'arrangeSystem of %s failed: %s', systems{k}, strrep(err.message, newline, ' '));
        end
    end
    try
        tidyChart(logFile, chartPath);
    catch err
        say(logFile, 'chart layout not tidied: %s', strrep(err.message, newline, ' '));
    end
end

function tidyChart(logFile, chartPath)
    % Presentation layout of the state machine: the normal sequence runs down the middle
    % column, SAFE_DISCHARGE is on the left and FAULT on the right, no transition runs
    % behind a state and every label sits beside its transition (Stateflow draws the
    % diagonal transitions as smooth curves). Only positions are changed: states, o'clock
    % positions, mid points and labels; states, transitions and their text stay as built.
    W = 260;
    H = 100;
    HF = 130;
    colX = [60, 510, 960];
    rowY = [60, 240, 420, 600];
    % state, column, row, height
    layout = {
        'OFF',            1, 1, H
        'STANDBY',        2, 1, H
        'PRECHARGE',      2, 2, H
        'READY',          2, 3, H
        'RUN',            2, 4, H
        'SAFE_DISCHARGE', 1, 3, H
        'FAULT',          3, 3, HF};
    % source, destination, source o'clock, destination o'clock, label side (x y), label position along
    % the line, distance of the label from the line (the long guard FAULT -> STANDBY gets room for the curve)
    spec = {
        'OFF',              'STANDBY',           2.40,  9.60,  0, -1, 0.5, 6
        'STANDBY',          'OFF',               8.40,  3.60,  0,  1, 0.5, 6
        'STANDBY',          'PRECHARGE',         6.00, 11.99, -1,  0, 0.5, 6
        'PRECHARGE',        'READY',             6.00, 11.99,  1,  0, 0.5, 6
        'PRECHARGE',        'SAFE_DISCHARGE',    9.00,  2.10, -1,  1, 0.5, 6
        'PRECHARGE',        'FAULT',             3.00,  9.92, -1,  1, 0.5, 6
        'READY',            'RUN',               5.52,  0.48,  1,  0, 0.5, 6
        'RUN',              'READY',            11.52,  6.48, -1,  0, 0.5, 6
        'READY',            'SAFE_DISCHARGE',    9.00,  3.00,  0, -1, 0.5, 6
        'READY',            'FAULT',             3.00,  9.00,  0, -1, 0.5, 6
        'RUN',              'SAFE_DISCHARGE',    9.00,  3.90, -1,  1, 0.5, 6
        'RUN',              'FAULT',             3.00,  6.78,  1,  1, 0.5, 6
        'SAFE_DISCHARGE',   'OFF',              11.99,  6.00,  1,  0, 0.5, 6
        'SAFE_DISCHARGE',   'FAULT',             6.00,  5.46,  0,  1, 0.5, 6
        'STANDBY',          'FAULT',             3.75, 10.98, -1,  1, 0.3, 6
        'FAULT',            'STANDBY',           0.30,  2.25,  1, -1, 0.5, 36};
    % the one curved transition: SAFE_DISCHARGE -> FAULT passes below RUN
    arcKey = 'SAFE_DISCHARGE>FAULT';
    arcMid = [640, 830];

    rt = sfroot;
    ch = rt.find('-isa', 'Stateflow.Chart', 'Path', chartPath);
    sts = ch.find('-isa', 'Stateflow.State');
    pos = struct();
    for j = 1:numel(sts)
        row = find(strcmp(layout(:, 1), sts(j).Name), 1);
        if isempty(row)
            error('export_diagrams:state', 'No layout for state %s.', sts(j).Name);
        end
        p = [colX(layout{row, 2}), rowY(layout{row, 3}), W, layout{row, 4}];
        if layout{row, 4} ~= H
            p(2) = p(2) + H / 2 - layout{row, 4} / 2;    % taller box: same center line as the others
        end
        sts(j).Position = p;
        pos.(sts(j).Name) = p;
    end

    trs = ch.find('-isa', 'Stateflow.Transition');
    keys = cell(numel(trs), 1);
    for j = 1:numel(trs)
        t = trs(j);
        if isempty(t.Source)
            keys{j} = '';
            continue
        end
        keys{j} = [t.Source.Name '>' t.Destination.Name];
        row = find(strcmp(spec(:, 1), t.Source.Name) & strcmp(spec(:, 2), t.Destination.Name), 1);
        if isempty(row)
            error('export_diagrams:transition', 'No layout for transition %s.', keys{j});
        end
        t.SourceOClock = spec{row, 3};
        t.DestinationOClock = spec{row, 4};
    end

    for j = 1:numel(trs)
        t = trs(j);
        if isempty(t.Source)
            % default transition into OFF: short arrow from above, as in build_inv_ctrl
            p = pos.(t.Destination.Name);
            t.DestinationOClock = 0;
            x0 = p(1) + p(3) / 2;
            t.SourceEndpoint = [x0, p(2) - 30];
            t.Midpoint = [x0, p(2) - 15];
            continue
        end
        row = find(strcmp(spec(:, 1), t.Source.Name) & strcmp(spec(:, 2), t.Destination.Name), 1);
        s = t.SourceEndpoint;
        d = t.DestinationEndpoint;
        if strcmp(keys{j}, arcKey)
            t.Midpoint = arcMid;
        else
            t.Midpoint = (s + d) / 2;
        end
        % label beside the line: the box of the label touches a parallel of the line
        dirv = d - s;
        u = dirv / norm(dirv);
        n = [-u(2), u(1)];
        side = [spec{row, 5}, spec{row, 6}];
        if n(1) * side(1) + n(2) * side(2) < 0
            n = -n;
        end
        if spec{row, 7} == 0.5
            P = t.Midpoint;
        else
            P = s + spec{row, 7} * dirv;
        end
        lp = t.LabelPosition;
        w = lp(3);
        h = lp(4);
        c = P + n * (abs(n(1)) * w / 2 + abs(n(2)) * h / 2 + spec{row, 8});
        t.LabelPosition = [c(1) - w / 2, c(2) - h / 2, w, h];
    end
    say(logFile, 'chart layout tidied (%d states, %d transitions)', numel(sts), numel(trs));
end

function writeChartText(logFile, textFile, chartPath)
    % data, states and transitions of the chart as text (needs no display)
    lines = {};
    try
        rt = sfroot;
        ch = rt.find('-isa', 'Stateflow.Chart', 'Path', chartPath);
        data = ch.find('-isa', 'Stateflow.Data');
        for j = 1:numel(data)
            lines{end + 1} = sprintf('data        %-22s %-10s %s', ...
                data(j).Name, data(j).Scope, data(j).DataType); %#ok<AGROW>
        end
        sts = ch.find('-isa', 'Stateflow.State');
        for j = 1:numel(sts)
            lines{end + 1} = ['state       ' strrep(sts(j).LabelString, newline, ' | ')]; %#ok<AGROW>
        end
        trs = ch.find('-isa', 'Stateflow.Transition');
        for j = 1:numel(trs)
            t = trs(j);
            if isempty(t.Source)
                from = '(default)';
            else
                from = t.Source.Name;
            end
            lines{end + 1} = sprintf('transition  %-15s -> %-15s order %d  %s', from, ...
                t.Destination.Name, t.ExecutionOrder, strrep(t.LabelString, newline, ' ')); %#ok<AGROW>
        end
    catch err
        say(logFile, 'chart text not written: %s', strrep(err.message, newline, ' '));
        return
    end
    fid = fopen(textFile, 'w');
    fprintf(fid, '%s\n', lines{:});
    fclose(fid);
end

function logEnvironment(logFile)
    say(logFile, 'MATLAB %s on %s, DISPLAY=''%s''', version('-release'), computer, getenv('DISPLAY'));
    say(logFile, 'usejava: jvm=%d awt=%d desktop=%d', usejava('jvm'), usejava('awt'), usejava('desktop'));
end

function say(logFile, fmt, varargin)
    % print to the CI log and append to EXPORT_LOG.txt
    msg = sprintf(fmt, varargin{:});
    fprintf('%s\n', msg);
    fid = fopen(logFile, 'a');
    if fid > 0
        fprintf(fid, '%s\n', msg);
        fclose(fid);
    end
end
