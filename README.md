# gs_env — Docker cho nghiên cứu 3D Gaussian Splatting

Một container chứa đủ pipeline **ảnh/video → pose (COLMAP) → train 3DGS (gsplat) → nén/xuất (splat-transform)**, chạy GPU, có GUI qua X11, không đụng tới môi trường ROS/Python trên host.

## 1. Cấu trúc thư mục

```
gs_env/
├── Dockerfile            # multi-stage: build COLMAP -> image làm việc
├── docker-compose.yml    # service gs_env (host network, GPU, X11, /dev)
├── .env.example          # phiên bản CUDA/torch, kiến trúc GPU, đường dẫn workspace
├── Makefile              # make setup | build | up | shell | verify | down
├── config/zshrc          # zsh tối giản, tự kích hoạt conda env "gs"
├── host/                 # chạy TRÊN HOST
│   ├── setup_host.sh     # dò driver + GPU, sinh .env, tạo workspace
│   └── x11_auth.sh       # tạo cookie X11 cho GUI
└── scripts/              # lệnh trong container (đã nằm trong PATH)
    ├── gs-verify             # kiểm tra toàn bộ môi trường
    ├── gs-video2img          # .mp4 -> images/*.jpg
    ├── gs-colmap             # images -> sparse/0/*.bin (+ images_2/4/8)
    ├── gs-train              # train gsplat -> .ply + metrics
    ├── gs-compress           # .ply -> .spz / .sog / .html
    ├── gs-download-sample    # dataset chuẩn (Tanks&Temples, Mip-NeRF 360)
    └── gs-install-nerfstudio # (tùy chọn) Nerfstudio trong env riêng
```

## 2. Có gì trong image

| Thành phần | Phiên bản | Dùng để |
|---|---|---|
| Ubuntu + CUDA toolkit (bộ công cụ CUDA) + cuDNN | 24.04 + 12.8.1 (hoặc 12.6.3) | nền; có `nvcc` để build CUDA extension |
| COLMAP (SfM — Structure-from-Motion, khôi phục cấu trúc từ chuyển động) | 4.2.1, có CUDA | ước lượng pose camera; có sẵn `global_mapper` (GLOMAP) |
| PyTorch | 2.9.1 | khớp đúng bản `gsplat/examples` đang pin |
| gsplat | nhánh `main`, build từ source, cài editable | rasterizer (bộ raster hóa) 3DGS; có LiDAR rasterization, 3DGUT, MCMC |
| gsplat examples deps | fused-ssim, fused-bilagrid, ppisp, viser, nerfview, pycolmap | `simple_trainer.py` + viewer web |
| splat-transform (Node 22) | 3.10.3 | đổi định dạng `.ply ↔ .spz/.sog/.glb/.splat` |
| Tool dữ liệu | open3d, plyfile, trimesh, laspy, rosbags | đọc/ghi `.ply/.pcd/.las`, đọc rosbag `.bag` **không cần cài ROS** |
| Hệ thống | ffmpeg, zsh, tmux, git-lfs, mesa-utils, vulkan-tools | tách frame, shell, test OpenGL |

Python nằm trong conda env `gs` (Miniforge, Python 3.10), là env mặc định cả khi `docker exec`.

## 3. Yêu cầu trên host

- Driver NVIDIA **≥ 570** (khuyến nghị; bắt buộc nếu GPU là RTX 50xx). Driver 535–565 vẫn chạy được, `setup_host.sh` sẽ tự chọn CUDA 12.6.
- Docker + **Docker Compose v2** (`docker compose`, có dấu cách).
- **nvidia-container-toolkit** (bộ công cụ cho container dùng GPU):
  ```bash
  sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker
  ```
- Ổ đĩa trống ~35 GB lúc build (image cuối ~20 GB), RAM ≥ 16 GB để compile.

## 4. Cài đặt

```bash
cd gs_env
make setup     # dò GPU/driver -> sinh .env (CUDA_ARCH, TORCH_CUDA_ARCH_LIST, MAX_JOBS...)
make build     # lần đầu ~40-70 phút (COLMAP và gsplat compile song song)
make up        # chạy container nền (restart: unless-stopped)
make shell     # vào zsh trong container
gs-verify      # phải ra "0 lỗi"
```

