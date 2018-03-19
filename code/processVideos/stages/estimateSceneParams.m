function sceneGeometry = estimateSceneParams(pupilFileName, sceneGeometryFileName, varargin)
% Estimate camera translation and eye rotation given image plane ellipses
%
% Syntax:
%  sceneGeometry = estimateSceneParams(pupilFileName, sceneGeometryFileName)
%
% Description:
%   This function searches over a set of ellipses from the passed pupil
%   file(s) to estimate the extrinsic camera translation vector and scaling
%   values for the azimuthal and elevational eye rotation centers. The
%   search attempts to minimize the error associated with the prediction of
%   the shape of ellipses in the image plane while minimizing the error in
%   prediction of the center of those ellipses in the image plane.
%
%   The search is conducted over 5 parameters, corresponding to three
%   parameters of camera translation (horizontal, vertical, depth), a
%   parameter for joint scaling of the centers of rotation of the eye
%   (azimuthal and elevational rotations), and then a parameter for
%   differential scaling of the eye rotation centers. For this last
%   parameter, a value > 1 increases the azimuthal rotation center values
%   and decreases the elevational.
%
% Inputs:
%	pupilFileName         - Full path to a pupilData file, a cell array
%                           of such paths, or a pupilData structure itself.
%                           If a single path, the pupilData file is loaded.
%                           If a cell array, the ellipse data from each
%                           pupilData file is loaded and concatenated.
%   sceneGeometryFileName - Full path to the file in which the
%                           sceneGeometry data should be saved
%
% Optional key/value pairs (display and I/O):
%  'verbosity'            - Level of verbosity. [none, full]
%  'sceneDiagnosticPlotFileName' - Full path (including suffix) to the
%                           location where a diagnostic plot of the
%                           sceneGeometry calculation is to be saved. If
%                           left empty, then no plot will be saved.
%
% Optional key/value pairs (flow control)
%  'useParallel'          - If set to true, use the Matlab parallel pool
%  'nWorkers'             - Specify the number of workers in the parallel
%                           pool. If undefined the default number will be
%                           used.
%  'tbtbProjectName'      - The workers in the parallel pool are configured
%                           by issuing a tbUseProject command for the
%                           project specified here.
%
%
% Optional key/value pairs (environment)
%  'tbSnapshot'           - This should contain the output of the
%                           tbDeploymentSnapshot performed upon the result
%                           of the tbUse command. This documents the state
%                           of the system at the time of analysis.
%  'timestamp'            - AUTOMATIC; The current time and date
%  'username'             - AUTOMATIC; The user
%  'hostname'             - AUTOMATIC; The host
%
% Optional key/value pairs (analysis)
%  'sceneParamsLB/UB'     - 5x1 vector. Hard upper and lower bounds. Should
%                           reflect the physical limits of the measurement.
%  'sceneParamsLBp/UBp'   - 5x1 vector. Plausible upper and lower bounds.
%                           Where you think the translation vector solution
%                           is likely to be.
%  'eyePoseLB/UB'         - 1x4 vector. Upper / lower bounds on the eyePose
%                           [azimuth, elevation, torsion, pupil radius].
%                           The torsion value is unusued and is bounded to
%                           zero. Biological limits in eye rotation and
%                           pupil size would suggest boundaries of [�35,
%                           �25, 0, 0.25-5]. Note, however, that these
%                           angles are relative to the center of
%                           projection, not the primary position of the
%                           eye. Therefore, in circumstances in which the
%                           camera is viewing the eye from an off-center
%                           angle, the bounds will need to be shifted
%                           accordingly.
%  'fitLabel'             - Identifies the field in pupilData that contains
%                           the ellipse fit params for which the search
%                           will be conducted.
%  'ellipseArrayList'     - A vector of frame numbers (indexed from 1)
%                           which identify the ellipses to be used for the
%                           estimation of scene geometry. If left empty,
%                           a list of ellipses will be generated.
%  'nBinsPerDimension'    - Scalar. Defines the number of divisions with
%                           which the ellipse centers are binned.
%  'useRayTracing'        - Logical; default false. Using ray tracing in
%                           the camera translation search improves accuracy
%                           slightly, but increases search time by about
%                           25x.
%  'nBADSsearches'        - Scalar or 1x2 vector. We perform the search for
%                           camera translation from a randomly selected
%                           starting point within the plausible bounds.
%                           This parameter sets how many random starting
%                           points to try; the best result is retained.
%                           Each search is run on a separate worker if the
%                           parpool is available. If a two element vector
%                           is passed, and if 'useRayTracing' is set to
%                           true, then the first element sets the number of
%                           non-ray-traced searches, and the second element
%                           the number of ray-traced searches.
%
%
% Outputs
%	sceneGeometry         - A structure that contains the components of the
%                           projection model.
%
% Examples:
%{
    %% Recover a veridical camera translation
    % Create a veridical sceneGeometry with some arbitrary translation
    veridicalSceneGeometry = createSceneGeometry();
    veridicalSceneGeometry.extrinsicTranslationVector = [-1.2; 0.9; 108];
    % Assemble the ray tracing functions
    rayTraceFuncs = assembleRayTraceFuncs( veridicalSceneGeometry );
    % Create a set of ellipses using the veridical geometry and
    % randomly varying pupil radii.
    ellipseIdx=1;
    for azi=-15:15:15
    	for ele=-15:15:15
            eyePose=[azi, ele, 0, 2+(randn()./5)];
            pupilData.initial.ellipses.values(ellipseIdx,:) = pupilProjection_fwd(eyePose, veridicalSceneGeometry, rayTraceFuncs);
            pupilData.initial.ellipses.RMSE(ellipseIdx,:) = 1;
            ellipseIdx=ellipseIdx+1;
        end
    end
    % Estimate the scene Geometry using the ellipses
    nBADSsearches = 4;
    estimatedSceneGeometry = estimateSceneParams(pupilData,'','useParallel',true,'verbosity','full','ellipseArrayList',1:1:ellipseIdx-1,'nBADSsearches',nBADSsearches,'useRayTracing',false);
    % Report how well we did
    fprintf('Error in the recovered camera translation vector (x, y, depth] in mm: \n');
    veridicalSceneGeometry.extrinsicTranslationVector - estimatedSceneGeometry.extrinsicTranslationVector
%}

