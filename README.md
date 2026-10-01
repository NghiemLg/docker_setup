# dockedr setup

**Tài liệu chi tiết nằm trong [`docs/`](docs/).** README này chỉ là luồng theo mục đích; bấm link để xem hướng dẫn đầy đủ.

---

## Bạn muốn làm gì?

| Mục đích | Tài liệu |
|----------|----------|
| **Chạy simulation ngay** (đã có Docker) | [Hướng dẫn simulation bên dưới](#chạy-simulation) → chi tiết: [docs/simulation.md](docs/simulation.md) |
| **Cài Docker + NVIDIA trên máy mới** | `sudo ./setup_docker.sh` — [docs/docker.md](docs/docker.md) |
| **Vận hành container** (compose, copy file, dọn dẹp…) | [docs/docker-ops.md](docs/docker-ops.md) |
| **Setup môi trường dev** (máy mới, lần đầu vào team) | [docs/dev-setup.md](docs/dev-setup.md) |

---

## Tài liệu chi tiết (`docs/`)

| Tài liệu | Nội dung |
|----------|----------|
| [docs/docker.md](docs/docker.md) | Cài Docker Engine, Compose plugin, NVIDIA toolkit (`setup_docker.sh`) |
| [docs/simulation.md](docs/simulation.md) | Chạy RViz simulation sau `docker compose up` |
| [docs/dev-setup.md](docs/dev-setup.md) | Setup môi trường dev (quy trình tối ưu, tùy chọn zsh) |

## Cấu trúc repo

| Đường dẫn | Nội dung |
|-----------|----------|
| [`docs/`](docs/) | Tài liệu chi tiết (bảng trên) |
| [`docker/`](docker/) | `docker-compose.yml`, Dockerfile, build script |
| [`repos_type/`](repos_type/) | Manifest `*.repos` (simulation, xe) |
| [`setup_zsh.sh`](setup_zsh.sh) | *(Tùy chọn)* Cài zsh + Oh My Zsh trên host — xem [dev-setup.md](docs/dev-setup.md#bước-2--tùy-chọn-terminal-zsh-trên-host) |
| [`setup_docker.sh`](setup_docker.sh) | Cài Docker + Compose + NVIDIA toolkit trên host — xem [docker.md](docs/docker.md) |