`gs-verify` kiểm tra thật: render 20k Gaussian + backward trên GPU, fused-ssim trên GPU, COLMAP có CUDA, OpenGL đi qua GPU NVIDIA.

Sau khi reboot host: chạy `make shell` (đã tự gọi `make x11` để làm mới cookie X11).

## 5. Workflow mẫu (kèm định dạng file từng bước)

Thư mục `/root/ws` trong container = `WS_DIR` trên host (mặc định `~/gs_ws`).

### 5.1. Test nhanh với dataset chuẩn (nên làm đầu tiên)

```bash
gs-download-sample tandt                               # ~650 MB, đã có COLMAP sẵn
gs-train /root/ws/datasets/tandt/truck -f 1            # mở http://localhost:8080 để xem lúc train
```

### 5.2. Dữ liệu của bạn: video → 3DGS

```bash
# (1) Video .mp4 -> ảnh .jpg (2 frame/giây)
gs-video2img /root/ws/raw/lab.mp4 /root/ws/scenes/lab 2
#     => scenes/lab/images/frame_00001.jpg ...

# (2) Ảnh -> pose camera + point cloud thưa
gs-colmap /root/ws/scenes/lab                 # mặc định: global mapper, camera OPENCV
#     => scenes/lab/database.db                 SQLite chứa keypoint + match
#        scenes/lab/sparse/0/cameras.bin        nội tham số (fx, fy, cx, cy, k1, k2, p1, p2)
#        scenes/lab/sparse/0/images.bin         pose world->camera (quaternion + translation)
#        scenes/lab/sparse/0/points3D.bin       điểm 3D -> khởi tạo tâm Gaussian
#        scenes/lab/images_2|4|8/*.png          ảnh thu nhỏ cho --data_factor

# (3) Train
gs-train /root/ws/scenes/lab -s mcmc -f 2
#     => results/lab_mcmc_<time>/ply/point_cloud_29999.ply   các Gaussian (xyz, scale, rot, opacity, SH)
#        results/.../stats/val_step29999.json                PSNR / SSIM / LPIPS trên tập test
#        results/.../ckpts/*.pt                              checkpoint PyTorch
#        results/.../tb/                                     log TensorBoard (lệnh: tb <thư mục>)

# (4) Nén / xuất
gs-compress /root/ws/results/lab_mcmc_<time>/ply/point_cloud_29999.ply
#     => .spz (nén ~10x)  .sog (cho web)  ; xem/sửa ở https://superspl.at/editor
```

Mẹo tham số:
- `-s default` = ADC (Adaptive Density Control — điều khiển mật độ thích nghi) gốc của 3DGS; `-s mcmc` = 3DGS-MCMC, ít floater (vết mờ lơ lửng) hơn, số Gaussian tối đa đặt bằng `-- --strategy.cap_max 500000` (mặc định 1 triệu).
- Camera fisheye hoặc rolling shutter: `gs-colmap ... -c OPENCV_FISHEYE` rồi `gs-train ... -- --with_ut --with_eval3d` (3DGUT).
- Xem toàn bộ tham số: `gsx && python simple_trainer.py mcmc --help`.

### 5.3. Ghi chú cho dữ liệu robot (rosbag LiDAR + camera)

- `rosbags` đọc trực tiếp `.bag` (ROS1) và thư mục `.db3/.mcap` (ROS2) bằng Python, không cần roscore.
- COLMAP 4.x có `pose_prior_mapper`: dùng pose từ LIO/GNSS làm prior thay vì để SfM tự đoán, hữu ích cho cảnh ngoài trời lớn.
- gsplat (nhánh main) có LiDAR rasterization: `pip show gsplat` để xem, tài liệu ở `/opt/gsplat/docs`.

## 6. Làm nghiên cứu trên gsplat

- `/opt/gsplat` là bản cài **editable**: sửa file `.py` có hiệu lực ngay. Sửa file CUDA (`gsplat/cuda/csrc/*.cu`) thì build lại:
  ```bash
  cd /opt/gsplat && pip install --no-build-isolation -e ".[lidar]"
  ```
