# syntax=docker/dockerfile:1
# =============================================================================
# gs_env — môi trường nghiên cứu 3D Gaussian Splatting
#   Stage 1 (colmap-builder): build COLMAP 4.x có CUDA (đã tích hợp GLOMAP)
#   Stage 2 (final): CUDA devel + Miniforge + PyTorch + gsplat (build từ source)
#                    + splat-transform (Node) + tool dữ liệu (open3d, rosbags...)
# Các ARG được truyền từ file .env qua docker-compose.yml (xem .env.example).
# =============================================================================

ARG CUDA_VERSION=12.8.1
ARG UBUNTU_VERSION=24.04

# -----------------------------------------------------------------------------
# Stage 1: build COLMAP (theo Dockerfile chính thức của COLMAP, Ubuntu 24.04)
# -----------------------------------------------------------------------------
FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION} AS colmap-builder

ARG COLMAP_VERSION=4.2.1
ARG CUDA_ARCH=86
ARG MAX_JOBS=8
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
        git ca-certificates ccache cmake ninja-build build-essential \
        libboost-program-options-dev libboost-graph-dev libboost-system-dev \
        libeigen3-dev libopenimageio-dev openimageio-tools libmetis-dev \
        libgoogle-glog-dev libgtest-dev libgmock-dev libsqlite3-dev libglew-dev \
        qt6-base-dev libqt6opengl6-dev libqt6openglwidgets6 qt6-svg-dev \
        libcgal-dev libceres-dev libsuitesparse-dev \
        libcurl4-openssl-dev libssl-dev libmkl-full-dev \
    && rm -rf /var/lib/apt/lists/* \
    # Fix lỗi CMake config của openimageio trên Ubuntu (theo docs COLMAP)
    && mkdir -p /usr/include/opencv4

RUN git clone --depth 1 --branch ${COLMAP_VERSION} https://github.com/colmap/colmap.git /colmap \
    && mkdir -p /colmap/build && cd /colmap/build \
    && cmake .. -GNinja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCH}" \
        -DCMAKE_INSTALL_PREFIX=/colmap-install \
        -DBLA_VENDOR=Intel10_64lp \
    && ninja -j"${MAX_JOBS}" install

# -----------------------------------------------------------------------------
# Stage 2: môi trường làm việc
# cudnn-devel: có nvcc để build CUDA extension + cuDNN cho ONNX Runtime
# (COLMAP dùng ONNX cho ALIKED/LightGlue)
# -----------------------------------------------------------------------------
FROM nvidia/cuda:${CUDA_VERSION}-cudnn-devel-ubuntu${UBUNTU_VERSION} AS final

ARG CUDA_ARCH=86
ARG TORCH_CUDA_ARCH_LIST=8.6
ARG MAX_JOBS=8
ARG PYTHON_VERSION=3.10
ARG TORCH_CUDA=cu128
ARG TORCH_VERSION=2.9.1
ARG TORCHVISION_VERSION=0.24.1
ARG GSPLAT_REF=main
ARG NODE_MAJOR=22
ARG SPLAT_TRANSFORM_VERSION=3.10.3
ARG TZ=Asia/Ho_Chi_Minh

LABEL org.opencontainers.image.title="gs_env" \
      org.opencontainers.image.description="3D Gaussian Splatting research environment (gsplat + COLMAP + splat-transform)"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=${TZ} \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    NVIDIA_DRIVER_CAPABILITIES=all \
    QT_XCB_GL_INTEGRATION=xcb_egl \
    # Kiến trúc GPU dùng khi build mọi CUDA extension (torch, fused-ssim, ...)
    TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST}" \
    CUDA_ARCHITECTURES="${CUDA_ARCH}" \
    MAX_JOBS=${MAX_JOBS} \
    CONDA_DIR=/opt/conda

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# --- 2.1 Tool hệ thống, X11/OpenGL/Vulkan, ffmpeg, zsh ----------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        tzdata ca-certificates curl wget gnupg git git-lfs unzip zip rsync \
        build-essential cmake ninja-build pkg-config ccache gdb \
        zsh zsh-autosuggestions zsh-syntax-highlighting \
        tmux htop nano vim less file tree jq \
        openssh-client iputils-ping net-tools \
        ffmpeg \
        xauth x11-apps mesa-utils \
        libgl1 libegl1 libglx0 libglvnd0 libopengl0 libglu1-mesa \
        libvulkan1 vulkan-tools \
        libxkbcommon-x11-0 libxcb-cursor0 libxcb-icccm4 libxcb-image0 \
        libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 libxcb-shape0 \
        libxcb-xfixes0 libxcb-xinerama0 libxcb-xkb1 libsm6 libxext6 libxrender1 \
    && ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone \
    && git lfs install --system \
    && chsh -s /usr/bin/zsh root \
    && rm -rf /var/lib/apt/lists/*

# --- 2.2 Thư viện runtime của COLMAP + copy binary từ stage 1 ---------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        libboost-program-options1.83.0 libomp5 libgomp1 libmetis5 libceres4t64 \
        libopenimageio2.4t64 libglew2.2 libgoogle-glog0v6t64 libsqlite3-0 \
        libqt6core6 libqt6gui6 libqt6widgets6 libqt6openglwidgets6 libqt6svg6 \
        qt6-qpa-plugins libcurl4 libssl3t64 \
        libmkl-locale libmkl-intel-lp64 libmkl-intel-thread libmkl-core \
    && rm -rf /var/lib/apt/lists/*

COPY --from=colmap-builder /colmap-install/ /usr/local/
RUN ldconfig \
    # Kiểm tra thiếu thư viện (bỏ qua libcuda/libnvidia: driver được mount lúc chạy)
    && missing="$(ldd /usr/local/bin/colmap | grep 'not found' | grep -vE 'libcuda|libnvidia' || true)" \
    && if [ -n "$missing" ]; then echo "COLMAP thiếu thư viện:"; echo "$missing"; exit 1; fi

# --- 2.3 Node.js + splat-transform (chuyển đổi .ply/.spz/.sog/.glb) ---------
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g @playcanvas/splat-transform@${SPLAT_TRANSFORM_VERSION} \
    && npm cache clean --force \
    && rm -rf /var/lib/apt/lists/*

# --- 2.4 Miniforge (conda-forge, không dính điều khoản kênh Anaconda) --------
RUN curl -fsSL -o /tmp/miniforge.sh \
        https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh \
    && bash /tmp/miniforge.sh -b -p ${CONDA_DIR} \
    && rm /tmp/miniforge.sh \
    && ${CONDA_DIR}/bin/conda config --system --set changeps1 false \
    && ${CONDA_DIR}/bin/conda create -y -n gs python=${PYTHON_VERSION} pip \
    && ${CONDA_DIR}/bin/conda clean -afy

# Env "gs" là mặc định cho cả shell tương tác lẫn docker exec
ENV PATH=/opt/gs-scripts:${CONDA_DIR}/envs/gs/bin:${CONDA_DIR}/bin:${PATH}

# --- 2.5 PyTorch + file constraints (chống pip tự đổi bản torch) ------------
RUN pip install --no-cache-dir \
        torch==${TORCH_VERSION} torchvision==${TORCHVISION_VERSION} \
        --index-url https://download.pytorch.org/whl/${TORCH_CUDA} \
    && printf 'torch==%s\ntorchvision==%s\nnumpy>=2,<3\n' \
        "${TORCH_VERSION}" "${TORCHVISION_VERSION}" > /opt/constraints.txt \
    && python -c "import torch; print('torch', torch.__version__, 'cuda', torch.version.cuda)"

# --- 2.6 gsplat từ source (nhánh main có LiDAR rasterization, 3DGUT, HiGS) ---
# Cài editable: sửa code Python trong /opt/gsplat có hiệu lực ngay
RUN pip install --no-cache-dir -c /opt/constraints.txt \
        setuptools wheel ninja numpy jaxtyping "rich>=12" nvtx scipy \
    && git clone --recursive https://github.com/nerfstudio-project/gsplat.git /opt/gsplat \
    && cd /opt/gsplat && git checkout ${GSPLAT_REF} && git submodule update --init --recursive \
    && pip install --no-cache-dir --no-build-isolation -c /opt/constraints.txt -e ".[lidar]" \
    && find /opt/gsplat/gsplat -name "*.so" -print -quit | grep -q . \
    && python -c "import gsplat; print('gsplat', gsplat.__version__)"

# --- 2.7 Dependencies của gsplat/examples (simple_trainer.py, viewer) --------
# Tách 2 nhóm: package thuần Python cài bình thường; CUDA extension cài
# --no-build-isolation để build với torch đã có (không tải torch khác)
RUN cd /opt/gsplat/examples \
    && grep -vE '^\s*(torch|torchvision)\s*==' requirements.txt \
       | grep -vE 'fused-ssim|fused-bilagrid|ppisp' > /tmp/req_py.txt \
    && grep -E 'fused-ssim|fused-bilagrid|ppisp' requirements.txt > /tmp/req_cuda.txt \
    && pip install --no-cache-dir -c /opt/constraints.txt -r /tmp/req_py.txt \
    && pip install --no-cache-dir --no-build-isolation -c /opt/constraints.txt -r /tmp/req_cuda.txt \
    && rm /tmp/req_py.txt /tmp/req_cuda.txt \
    # find_spec: kiểm tra module có tồn tại mà không chạy code cần GPU lúc build
    && python -c "import importlib.util as u; m=['fused_ssim_cuda','fused_bilagrid_cuda','ppisp_cuda','pycolmap','viser','nerfview']; miss=[x for x in m if u.find_spec(x) is None]; assert not miss, miss; print('examples deps OK')"

# --- 2.8 Tool dữ liệu: point cloud, mesh, rosbag (đọc .bag không cần ROS) ----
RUN pip install --no-cache-dir -c /opt/constraints.txt \
        plyfile open3d trimesh laspy rosbags \
        ipython gdown huggingface_hub \
    && python -c "import importlib.util as u; m=['open3d','rosbags','plyfile','trimesh','laspy']; miss=[x for x in m if u.find_spec(x) is None]; assert not miss, miss; print('data tools OK')"

# --- 2.9 Cấu hình shell + script tiện ích ------------------------------------
COPY config/zshrc /root/.zshrc
COPY scripts/ /opt/gs-scripts/
RUN chmod +x /opt/gs-scripts/* && mkdir -p /root/ws

WORKDIR /root
CMD ["zsh"]
