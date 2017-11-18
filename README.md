# transparentTrack
Code to analyze pupil size and gaze location in IR video of the eye.

These MATLAB routines are designed to operate upon infra-red videos of the human eye and extract the elliptical boundary of the pupil and the location of the IR "glint" (first Purkinje image). Additional routines support calibration of absolute pupil size and gaze position, resulting in extracted time-series data that provide eye gaze in degrees of visual angle relative to a viewed screen and pupil size in mm^2 on the surface of the eye.

Notably, this software is computationally intensive and is designed to be run post-hoc upon videos collected during an experimental session. A particular design goal is to provide an accurate fit to the pupil boundary when it is partially obscured by the eyelid. This circumstance is encountered when the pupil is large (as is seen in data collected under low-light conditions) or in people with retinal disease.

The central computation is to fit an ellipse to the pupil boundary in each image frame. This fitting operation is performed iteratively, aided by ever more informed constraints on the parameters that define the ellipse. The ellipse function is recast in "transparent" form, with parameters that define the ellipse by X center, Y center, area, eccentricity (e.g., aspect ratio), and theta (angle). Expressing the parameters of the ellipse in this way allows us to place linear and non-linear constraints upon different parameters. At a high level of description, the fitting approach involves:

- **Intensity segmentation to extract the boundary of the pupil**. A preliminary circle fit via the Hough transform and an adaptive size window is used. In principle, another algorithm (e.g., the Starburst) could be substituted here.
- **Initial ellipse fit with minimal parameter constraints**. As part of this first stage, the pupil boundary is refined through the application of "cuts" of different angles or extent. The minimum cut that provides an acceptable ellipse fit is retained. This step addresses obscuration of the pupil border by the eye lids or by non-uniform IR illumination of the pupil.
- **Estimation of scene geometry**. Assuming an underlying physical model for the data (circular pupil on a spherical eye), an estimate of scene geometry is obtained that best accounts for the observed ellipses. Specifically, the [X, Y, Z] position of the center of rotation of the eye (relative to the image plane), and the radius of the eye, are estimated.
- **Repeat ellipse fit with scene geometry constraints**. Given the scene geometry, some combinations of ellipse parameters are valid while others are not. Specifically, a non-linear constraint is placed upon ellipse fits such that the x, y position of the center of the ellipse in the image plane is concordant with the eccentricity and theta of the ellipse, given the scene geometry.
- **Smooth pupil area**. The area of the pupil is not expected to change abruptly. We perform an empirical Bayes smoothing of pupil area in the scene. First, the area of each ellipse is converted to the area of the pupil on the surface of the eye in the scene that would have given rise to this ellipse given the scene geometry constraints. Next, a non-causal, empirical prior is constructed for each time point using the (exponentially weighted) pupil area observed in adjacent time points. The calculated, posterior area is then projected back to the image plane and used as a constraint to refit the ellipse.

There are many software parameters that control the behavior of the routines. While the default settings work well for some videos (including those that are part of the sandbox demo included in this repository), other parameter settings may be needed for videos with different qualities. The Matlab parpool may be used to speed the analysis on multi-core systems.

To install and configure transparentTrack, first install toolboxToolbox (tBtB), which provides for declarative dependency management for Matlab: https://github.com/ToolboxHub/ToolboxToolbox

Once tBtB is installed, transparentTrack (and all its dependencies) can be installed and readied for use with the command `tbUse('transparentTrack')`.