- `/opt/gsplat` nằm trong image, **mất khi tạo lại container**. Code nghiên cứu nên để ở workspace (persist trên host):
  ```bash
  cd /root/ws && git clone https://github.com/<bạn>/gsplat.git my_gsplat
  cd my_gsplat && git submodule update --init --recursive
  pip install --no-build-isolation -e ".[lidar]"   # thay thế bản /opt/gsplat
  ```
- Reproducibility (tái lập kết quả) cho paper: đặt `GSPLAT_REF=<commit hash>` trong `.env` rồi `make build`.
- Cài thêm package mà không làm đổi torch/numpy: dùng alias `pipc <package>` (pip với `/opt/constraints.txt`).
- Repo 3DGS khác có CUDA extension (2DGS, Scaffold-GS, ...): biến `TORCH_CUDA_ARCH_LIST` đã đặt sẵn, thường chỉ cần `pip install --no-build-isolation -e .` trong repo đó.

## 7. Công cụ tùy chọn

| Công cụ | Cách dùng |
|---|---|
| **SuperSplat** (editor 3DGS trên web) | Mở https://superspl.at/editor trên trình duyệt host, kéo thả `.ply/.sog`. Không cần cài. |
| **Nerfstudio** | `gs-install-nerfstudio` → env riêng `ns` (vì nerfstudio 1.1.5 pin gsplat 1.4.0, xung đột với gsplat main). |
| **LichtFeld Studio** (app C++ train + edit) | Cần driver ≥ 570, gcc 14. Dùng Docker riêng của dự án: `git clone https://github.com/MrNeRF/LichtFeld-Studio && cd LichtFeld-Studio && ./docker/run_docker.sh -b -u` |
| **Brush** (không cần CUDA) | Dùng bản web/desktop của tác giả, không cần container này. |

## 8. Khác biệt so với template `ai_env`

- Tên service/container/image là `gs_env` / `gs-env:v1.0` để **không đụng** container `ai_env` đang chạy.
- X11: mount **thư mục** `/tmp/.gs-xauth` thay vì file `/tmp/.docker.xauth`. Nếu mount file, khi host reboot mà container khởi động trước lúc file tồn tại, Docker tự tạo nó thành thư mục và GUI hỏng.
- Thêm `ipc: host` (shared memory cho DataLoader của PyTorch), `ulimits`, volume `gs_cache` (cache pip, kernel JIT, lịch sử zsh), mount `./scripts` để sửa script không cần build lại.

## 9. Lỗi thường gặp

| Triệu chứng | Nguyên nhân / cách sửa |
|---|---|
| `unsatisfied condition: cuda>=12.x` khi `make up` | Driver cũ hơn CUDA trong image. Chạy `./host/setup_host.sh --force` rồi `make build`, hoặc nâng driver ≥ 570. |
| `could not select device driver "nvidia"` | Chưa cài/cấu hình nvidia-container-toolkit (mục 3). |
| Build chết giữa chừng, `Killed` / `c++: fatal error` | Hết RAM khi compile → giảm `MAX_JOBS` trong `.env`. |
| `no kernel image is available for execution on the device` | `CUDA_ARCH`/`TORCH_CUDA_ARCH_LIST` không khớp GPU → `./host/setup_host.sh --force` rồi `make build`. |
| `cannot open display` / `Authorization required` | Chạy `make x11` trên host; nếu dùng SSH thì `ssh -X` hoặc chỉ dùng viewer web. |
| COLMAP GUI lỗi OpenGL | Thử `QT_XCB_GL_INTEGRATION=xcb_glx colmap gui`. |
| Viewer `:8080` không mở được qua SSH | `ssh -L 8080:localhost:8080 user@host` rồi mở `http://localhost:8080` trên máy mình. |
| `gs-compress` lỗi khi nén `.sog` | Lỗi WebGPU/Vulkan → `splat-transform -g cpu -w in.ply out.sog`. |
| gsplat báo thiếu `images_4` | Chạy `gs-colmap` (tự tạo `images_2/4/8`) hoặc train với `-f 1`. |
| COLMAP ra nhiều model `sparse/0, 1, ...` | Ảnh thiếu overlap giữa các vùng; gsplat chỉ dùng `sparse/0`. Chụp thêm ảnh nối. |
