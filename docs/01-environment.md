# 01 · Ubuntu 22.04 环境与依赖

> 目标：一台干净的 Ubuntu 22.04（x86_64/amd64）上，装齐 CMaNGOS Classic 三件套（核心 + 数据库 + AI 模块）所需的全部系统依赖。对应的自动化脚本：`scripts/10-install-deps.sh`（需 sudo）。

## 系统要求

| 项 | 要求 |
|---|---|
| 发行版 | Ubuntu 22.04 LTS（对齐 CMaNGOS 官方 CI 的 ubuntu-22.04 runner） |
| CPU 架构 | **x86_64 / amd64**（既能编服务器也能编地图提取器） |
| | ⚠️ arm64/aarch64：服务器可以编译运行，但**地图提取器会被强制禁用**（core 顶层 `CMakeLists.txt` 的 ARM 检查），需另找一台 x86_64 机器跑提取（产物是跨平台数据文件，拷回即可） |
| 磁盘 | 约 5 GB（源码 + 编译 + 数据库）；客户端 Data/ 提取另需约 3 GB 余量 |
| Docker 形态（可选） | 以容器代替物理机/虚拟机时：**`docker run` 必须带 `--init`**（否则 mysql-server 装不上，见 troubleshooting #26）；`docker build` 的 RUN 层执行 10 号脚本直接可行。服务管理用 `service mysql start/stop`，对外记得 `-p 3724:3724 -p 8085:8085` |
| 网络 | 编译期一次 `git`（拉取仓库）+ 首次 cmake 若缺 zlib 时可能 FetchContent——常规联网即可 |

## 依赖清单（apt 一键装）

依赖组合对齐 CMaNGOS 官方 wiki（Ubuntu 22.04 章节）与官方 CI `ubuntu.yml`（gcc-12/clang 双矩阵、`BUILD_EXTRACTORS=ON`、PCH ON）：

```bash
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential gcc-12 g++-12 clang \
  automake autoconf make patch libtool binutils grep \
  cmake libboost-all-dev \
  libssl-dev zlib1g-dev libbz2-dev \
  libmysqlclient-dev mysql-client \
  mysql-server \
  git ca-certificates gzip
```

逐包用途：

| 包 | 用途 |
|---|---|
| `build-essential` / `make` / `binutils` | 基础编译链 |
| `gcc-12 g++-12`（或 `clang`） | **二选一必装**：22.04 默认 gcc/g++ 11 存在编译器内部 bug，官方 wiki 明确提示 GCC 11.2/11.3 编不过 `TileAssembler.cpp`。构建时以 `CC/CXX` 环境变量指定 |
| `cmake` | 构建系统（源码要求 ≥ 3.16；22.04 仓库约 3.22，满足；官方 CI 亦直接用 3.2x） |
| `libboost-all-dev` | Boost 1.74（源码要求 ≥ 1.70，满足；CI 固定 1.87 只是跨平台一致性，非硬性）。注入 5 个组件：program_options / thread / regex / serialization / filesystem |
| `libssl-dev` | OpenSSL ≥ 3.0（22.04 仓库默认 3.0.x，满足） |
| `libmysqlclient-dev` | MySQL **开发库**（`mysql.h` + `libmysqlclient.so`）。注意：core 的 CMake 对 MySQL 是**配置阶段强制检查**——条件包含 `BUILD_EXTRACTORS`，也就是说**即使只构建提取器也必须装**（对应 core `CMakeLists.txt:252-258`） |
| `mysql-client` | `mysql` / `mysqldump` 命令行客户端（`InstallFullDB.sh` 的运行依赖之一） |
| `mysql-server` | 数据库服务本体（四库都要落在它里面；Ubuntu 特有的 auth_socket 问题见 `05-database.md`） |
| `zlib1g-dev` / `libbz2-dev` | 压缩库。**可省但建议装**：bz2 找不到会退回用源码树 `dep/` 自带副本（`CMakeLists.txt:272-278` 有兜底）；zlib 找不到会在配置时走 FetchContent 从网上拉——装上就免除该联网环节 |
| `git` + `ca-certificates` | 拉取三仓库、core 构建时打 revision 戳 |
| `automake autoconf patch libtool grep` | 官方清单的传统配套工具 |
| `gzip` | `InstallFullDB.sh` 解压 `Full_DB/*.sql.gz` 需要（发行版自带，装上作显式声明） |

## 明确"不需要"的东西（对照老教程清障）

- **不需要 ICU**——core 只在 `if(APPLE)` 分支里 `find_package(ICU)`（`CMakeLists.txt:210`）。Linux 上没有这个依赖，也就没有 macOS 上著名的 ICU 坑；
- **不需要 ACE**——老 MaNGOS 时代的 ACE 依赖已被移除，线程/网络改走系统与 Boost 实现；
- **不需要** MySQL++（老 wiki 清单里的 `libmysql++-dev` 属历史遗留，多装无害但无必要）；
- **不需要** 换装新版编译器/Boost——仓库版本即测试版本。

## bash 版本

`InstallFullDB.sh` 里有 `BASH_VERSION > 4` 的特性检测分支。Ubuntu 22.04 自带 bash 5.x，**直接跑即可**（macOS 用户熟悉 `/opt/homebrew/bin/bash` 的心智负担在本平台不存在）。

## 自检

```bash
gcc-12 --version && cmake --version && mysql --version
systemctl is-active mysql   # 应输出 active
```

下一篇：`02-source-layout.md` —— 三仓库如何就位、playerbots 模块如何挂进核心（整个项目最反直觉的一步）。
