# ================================================================
# AI Environment
# Base: Ubuntu 20.04 + CUDA 12.2 runtime (compatible with driver 535)
# Extra: nvcc 11.8 (toolkit) installed via conda for build compat
# ================================================================
FROM nvidia/cuda:12.2.0-devel-ubuntu20.04

LABEL description="Ubuntu 20.04, CUDA 12.2 (driver 535), nvcc 11.8, Miniconda, full permissions"

USER root
WORKDIR /root

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# ----------------------------------------------------------------
# System dependencies
# ----------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    git \
    build-essential \
    ca-certificates \
    bzip2 \
    vim \
    unzip \
    software-properties-common \
    zsh \
    && rm -rf /var/lib/apt/lists/*

# Set zsh as the default shell for root
RUN chsh -s $(which zsh) root

# ----------------------------------------------------------------
# Install Miniconda
# ----------------------------------------------------------------
ENV CONDA_DIR=/opt/miniconda3
RUN wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh \
    && bash /tmp/miniconda.sh -b -p $CONDA_DIR \
    && rm /tmp/miniconda.sh

ENV PATH=$CONDA_DIR/bin:$PATH

RUN conda init zsh \
    && conda config --set always_yes true \
    && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main \
    && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r \
    && conda update -n base -c defaults conda

# ----------------------------------------------------------------
# Install nvcc 11.8 (CUDA compiler) via conda, on top of the
# CUDA 12.2 runtime already provided by the base image (driver 535+)
# ----------------------------------------------------------------
RUN conda install -c "nvidia/label/cuda-11.8.0" cuda-nvcc cuda-cudart-dev -y \
    && conda clean -afy

ENV CUDA_HOME=$CONDA_DIR

# NOTE: $CONDA_DIR/lib must NOT go on LD_LIBRARY_PATH.
# Conda ships compat aliases (libffi.so.7 -> libffi.so.8, libtinfo.so.6 ->
# libtinfow) that shadow the system libraries for *every* process, which
# breaks apt: /usr/lib/apt/methods/http -> libp11-kit -> "undefined symbol:
# ffi_type_pointer, version LIBFFI_BASE_7.0". Conda binaries find their own
# libs through RPATH ($ORIGIN/../lib), so they do not need the variable.
# Expose only the conda CUDA 11.8 runtime via ldconfig, from a directory
# that holds nothing else, so no system SONAME can ever be shadowed.
RUN mkdir -p /opt/conda-cuda-libs \
    && ln -sf $CONDA_DIR/lib/libcudart.so* /opt/conda-cuda-libs/ \
    && echo "/opt/conda-cuda-libs" > /etc/ld.so.conf.d/zzz-conda-cuda.conf \
    && ldconfig

# ----------------------------------------------------------------
# Default conda env
# ----------------------------------------------------------------
RUN conda create -n ai python=3.8 -y
ENV PATH=$CONDA_DIR/envs/ai/bin:$PATH

# Shell config. This replaces the ~/.zshrc written by `conda init zsh` above —
# ./zshrc carries that same conda block plus `conda activate ai`, and guards
# every optional integration (oh-my-zsh, ROS, colcon) so a missing tool does
# not throw errors on shell startup.
COPY zshrc /root/.zshrc

# ----------------------------------------------------------------
# Full permissions (root user + world-writable dirs)
# ----------------------------------------------------------------
RUN chmod -R 777 $CONDA_DIR \
    && chmod -R 777 /root \
    && umask 0000

# ----------------------------------------------------------------
# Sanity check at build time
# ----------------------------------------------------------------
# apt-get update is part of the check on purpose: it is what regresses if a
# conda lib dir ever ends up back on LD_LIBRARY_PATH.
RUN nvcc --version && conda --version && python --version \
    && ldconfig -p | grep libcudart.so.11.0 \
    && apt-get update && rm -rf /var/lib/apt/lists/*

COPY setup_zsh.sh /tmp/setup_zsh.sh

RUN chmod +x /tmp/setup_zsh.sh && \
    TYPE_SHELL=zsh /tmp/setup_zsh.sh && \
    rm /tmp/setup_zsh.sh



WORKDIR /root
CMD ["/bin/zsh"]
