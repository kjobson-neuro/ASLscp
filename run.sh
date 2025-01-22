#!/usr/bin/env bash 

IMAGE=kjobson/aslscp:0.1.1

# Command:
docker run -v /Users/katiejobson/github/aslscp/input:/flywheel/v0/input -v \
	/Users/katiejobson/github/aslscp/output:/flywheel/v0/output -v \
	/Users/katiejobson/github/aslscp/work:/flywheel/v0/work -v \
	/Users/katiejobson/github/aslscp/config.json:/flywheel/v0/config.json -v \
	/Users/katiejobson/github/aslscp/manifest.json:/flywheel/v0/manifest.json \
	--entrypoint=/bin/sh -e FLYWHEEL='/flywheel/v0' -e \
	PYTHON_GET_PIP_URL='https://github.com/pypa/get-pip/raw/0d8570dc44796f4369b652222cf176b3db6ac70e/public/get-pip.py' \
	-e \
	PATH='/opt/fsl-6.0.7.1/bin::/opt/freesurfer/bin:/opt/freesurfer/tktools:/opt/freesurfer/mni/bin:/opt/fsl-6.0.7.1/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
	-e LANG='C.UTF-8' -e PYTHON_VERSION='3.13.0' -e PWD='/flywheel/v0' -e \
	PYTHON_GET_PIP_SHA256='96461deced5c2a487ddc65207ec5a9cffeca0d34e7af7ea1afc470ff0d746207' \
	-e PYTHONPATH='/usr/local/lib/python3.12/site-packages:/usr/local/flywheel/lib/' -e \
	BASEDIR='/opt/base' -e MINC_LIB_DIR='/opt/freesurfer/mni/lib' -e \
	FREESURFER_HOME='/opt/freesurfer' -e MINC_BIN_DIR='/opt/freesurfer/mni/bin' -e \
	PYTHONNOUSERSITE='1' -e FSLDIR='/opt/fsl-6.0.7.1' -e ANTSPATH='/opt/ants-2.4.3/bin' -e \
	FUNCTIONALS_DIR='/opt/freesurfer/sessions' -e FSLMULTIFILEQUIT='TRUE' -e OS='Linux' -e \
	PERL5LIB='/opt/freesurfer/mni/lib/perl5/5.8.5' -e FSLGECUDAQ='cuda.q' -e \
	MNI_DIR='/opt/freesurfer/mni' -e FSLOUTPUTTYPE='NIFTI_GZ' -e \
	MNI_PERL5LIB='/opt/freesurfer/mni/lib/perl5/5.8.5' -e LOCAL_DIR='/opt/freesurfer/local' \
	-e FS_OVERRIDE='0' -e FSF_OUTPUT_FORMAT='nii.gz' -e \
	MNI_DATAPATH='/opt/freesurfer/mni/data' -e LC_ALL='C.UTF-8' -e \
	SUBJECTS_DIR='/opt/freesurfer/subjects' -e MKL_NUM_THREADS='1' -e OMP_NUM_THREADS='1' -e \
	LD_LIBRARY_PATH='/opt/fsl-6.0.7.1/lib:' -e DEBIAN_FRONTEND='noninteractive' -e \
	FSLTCLSH='/opt/fsl-6.0.7.1/bin/fsltclsh' -e FSLWISH='/opt/fsl-6.0.7.1/bin/fslwish' \
	$IMAGE -c /flywheel/v0/pipeline_singlePLD.sh \
