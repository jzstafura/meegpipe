function obj = eog(varargin)

import spt.criterion.tfd.*;

obj = tfd( ...
    'MinCard',      2, ...
    'MaxCard',      5, ...
    'Percentile',   75, ...
    'Algorithm',    'sevcik_10', ...
    'WindowLength', @(sr) 2*sr, ...
    'WindowShift',  @(sr) sr, ...
    varargin{:} ...
    );


end