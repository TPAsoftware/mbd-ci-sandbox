function pos = mbd_pos(col, row, w, h)
%MBD_POS  Block position on a simple layout grid.
%
%   pos = mbd_pos(col, row)          default block size 50 x 30
%   pos = mbd_pos(col, row, w, h)
%
%   Columns are 150 px apart, rows 70 px apart.

    if nargin < 3, w = 50; end
    if nargin < 4, h = 30; end
    x = 40 + (col - 1) * 150;
    y = 40 + (row - 1) * 70;
    pos = [x, y, x + w, y + h];
end
