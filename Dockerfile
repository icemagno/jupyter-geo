FROM openjdk:18-jdk-bullseye
LABEL maintainer "Carlos M. Abreu <magno.mabreu@gmail.com>"

WORKDIR /tmp

ARG NB_USER="jovyan"
ARG NB_UID="1000"
ARG NB_GID="100"
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update --yes && \
    # - apt-get upgrade is run to patch known vulnerabilities in apt-get packages as
    #   the ubuntu base image is rebuilt too seldom sometimes (less than once a month)
    apt-get upgrade --yes && \
    apt-get install --yes --no-install-recommends \
	apt-utils \
    ca-certificates \
    fonts-liberation \
    locales \
    # - pandoc is used to convert notebooks to html files
    #   it's not present in arm64 ubuntu image, so we install it here
    pandoc \
    sudo \
    # - tini is installed as a helpful container entrypoint that reaps zombie
    #   processes and such of the actual executable we want to start, see
    #   https://github.com/krallin/tini#why-tini for details.
    tini \
    wget && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen
	
# Configure environment
ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    NB_USER="${NB_USER}" \
    NB_UID=${NB_UID} \
    NB_GID=${NB_GID} \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8
ENV PATH="${CONDA_DIR}/bin:${PATH}" \
    HOME="/home/${NB_USER}"

# Copy a script that we will use to correct permissions after running certain commands
COPY fix-permissions /usr/local/bin/fix-permissions
RUN chmod a+rx /usr/local/bin/fix-permissions	

# Enable prompt color in the skeleton .bashrc before creating the default NB_USER
# hadolint ignore=SC2016
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc && \
   # Add call to conda init script see https://stackoverflow.com/a/58081608/4413446
   echo 'eval "$(command conda shell.bash hook 2> /dev/null)"' >> /etc/skel/.bashrc

# Create NB_USER with name jovyan user with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    useradd -l -m -s /bin/bash -N -u "${NB_UID}" "${NB_USER}" && \
    mkdir -p "${CONDA_DIR}" && \
    chown "${NB_USER}:${NB_GID}" "${CONDA_DIR}" && \
    chmod g+w /etc/passwd && \
    fix-permissions "${HOME}" && \
    fix-permissions "${CONDA_DIR}"

USER ${NB_UID}
ARG PYTHON_VERSION=default

# Setup work directory for backward-compatibility
RUN mkdir "/home/${NB_USER}/work" && \
    fix-permissions "/home/${NB_USER}"

# Install conda as jovyan and check the sha256 sum provided on the download site
WORKDIR /tmp

# CONDA_MIRROR is a mirror prefix to speed up downloading
# For example, people from mainland China could set it as
# https://mirrors.tuna.tsinghua.edu.cn/github-release/conda-forge/miniforge/LatestRelease
ARG CONDA_MIRROR=https://github.com/conda-forge/miniforge/releases/latest/download

# ---- Miniforge installer ----
# Check https://github.com/conda-forge/miniforge/releases
# Package Manager and Python implementation to use (https://github.com/conda-forge/miniforge)
# We're using Mambaforge installer, possible options:
# - conda only: either Miniforge3 to use Python or Miniforge-pypy3 to use PyPy
# - conda + mamba: either Mambaforge to use Python or Mambaforge-pypy3 to use PyPy
# Installation: conda, mamba, pip
RUN set -x && \
    # Miniforge installer
    miniforge_arch=$(uname -m) && \
    miniforge_installer="Mambaforge-Linux-${miniforge_arch}.sh" && \
    wget --quiet "${CONDA_MIRROR}/${miniforge_installer}" && \
    /bin/bash "${miniforge_installer}" -f -b -p "${CONDA_DIR}" && \
    rm "${miniforge_installer}" && \
    # Conda configuration see https://conda.io/projects/conda/en/latest/configuration.html
    conda config --system --set auto_update_conda false && \
    conda config --system --set show_channel_urls true && \
    if [[ "${PYTHON_VERSION}" != "default" ]]; then mamba install --quiet --yes python="${PYTHON_VERSION}"; fi && \
    # Pin major.minor version of python
    mamba list python | grep '^python ' | tr -s ' ' | cut -d ' ' -f 1,2 >> "${CONDA_DIR}/conda-meta/pinned" && \
    # Using conda to update all packages: https://github.com/mamba-org/mamba/issues/1092
    conda update --all --quiet --yes && \
    conda clean --all -f -y && \
    rm -rf "/home/${NB_USER}/.cache/yarn" && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"

# Using fixed version of mamba in arm, because the latest one has problems with arm under qemu
# See: https://github.com/jupyter/docker-stacks/issues/1539
RUN set -x && \
    arch=$(uname -m) && \
    if [ "${arch}" == "aarch64" ]; then \
        mamba install --quiet --yes \
            'mamba<0.18' && \
            mamba clean --all -f -y && \
            fix-permissions "${CONDA_DIR}" && \
            fix-permissions "/home/${NB_USER}"; \
    fi;