%% input parser
p = inputParser; p.KeepUnmatched = true;

% Required
p.addRequired('pupilFileName',@(x)(isstruct(x) | iscell(x) | ischar(x)));
p.addRequired('sceneGeometryFileName',@ischar);

% Optional display and I/O params
p.addParameter('verbosity', 'none', @isstr);
p.addParameter('sceneDiagnosticPlotFileName', '', @(x)(isempty(x) | ischar(x)));

% Optional flow control params
p.addParameter('useParallel',false,@islogical);
p.addParameter('nWorkers',[],@(x)(isempty(x) | isnumeric(x)));
p.addParameter('tbtbRepoName','transparentTrack',@ischar);

% Optional environment parameters
p.addParameter('tbSnapshot',[],@(x)(isempty(x) | isstruct(x)));
p.addParameter('timestamp',char(datetime('now')),@ischar);
p.addParameter('username',char(java.lang.System.getProperty('user.name')),@ischar);
p.addParameter('hostname',char(java.net.InetAddress.getLocalHost.getHostName),@ischar);

% Optional analysis params
p.addParameter('sceneParamsLB',[-20; -20; 90; 0.75; .9],@isnumeric);
p.addParameter('sceneParamsUB',[20; 20; 200; 1.25; 1.1],@isnumeric);
p.addParameter('sceneParamsLBp',[-5; -5; 100; 0.85; 0.95],@isnumeric);
p.addParameter('sceneParamsUBp',[5; 5; 160; 1.15; 1.05],@isnumeric);
p.addParameter('eyePoseLB',[-35,-25,0,0.25],@(x)(isempty(x) | isnumeric(x)));
p.addParameter('eyePoseUB',[35,25,0,4],@(x)(isempty(x) | isnumeric(x)));
p.addParameter('fitLabel','initial',@ischar);
p.addParameter('ellipseArrayList',[],@(x)(isempty(x) | isnumeric(x)));
p.addParameter('nBinsPerDimension',4,@isnumeric);
p.addParameter('useRayTracing',false,@islogical);
p.addParameter('nBADSsearches',10,@isnumeric);

% parse
p.parse(pupilFileName, sceneGeometryFileName, varargin{:})


%% Announce we are starting
if strcmp(p.Results.verbosity,'full')
    tic
    fprintf(['Estimating camera translation and eye rotation from pupil ellipses. Started ' char(datetime('now')) '\n']);
end

%% Create initial sceneGeometry structure and ray tracing functions
initialSceneGeometry = createSceneGeometry(varargin{:});

% Assemble the ray tracing functions
if p.Results.useRayTracing
    if strcmp(p.Results.verbosity,'full')
        fprintf('Assembling ray tracing functions.\n');
    end
    [rayTraceFuncs] = assembleRayTraceFuncs( initialSceneGeometry );
