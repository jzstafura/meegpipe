function [rawFiles, processedFile, processedData] = main(varargin)
% MAIN - Performs all pre-preprocessing steps from the raw data

import mperl.file.find.finddepth_regex_match;

fileList = {...
    'export_26-11_calibratie.Poly5' ...
    };

rawFiles = cell(size(fileList));
processedFile = cell(size(fileList));
processedData = cell(size(fileList));

preprocPipe = grunberg.preprocess_pipeline(varargin{:});
artifactPipe = grunberg.artifact_rejection_pipeline(varargin{:});
supervisedBssPipe = grunberg.supervised_bss_pipeline(varargin{:});

for fileItr = 1:numel(fileList)
    
    %% Basic preprocessing
    preprocFile = get_output_filename(preprocPipe, fileList{fileItr});
    if ~exist(preprocFile, 'file')
        run(preprocPipe, fileList{fileItr});
    end
    
    % Find the EEGLAB dataset produced by the processing pipeline
    outputDir = get_full_dir(preprocPipe, fileList{fileItr});
    rawFiles(fileItr) = finddepth_regex_match(outputDir, '\.set$');
    
    % Get a symbolic link to the pre-processed data so that meegpipe
    % produces the processing output in the directory that we want
    dataFile = link2previous(preprocFile);
    
    %% Fully automatic artifact rejection
    artifactFile = get_output_filename(artifactPipe, dataFile);
    if ~exist(artifactFile, 'file'),
        run(artifactPipe, dataFile);
    end
    
    %% Supervised BSS
    % Get a symbolic link to the output of the artifact rejection pipeline
    dataFile = link2previous(artifactFile);
    finalOutput = get_output_filename(supervisedBssPipe, dataFile);
    if ~exist(finalOutput, 'file'),
        run(supervisedBssPipe, dataFile);
    end
    
    % Find the EEGLAB dataset produced by the artifact rejection pipeline
    outputDir = get_full_dir(supervisedBssPipe, dataFile);
    processedFile{fileItr} = finddepth_regex_match(outputDir, '\.set$');
end


end


function dataFile = link2previous(previousDataFile)
import mperl.file.spec.catfile;

[path, name] = fileparts(previousDataFile);
thisOutputFiles = {...
    catfile(path, [name '.pseth']), ...
    catfile(path, [name '.pset'])};
tmp = somsds.link2files(thisOutputFiles, pwd);
dataFile = tmp{1};


end