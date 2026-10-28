#!/usr/bin/env bash
# =============================================================================
# Chạy TRÊN HOST (một lần, trước khi build):
#   - kiểm tra docker / docker compose / driver NVIDIA / nvidia-container-toolkit
#   - dò compute capability + phiên bản CUDA mà driver hỗ trợ
#   - sinh file .env phù hợp (không ghi đè nếu đã có, trừ khi --force)
#   - tạo thư mục workspace + file xauth cho GUI
# Dùng: ./host/setup_host.sh [--force]
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

ok()   { printf '\033[32m[OK]\033[0m   %s\n' "$*"; }
warn() { printf '\033[33m[WARN]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[ERR]\033[0m  %s\n' "$*"; exit 1; }
# ver_ge A B  -> true nếu A >= B (so sánh kiểu version)
ver_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | sed -n 1p)" == "$2" ]]; }

# --- 1. Docker ---------------------------------------------------------------
command -v docker >/dev/null || die "Chưa cài docker."
docker compose version >/dev/null 2>&1 || die "Cần Docker Compose v2 (lệnh 'docker compose', không phải 'docker-compose')."
ok "$(docker compose version | sed -n 1p)"
if ! docker info >/dev/null 2>&1; then
  warn "User hiện tại không gọi được docker daemon. Thêm vào group: sudo usermod -aG docker \$USER (rồi logout/login)."
fi

# --- 2. Driver NVIDIA --------------------------------------------------------
command -v nvidia-smi >/dev/null || die "Không thấy nvidia-smi: chưa cài driver NVIDIA."
DRIVER="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | sed -n 1p | tr -d ' ')"
DRV_CUDA="$(nvidia-smi | grep -oP 'CUDA Version:\s*\K[0-9]+\.[0-9]+' | sed -n 1p || true)"
[[ -n "$DRV_CUDA" ]] || die "Không đọc được 'CUDA Version' từ nvidia-smi."
mapfile -t GPU_NAMES < <(nvidia-smi --query-gpu=name --format=csv,noheader)
mapfile -t CAPS < <(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | tr -d ' ' | sort -uV)
ok "GPU: ${GPU_NAMES[*]}"
ok "Driver $DRIVER, hỗ trợ tối đa CUDA $DRV_CUDA, compute capability: ${CAPS[*]}"

# --- 3. nvidia-container-toolkit ---------------------------------------------
if command -v nvidia-ctk >/dev/null || docker info 2>/dev/null | grep -i 'nvidia' >/dev/null; then
  ok "nvidia-container-toolkit đã có."
else
  warn "Chưa thấy nvidia-container-toolkit. Cài theo:"
  warn "  https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html"
  warn "  sau đó: sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker"
fi

# --- 4. Chọn CUDA toolkit cho container --------------------------------------
TORCH_CUDA_ARCH_LIST="$(IFS=';'; echo "${CAPS[*]}")"     # 8.6;8.9
CUDA_ARCH="${TORCH_CUDA_ARCH_LIST//./}"                   # 86;89
MAX_CAP="${CAPS[-1]}"
DISABLE_REQUIRE=false

if ver_ge "$DRV_CUDA" "12.8"; then
  CUDA_VERSION=12.8.1; TORCH_CUDA=cu128
elif ver_ge "$DRV_CUDA" "12.6"; then
  CUDA_VERSION=12.6.3; TORCH_CUDA=cu126
elif ver_ge "$DRV_CUDA" "12.0"; then
  CUDA_VERSION=12.6.3; TORCH_CUDA=cu126; DISABLE_REQUIRE=true
  warn "Driver chỉ hỗ trợ CUDA $DRV_CUDA (< 12.6). Sẽ chạy CUDA 12.6 nhờ minor-version compatibility"
  warn "(NVIDIA_DISABLE_REQUIRE=true). Khuyến nghị nâng driver >= 570 để tránh lỗi PTX/JIT."
else
  die "Driver quá cũ (CUDA $DRV_CUDA). Cần driver hỗ trợ CUDA >= 12.0, khuyến nghị >= 570."
fi

if ver_ge "$MAX_CAP" "10.0" && [[ "$TORCH_CUDA" != "cu128" ]]; then
  die "GPU Blackwell (compute $MAX_CAP) cần CUDA 12.8 -> nâng driver lên >= 570."
fi
if ! ver_ge "$MAX_CAP" "7.5"; then
  warn "GPU compute $MAX_CAP < 7.5: gsplat vẫn chạy nhưng LichtFeld Studio và một số repo mới sẽ không hỗ trợ."
fi

# --- 5. MAX_JOBS theo RAM (mỗi job nvcc ~2.5 GB) -----------------------------
MEM_GB="$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)"
NPROC="$(nproc)"
MAX_JOBS=$(( MEM_GB * 10 / 25 ))
(( MAX_JOBS > NPROC )) && MAX_JOBS=$NPROC
(( MAX_JOBS < 1 )) && MAX_JOBS=1
ok "RAM ${MEM_GB} GB, ${NPROC} CPU -> MAX_JOBS=$MAX_JOBS"

WS_DIR="${WS_DIR:-$HOME/gs_ws}"

# --- 6. Ghi .env -------------------------------------------------------------
if [[ -f "$ENV_FILE" && $FORCE -eq 0 ]]; then
  warn ".env đã tồn tại -> giữ nguyên (dùng --force để sinh lại). Giá trị đề xuất:"
  OUT=/dev/stdout
else
  OUT="$ENV_FILE"
fi
{
  echo "# Sinh tự động bởi host/setup_host.sh lúc $(date '+%F %T')"
  echo "# GPU: ${GPU_NAMES[*]} | driver $DRIVER (CUDA $DRV_CUDA)"
  echo "CUDA_VERSION=$CUDA_VERSION"
  echo "TORCH_CUDA=$TORCH_CUDA"
  echo "TORCH_VERSION=2.9.1"
  echo "TORCHVISION_VERSION=0.24.1"
  echo "CUDA_ARCH=$CUDA_ARCH"
  echo "TORCH_CUDA_ARCH_LIST=$TORCH_CUDA_ARCH_LIST"
  echo "COLMAP_VERSION=4.2.1"
  echo "GSPLAT_REF=main"
  echo "MAX_JOBS=$MAX_JOBS"
  echo "WS_DIR=$WS_DIR"
  echo "NVIDIA_DISABLE_REQUIRE=$DISABLE_REQUIRE"
} > "$OUT"
[[ "$OUT" == "$ENV_FILE" ]] && ok "Đã ghi $ENV_FILE"

# --- 7. Workspace + X11 ------------------------------------------------------
mkdir -p "$WS_DIR"/{scenes,results,datasets}
ok "Workspace: $WS_DIR (mount vào /root/ws)"
"$ROOT/host/x11_auth.sh" || warn "Chưa tạo được xauth (bình thường nếu đang SSH không có X)."

echo
echo "Tiếp theo:  make build   (lần đầu ~40-70 phút)  ->  make up  ->  make shell  ->  gs-verify"
