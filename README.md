# ASL Self-Contained Processing Docker Container (ASLscp)

This GitHub Repo is the basis for a Docker container to process ASL data without any structural scan. This processing pipeline was developed at Penn Medicine by Manuel Taso. The Docker container and Flywheel gear were developed by Katie Jobson.

This pipeline requires Siemens ASL data. Two files will be used as input: the ASL timeseries data and M0 image. Data must be 3D pCASL data. The pipeline will take the ASL and M0 data and compute a CBF map. 

The pipeline is also built to register common atlases to the CBF map and automatically extract mean CBF in Alzheimer's Disease relevant regions. Results included are text files with mean CBF values from those altlases, an output PDF that includes images for QC and tables with mean CBF and rCBF values, and the CBF map.

If the ASL data that you acquire does not include the LD and PLD information in the JSON files, they will need to be provided. There are four parameters that need to be set: labeling delay (ld), post-labeling delay (pld), number of background suppressions (nbs), and the m0 scale (m0_scale). These parameters need to be set before building the Docker container (but not a Flywheel gear). The parameters.json file can be edited and used for this purpose. If there are no background suppressions included in the ASL protocol, set nbs to 1.

## Examples of running the Docker container

WIP

## Examples of uploading the container as a Flywheel gear
 
WIP