else
    rayTraceFuncs = [];
end

%% Set up the parallel pool
if p.Results.useParallel
    nWorkers = startParpool( p.Results.nWorkers, p.Results.tbtbRepoName, p.Results.verbosity );
else
    nWorkers=0;
end


%% Load pupil data
if iscell(pupilFileName)
    ellipses = [];
    ellipseFitSEM = [];
    for cc = 1:length(pupilFileName)
        load(pupilFileName{cc})
        ellipses = [ellipses; pupilData.(p.Results.fitLabel).ellipses.values];
        ellipseFitSEM = [ellipseFitSEM; pupilData.(p.Results.fitLabel).ellipses.RMSE];
    end
end
if ischar(pupilFileName)
    load(pupilFileName)
    ellipses = pupilData.(p.Results.fitLabel).ellipses.values;
    ellipseFitSEM = pupilData.(p.Results.fitLabel).ellipses.RMSE;
end
if isstruct(pupilFileName)
    pupilData = pupilFileName;
    ellipses = pupilData.(p.Results.fitLabel).ellipses.values;
    ellipseFitSEM = pupilData.(p.Results.fitLabel).ellipses.RMSE;
end


%% Identify the ellipses that will guide the sceneGeometry estimation
% If not supplied, we will generate a list of ellipses to use for the
% estimation.
if ~isempty(p.Results.ellipseArrayList)
    ellipseArrayList = p.Results.ellipseArrayList;
    Xedges = [];
    Yedges = [];
else
    if strcmp(p.Results.verbosity,'full')
        fprintf('Selecting ellipses to guide the search.\n');
    end
    
    % First we divide the ellipse centers amongst a set of 2D bins across
    % image space.
    [ellipseCenterCounts,Xedges,Yedges,binXidx,binYidx] = ...
        histcounts2(ellipses(:,1),ellipses(:,2),p.Results.nBinsPerDimension);
    
    % Anonymous functions for row and column identity given array position
    rowIdx = @(b) fix( (b-1) ./ (size(ellipseCenterCounts,2)) ) +1;
    colIdx = @(b) 1+mod(b-1,size(ellipseCenterCounts,2));
    
    % Create a cell array of index positions corresponding to each of the
    % 2D bins
    idxByBinPosition = ...
        arrayfun(@(b) find( (binXidx==rowIdx(b)) .* (binYidx==colIdx(b)) ),1:1:numel(ellipseCenterCounts),'UniformOutput',false);
    
    % Identify which bins are not empty
    filledBinIdx = find(~cellfun(@isempty, idxByBinPosition));
    
    % Identify the ellipse in each bin with the lowest fit SEM
    [~, idxMinErrorEllipseWithinBin] = arrayfun(@(x) nanmin(ellipseFitSEM(idxByBinPosition{x})), filledBinIdx, 'UniformOutput', false);
    returnTheMin = @(binContents, x)  binContents(idxMinErrorEllipseWithinBin{x});
    ellipseArrayList = cellfun(@(x) returnTheMin(idxByBinPosition{filledBinIdx(x)},x),num2cell(1:1:length(filledBinIdx)));
end


%% Generate the errorWeights
errorWeights = ellipseFitSEM(ellipseArrayList);
errorWeights = 1./errorWeights;
errorWeights = errorWeights./mean(errorWeights);


%% Perform the search
if strcmp(p.Results.verbosity,'full')
    fprintf(['Searching over camera translations without ray tracing.\n']);
    fprintf('| 0                      50                   100%% |\n');
    fprintf('.\n');
end

% Peform the search without rayTracing
searchResults = {};
parfor (ss = 1:p.Results.nBADSsearches(1),nWorkers)
    %for ss = 1:p.Results.nBADSsearches(1)
    
    searchResults{ss} = ...
        performSceneSearch(initialSceneGeometry, [], ...
        ellipses(ellipseArrayList,:), ...
        errorWeights, ...
        p.Results.sceneParamsLB, ...
        p.Results.sceneParamsUB, ...
        p.Results.sceneParamsLBp, ...
        p.Results.sceneParamsUBp, ...
        p.Results.eyePoseLB, ...
        p.Results.eyePoseUB);
    
    % update progress
    if strcmp(p.Results.verbosity,'full')
        for pp=1:floor(50/p.Results.nBADSsearches(1))
            fprintf('\b.\n');
        end
    end
    
end
if strcmp(p.Results.verbosity,'full')
    fprintf('\n');
end

