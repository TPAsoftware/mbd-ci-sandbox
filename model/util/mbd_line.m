function h = mbd_line(sys, src, dst, signalName)
%MBD_LINE  Connect two block ports and optionally name the signal.
%
%   h = mbd_line(sys, 'Src/1', 'Dst/2')
%   h = mbd_line(sys, 'Src/1', 'Dst/2', 'SignalName')
%
%   Several lines from the same source port create branches of one signal.

    h = add_line(sys, src, dst);
    if nargin > 3 && ~isempty(signalName)
        set_param(h, 'Name', signalName);
    end
end
