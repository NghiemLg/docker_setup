#!/usr/bin/env bash
set -euo pipefail

readonly DOCKER_GPG_URL="https://download.docker.com/linux/ubuntu/gpg"
readonly NVIDIA_GPG_URL="https://nvidia.github.io/libnvidia-container/gpgkey"
readonly NVIDIA_LIST_URL="https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list"

# INSTALL_NVIDIA=1 (mặc định): cài NVIDIA Container Toolkit
# GPU_TEST=1: chạy container thử GPU sau khi cài (cần mạng, kéo image cuda)
INSTALL_NVIDIA="${INSTALL_NVIDIA:-1}"
GPU_TEST="${GPU_TEST:-0}"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Vui lòng chạy script với quyền root: sudo ./setup_docker.sh"
    exit 1
fi

if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    TARGET_USER="${SUDO_USER}"
else
    TARGET_USER="${USER:-root}"
fi

if ! id "${TARGET_USER}" &>/dev/null; then
    echo "Không tìm thấy user '${TARGET_USER}'."
    exit 1
fi

if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
    echo "Cảnh báo: script được viết cho Ubuntu. Bản phân phối khác có thể không tương thích."
fi

export DEBIAN_FRONTEND=noninteractive

log() { echo "==> $*"; }

user_in_docker_group() {
    id -nG "${TARGET_USER}" 2>/dev/null | grep -qw docker
}

install_docker_engine() {
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        log "Docker Engine và Compose plugin đã có — bỏ qua cài đặt."
        return 0
    fi

    log "Gỡ các gói Docker cũ (nếu có)..."
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    log "Cài dependency apt..."
    apt-get update -qq
    apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg lsb-release

    log "Thêm Docker APT repository..."
    install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        curl -fsSL "${DOCKER_GPG_URL}" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
    fi

    if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
            > /etc/apt/sources.list.d/docker.list
    fi

    log "Cài Docker Engine + Compose plugin..."
    apt-get update -qq
    apt-get install -y --no-install-recommends \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_x11_utils() {
    log "Cài x11-xserver-utils (lệnh xhost cho RViz)..."
    apt-get install -y --no-install-recommends x11-xserver-utils
}

install_nvidia_toolkit() {
    if [[ "${INSTALL_NVIDIA}" != "1" ]]; then
        log "INSTALL_NVIDIA=${INSTALL_NVIDIA} — bỏ qua NVIDIA Container Toolkit."
        return 0
    fi

    if command -v nvidia-ctk &>/dev/null; then
        log "NVIDIA Container Toolkit đã có — chỉ cấu hình lại runtime Docker."
    else
        if ! command -v nvidia-smi &>/dev/null; then
            echo "Cảnh báo: không thấy nvidia-smi — driver NVIDIA có thể chưa cài. Toolkit vẫn được cài nhưng GPU test có thể thất bại."
        fi

        log "Thêm NVIDIA Container Toolkit repository..."
        install -m 0755 -d /etc/apt/keyrings
        if [[ ! -f /etc/apt/keyrings/nvidia-container-toolkit.gpg ]]; then
            curl -fsSL "${NVIDIA_GPG_URL}" | gpg --dearmor -o /etc/apt/keyrings/nvidia-container-toolkit.gpg
            chmod a+r /etc/apt/keyrings/nvidia-container-toolkit.gpg
        fi

        if [[ ! -f /etc/apt/sources.list.d/nvidia-container-toolkit.list ]]; then
            curl -s -L "${NVIDIA_LIST_URL}" \
                | sed 's#deb https://#deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit.gpg] https://#g' \
                > /etc/apt/sources.list.d/nvidia-container-toolkit.list
        fi

        log "Cài NVIDIA Container Toolkit..."
        apt-get update -qq
        apt-get install -y --no-install-recommends nvidia-container-toolkit
    fi

    log "Cấu hình Docker runtime cho NVIDIA..."
    nvidia-ctk runtime configure --runtime=docker
}

configure_docker_service() {
    log "Bật và khởi động Docker..."
    systemctl enable docker
    systemctl restart docker
}

add_user_to_docker_group() {
    if user_in_docker_group; then
        log "User ${TARGET_USER} đã trong group docker."
    else
        log "Thêm ${TARGET_USER} vào group docker..."
        usermod -aG docker "${TARGET_USER}"
        echo "Lưu ý: ${TARGET_USER} cần đăng xuất và đăng nhập lại (hoặc newgrp docker) để chạy docker không cần sudo."
    fi
}

verify_installation() {
    log "Kiểm tra phiên bản..."
    docker --version
    docker compose version

    if [[ "${INSTALL_NVIDIA}" == "1" && "${GPU_TEST}" == "1" ]]; then
        log "Chạy container thử GPU..."
        docker run --rm --gpus all nvidia/cuda:11.0.3-base-ubuntu20.04 nvidia-smi
    fi
}

echo "User: ${TARGET_USER}"
echo "INSTALL_NVIDIA=${INSTALL_NVIDIA}  GPU_TEST=${GPU_TEST}"
echo ""

install_docker_engine
install_x11_utils
install_nvidia_toolkit
configure_docker_service
add_user_to_docker_group
verify_installation

echo ""
echo "Hoàn tất cài Docker."
echo "Bước tiếp theo:"
echo "  1. Đăng xuất/đăng nhập lại (hoặc: newgrp docker)"
echo "  3. cd docker && docker compose pull && docker compose up -d"
echo "  4. xhost +local:docker"
echo "Chi tiết: docs/dev-setup.md · docs/docker-ops.md"
