# 04 · 客户端数据提取（dbc / maps / vmaps / mmaps）

> 对应自动化脚本：`scripts/50-extract-client-data.sh <客户端目录>`。工具与说明全部来自 **mangos-classic 仓库**：一键脚本 `contrib/extractor_scripts/`（`ExtractResources.sh`、`MoveMapGen.sh`、`README.txt`），四个工具本体分别为 `contrib/extractor`（ad：maps+dbc）、`contrib/vmap_extractor`、`contrib/vmap_assembler`、`contrib/mmap`（MoveMapGen）。

## 先分清两条线（新人最大误区）

| 线 | 材料 | 产物 | 与客户端的关系 |
|---|---|---|---|
| **数据库线** | classic-db 仓库自带的 SQL 文件 | MySQL 四库（世界/角色/账号/日志） | **零关系**。SQL 是现成的文本文件，`InstallFullDB.sh` 只是把它们灌进 MySQL |
| **数据文件线** | 客户端 `Data/` 目录内的 MPQ | `dbc/ maps/ vmaps/ mmaps/` 四个**二进制数据目录** | **唯一必须依赖客户端的环节**。注意产物**不是 SQL**——"DBC 文件"名字像数据库，其实是暴雪客户端自带的二进制表，与 MySQL 毫无关系 |

`mangosd` 启动 = 读 MySQL（内容） + 读这四个目录（结构），两者缺一不可。没有客户端时，编译、装库、配置、`realmd` 启动全部畅通；`mangosd` 会在最后因缺 `*.map` 退出（这句话 = 服务器其余全部正确的标志，见 06）。

## 客户端准备

- 版本：**1.12.1 (5875) / 1.12.2 (6005) / 1.12.3 (6141)** 任一，中英文客户端均可（zhCN/zhTW 对应 build 相同即可）；
- 只需要其中的 **`Data/`** 目录（约 2-3 GB 的 MPQ 文件）；先在 Windows/macOS 侧把客户端目录通过 scp / 移动硬盘 / 局域网共享传到本机，例如：

```bash
scp -r user@<来源机>:'/path/to/WoW 1.12/Data'  ~/client112/     # 示例
# 只要 Data 目录与最外层部分文件（提取仅需 Data/）
```

- **Linux 大小写敏感**：目录必须叫 `Data`（大写 D），命名成 `data` 会直接失败；
- 合规说明：CMaNGOS 不分发客户端；请使用你自有的客户端（本项目仅作个人本地研究用途）。

## 提取（Ubuntu x86_64 原生可用）

cmangos 的官方交互式脚本会依次提取 maps+dbc、vmaps（需要装配）、mmaps（可跳过）：

```bash
# 工具已随 03 的 make install 装在 run/bin/tools/
cp run/bin/tools/* ~/client112/
cd ~/client112 && chmod +x *.sh
bash ./ExtractResources.sh        # 按提示作答；MoveMapGen 问询决定是否生成 mmaps
```

（`50-extract-client-data.sh <客户端目录>` 会替你完成拷贝、校验、运行与回拷，mmaps 缺省时也给出明确降级提示。）

产物收集：

```bash
cp -R ~/client112/{dbc,maps,vmaps,mmaps} run/bin/
```

## 耗时与取舍

| 产物 | 耗时 | 作用 | 可否推迟 |
|---|---|---|---|
| `maps` + `dbc` | 分钟级 | 服务器启动**必需** | ❌ |
| `vmaps` | 十分钟级 | 视线/建筑碰撞、室内判定 | 建议 |
| `mmaps` | **数十分钟到数小时**（CPU 密集，`nproc` 越多越快） | bot 寻路（Recast/Detour 网格） | ✅ 可先跳过，之后补提（只影响 bot 寻路智能） |

## arm64 Ubuntu 的特别说明

提取器的编译被 core 顶层 `CMakeLists.txt`（约 401 行）强制 `BUILD_EXTRACTORS=OFF`——arm64 上无法本地编译。请在**任意一台 x86_64 Linux**（物理机/虚拟机/容器均可）上按本篇流程提取，**提取产物是跨平台的纯数据文件**，拷回 arm64 服务器的 `run/bin/` 直接可用（服务器本体仍在 arm64 上编译运行）。

提取完 `Data/` 即可归还——后续步骤与客户端文件再无关系（直到真正登录游玩时需要客户端本体，见 07）。

下一篇：`05-database.md` —— MySQL 与 InstallFullDB 全流程。
