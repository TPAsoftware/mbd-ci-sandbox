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
%   Every picture is written as PNG (required) and as SVG and PDF (best effort). The
%   methods are tried in this order and the first one that leaves a usable file wins:
%   print -s<system>, saveas, and for the chart also sfprint. For the chart the result
%   of every method is kept as <name>__<method>.<ext>.
%
%   Simulink does not print in the no-display mode of MATLAB, so on a headless Linux
%   machine MATLAB has to run under a virtual display (see .github/workflows/diagrams.yml).
%
%   Also written to outDir:
%     EXPORT_LOG.txt                 every attempt with its result or error message
%     StateMachine_transitions.txt   data, states and transitions of the chart as text
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

    writeChartText(logFile, fullfile(outDir, 'StateMachine_transitions.txt'), 'InvCtrl/InvStateMachine');

    % name, system, is it a Stateflow chart?
    targets = {
        '01_InvCtrl_top_level', 'InvCtrl',                 false
        '02_TorqueToCurrent',   'InvCtrl/TorqueToCurrent', false
        '03_CurrentCtrl',       'InvCtrl/CurrentCtrl',     false
        '04_Derating',          'InvCtrl/Derating',        false
        '05_FaultMonitor',      'InvCtrl/FaultMonitor',    false
        '06_StateMachine',      'InvCtrl/InvStateMachine', true};
    missing = {};
    for k = 1:size(targets, 1)
        name = targets{k, 1};
        sys = targets{k, 2};
        isChart = targets{k, 3};
        say(logFile, '--- %s (%s)', name, sys);
        formats = {'png', 'svg', 'pdf'};
        for f = 1:numel(formats)
            file = fullfile(outDir, [name '.' formats{f}]);
            if exportImage(logFile, sys, isChart, formats{f}, file)
                files{end + 1} = file; %#ok<AGROW>
            elseif strcmp(formats{f}, 'png')
                missing{end + 1} = name; %#ok<AGROW>
            end
        end
    end
    close_system('InvCtrl', 0);

    say(logFile, '%d files in %s', numel(files), outDir);
    if ~isempty(missing)
        error('export_diagrams:missing', 'No PNG exported for: %s (see EXPORT_LOG.txt).', ...
              strjoin(missing, ', '));
    end
end

% =====================================================================================
function ok = exportImage(logFile, sys, isChart, fmt, file)
    % print -s first, then saveas, then (chart only) sfprint; the first usable file wins
    tries = {'print', 'saveas'};
    if isChart
        tries{end + 1} = 'sfprint';
    end
    [folder, base, ext] = fileparts(file);
    ok = false;
    for i = 1:numel(tries)
        if ok && ~isChart
            break       % a block diagram needs one working method, the chart keeps all
        end
        m = tries{i};
        out = file;
        if isChart
            out = fullfile(folder, [base '__' m ext]);
        end
        if isfile(out)
            delete(out);
        end
        [good, why] = runMethod(m, sys, fmt, out);
        if good
            tag = 'ok';
        else
            tag = 'FAILED';
        end
        say(logFile, '  %-8s %-4s %-7s %s', m, fmt, tag, why);
        if good && ~ok && isChart
            copyfile(out, file);
        end
        ok = ok || good;
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
        say(logFile, 'chart text not written: %s', err.message);
        return
    end
    fid = fopen(textFile, 'w');
    fprintf(fid, '%s\n', lines{:});
    fclose(fid);
end

function logEnvironment(logFile)
    say(logFile, 'MATLAB %s on %s, DISPLAY=''%s''', version('-release'), computer, getenv('DISPLAY'));
    say(logFile, 'usejava: jvm=%d awt=%d desktop=%d', usejava('jvm'), usejava('awt'), usejava('desktop'));
    if isunix
        % the command line of MATLAB shows whether it was started with -nodisplay
        [~, out] = system(['ps -eo ppid,pid,args | grep -i "[m]atlab" | cut -c1-300 | ' ...
                           'sed -E ''s/[A-Za-z0-9_-]{24,}/<id>/g''']);
        say(logFile, 'MATLAB processes:\n%s', strtrim(out));
        [~, out] = system('pgrep -a Xvfb');
        say(logFile, 'Xvfb: %s', strtrim(out));
    end
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
