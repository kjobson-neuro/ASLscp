# original script from William Tackett, adapted by Katie Jobson
# Ubuntu 22.04 LTS - Jammy

#this ARG command is ideal for setting up things that will not be passed to the gear
ARG TARGETARCH

FROM --platform=linux/amd64 ubuntu:jammy

#
## Download stages
#

# Utilities for downloading packages

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
                    binutils \
                    bzip2 \
                    ca-certificates \
                    curl \
                    unzip && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# FreeSurfer 7.3.2
COPY freesurfer7.3-exclude.txt /usr/local/etc/freesurfer7.3-exclude.txt
RUN curl -sSL https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/7.3.2/freesurfer-linux-ubuntu22_amd64-7.3.2.tar.gz \
     | tar zxv --no-same-owner -C /opt --exclude-from=/usr/local/etc/freesurfer7.3-exclude.txt

# ANTs 2.5.3
# Old ANTs code, save in case new doesn't work
RUN mkdir /opt/ants && \
   curl -fsSL https://github.com/ANTsX/ANTs/releases/download/v2.4.3/ants-2.4.3-centos7-X64-gcc.zip -o ants.zip && \
   unzip ants.zip -d /opt && \
   rm ants.zip

ENV FSLDIR="/opt/fsl-6.0.7.1" \
    PATH="/opt/fsl-6.0.7.1/bin:$PATH" \
    FSLOUTPUTTYPE="NIFTI_GZ" \
    FSLMULTIFILEQUIT="TRUE" \
    FSLTCLSH="/opt/fsl-6.0.7.1/bin/fsltclsh" \
    FSLWISH="/opt/fsl-6.0.7.1/bin/fslwish" \
    FSLLOCKDIR="" \
    FSLMACHINELIST="" \
    FSLREMOTECALL="" \
    FSLGECUDAQ="cuda.q"
RUN apt-get update -qq \
    && apt-get install -y -q --no-install-recommends \
           bc \
           ca-certificates \
           curl \
           dc \
           file \
           libfontconfig1 \
           libfreetype6 \
           libgl1-mesa-dev \
           libgl1-mesa-dri \ 
           libglu1-mesa-dev \
           libgomp1 \
           libice6 \
           libopenblas-base \
           libxcursor1 \
           libxft2 \
           libxinerama1 \
           libxrandr2 \
           libxrender1 \
           libxt6 \
           nano \
           python3 \
           sudo \
           wget \
    && rm -rf /var/lib/apt/lists/* \
    && echo "Installing FSL ..." \
    && curl -fsSL https://fsl.fmrib.ox.ac.uk/fsldownloads/fslconda/releases/fslinstaller.py | python3 - -d /opt/fsl-6.0.7.1 -V 6.0.7.1

#
# Main stage
#

# Create the FW environment
ENV FLYWHEEL=/flywheel/v0
RUN mkdir -p ${FLYWHEEL}

WORKDIR ${FLYWHEEL}

# Configure APT
ENV DEBIAN_FRONTEND="noninteractive" \
    LANG="en_US.UTF-8" \
    LC_ALL="en_US.UTF-8"


RUN apt-get update && \
    apt-get install -y --no-install-recommends \
                    ca-certificates \
                    curl \
                    gnupg && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Configure PPAs for libpng12 and libxp6
RUN GNUPGHOME=/tmp gpg --keyserver hkps://keyserver.ubuntu.com --no-default-keyring --keyring /usr/share/keyrings/linuxuprising.gpg --recv 0xEA8CACC073C3DB2A \
    && GNUPGHOME=/tmp gpg --keyserver hkps://keyserver.ubuntu.com --no-default-keyring --keyring /usr/share/keyrings/zeehio.gpg --recv 0xA1301338A3A48C4A \
    && echo "deb [signed-by=/usr/share/keyrings/linuxuprising.gpg] https://ppa.launchpadcontent.net/linuxuprising/libpng12/ubuntu jammy main" > /etc/apt/sources.list.d/linuxuprising.list \
    && echo "deb [signed-by=/usr/share/keyrings/zeehio.gpg] https://ppa.launchpadcontent.net/zeehio/libxp/ubuntu jammy main" > /etc/apt/sources.list.d/zeehio.list

# Simulate SetUpFreeSurfer.sh
ENV OS="Linux" \
    FS_OVERRIDE=0 \
    FIX_VERTEX_AREA="" \
    FSF_OUTPUT_FORMAT="nii.gz" \
    FREESURFER_HOME="/opt/freesurfer" \
    FSLDIR="/opt/fsl-6.0.7.1/"
ENV SUBJECTS_DIR="$FREESURFER_HOME/subjects" \
    FUNCTIONALS_DIR="$FREESURFER_HOME/sessions" \
    MNI_DIR="$FREESURFER_HOME/mni" \
    LOCAL_DIR="$FREESURFER_HOME/local" \
    MINC_BIN_DIR="$FREESURFER_HOME/mni/bin" \
    MINC_LIB_DIR="$FREESURFER_HOME/mni/lib" \
    MNI_DATAPATH="$FREESURFER_HOME/mni/data"
ENV PERL5LIB="$MINC_LIB_DIR/perl5/5.8.5" \
    MNI_PERL5LIB="$MINC_LIB_DIR/perl5/5.8.5" \
    PATH="$FREESURFER_HOME/bin:$FREESURFER_HOME/tktools:$MINC_BIN_DIR:$PATH"

# ANTs config
ENV ANTSPATH="/opt/ants-2.4.3/bin" \
    PATH="$ANTSPATH:$PATH"

# FSL environment
ENV LANG="C.UTF-8" \
    LC_ALL="C.UTF-8" \
    LC_NUMERIC="en_US.UTF-8" \
    PYTHONNOUSERSITE=1 \
    FSLDIR="/opt/fsl-6.0.7.1" \
    FSLOUTPUTTYPE="NIFTI_GZ" \
    FSLMULTIFILEQUIT="TRUE" \
    FSLLOCKDIR="" \
    FSLMACHINELIST="" \
    FSLREMOTECALL="" \
    FSLGECUDAQ="cuda.q" \
    PATH="/opt/fsl-6.0.7.1/bin:$PATH" \
    LD_LIBRARY_PATH=""

# Unless otherwise specified each process should only use one thread - nipype
# will handle parallelization
ENV MKL_NUM_THREADS=1 \
    OMP_NUM_THREADS=1

#################
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
                    binutils \
                    bzip2 \
                    ca-certificates \
                    curl \
                    python3 \
                    python3-pip \
                    zip \
                    jq \
                    gnupg \
                    lsb-release \
                    netbase \
                    pipx \
                    dcm2niix \
                    libc6-amd64-cross \
                    bsdmainutils \
                    unzip && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Installing and setting up python packages
RUN pipx ensurepath
RUN pipx install numpy \
    && pipx install scipy --include-deps \
    && pipx install nibabel \
    && pipx install matplotlib --include-deps \
    && pipx install transforms3d --include-deps \
    && pipx install flywheel-sdk --include-deps \
    && pip3 install aspose-words

# Copy stuff over & change permissions
COPY ./input/ ${FLYWHEEL}/input/
COPY ./workflows/ ${FLYWHEEL}/workflows/
COPY ./pipeline_singlePLD.sh ${FLYWHEEL}/
RUN chmod -R 777 ${FLYWHEEL}

# Configure entrypoints-
ENTRYPOINT ["/bin/bash", "/flywheel/v0/pipeline_singlePLD.sh"]
