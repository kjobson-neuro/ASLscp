#!/bin/bash
IMAGE=$(jq -r '.custom["gear-builder"].image' manifest.json)
BASEDIR=~/Work/Asl/
CURDIR=${BASEDIR}/docker-ashs-base
# Command:
docker run --rm -it --entrypoint='/bin/bash'\
	-e FLYWHEEL=/flywheel/v0\
        -v ~/.config/flywheel:/root/.config/flywheel \
	-v ${BASEDIR}/output:/flywheel/v0/output\
	$IMAGE
