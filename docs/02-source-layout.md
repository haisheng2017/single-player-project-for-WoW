# 02 · 三仓库就位与 playerbots 挂载（双保险）

> 对应自动化脚本：`scripts/20-prepare-playerbots.sh`。本篇是整个项目**最反直觉**的一步，原理请至少通读一遍再跑脚本。

## 1. 拉取三仓库（同级摆放，以主分支为准）

约定一个父目录（下文以 `$WOW_ROOT` 代指，它也是全部脚本的输入约定）：

```bash
mkdir -p $HOME/wow && cd $HOME/wow     # 示例路径，可自定
git clone https://github.com/haisheng2017/mangos-classic.git mangos-classic
git clone https://github.com/haisheng2017/classic-db.git     classic-db
git clone https://github.com/haisheng2017/playerbots.git     playerbots
```

- **三个代码仓库均为本体系的 fork**（`haisheng2017` 命名空间下，默认分支 `master`），与对应上游（CMaNGOS）定期同步；fork 可能含本地定制，因此**文档与脚本一律以 fork 主分支为准，不要改克隆上游 cmangos 原仓库**；
- 三个仓库克隆后**留在默认主分支**即可，本指导全部事实以主分支形态记录。

## 2. fork 策略与上游同步（本体系的维护方式）

三个代码仓库都是**本体系内的 fork**，维护约定：

- **定期同步上游主分支**：`git fetch upstream && git merge upstream/master`（或 rebase，按各 fork 惯例）；上游即 CMaNGOS 社区对应项目（core / classic-db / playerbots 各自的上游）。
- **fork 允许本地定制**：典型如 `src/CMakeLists.txt` 里为"FetchContent 覆盖变量指向仓库外目录"而做的 out-of-tree 二元目录改动（已提交进 fork 主分支，行的形态见 §4）。按本文档克隆 fork 即开箱自带、无需打档；`scripts/20-prepare-playerbots.sh` 只做**在位校验**：在位 → `[OK]`；不在位（说明当前检出不是 fork 主分支形态，例如误克隆上游、同步上游时丢失该行）→ 报错并给出诊断，不会替你打档。
- **同步后冲突出现在预期位置时**：`src/CMakeLists.txt` 的 `add_subdirectory` 一行（上游若重构 FetchContent 相关代码）优先保留 **fork 侧带二元目录参数**的形态；数据库脚本类文件（`InstallFullDB.sh`、菜单结构 SQL）如有行为级变化，需回勘本指导 `docs/05-database.md` 并同步修订——菜单号或确认词是实测记录，上游改动会使其失准。
- 同步上游后**先重跑 `20-prepare-playerbots.sh`**（重建软链接 + 校验 fork 定制在位），再增量编译（`30` 号脚本可直接重跑）。

## 3. 三仓库角色

| 仓库 | 角色 |
|---|---|
| `mangos-classic/` | C++ **服务端核心**：编译出 `mangosd`（世界服，端口 8085）与 `realmd`（登录认证，端口 3724）；内置 ScriptDev2 脚本引擎、反作弊、地图提取工具（x86_64） |
| `classic-db/` | **世界内容数据库**（NPC/任务/物品/掉落……全部游戏内容）：`Full_DB/` 全量快照 + 增量 `Updates/`，经 `InstallFullDB.sh` 灌入 MySQL |
| `playerbots/` | **AI 机器人模块**（ike3 版）：不是独立程序，是**编译进 mangosd 的模块**；自备需入库的 SQL 与 `aiplayerbot.conf` 配置；附带 `ahbot/`（拍卖行机器人，构建开关控制） |

支持的客户端版本：**1.12.1 (build 5875) / 1.12.2 (6005) / 1.12.3 (6141)** 任一（core 源码 `src/game/Globals/SharedDefines.h` 的 `EXPECTED_MANGOSD_CLIENT_BUILD`）。

## 4. playerbots 挂载："双保险"

**保险一 · 三层软链接**：

```bash
mkdir -p mangos-classic/src/modules
ln -sfn ../../../playerbots mangos-classic/src/modules/PlayerBots
```

⚠️ **必须是三层 `../../../playerbots`**。链接文件位于 `src/modules/` 内部，向上三级才回到三仓库父目录——写成两层指向的是 `mangos-classic/playerbots`（不存在）：

- 死链的**症状极具迷惑性**：编译完全不受影响（编译走的是下述的显式路径变量），但 `InstallFullDB.sh` 按 `${CORE_PATH}/src/modules/PlayerBots/sql` 找 SQL，一无所获后**静默空转**——屏幕照样打 SUCCESS，但数据库里 `ai_playerbot_*` 一张表都不会有。

为什么需要这个链接（core 与 DB 仓库共三处硬编码引用该路径）：

- `mangos-classic/src/game/CMakeLists.txt`：头文件 include 路径；
- `mangos-classic/src/mangosd/CMakeLists.txt`：`aiplayerbot.conf` 的构建拷贝；
- `classic-db/InstallFullDB.sh` 的 `apply_playerbots_db()`：导入 `sql/` 三组 SQL（world、world/classic、characters）。

**保险二 · FetchContent 覆盖变量（out-of-tree 支持由 fork 主分支自带）**：

开 `BUILD_PLAYERBOTS` 后，core 会在 cmake 配置时用 CMake FetchContent 拉取 playerbots，其中 **git 下载路径是先 `rm -rf` 目标目录再 `git clone`**（CMake `gitclone.cmake.in` 模板的行为）——也就是会**清掉**你预放的 `src/modules/PlayerBots`。带上下面的参数后，FetchContent 完全复用你的本地克隆、跳过下载（命令在 `03-build.md`）：

```text
-DFETCHCONTENT_SOURCE_DIR_PLAYERBOTS=<三仓库父目录>/playerbots   （绝对路径）
```

而指向 core 外部目录后，`mangos-classic/src/CMakeLists.txt` 原来的 `add_subdirectory(${playerbots_SOURCE_DIR})` 会缺少二元目录参数而报错（CMake 对 out-of-tree 源的强制要求）。fork 主分支已内置该处改动——**克隆 fork 即自带，无需打档**：

```diff
-  add_subdirectory(${playerbots_SOURCE_DIR})
+  add_subdirectory(${playerbots_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR}/modules/PlayerBots)
```

（二元目录取的是与"模块在默认 in-tree 位置时 CMake 自动选择"完全相同的路径，零副作用。上面 diff 供两种场合识别：与上游合并冲突时认准保留 fork 侧"+"行；`20-prepare-playerbots.sh` 在位校验命中的就是这一行。）

> 上游若哪天改用 `FetchContent_MakeAvailable`，fork 的这处改动即可随下次同步自然撤销。

**运维提示**：未来任何一次 cmake 配置忘带 `-DFETCHCONTENT_SOURCE_DIR_PLAYERBOTS`，都会让 FetchContent 把这个软链接删掉重建。发现 `src/modules/PlayerBots` 失效时，回到 `src/modules` 重跑 `ln` 命令即可（`20-prepare-playerbots.sh` 幂等，直接重跑最省事）。

## 5. 自检

```bash
ls mangos-classic/src/modules/PlayerBots/sql/world/*.sql   # 应列出 ai_playerbot_*.sql
grep -n "modules/PlayerBots)" mangos-classic/src/CMakeLists.txt  # fork 主分支形态应命中带二元目录参数的那行
```

下一篇：`03-build.md` —— 编译。
