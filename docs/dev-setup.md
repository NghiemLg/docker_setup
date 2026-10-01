# Setup môi trường dev

Quy trình setup cho developer chạy simulation hoặc cài đặt docker image.

**Liên quan:** [README](../README.md) · [Docker](docker.md) · [Simulation](simulation.md)

---

## Trước khi bắt đầu

| Yêu cầu | Ghi chú |
|---------|---------|
| Ubuntu 20.04+ host | NVIDIA GPU + driver |
| Docker + NVIDIA toolkit | `sudo ./setup_docker.sh` — [docker.md](docker.md) |

---

## Quy trình setup (theo thứ tự)

### Bước 1 — Clone repo

```sh
git clone https://github.com/NghiemLg/docker_setup.git
cd docker_setup
```

### Bước 2 — *(Tùy chọn)* Terminal zsh trên host

Container mặc định dùng **zsh**. Nếu muốn terminal **host** đồng bộ (Oh My Zsh, gợi ý lệnh, theme giống trong container), chạy script có sẵn:

```sh
sudo TYPE_SHELL=zsh ./setup_zsh.sh
```

| | |
|---|---|
| **Khi nào dùng** | Dev làm việc nhiều trên host (ngoài container), muốn shell thống nhất |
| **Bỏ qua** | Chỉ dùng bash host + `docker exec` vào zsh container là đủ |
| **Yêu cầu** | Quyền root (`sudo`) |
| **Sau khi chạy** | Mở terminal mới hoặc đăng nhập lại |

Script [`setup_zsh.sh`](../setup_zsh.sh) cài:

- `zsh` + đặt mặc định khi `TYPE_SHELL=zsh`
- [Oh My Zsh](https://ohmyzsh.sh/) — theme `agnoster`
- Plugin: `git`, `zsh-autosuggestions`, `zsh-syntax-highlighting`
- `fonts-powerline`, `language-pack-en`

Chỉ cài gói zsh, **không** đổi shell mặc định (giữ bash):

```sh
sudo ./setup_zsh.sh
```

### Bước 3 — Docker & container

**Cài Docker trên host** (máy mới):

```sh
sudo ./setup_docker.sh
# Đăng xuất/đăng nhập lại hoặc: newgrp docker
```

Script [`setup_docker.sh`](../setup_docker.sh) cài Docker Engine, Compose plugin, NVIDIA Container Toolkit, `xhost`. Chi tiết: [docker.md](docker.md).

**Khởi động container** (sau khi Docker đã cài):

```sh
cd docker
docker compose pull
docker compose up -d
xhost +local:docker
```

Vận hành compose, image stable, troubleshooting: [docker-ops.md](docker-ops.md).

### Bước 4 — Vào container

```sh
docker exec -it vf_ap /usr/bin/zsh
```

### Bước 5 — Git & SSH (trong container)

```sh
git config --global user.name "Tên của bạn"
git config --global user.email "you@gmail.com"

ssh-keygen -t ed25519 -C "you@gmail.com"
cat ~/.ssh/id_ed25519.pub   # GitHub → Settings → SSH Keys
ssh -T git@github.com
```
