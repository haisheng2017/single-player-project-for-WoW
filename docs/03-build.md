# 03 · 编译服务端（core + playerbots + 提取器）

> 对应自动化脚本：`scripts/30-build-server.sh`。前提：完成 `01`（依赖）与 `02`（仓库就位 + 双保险挂载）。

## 配置 + 编译 + 安装

以下命令假定你在三仓库父目录（`$WOW_ROOT`）。产物统一装到 `$WOW_ROOT/run`：

```bash
mkdir -p build && cd build
CC=gcc-12 CXX=g++-12 cmake ../mangos-classic \
  -DCMAKE_INSTALL_PREFIX="$WOW_ROOT/run" \
  -DPCH=1 -DDEBUG=0 \
  -DBUILD_PLAYERBOTS=ON \
  -DBUILD_AHBOT=ON \
  -DFETCHCONTENT_SOURCE_DIR_PLAYERBOTS="$WOW_ROOT/playerbots" \
  -DBUILD_EXTRACTORS=ON
make -j"$(nproc)"
make install
```

（`$WOW_ROOT` 若未导出可直接用 `$(cd .. && pwd)` 或绝对路径代替。）

### 参数逐条说明

| 参数 | 作用 / 备注 |
|---|---|
| `CC=gcc-12 CXX=g++-12` | 绕开 22.04 默认 gcc-11 的编译器 bug（见 01）。已装 clang 的也可用 `CC=clang CXX=clang++`（官方 CI 双矩阵的另一条腿） |
| `-DCMAKE_INSTALL_PREFIX=.../run` | 安装目标目录（不指定会落到 `/opt/mangos`，需 root） |
| `-DPCH=1` | 预编译头，显著加速全量/增量编译（CI 同款） |
| `-DDEBUG=0` | Release 行为（默认也是 release，显式写出更直观） |
| `-DBUILD_PLAYERBOTS=ON` | 把 playerbots 模块编进 mangosd |
| `-DBUILD_AHBOT=ON` | 拍卖行机器人默认编入：宏经 `src/game/CMakeLists.txt:145-148` 注入 core，激活 World 启动/更新钩子与 `.ahbot` 管理命令（`World.cpp`/`Chat.cpp` 的 `#ifdef BUILD_AHBOT`）；AhBot 源码本就随模块编译，此开关只控制 core 侧钩子。跑脚本时可用环境变量 `BUILD_AHBOT=OFF` 关闭 |
| `-DFETCHCONTENT_SOURCE_DIR_PLAYERBOTS=.../playerbots` | **双保险之二**：绝对路径指向本地克隆，FetchContent 不再联网、不再 `rm -rf` 本地目录（原理见 02） |
| `-DBUILD_EXTRACTORS=ON` | 顺带把地图提取器编出来（x86_64 可用；arm64 会被 core 顶层 CMake 自动置 OFF——报一行 `BUILD_EXTRACTORS forced to OFF. Not supported on ARM architecture`，属预期） |

### 顺带的高频构建参数（按需）

- `-DPOSTGRESQL=ON` / `-DSQLITE=ON`：改用 PostgreSQL / SQLite（默认 MySQL，本项目全程按 MySQL 叙述）。

## 常见配置期输出解读

- `Could NOT find ZLIB (missing: ZLIB_DIR)`——**正常一行，不是缺包**。这是 CONFIG 模式查找失败的标准输出（该模式只认带 `zlibConfig.cmake` 的 CMake 化安装，apt 的 `zlib1g-dev` 不带此文件，装没装都必现）。fork 主分支随后**以模块模式接系统包**：应紧接一行 `Found ZLIB: /usr/lib/x86_64-linux-gnu/libz.so (found version "1.2.11")`——此时**不联网、不编 zlib**，mangosd 直接链系统 libz。仅当 zlib 开发包（`zlib1g-dev`）压根没装时，才会见 `Setting up zlib ...`（上游 FetchContent 联网拉 v1.3.2 做兜底；那串 `Looking for sys/types.h` / `Check size of off64_t` 是 zlib 子项目自己的检查）——回 01 装上 `zlib1g-dev` 重配即走系统包；
- `Playerbots module source dir: /...playerbots`——FetchContent 已按覆盖变量复用本地克隆（正确形态）；
- `FetchContent_Populate(PlayerBots) is deprecated ... CMP0169`——**仅是弃用警告**，cmangos 尚未迁移到新 API，忽略即可；
- `Playerbots module exists, but not building`——你同时没开 `BUILD_PLAYERBOTS`（本流程不出现；若在别处做"只编提取器"的构建会见到，无影响）。

## 产物布局

```
run/
├── bin/
│   ├── mangosd              # 世界服（前台运行、自带控制台）
│   ├── realmd               # 登录服
│   ├── tools/               # 提取工具（ad / vmapextractor / vmap_assembler / MoveMapGen + 脚本）
│   └── warden_modules/      # 反作弊数据
└── etc/
    ├── mangosd.conf.dist
    ├── realmd.conf.dist
    ├── anticheat.conf.dist
    ├── aiplayerbot.conf.dist   # 由 playerbots 模块自己的 install 规则装入（playerbots/CMakeLists.txt）
    └── ahbot.conf              # 无上游 install 规则——30 号脚本在安装后从
                                #   playerbots/ahbot/ahbot.conf.dist.in 直接拷贝生成（模板无 @ 替换符）
```

> 曾经流行的一些教程说"aiplayerbot.conf 不随 make install 安装、需从构建目录手拷"——那是旧版模块的行为，现在的模块自带 install 规则，`run/etc/` 里就有 **`aiplayerbot.conf.dist`**，去后缀即用（见 06）。

## 编译耗时参考

Ubuntu 22.04 CI（2 核 runner、PCH）全量约 10-20 分钟；典型桌面/服务器 CPU（`nproc` ≥ 4）会更快。内存小于 2 GB 的低配机建议把 `make -j$(nproc)` 降为 `make -j2` 以防 OOM。

下一篇：`04-extract.md` —— 从客户端提取四个数据目录。
