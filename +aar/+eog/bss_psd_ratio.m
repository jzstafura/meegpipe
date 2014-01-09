function obj = bss_psd_ratio(varargin)
% BSS_PSD_RATIO - EOG removal using BSS and PSD ratios as criterion

import misc.process_arguments;
import misc.split_arguments;
import pset.selector.sensor_class;
import pset.selector.good_data;
import pset.selector.cascade;

%% Default criterion
myFeat1 = spt.feature.psd_ratio.eog;
myFeat2 = spt.feature.bp_var;
myCrit = spt.criterion.threshold('Feature', {myFeat1, myFeat2}, ...
    'Max',      {25 10}, ...
    'MinCard',  2, ...
    'MaxCard',  @(d) ceil(0.25*length(d)));

%% Process input arguments
opt.RetainedVar     = 99.75;
opt.MaxPCs          = 40;
opt.MinPCs          = @(lambda) max(3, ceil(0.1*numel(lambda)));
opt.BSS             = spt.bss.efica;
opt.Criterion       = myCrit; 

[thisArgs, varargin] = split_arguments(fieldnames(opt), varargin);

[~, opt] = process_arguments(opt, thisArgs);

%% PCA
myFilter = @(sr) filter.lpfilt('fc', 13/(sr/2));
myPCA = spt.pca(...
    'RetainedVar',              opt.RetainedVar, ...
    'MaxCard',                  opt.MaxPCs, ...
    'MinCard',                  opt.MinPCs, ...
    'MinSamplesPerParamRatio',  15, ...
    'LearningFilter',           myFilter);

%% Build the bss node
dataSel = cascade(sensor_class('Class', {'EEG', 'MEG'}), good_data);
obj = meegpipe.node.bss.new(...
    'DataSelector', dataSel, ...
    'Criterion',    opt.Criterion, ...
    'PCA',          myPCA, ...
    'BSS',          opt.BSS, ...
    'Filter',       filter.lasip.eog, ...
    'RegrFilter',   filter.mlag_regr('Order', 5), ...
    'Name',         'bss.eog', ...
    varargin{:});


end