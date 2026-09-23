# 坑位速查（实战全部踩过/验证过）

按流程顺序排列；右侧给出定位与解法。**macOS 同栈部署特有的坑不在此列**（如 ICU 查找失败、`brew link` 类问题——Linux 上不存在 ICU 依赖，见 01 的"不需要"清单）。

| # | 现象 | 定位 / 解法 |
|---|---|---|
| 1 | cmake 配置报 `Could not find Boost/MySQL/OpenSSL` | `01` 的 apt 清单没装全。注意 **MySQL 开发库在只编提取器的场景也是强制的**（core 对三者的 find 条件都包含 `BUILD_EXTRACTORS`） |
| 2 | 编译期 `TileAssembler.cpp` 奇怪的内部编译错误 | gcc-11 bug。`CC=gcc-12 CXX=g++-12`（或 clang）重新配置 |
| 3 | `FetchContent_Populate(PlayerBots) is deprecated (CMP0169)` | **弃用警告，无害**，忽略（上游尚未迁移新 API；cmangos CI 同然） |
| 4 | `add_subdirectory not given a binary directory … is not a subdirectory` | 说明**当前检出不是 fork 主分支形态**（误克隆上游 cmangos 原仓库、或同步上游时丢失了 `add_subdirectory` 的二元目录参数）——fork 主分支自带该支持；核对：`git remote -v` 应为 fork 地址、`git log --oneline -1` 应含相应提交；同步冲突的处理见 #21 |
| 5 | 任何一次 configure 忘带 `-DFETCHCONTENT_SOURCE_DIR_PLAYERBOTS` | 该次配置会让 FetchContent `rm -rf` 掉 `src/modules/PlayerBots` 并从 GitHub 重克隆——重跑脚本 `20` 号（幂等：重挂链接 + 在位校验） |
| 6 | 编译全好、装库全好，但 `ai_playerbot_*` 表为 0 | 两个之一：**(a)** 三层软链接写成了两层（死链，InstallFullDB 静默空转、照样打 SUCCESS）——`ls mangos-classic/src/modules/PlayerBots/sql/world/*.sql` 验证；**(b)** `InstallFullDB` 全装流程中 `Type 'Mangosbots'` 确认词漏敲/敲错（回车=静默跳过）——重跑脚本 `5) Advanced → 8)` 补装并逐字敲词 |
| 7 | InstallFullDB 设置菜单报 `ERROR 1045 (Access denied for user 'mangos')` | **首装正常现象**（mangos 用户尚未创建）：菜单 `2` → root 用户名**手敲 root**（直接回车=空用户名必失败）→ 密码静默输入（无回显属正常）→ 通过后 `9` 进主菜单 |
| 8 | Ubuntu：`sudo mysql` 能进，`mysql -uroot -p` 无论如何被拒 | root 用 `auth_socket` 插件——见 `05` 第 1 节或跑脚本 `40` 号：`ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '<密码>';` |
| 9 | root 密码忘了 | `systemctl stop mysql` → `mysqld --skip-grant-table --skip-networking &` → `mysql -uroot` → `FLUSH PRIVILEGES;` + `ALTER USER ...` → kill 手动进程 → `systemctl start mysql` |
| 10 | `bash InstallFullDB.sh: line NNN: mysql: command not found` | `mysql-client` 未装或不在 PATH——回到 `01` 补装（脚本用 `type -P mysql` 自动探测） |
| 11 | `Check existing of map file './maps/0004331.map': not exist!` 后退出 | **四库/服务端全部正常的标志**——缺 `dbc/maps/vmaps/mmaps`，回 `04` 提取并放入 `run/bin/` |
| 12 | 提取脚本在客户端目录一启动就报找不到数据 | 客户端目录缺 `Data/`（**大写 D**，Linux 大小写敏感）或 client 数据路径未传对 |
| 13 | 提取器不可构建：`BUILD_EXTRACTORS forced to OFF. Not supported on ARM architecture` | arm64 机器的**内核级限制**（core CMakeLists 硬性检查）——到任意 x86_64 Linux 机器/容器提取，产物拷回（数据文件跨平台） |
| 14 | `mangosd`/`realmd` 启了但 playerbots 没行为、控制台无 bot 指令 | 大概率不是从 `run/bin` 启动（配置按 `../etc/` 相对路径加载）或 `run/etc/aiplayerbot.conf` 未生成（.dist 未去后缀）——见 `06` 的两条铁律 |
| 15 | 首次启动很慢/像卡死 | 随机 bot 在批量生成装备/角色——正常，等进度完 |
| 16 | 登录界面报"无法连接" | realmd 没起（`ss -ltnp 'sport = :3724'` 检查）、`realmlist.wtf` 没改、或跨机访问未放行 3724/8085 |
| 17 | 升级 core 后连库报 `db_version` 相关不匹配 | core 比库新——`InstallFullDB.sh` 菜单 `3) Install core updates only` 应用 core `sql/updates/`；反向（库比 core 新）则重新编译 core |
| 18 | 想清库重来 | `InstallFullDB.sh` → `5) Advanced → 7) Delete all databases and users`（确认词 `DeleteAll`）再全装 |
| 19 | `make install` 后 `run/etc` 里没有 `aiplayerbot.conf.dist` | 该文件由 playerbots 模块自身的 install 规则装入（`playerbots/CMakeLists.txt`）——没开 `BUILD_PLAYERBOTS` 就不会有；确认编译参数 |
| 20 | 玩家数据位置 / 备份 | 角色背包邮件等都在 `classiccharacters` 库；`mysqldump classiccharacters > backup.sql`（导入 `mysql classiccharacters < backup.sql`） |
| 21 | fork 同步上游主分支后构建异常 | 同步后**先重跑 `20-prepare-playerbots.sh`**（重建软链接 + 校验 fork 定制在位；`src/CMakeLists.txt` 若冲突出现在 `add_subdirectory` 处，保留 fork 侧带二元目录参数的形态），再 `30` 号脚本增量编译 |
| 22 | 同步上游后 InstallFullDB 菜单/流程与本文档描述不符 | 上游重构了安装脚本——以脚本实跑表现为准，并回勘修订 `05-database.md`（菜单实录），差异处多为编号位移，逐字确认词机制不变 |
| 23 | 角色迁移后账号登录被拒 | 70 号按表级 dump 迁 `account`（SRP6 `v`/`s` 随行，原密码有效）；排查源 dump 是否早于玩家改密时间——重新导一份新 dump；详见 `08-character-migration.md` 第 8 节 |
| 24 | 角色迁移导入时被 80 号拒绝（"源数据比目标 core 新"） | 方向问题：先升级目标服 core（`git pull` + 30 号重编译）再迁移；源旧于目标才是受支持的升级方向（docs/08 第 4 节） |
| 25 | mangosd 运行中误导入角色库 | 80 号有 8085/3724 端口前置检查拦住正常运行场景；若已发生——停服、用最新 dump 重新走 80 号导入（库处于半新半旧状态不可信） |
| 26 | **Docker 容器内**跑 10 号脚本装 mysql-server 失败（`dpkg: error processing mysql-server-8.0`，如 `Unable to shut down server with process id NN`） | **实测结论：`docker run` 启动的容器必须加 `--init`，否则本脚本无法完成 mysql-server 安装**——pid 1 为 bash 等普通进程时无人收割退出的 mysqld（成僵尸），postinst 以 `kill -0` 判存活对僵尸恒真，稳定误报"关不掉"（`/var/log/mysql/error.log` 可证 mysqld 实际每轮都 `Shutdown complete`）。两种实测形态：① `docker run --init` → 交互安装 ✅（不加 `--init` 即复现失败）；② **`docker build`（RUN 层执行 10 号脚本）→ 直接可行** ✅，构建执行环境自带进程托管，无需任何处理。容器内无 systemd，服务管理一律 `service mysql start/stop`（脚本已内置兜底） |
| 27 | Docker 容器部署缺端口映射，客户端连不上 | 容器启动需 `-p 3724:3724 -p 8085:8085`（realmd/mangosd；3306 视拓扑），`realmlist.wtf` 指向宿主机 IP——容器重建趁早（装库编译前成本最低） |
| 28 | configure 输出 `Could NOT find ZLIB (missing: ZLIB_DIR)` | **正常一行**：CONFIG 模式查找失败的标准输出（只认 `zlibConfig.cmake`，apt 的 zlib1g-dev 不带，装没装都必现）。fork 主分支查找顺序为 CONFIG → **系统 zlib（模块模式）** → FetchContent 联网兜底：装了 `zlib1g-dev` 时紧接应见 `Found ZLIB: ... (found version "1.2.11")`——离线、直链系统包；只有 zlib 开发包完全没装才会走 `Setting up zlib ...`（FetchContent 拉 v1.3.2，需联网），回 01 补装即可。上游原版（非 fork）恒走 FetchContent。详见 `03` 输出解读 |
| 29 | AHBot 不工作：mangosd 日志 `AhBot is Disabled. Unable to open configuration file ahbot.conf` | AhBot 运行配置读 `run/etc/ahbot.conf`，但 **playerbots 模块没有该文件的 install 规则**——30 号脚本会在 make install 后自动从 `playerbots/ahbot/ahbot.conf.dist.in` 生成（模板无 @ 替换符，直拷即用）。手工补：`cp playerbots/ahbot/ahbot.conf.dist.in run/etc/ahbot.conf` 后重启。另确认构建带了 `-DBUILD_AHBOT=ON`（30 号默认）；`ai_playerbot_ahbot` 表无需另装，InstallFullDB 的 playerbots 步骤已带入 |

## 与本体系和上游的关系

- **一切以本体系 fork 的主分支代码为准**：菜单号、确认词、行号、行为描述都是对 fork 当前形态的实测记录；
- 三个代码仓库定期**同步上游 CMaNGOS 主分支**（见 `02-source-layout.md` 的"fork 策略"）——同步可能带来冲突或行为漂移：
  - `src/CMakeLists.txt` 的 `add_subdirectory` 冲突 → 保留 fork 侧**带二元目录参数**的形态；
  - `InstallFullDB.sh` 若上游重构（菜单结构/确认流程变化）→ 本指导 `05` 的菜单实录需同步回勘修订；
  - 同步完成后重跑 `20-prepare-playerbots.sh`（幂等：链接 + fork 定制在位一次性核对），再增量 `30` 号脚本重编译；
- 上游 wiki（[Installation Instructions](https://github.com/cmangos/issues/wiki/Installation-Instructions)）与各仓库 README 作为排障参考。
