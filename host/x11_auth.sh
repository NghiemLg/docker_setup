#!/usr/bin/env bash
# =============================================================================
# Chạy TRÊN HOST: tạo cookie X11 cho container (GUI: COLMAP, glxgears, open3d).
# Cần chạy lại sau mỗi lần reboot/đăng nhập lại (vì /tmp bị xóa).
# `make up` và `make shell` đã tự gọi script này.
# =============================================================================
set -euo pipefail

XDIR=/tmp/.gs-xauth
XAUTH="$XDIR/xauth"

if [[ -z "${DISPLAY:-}" ]]; then
  echo "[WARN] DISPLAY trống (SSH không -X?). Bỏ qua X11; vẫn dùng được viewer web qua cổng 8080."
  exit 0
fi
command -v xauth >/dev/null || { echo "[ERR] Thiếu xauth: sudo apt install xauth"; exit 1; }

# Docker có thể đã tạo sẵn thư mục này bằng root (container khởi động lúc boot)
mkdir -p "$XDIR" 2>/dev/null || true
if [[ ! -w "$XDIR" ]]; then
  sudo chown "$(id -u):$(id -g)" "$XDIR"
fi

: > "$XAUTH"
# 'ffff' = FamilyWild: cookie dùng được với mọi hostname (cần cho network_mode host)
xauth nlist "$DISPLAY" | sed -e 's/^..../ffff/' | xauth -f "$XAUTH" nmerge -
chmod 644 "$XAUTH"
echo "[OK] X11 cookie: $XAUTH (DISPLAY=$DISPLAY)"
