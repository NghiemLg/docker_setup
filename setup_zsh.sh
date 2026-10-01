#!/usr/bin/env bash
set -euo pipefail

readonly OHMYZSH_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
readonly AUTOSUGGESTIONS_REPO="https://github.com/zsh-users/zsh-autosuggestions"
readonly SYNTAX_HIGHLIGHTING_REPO="https://github.com/zsh-users/zsh-syntax-highlighting.git"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Vui lòng chạy script với quyền root: sudo ./setup_zsh.sh"
    exit 1
fi

# Người dùng thực tế (khi chạy sudo), không phải root
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    TARGET_USER="${SUDO_USER}"
    TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
else
    TARGET_USER="${USER:-root}"
    TARGET_HOME="${HOME:-/root}"
fi

if [[ -z "${TARGET_HOME}" || ! -d "${TARGET_HOME}" ]]; then
    echo "Không xác định được thư mục home cho user '${TARGET_USER}'."
    exit 1
fi

# TYPE_SHELL: zsh = cấu hình đầy đủ; mặc định chỉ cài gói zsh, giữ bash
TYPE_SHELL="${TYPE_SHELL:-bash}"
echo "User: ${TARGET_USER} (${TARGET_HOME})"
echo "Chế độ shell: ${TYPE_SHELL}"

run_as_user() {
    if [[ "${TARGET_USER}" == "root" ]]; then
        HOME="${TARGET_HOME}" "$@"
    else
        sudo -u "${TARGET_USER}" HOME="${TARGET_HOME}" "$@"
    fi
}

clone_plugin_if_missing() {
    local repo="$1"
    local dest="$2"
    if [[ -d "${dest}/.git" ]]; then
        echo "  Đã có: ${dest}"
    else
        run_as_user git clone --depth 1 "${repo}" "${dest}"
    fi
}

export DEBIAN_FRONTEND=noninteractive

echo "Cập nhật danh sách gói phần mềm..."
apt-get update -qq

echo "Cài đặt zsh, fonts-powerline, language-pack-en..."
apt-get install -y --no-install-recommends zsh fonts-powerline language-pack-en

ZSH_PATH="$(command -v zsh)"

if [[ "${TYPE_SHELL}" == "zsh" ]]; then
    echo "Đặt zsh làm shell mặc định cho ${TARGET_USER}..."
    chsh -s "${ZSH_PATH}" "${TARGET_USER}"

    ZSH_CUSTOM="${TARGET_HOME}/.oh-my-zsh/custom"
    PLUGINS_DIR="${ZSH_CUSTOM}/plugins"

    if [[ ! -d "${TARGET_HOME}/.oh-my-zsh" ]]; then
        echo "Cài đặt Oh My Zsh..."
        run_as_user env RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
            sh -c "$(curl -fsSL "${OHMYZSH_INSTALL_URL}")"
    else
        echo "Oh My Zsh đã được cài đặt, bỏ qua."
    fi

    echo "Cài đặt plugin zsh..."
    clone_plugin_if_missing "${AUTOSUGGESTIONS_REPO}" "${PLUGINS_DIR}/zsh-autosuggestions"
    clone_plugin_if_missing "${SYNTAX_HIGHLIGHTING_REPO}" "${PLUGINS_DIR}/zsh-syntax-highlighting"

    ZSHRC="${TARGET_HOME}/.zshrc"
    if [[ -f "${ZSHRC}" ]]; then
        echo "Cấu hình ~/.zshrc (theme agnoster, plugins)..."
        sed -i 's/^ZSH_THEME=.*/ZSH_THEME="agnoster"/' "${ZSHRC}"
        if grep -q '^plugins=' "${ZSHRC}"; then
            sed -i '/^plugins=/c\plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' "${ZSHRC}"
        else
            echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> "${ZSHRC}"
        fi
        chown "${TARGET_USER}:${TARGET_USER}" "${ZSHRC}" 2>/dev/null || true
    else
        echo "Cảnh báo: không tìm thấy ${ZSHRC} — bỏ qua cấu hình theme/plugin."
    fi
else
    echo "TYPE_SHELL='${TYPE_SHELL}': chỉ cài gói zsh, giữ bash làm shell mặc định."
fi

echo "Cài đặt locale en_US.UTF-8..."
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 2>/dev/null || update-locale || true

echo ""
echo "Hoàn tất."
if [[ "${TYPE_SHELL}" == "zsh" ]]; then
    echo "Mở terminal mới hoặc đăng nhập lại để dùng zsh."
    echo "Kiểm tra: su - ${TARGET_USER} -c 'echo \$SHELL'  # kỳ vọng: ${ZSH_PATH}"
fi
