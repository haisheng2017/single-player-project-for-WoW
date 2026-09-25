# 09 · 四个外观/天赋模块（transmog / dualspec / achievements / barber）

> 对应脚本：`20-prepare-playerbots.sh`（挂链）、`30-build-server.sh`（编译开关）、`45-install-module-sql.sh`（世界 SQL）、`60-start-server.sh`（首次 Enable）。  
> 核心钩子与 CMake 解析在 fork 的 `mangos-classic` 主分支；本指导包只管布局、构建开关与装库步骤。

## 1. 要克隆的仓库（与 mangos-classic 同级）

```bash
cd $WOW_ROOT   # 与 mangos-classic / playerbots 同级的父目录
git clone https://github.com/flekz-games/cmangos-modules.git        cmangos-modules
git clone https://github.com/flekz-games/cmangos-transmog.git        cmangos-transmog
git clone https://github.com/flekz-games/cmangos-dualspec.git        cmangos-dualspec
git clone https://github.com/flekz-games/cmangos-achievements.git    cmangos-achievements
git clone https://github.com/celguar/cmangos-barber.git               cmangos-barber
```

| 目录名 | 角色 |
|---|---|
| `cmangos-modules` | 模块框架（`Module` / `ModuleMgr`）；编任意功能模块前必须在位 |
| `cmangos-transmog` | 幻化 |
| `cmangos-dualspec` | 双天赋（入口是生物 **100601**「Dual Specialization Crystal」，不是人型 NPC） |
| `cmangos-achievements` | 成就（客户端需 Achiever 插件才有完整 UI） |
| `cmangos-barber` | 理发店 |

脚本**不会**替你克隆，也**不会**从 `../cmangos-*` 自动发现。目录名必须与上表一致。

## 2. 挂载（20 号脚本）

与 PlayerBots 相同：在 `mangos-classic/src/modules/` 下做**三层**相对软链接：

```text
src/modules/modules      -> ../../../cmangos-modules
src/modules/transmog     -> ../../../cmangos-transmog
src/modules/dualspec     -> ../../../cmangos-dualspec
src/modules/achievements -> ../../../cmangos-achievements
src/modules/barber       -> ../../../cmangos-barber
```

跑 `bash scripts/20-prepare-playerbots.sh` 即可（幂等）。缺任一仓库目录则报错退出。

本地已有 `CMakeLists.txt` 时，CMake **不会**再 FetchContent；只有 `src/modules/<folder>` 缺失且该模块开关为 ON 时才会联网拉取。

## 3. 编译开关（30 号脚本已带）

```text
-DBUILD_MODULES=ON
-DBUILD_MODULE_TRANSMOG=ON
-DBUILD_MODULE_DUALSPEC=ON
-DBUILD_MODULE_ACHIEVEMENTS=ON
-DBUILD_MODULE_BARBER=ON
```

`make install` 后应出现：

```text
run/etc/transmog.conf.dist
run/etc/dualspec.conf.dist
run/etc/achievements.conf.dist
run/etc/barber.conf.dist
```

## 4. 世界 SQL（45 号脚本）

在 `InstallFullDB` **之后**执行：

```bash
bash scripts/45-install-module-sql.sh
```

导入目标库默认 `classicmangos`（连接信息读 `classic-db/InstallFullDB.config`，可用 `MYSQL_*` / `WORLD_DB_NAME` 覆盖）：

| 模块 | 文件 |
|---|---|
| transmog | `sql/install/world/world.sql` |
| dualspec | `sql/install/world/world.sql` |
| achievements | `01_world_data.sql` → `02_world_update.sql`（**不**导西班牙文 `03_world_locales.sql`） |
| barber | `world_classic.sql`（**不要** `world_tbc.sql`） |

**不导入角色库。** 角色库脚本会 `DROP` 双天赋/成就进度表；需要时手工导入，并先备份 `classiccharacters`。

导入后**不**自动改水晶 `DisplayId` / 坐标。上游 dualspec 模板默认 `DisplayId1=11659`（1.12 客户端没有），刷新点也可能在墙内——现象与改法见 `troubleshooting.md` 对应条目。

## 5. 配置 Enable（60 号脚本）

模板默认：`Transmog.Enable` / `Dualspec.Enable` / `Achievements.Enable` 为 `0`，`Barber.Enable` 为 `1`。

`60-start-server.sh` 在**首次**从 `.dist` 生成 `.conf` 时，会把前三个的 `Enable` 改成 `1`；已存在的 `.conf` **不覆盖**。

也可手工：

```bash
cd run/etc
cp transmog.conf.dist transmog.conf       # 再把 Transmog.Enable = 1
cp dualspec.conf.dist dualspec.conf       # Dualspec.Enable = 1
cp achievements.conf.dist achievements.conf
cp barber.conf.dist barber.conf
```

改配置后需**重启 mangosd**（进程内不热加载这些 conf）。

## 6. 启动日志通关

mangosd 启动接近 `CMANGOS: World initialized` 之前应依次（或相近）出现：

```text
Initializing Transmog module
Initializing DualSpec module
Initializing Achievements module
Initializing Barber module
```

`Enable=0` 时仍可能打印 Initializing，但钩子不做事。缺 conf 文件会报 `Failed to open configuration file <name>.conf`。

成就完整 UI 还需要客户端 Achiever 插件；幻化 UI 见 `cmangos-transmog/addons/1.12`。

## 7. 游戏内快速验证

| 功能 | 怎么验 |
|---|---|
| 幻化 | 暴风城 / 奥格瑞玛附近找 entry **190010** Magister Stellaria，对装备右键幻化 |
| 双天赋 | entry **100601** 水晶；购买后用物品 **17731** 切换并下线重登。模板可见 `.lookup creature 100601`；看不见时见 troubleshooting |
| 理发 | entry **190012** Shav Cutiss |
| 成就 | 装好 Achiever 后看进度面板；服务端日志在 Enable=1 时有 `Loading Achievements...` |

下一篇排障：`troubleshooting.md`（水晶不可见、`creature_respawn`、`.npc move` 等）。
