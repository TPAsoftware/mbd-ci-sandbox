function h = mbd_add(libBlock, path, pos, varargin)
%MBD_ADD  Add a block at a grid position and set its parameters.
%
%   h = mbd_add(libBlock, path, pos, 'Param1', value1, ...)
%
%   libBlock  library block, e.g. 'built-in/Gain' or 'simulink/Lookup Tables/1-D Lookup Table'
%   path      full path of the new block, e.g. 'InvCtrl/Derating/TrqMax'
%   pos       [left top right bottom], see mbd_pos

    h = add_block(libBlock, path, 'Position', pos);
    if ~isempty(varargin)
        set_param(h, varargin{:});
    end
end
