# Docker — Cài đặt trên Ubuntu

Cài **Docker Engine**, **Docker Compose plugin**, **NVIDIA Container Toolkit** và các gói liên quan trên host Ubuntu.

Sau khi cài xong → vận hành container: [docker-ops.md](docker-ops.md) · quy trình dev: [dev-setup.md](dev-setup.md).

**Liên quan:** [README](../README.md) · [Vận hành container](docker-ops.md) · [Setup dev](dev-setup.md)

---

## Mục lục

- [Yêu cầu](#yêu-cầu)
- [Cài nhanh (khuyến nghị)](#cài-nhanh-khuyến-nghị)
- [Cài thủ công](#cài-thủ-công)
- [NVIDIA Container Toolkit](#nvidia-container-toolkit)
- [Sau khi cài](#sau-khi-cài)
- [Kiểm tra](#kiểm-tra)
- [Xử lý sự cố cài đặt](#xử-lý-sự-cố-cài-đặt)
- [Tiếp theo](#tiếp-theo)

---

## Yêu cầu

| Thành phần | Ghi chú |
|------------|---------|
| Ubuntu 20.04+ | Script và repo hướng dẫn theo Ubuntu |
| NVIDIA GPU + driver | Cần cho RViz/simulation trong container |
| Quyền `sudo` | Cài gói hệ thống |
| Mạng | Tải repo Docker / NVIDIA |

Driver NVIDIA cài **trên host** (không nằm trong script). Kiểm tra: `nvidia-smi`.

---

## Cài nhanh (khuyến nghị)

Từ thư mục gốc repo (sau khi clone):

```sh
sudo ./setup_docker.sh
```

Script [`setup_docker.sh`](../setup_docker.sh) tự động:

| Bước | Nội dung |
|------|----------|
| Docker Engine | `docker-ce`, CLI, `containerd`, Buildx |
| Compose | Plugin `docker-compose-plugin` (`docker compose`) |
| X11 | `x11-xserver-utils` — lệnh `xhost` cho RViz |
| NVIDIA | [Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) + cấu hình runtime Docker |
| Post-install | Thêm user hiện tại vào group `docker`, bật service |

Script **idempotent**: chạy lại an toàn nếu Docker/NVIDIA đã cài.

### Tuỳ chọn môi trường

```sh
# Bỏ qua NVIDIA Toolkit (máy không GPU / chỉ cần Docker)
sudo INSTALL_NVIDIA=0 ./setup_docker.sh

# Chạy thử container GPU sau khi cài (kéo image cuda, cần mạng)
sudo GPU_TEST=1 ./setup_docker.sh
```

Sau khi chạy: **đăng xuất và đăng nhập lại** (hoặc `newgrp docker`), rồi làm theo [dev-setup.md — Bước 3](dev-setup.md#bước-3--docker--container).

---

## Cài thủ công

Nguồn chính thức: [Docker Engine trên Ubuntu](https://docs.docker.com/engine/install/ubuntu/) · [Post-install](https://docs.docker.com/engine/install/linux-postinstall/)

### Docker Engine + Compose plugin

```sh
# Gỡ bản cũ (nếu có)
sudo apt-get remove docker docker-engine docker.io containerd runc

sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

docker --version
docker compose version
```

### xhost (RViz trên host)

```sh
sudo apt install -y x11-xserver-utils
```

---

## NVIDIA Container Toolkit

Bắt buộc cho workload GPU trong container (RViz, CUDA).

Nguồn: [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)

```sh
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /etc/apt/keyrings/nvidia-container-toolkit.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update
sudo apt install -y nvidia-container-toolkit

sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

*(Các bước trên được gộp trong `setup_docker.sh` khi `INSTALL_NVIDIA=1`.)*

---

## Sau khi cài

Thêm user vào group `docker` để không cần `sudo` mỗi lệnh:

```sh
sudo usermod -aG docker $USER
```

**Đăng xuất và đăng nhập lại** (hoặc `newgrp docker` trong terminal hiện tại).

Bật Docker khi khởi động (thường đã bật sau `setup_docker.sh`):

```sh
sudo systemctl enable docker
sudo systemctl start docker
```

---

## Kiểm tra

```sh
docker --version
docker compose version
docker ps                    # không lỗi permission
```

GPU trong container:

```sh
docker run --rm --gpus all nvidia/cuda:11.0.3-base-ubuntu20.04 nvidia-smi
```

Hoặc chạy `sudo GPU_TEST=1 ./setup_docker.sh` để script tự kiểm tra.

---

## Xử lý sự cố cài đặt

| Triệu chứng | Cách xử lý |
|-------------|------------|
| `permission denied` khi chạy `docker` | `groups` có `docker`; đăng nhập lại sau `usermod` |
| `docker compose`: command not found | Cài `docker-compose-plugin`, không dùng `docker-compose` standalone cũ |
| `nvidia-smi` không có trên host | Cài driver NVIDIA trước khi test GPU trong container |
| GPU không thấy trong container | Chạy lại `nvidia-ctk runtime configure --runtime=docker`; `sudo systemctl restart docker` |
| Lỗi GPG / apt key | Xóa file key cũ trong `/etc/apt/keyrings/`, chạy lại script |
| Ubuntu không phải 20.04+ | Script cảnh báo; kiểm tra [tài liệu Docker](https://docs.docker.com/engine/install/) cho bản distro của bạn |

Lỗi khi **chạy container** (RViz, pull image, compose): [docker-ops.md — Xử lý sự cố](docker-ops.md#xử-lý-sự-cố).

---

## Tiếp theo

| Bước | Tài liệu |
|------|----------|
| Image stable, compose, VS Code, copy file | [docker-ops.md](docker-ops.md) |
| Chạy simulation RViz | [simulation.md](simulation.md) |
