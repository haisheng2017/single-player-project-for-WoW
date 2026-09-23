# single-player-project-for-WoW

**Ubuntu 22.04 从 0 到 1**：一台干净服务器 → 一台可登录、可练级、可带 AI 队友下副本的 **WoW 1.12 原版（Vanilla）单机服务器**。

**面向本仓库体系内的 fork 版本**：本指导包与三个 fork 仓库（服务端核心、世界内容数据库、AI 机器人模块）配套维护。fork 会**定期同步上游主分支**，并允许存在本地定制（差异点在 `docs/02-source-layout.md` 的"fork 策略"一节集中列出）——因此**文档与脚本一律以本 fork 的当前代码为准**，上游原始项目（CMaNGOS）仅作历史出处与排障参考。本仓库不包含三个 fork 中的任何一行代码——只提供经过实机验证的文档与自动化脚本（fork 定制直接维护在各自主分支中）。

> 定位：个人本地研究/学习用单机环境（开源生态 + 自备原版客户端）。请勿用于公开运营。

## 目录导览

| 路径 | 内容 |
|---|---|
| `docs/01-environment.md` | Ubuntu 22.04 依赖清单与逐包解释（gcc-11 坑、哪些"老教程依赖"其实不需要） |
| `docs/02-source-layout.md` | 三仓库布局与 **playerbots 挂载双保险**（三层软链接 + FetchContent 覆盖变量；out-of-tree 支持由 fork 主分支自带）——全项目最反直觉的一步 |
| `docs/03-build.md` | cmake/make 全参数解释、产物布局、常见配置输出解读 |
| `docs/04-extract.md` | 从 1.12.x 客户端 `Data/` 提取 `dbc/maps/vmaps/mmaps`（am64 机器的替代路径） |
| `docs/05-database.md` | MySQL 就绪（**Ubuntu auth_socket 大坑**）+ `InstallFullDB.sh` 交互菜单逐步实录与全部陷阱 |
| `docs/06-configure-and-run.md` | 配置文件、两条启动铁律、**启动日志通关判读**、建号 |
| `docs/07-client.md` | 客户端接入（realmlist、版本匹配、防火墙）与 playerbots 上手 |
| `docs/08-character-migration.md` | **角色数据迁移**（源服 → 目标服：迁什么不迁什么、playerbots 开发者须知、版本守门、种子账号替换语义） |
| `docs/troubleshooting.md` | 坑位速查表（每条都实机踩过/验证过） |
| `scripts/10-install-deps.sh` | 一键 apt 依赖（sudo） |
| `scripts/20-prepare-playerbots.sh` | 三层软链接 + out-of-tree 支持在位校验（幂等，不打档——fork 自带） |
| `scripts/30-build-server.sh` | 配置+编译+安装（默认 gcc-12，可切 clang；AHBot 默认一并编入并生成 ahbot.conf，`BUILD_AHBOT=OFF` 可关） |
| `scripts/40-prepare-database.sh` | MySQL 就绪/auth_socket 处理/装 `InstallFullDB.config` 预备（sudo，交互菜单步骤打印） |
| `scripts/50-extract-client-data.sh` | 提取包装：工具就位→跑官方 ExtractResources→产物回拷（含 mmaps 缺失降级） |
| `scripts/60-start-server.sh` | 双进程启动（realmd 后台守护 + mangosd 前台控制台） |
| `scripts/70-export-character-data.sh` | 【源端】角色数据导出：characters 整库 + realmd 三表 + manifest（SRP6 原密码随行） |
| `scripts/80-import-character-data.sh` | 【目标端】导入：版本守门 + 确认词 + 整库替换（支持 --dry-run 预演） |

## 快速开始

```bash
# 0) 取仓库（四个仓库同级摆放——脚本按此约定；克隆后留在默认主分支）
#    三个代码仓库均为本体系 fork（haisheng2017），与上游 cmangos 定期同步
mkdir -p $HOME/wow && cd $HOME/wow
git clone https://github.com/haisheng2017/mangos-classic.git mangos-classic
git clone https://github.com/haisheng2017/classic-db.git     classic-db
git clone https://github.com/haisheng2017/playerbots.git     playerbots
git clone <本指导包仓库.git>		                          single-player-project-for-WoW

# 1) 系统依赖（Ubuntu 22.04, amd64）+ 2) 模块挂载（软链 + 在位校验，fork 主分支已自带补丁）
sudo bash single-player-project-for-WoW/scripts/10-install-deps.sh
bash     single-player-project-for-WoW/scripts/20-prepare-playerbots.sh

# 3) 编译（产物 → ./run）
bash     single-player-project-for-WoW/scripts/30-build-server.sh

# 4) 数据库预备 + 按脚本尾部的指引人工走完交互菜单（文档 05 全程对照）
sudo bash single-player-project-for-WoW/scripts/40-prepare-database.sh
cd classic-db && bash InstallFullDB.sh    # 菜单路线与确认词陷阱：务必先读 05 第 2.3 节

# 5) 提取客户端数据（需要一份 1.12.x 客户端的 Data/ 目录；1.12.1/1.12.2/1.12.3 任一）
bash     single-player-project-for-WoW/scripts/50-extract-client-data.sh /path/to/WoW112client

# 6) 复制正式配置（去 .dist 后缀，见 06）后启动
bash     single-player-project-for-WoW/scripts/60-start-server.sh

# 7) 建号 → 客户端 realmlist → 进游戏
```

> `WOW_ROOT` 环境变量可在任意脚本上覆盖默认目录。所有脚本幂等，可重复执行。

## 参考与致谢

- **上游原始项目**（各 fork 的同步来源，仅作历史出处与排障参考）：CMaNGOS 官方 wiki [Installation Instructions](https://github.com/cmangos/issues/wiki/Installation-Instructions)、[Beginner's Guide](https://github.com/cmangos/issues/wiki/Beginners-Guide)
- **fork 内自带文档**（以 fork 当前内容为准）：`mangos-classic/doc/`、`mangos-classic/contrib/extractor_scripts/README.txt`、`classic-db/README.md`、`playerbots/README.md`
- core 内 `README_PLAYERBOT.txt` / `doc/PlayerBot/` 描述的是**已弃用**的 in-tree 老 bot 模块（`BUILD_DEPRECATED_PLAYERBOT`），与本指导无关——别按它配置。

## 版权与合规

- 本指导文档与脚本：随本仓库许可发布；
- 三个代码仓库（fork）沿用其许可证：GPL-2.0（core）/ GPL-3.0（classic-db）/ GPL（playerbots），并对上游 CMaNGOS 社区的工作致谢；
- World of Warcraft 客户端与游戏数据：© Blizzard Entertainment——请自备合法客户端，仅作个人本地研究用途；本仓库不含任何暴雪资产。