% Find the weighted mean and SD of the translation vector and rotation
% scaling
allFvalsNoRayTrace = cellfun(@(x) x.meta.estimateSceneParams.search.fVal,searchResults);
allsceneParamVecsNoRayTrace = cellfun(@(x) [x.extrinsicTranslationVector; x.eye.rotationCenters.scaling],searchResults,'UniformOutput',false);
for dim = 1:3
    vals = cellfun(@(x) x(dim), allsceneParamVecsNoRayTrace);
    sceneParamVecMeanNoRayTrace(dim)=mean(vals.*(1./allFvalsNoRayTrace))/mean(1./allFvalsNoRayTrace);
    sceneParamVecSDNoRayTrace(dim)=std(vals,1./allFvalsNoRayTrace);
end
sceneParamVecMeanNoRayTrace=sceneParamVecMeanNoRayTrace';
sceneParamVecSDNoRayTrace=sceneParamVecSDNoRayTrace';

% If rayTraceFuncs is not empty, now repeat the search, using the initial
% result to inform the bounds for the search with rayTracing
if ~isempty(rayTraceFuncs)
    if strcmp(p.Results.verbosity,'full')
        fprintf(['Searching over camera translations with ray tracing.\n']);
        fprintf('| 0                      50                   100%% |\n');
        fprintf('.\n');
    end
    
    % Peform the search with rayTracing, and with plausible upper and lower
    % boundaries informed by the initial search without ray tracing
    searchResults = {};
    pLB = sceneParamVecMeanNoRayTrace-sceneParamVecSDNoRayTrace;
    pUB = sceneParamVecMeanNoRayTrace+sceneParamVecSDNoRayTrace;
    
    pLB = max([pLB p.Results.sceneParamsLB],[],2);
    pUB = min([pUB p.Results.sceneParamsUB],[],2);
    
    % Check if there is a second value in nBADSsearches we should use
    if length(p.Results.nBADSsearches)>1
        nRayTracedSearches = p.Results.nBADSsearches(2);
    else
        nRayTracedSearches = p.Results.nBADSsearches(1);
    end
    parfor (ss = 1:nRayTracedSearches,nWorkers)
        
        searchResults{ss} = ...
            performSceneSearch(initialSceneGeometry, rayTraceFuncs, ...
            ellipses(ellipseArrayList,:), ...
            errorWeights, ...
            p.Results.sceneParamsLB, ...
            p.Results.sceneParamsUB, ...
            pLB, ...
            pUB, ...
            p.Results.eyePoseLB, ...
            p.Results.eyePoseUB);
        
        % update progress
        if strcmp(p.Results.verbosity,'full')
            for pp=1:floor(50/nRayTracedSearches)
                fprintf('\b.\n');
            end
        end
        
    end
    if strcmp(p.Results.verbosity,'full')
        fprintf('\n');
    end
    
end

% Find the solution with the best fVal.
if isempty(rayTraceFuncs)
    [~, idx]=min(allFvalsNoRayTrace);
    sceneGeometry = searchResults{idx};
else
    [~, idx]=min(allFvalsWithRayTrace);
    sceneGeometry = searchResults{idx};
end

% Add additional search and meta field info to sceneGeometry
tmpHold=sceneGeometry.meta.estimateSceneParams.search;
sceneGeometry.meta.estimateSceneParams = p.Results;
sceneGeometry.meta.estimateSceneParams.search = tmpHold;
sceneGeometry.meta.estimateSceneParams.search.ellipseArrayList = ellipseArrayList';
sceneGeometry.meta.estimateSceneParams.search.allFvalsNoRayTrace = allFvalsNoRayTrace;
sceneGeometry.meta.estimateSceneParams.search.allsceneParamVecsNoRayTrace = allsceneParamVecsNoRayTrace;
sceneGeometry.meta.estimateSceneParams.search.sceneParamVecMeanNoRayTrace = sceneParamVecMeanNoRayTrace;
sceneGeometry.meta.estimateSceneParams.search.sceneParamVecSDNoRayTrace = sceneParamVecSDNoRayTrace;

if ~isempty(rayTraceFuncs)
    sceneGeometry.meta.estimateSceneParams.search.allFvalsWithRayTrace = allFvalsWithRayTrace;
    sceneGeometry.meta.estimateSceneParams.search.allsceneParamVecsWithRayTrace = allsceneParamVecsWithRayTrace;
end

%% Save the sceneGeometry file
if ~isempty(sceneGeometryFileName)
    save(sceneGeometryFileName,'sceneGeometry');
end