# Install Jupyter Notebook, Lab, and Hub
# Generate a notebook server config
# Cleanup temporary files
# Correct permissions
# Do all this in a single RUN command to avoid duplicating all of the
# files across image layers when the permissions change
RUN mamba install --quiet --yes \
    'notebook' \
    'jupyterhub' \
    'jupyterlab' && \
    mamba clean --all -f -y && \
    npm cache clean --force && \
    jupyter notebook --generate-config && \
    jupyter lab clean && \
    rm -rf "/home/${NB_USER}/.cache/yarn" && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"

EXPOSE 8888

# Configure container startup
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start-notebook.sh"]

# Copy local files as late as possible to avoid cache busting
COPY start.sh start-notebook.sh start-singleuser.sh /usr/local/bin/

# Currently need to have both jupyter_notebook_config and jupyter_server_config to support classic and lab
COPY jupyter_server_config.py /etc/jupyter/

# Fix permissions on /etc/jupyter as root
USER root


ENV SUPPLIBS=$HOME/supplibs 
ENV PATH="/opt/opengrads:${PATH}"	

RUN apt update && apt -y upgrade \
    && apt -y install \
	make \
	g++ \
	libc6-dev \
	build-essential \
	bison \
	flex \
	freetds-dev \
	pkg-config \
	fortran-compiler \
	musl \
	musl-dev \
	libperl-dev \
	python3-dev \
	libtiff-dev \
	libpq-dev \
	libxml2-dev \
	libgeos-dev \
	libnetcdf-dev \
	libxerces-c-dev \
	libheif-dev \
	libfreetype-dev \
	libxmu-dev \
	libxpm-dev \
	libxaw7-dev \
	libncurses-dev \
	libzstd-dev \
	libsnappy-dev \
	libopenexr-dev \
	libcfitsio-dev \
	libfreexl-dev \
	liblz4-dev \
	libwebp-dev \
	libsqlite3-dev \
	libproj-dev \
	libprotobuf-c-dev \
	python3-numpy-dev \
	libminizip-dev \
	imagemagick \
	gis-devel \
	gdal-bin \
	libgdal-grass \
	postgis \
	osm2pgsql \
	vim \
    grass \
	grass-dev \
	python3-grib \
	python3-pip \
	libgdal-dev \
	aria2
	
	
COPY ./opengrads-2.2.1.tar.gz /grads/

RUN cd /grads/ && tar -xf opengrads-2.2.1.tar.gz \
	&& mv opengrads-2.2.1.oga.1/Contents /opt/opengrads \
	&& rm -rf opengrads-2.2.1*

RUN chmod 777 /usr/local/bin/start*

# Legacy for Jupyter Notebook Server, see: [#1205](https://github.com/jupyter/docker-stacks/issues/1205)
RUN sed -re "s/c.ServerApp/c.NotebookApp/g" \
    /etc/jupyter/jupyter_server_config.py > /etc/jupyter/jupyter_notebook_config.py && \
    fix-permissions /etc/jupyter/

RUN sudo -H apt update && apt -y upgrade && \
	sudo -H pip3 install \
	rasterio \
	geopandas\
	pygeos \
	sentinelsat \
	sentinelhub \
	matplotlib \
	grass \
	grass-session \
	scipy

RUN conda install -y -c conda-forge \
	gdal \
	rasterio \
	imagemagick \
	postgis \
	pygeos \
	sentinelsat \
	matplotlib \
	geopandas \
	sentinelhub \
	scipy

RUN git clone https://github.com/ykatsu111/jupyter-grads-kernel && \
    sudo -H pip install --user git+https://github.com/ykatsu111/jupyter-grads-kernel && \
	cd jupyter-grads-kernel && \
	jupyter kernelspec install --user grads_spec && \
	cd .. && rm -rf jupyter-grads-kernel

RUN wget https://step.esa.int/thirdparties/sen2cor/2.10.0/Sen2Cor-02.10.01-Linux64.run && \
	sudo -H bash Sen2Cor-02.10.01-Linux64.run --target /usr/bin/sen2cor && \
	rm -rf Sen2Cor-02.10.01-Linux64.run && \
	echo "source /usr/bin/sen2cor/L2A_Bashrc" >> ~/.bashrc
	
	
RUN git clone https://github.com/smfm-project/sen2mosaic.git && \
	mv sen2mosaic /usr/bin/ && \
	cd /usr/bin/sen2mosaic && \
	python3 setup.py install && \
	echo "alias s2m='_s2m() { python3 /usr/bin/sen2mosaic/cli/\"\$1\".py \$(shift; echo \"\$@\") ;}; _s2m'" >> ~/.bashrc	
	
RUN conda update --all --quiet --yes && \
    conda clean --all -f -y 

RUN fix-permissions "/home/${NB_USER}"

# Switch back to jovyan to avoid accidental container runs as root
USER ${NB_UID}

RUN echo "source /usr/bin/sen2cor/L2A_Bashrc" >> ~/.bashrc && \
	echo "alias s2m='_s2m() { python3 /usr/bin/sen2mosaic/cli/\"\$1\".py \$(shift; echo \"\$@\") ;}; _s2m'" >> ~/.bashrc	

WORKDIR "${HOME}"