%% Create a sceneGeometry plot
if ~isempty(p.Results.sceneDiagnosticPlotFileName)
    if strcmp(p.Results.verbosity,'full')
        fprintf('Creating a sceneGeometry diagnostic plot.\n');
    end
    saveSceneDiagnosticPlot(...
        ellipses(ellipseArrayList,:),...
        Xedges, Yedges,...
        p.Results.eyePoseLB, ...
        p.Results.eyePoseUB, ...
        sceneGeometry,...
        rayTraceFuncs,...
        p.Results.sceneDiagnosticPlotFileName)
end


%% alert the user that we are done with the routine
if strcmp(p.Results.verbosity,'full')
    toc
    fprintf('\n');
end


end % main function



%% LOCAL FUNCTIONS

function sceneGeometry = performSceneSearch(initialSceneGeometry, rayTraceFuncs, ellipses, errorWeights, LB, UB, LBp, UBp, eyePoseLB, eyePoseUB, shapeErrorMultiplier)
% Pattern search for best fitting sceneGeometry parameters
%
% Description:
%   The routine searches for parameters of the extrinsic translation vector
%   of the camera and rotation centers of the eye that best model the
%   shapes (and areas) of ellipses found on the image plane, while
%   minimizing the distance between the modeled and observed ellipse
%   centers. The passed sceneGeometry structure is used as the starting
%   point for the search. Across each iteration of the search, a candidate
%   sceneGeometry is assembled from the current values of the parameters.
%   This sceneGeometry is then used in the inverse pupil projection model.
%   The inverse projection searches for an eye azimuth, elevation, and
%   pupil radius that, given the sceneGeometry, best accounts for the
%   parameters of the target ellipse on the image plane. This inverse
%   search attempts to minimize the distance bewteen the centers of the
%   predicted and targeted ellipse on the image plane, while satisfying
%   non-linear constraints upon matching the shape (eccentricity and theta)
%   and area of the ellipses. Only when the translation vector is correctly
%   specified will the inverse pupil projection model be able to
%   simultaneouslty match the center and shape of the ellipse on the image
%   plane.
%
%   The iterative search across sceneGeometry parameters attempts to
%   minimize the L2 norm of the shape and area errors between the targeted
%   and modeled centers of the ellipses. In the calculation of this
%   objective functon, each distance error is weighted. The error weight is
%   derived from the accuracy with which the boundary points of the pupil
%   in the image plane are fit by an unconstrained ellipse.
%
%   The search is performed using Bayesian Adaptive Direct Search (bads),
%   as we find that it performs better than (e.g.) patternsearch. BADS only
%   accepts row vectors, so there is much transposing ahead.
%

% Pick a random x0 from within the plausible bounds
x0 = LBp + (UBp-LBp).*rand(numel(LBp),1);

% Define search options
options = bads('defaults');          % Get a default OPTIONS struct
options.Display = 'off';             % Silence display output
options.UncertaintyHandling = 0;     % The objective is deterministic

% Silence the mesh overflow warning from BADS
warningState = warning;
warning('off','bads:meshOverflow');

% Define nested variables for within the search
centerDistanceErrorByEllipse=zeros(size(ellipses,1),1);
shapeErrorByEllipse=zeros(size(ellipses,1),1);
areaErrorByEllipse=zeros(size(ellipses,1),1);
recoveredEyePoses =zeros(size(ellipses,1),4);

% Detect if we have pinned the parameters, in which case just evaluate the
% objective function
if all(x0==LB) && all(x0==UB)
    x=x0';
    fVal = objfun(x);
else
    % Perform the seach using bads
    [x, fVal] = bads(@objfun,x0',LB',UB',LBp',UBp',[],options);
end
% Nested function computes the objective
    function fval = objfun(x)
        % Assemble a candidate sceneGeometry structure
        candidateSceneGeometry = initialSceneGeometry;
        % Store the extrinsic camera translation vector
        candidateSceneGeometry.extrinsicTranslationVector = x(1:3)';
        % Scale the rotation center values by the joint parameter and
        % differential parameters
        candidateSceneGeometry.eye.rotationCenters.azi = candidateSceneGeometry.eye.rotationCenters.azi .* x(4) .* x(5);
        candidateSceneGeometry.eye.rotationCenters.ele = candidateSceneGeometry.eye.rotationCenters.ele .* x(4) ./ x(5);
        % For each ellipse, perform the inverse projection from the ellipse
        % on the image plane to eyePose. We retain the errors from the
        % inverse projection and use these to assemble the objective
        % function. We parallelize the computation across ellipses.
        for ii = 1:size(ellipses,1)
            exitFlag = [];
            eyePose = [];
            [eyePose, ~, centerDistanceErrorByEllipse(ii), shapeErrorByEllipse(ii), areaErrorByEllipse(ii), exitFlag] = ...
                pupilProjection_inv(...
                ellipses(ii,:),...
                candidateSceneGeometry, rayTraceFuncs, ...
                'eyePoseLB',eyePoseLB,...
                'eyePoseUB',eyePoseUB...
                );
            % if the exitFlag indicates a possible local minimum, repeat
            % the search and initialize with the returned eyePose
            if exitFlag == 2
                x0tmp = eyePose + [1e-3 1e-3 0 1-3];
                [eyePose, ~, centerDistanceErrorByEllipse(ii), shapeErrorByEllipse(ii), areaErrorByEllipse(ii)] = ...
                    pupilProjection_inv(...
                    ellipses(ii,:),...
                    candidateSceneGeometry, rayTraceFuncs, ...
                    'eyePoseLB',eyePoseLB,...
                    'eyePoseUB',eyePoseUB,...
                    'x0',x0tmp...
                    );
            end
            recoveredEyePoses(ii,:)=eyePose;
        end
        % Now compute objective function as the RMSE of the distance
        % between the taget and modeled ellipses in shape and area
        fval = mean(((shapeErrorByEllipse+1).*errorWeights + (areaErrorByEllipse+1).*errorWeights).^2).^(1/2);
        % We have to keep the fval non-infinite to keep BADS happy
        fval=min([fval realmax]);
    end



% Restore the warning state
warning(warningState);

% Assemble the sceneGeometry file to return
sceneGeometry = initialSceneGeometry;
sceneGeometry.extrinsicTranslationVector = x(1:3)';
sceneGeometry.eye.rotationCenters.scaling = x(4:5)';
sceneGeometry.eye.rotationCenters.azi = sceneGeometry.eye.rotationCenters.azi .* x(4) .* x(5);
sceneGeometry.eye.rotationCenters.ele = sceneGeometry.eye.rotationCenters.ele .* x(4) ./ x(5);
sceneGeometry.meta.estimateSceneParams.search.options = options;
sceneGeometry.meta.estimateSceneParams.search.initialSceneGeometry = initialSceneGeometry;
sceneGeometry.meta.estimateSceneParams.search.ellipses = ellipses;
sceneGeometry.meta.estimateSceneParams.search.errorWeights = errorWeights;
sceneGeometry.meta.estimateSceneParams.search.x0 = x0;
sceneGeometry.meta.estimateSceneParams.search.LB = LB;
sceneGeometry.meta.estimateSceneParams.search.UB = UB;
sceneGeometry.meta.estimateSceneParams.search.LBp = LBp;
sceneGeometry.meta.estimateSceneParams.search.UBp = UBp;
sceneGeometry.meta.estimateSceneParams.search.eyePoseLB = eyePoseLB;
sceneGeometry.meta.estimateSceneParams.search.eyePoseUB = eyePoseUB;
sceneGeometry.meta.estimateSceneParams.search.fVal = fVal;
sceneGeometry.meta.estimateSceneParams.search.centerDistanceErrorByEllipse = centerDistanceErrorByEllipse;
sceneGeometry.meta.estimateSceneParams.search.shapeErrorByEllipse = shapeErrorByEllipse;
sceneGeometry.meta.estimateSceneParams.search.areaErrorByEllipse = areaErrorByEllipse;
sceneGeometry.meta.estimateSceneParams.search.recoveredEyePoses = recoveredEyePoses;

end % local search function


function [] = saveSceneDiagnosticPlot(ellipses, Xedges, Yedges, eyePoseLB, eyePoseUB, sceneGeometry, rayTraceFuncs, sceneDiagnosticPlotFileName)
% Creates and saves a plot that illustrates the sceneGeometry results
%
% Inputs:
%   ellipses              - An n x p array containing the p parameters of
%                           the n ellipses used to derive sceneGeometry
%   Xedges                - The X-dimension edges of the bins used to
%                           divide and select ellipses across the image.
%   Yedges                - The Y-dimension edges of the bins used to
%                           divide and select ellipses across the image.
%   eyePoseLB, eyePoseUB  - Bounds for the eye pose to be passed to
%                           pupilProjection_inv.
%   sceneGeometry         - The sceneGeometry structure
%   sceneDiagnosticPlotFileName - The full path (including .pdf suffix)
%                           to the location to save the diagnostic plot
%
% Outputs:
%   none
%

figHandle=figure('visible','off');
set(gcf,'PaperOrientation','landscape');

set(figHandle, 'Units','inches')
height = 6;
width = 11;

% the last two parameters of 'Position' define the figure size
set(figHandle, 'Position',[25 5 width height],...
    'PaperSize',[width height],...
    'PaperPositionMode','auto',...
    'Color','w',...
    'Renderer','painters'...
    );

%% Left panel -- distance error
subplot(3,3,[1 4]);

if ~isempty(Xedges)
    % plot the 2D histogram grid
    for xx = 1: length(Xedges)
        if xx==1
            hold on
        end
        plot([Xedges(xx) Xedges(xx)], [Yedges(1) Yedges(end)], '-', 'Color', [0.9 0.9 0.9], 'LineWidth', 0.5 );
    end
    for yy=1: length(Yedges)
        plot([Xedges(1) Xedges(end)], [Yedges(yy) Yedges(yy)], '-', 'Color', [0.9 0.9 0.9], 'LineWidth', 0.5);
    end
    binSpaceX = Xedges(2)-Xedges(1);
    binSpaceY = Yedges(2)-Yedges(1);
end

% plot the ellipse centers
scatter(ellipses(:,1),ellipses(:,2),'o','filled', ...
    'MarkerFaceAlpha',2/8,'MarkerFaceColor',[0 0 0]);
hold on

% get the predicted ellipse centers
[~, projectedEllipses] = ...
    arrayfun(@(x) pupilProjection_inv...
    (...
    ellipses(x,:),...
    sceneGeometry,...
    rayTraceFuncs,...
    'eyePoseLB',eyePoseLB,'eyePoseUB',eyePoseUB),...
    1:1:size(ellipses,1),'UniformOutput',false);
projectedEllipses=vertcat(projectedEllipses{:});

% plot the projected ellipse centers
scatter(projectedEllipses(:,1),projectedEllipses(:,2),'o','filled', ...
    'MarkerFaceAlpha',2/8,'MarkerFaceColor',[0 0 1]);

% connect the centers with lines
errorWeightVec=sceneGeometry.meta.estimateSceneParams.search.errorWeights;
for ii=1:size(ellipses,1)
    lineAlpha = errorWeightVec(ii)/max(errorWeightVec);
    lineWeight = 0.5 + (errorWeightVec(ii)/max(errorWeightVec));
    ph=plot([projectedEllipses(ii,1) ellipses(ii,1)], ...
        [projectedEllipses(ii,2) ellipses(ii,2)], ...
        '-','Color',[1 0 0],'LineWidth', lineWeight);
    ph.Color(4) = lineAlpha;
end

% plot the estimated center of rotation of the eye
rotationCenterEllipse = pupilProjection_fwd([0 0 0 2], sceneGeometry, rayTraceFuncs);
plot(rotationCenterEllipse(1),rotationCenterEllipse(2), '+g', 'MarkerSize', 5);

% Calculate the plot limits
if ~isempty(Xedges)
    xPlotBounds = [Xedges(1)-binSpaceX Xedges(end)+binSpaceX];
    yPlotBounds = [Yedges(1)-binSpaceY Yedges(end)+binSpaceY];
else
    minX = min([projectedEllipses(:,1);ellipses(:,1)]);
    maxX = max([projectedEllipses(:,1);ellipses(:,1)]);
    minY = min([projectedEllipses(:,2);ellipses(:,2)]);
    maxY = max([projectedEllipses(:,2);ellipses(:,2)]);
    xPlotBounds = [(minX - (maxX-minX)/10) (maxX + (maxX-minX)/10) ];
    yPlotBounds = [(minY - (maxY-minY)/10) (maxY + (maxY-minY)/10) ];
end

% label and clean up the plot
axis equal
set(gca,'Ydir','reverse')
title('Distance error')
xlim (xPlotBounds);
ylim (yPlotBounds);

% Create a legend
hSub = subplot(3,3,7);
scatter(nan, nan,2,'filled', ...
    'MarkerFaceAlpha',2/8,'MarkerFaceColor',[0 0 0]);
hold on
scatter(nan, nan,2,'filled', ...
    'MarkerFaceAlpha',2/8,'MarkerFaceColor',[0 0 1]);
plot(nan, nan, '+g', 'MarkerSize', 5);
set(hSub, 'Visible', 'off');
legend({'observed ellipse centers','modeled ellipse centers', 'azimuth 0, elevation 0'},'Location','north', 'Orientation','vertical');


%% Center panel -- shape error
subplot(3,3,[2 5]);

if ~isempty(Xedges)
    % plot the 2D histogram grid
    for xx = 1: length(Xedges)
        if xx==1
            hold on
        end
        plot([Xedges(xx) Xedges(xx)], [Yedges(1) Yedges(end)], '-', 'Color', [0.9 0.9 0.9], 'LineWidth', 0.5 );
    end
    for yy=1: length(Yedges)
        plot([Xedges(1) Xedges(end)], [Yedges(yy) Yedges(yy)], '-', 'Color', [0.9 0.9 0.9], 'LineWidth', 0.5);
    end
end

% Calculate a color for each plot point corresponding to the degree of
% shape error
shapeErrorVec = sceneGeometry.meta.estimateSceneParams.search.shapeErrorByEllipse;
shapeErrorVec = shapeErrorVec./sceneGeometry.constraintTolerance;
colorMatrix = zeros(3,size(ellipses,1));
colorMatrix(1,:)=1;
colorMatrix(2,:)= shapeErrorVec;
scatter(ellipses(:,1),ellipses(:,2),[],colorMatrix','o','filled');

% label and clean up the plot
axis equal
set(gca,'Ydir','reverse')
title('Shape error')
xlim (xPlotBounds);
ylim (yPlotBounds);

% Create a legend
hSub = subplot(3,3,8);
scatter(nan, nan,2,'filled', ...
    'MarkerFaceAlpha',6/8,'MarkerFaceColor',[1 0 0]);
hold on
scatter(nan, nan,2,'filled', ...
    'MarkerFaceAlpha',6/8,'MarkerFaceColor',[1 0.5 0]);
scatter(nan, nan,2,'filled', ...
    'MarkerFaceAlpha',6/8,'MarkerFaceColor',[1 1 0]);
set(hSub, 'Visible', 'off');
legend({'0',num2str(sceneGeometry.constraintTolerance/2), ['=> ' num2str(sceneGeometry.constraintTolerance)]},'Location','north', 'Orientation','vertical');

% Add text to report the extrinsic translation vector
myString = sprintf('Translation vector [mm] = %4.1f, %4.1f, %4.1f; rotation center scaling [joint, differential] = %4.2f, %4.2f',sceneGeometry.extrinsicTranslationVector(1),sceneGeometry.extrinsicTranslationVector(2),sceneGeometry.extrinsicTranslationVector(3),sceneGeometry.eye.rotationCenters.scaling(1),sceneGeometry.eye.rotationCenters.scaling(2));
text(0.5,1.0,myString,'Units','normalized','HorizontalAlignment','center')

%% Right panel -- area error
subplot(3,3,[3 6]);

if ~isempty(Xedges)
    % plot the 2D histogram grid
    for xx = 1: length(Xedges)
        if xx==1
            hold on
        end
        plot([Xedges(xx) Xedges(xx)], [Yedges(1) Yedges(end)], '-', 'Color', [0.9 0.9 0.9], 'LineWidth', 0.5 );
    end
    for yy=1: length(Yedges)
        plot([Xedges(1) Xedges(end)], [Yedges(yy) Yedges(yy)], '-', 'Color', [0.9 0.9 0.9], 'LineWidth', 0.5);
    end
end

% Calculate a color for each plot point corresponding to the degree of
% shape error
areaErrorVec = sceneGeometry.meta.estimateSceneParams.search.areaErrorByEllipse;
areaErrorVec = abs(areaErrorVec)./sceneGeometry.constraintTolerance;
areaErrorVec = min([areaErrorVec ones(size(ellipses,1),1)],[],2);
colorMatrix = zeros(3,size(ellipses,1));
colorMatrix(1,:)=1;
colorMatrix(2,:)= areaErrorVec;
scatter(ellipses(:,1),ellipses(:,2),[],colorMatrix','o','filled');

% label and clean up the plot
axis equal
set(gca,'Ydir','reverse')
title('Area error')
xlim (xPlotBounds);
ylim (yPlotBounds);

% Create a legend
hSub = subplot(3,3,9);
scatter(nan, nan,2,'filled', ...
    'MarkerFaceAlpha',6/8,'MarkerFaceColor',[1 0 0]);
hold on
scatter(nan, nan,2,'filled', ...
    'MarkerFaceAlpha',6/8,'MarkerFaceColor',[1 0.5 0]);
scatter(nan, nan,2,'filled', ...
    'MarkerFaceAlpha',6/8,'MarkerFaceColor',[1 1 0]);
set(hSub, 'Visible', 'off');
legend({'0',num2str(sceneGeometry.constraintTolerance/2), ['=> ' num2str(sceneGeometry.constraintTolerance)]},'Location','north', 'Orientation','vertical');


%% Save the plot
saveas(figHandle,sceneDiagnosticPlotFileName)
close(figHandle)

end % saveSceneDiagnosticPlot

