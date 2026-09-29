# 09 · 五个功能模块（transmog / dualspec / achievements / barber / immersive）

> 对应脚本：`20-prepare-playerbots.sh`（挂链）、`30-build-server.sh`（编译开关）、`45-install-module-sql.sh`（模块 SQL）、`60-start-server.sh`（首次 Enable）。  
> 核心钩子与 CMake 解析在 fork 的 `mangos-classic` 主分支；本指导包只管布局、构建开关与装库步骤。

## 1. 要克隆的仓库（与 mangos-classic 同级）

```bash
cd $WOW_ROOT   # 与 mangos-classic / playerbots 同级的父目录
git clone https://github.com/flekz-games/cmangos-modules.git        cmangos-modules
git clone https://github.com/flekz-games/cmangos-transmog.git        cmangos-transmog
git clone https://github.com/flekz-games/cmangos-dualspec.git        cmangos-dualspec
git clone https://github.com/flekz-games/cmangos-achievements.git    cmangos-achievements
git clone https://github.com/celguar/cmangos-barber.git               cmangos-barber
git clone https://github.com/flekz-games/cmangos-immersive.git     cmangos-immersive
```

| 目录名 | 角色 |
|---|---|
| `cmangos-modules` | 模块框架（`Module` / `ModuleMgr`）；编任意功能模块前必须在位 |
| `cmangos-transmog` | 幻化 |
| `cmangos-dualspec` | 双天赋（入口是生物 **100601**「Dual Specialization Crystal」，不是人型 NPC） |
| `cmangos-achievements` | 成就（客户端需 Achiever 插件才有完整 UI） |
| `cmangos-barber` | 理发店 |
| `cmangos-immersive` | 跨号进度共享（声望全账号合并、任务完成同步到小号——ike3/mangosbot-immersive 移植；详 §8） |

脚本**不会**替你克隆，也**不会**从 `../cmangos-*` 自动发现。目录名必须与上表一致。

## 2. 挂载（20 号脚本）

与 PlayerBots 相同：在 `mangos-classic/src/modules/` 下做**三层**相对软链接：

```text
src/modules/modules      -> ../../../cmangos-modules
src/modules/transmog     -> ../../../cmangos-transmog
src/modules/dualspec     -> ../../../cmangos-dualspec
src/modules/achievements -> ../../../cmangos-achievements
src/modules/barber       -> ../../../cmangos-barber
src/modules/immersive    -> ../../../cmangos-immersive
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
-DBUILD_MODULE_IMMERSIVE=ON
```

`make install` 后应出现：

```text
run/etc/transmog.conf.dist
run/etc/dualspec.conf.dist
run/etc/achievements.conf.dist
run/etc/barber.conf.dist
run/etc/immersive.conf.dist
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
| immersive | `sql/install/world/world.sql`（npc_text/mangos_string，DELETE+INSERT 可重跑）+ **characters 库** `sql/install/characters/characters.sql`（模块自建表 `custom_immersive_values`，首装导入、表在位则跳过） |
| zhCN 补缺 | `classic-db/locales/Chinese/supplements/01..05_*_zhCN_fixup.sql`（目录缺失则跳过并告警） |

主中文包仍由 `40-prepare-database.sh` 在 locale 表为空时导入 `locales/Chinese/*.sql`；45 号在其后用 supplements 补缺/纠错（含任务 707），可重复执行。

除 immersive 的模块自建表外**不导入角色库**：dualspec/achievements 的角色库脚本会 `DROP` 进度表；需要时手工导入，并先备份 `classiccharacters`。

导入后**不**自动改水晶 `DisplayId` / 坐标。上游 dualspec 模板默认 `DisplayId1=11659`（1.12 客户端没有），刷新点也可能在墙内——现象与改法见 `troubleshooting.md` 对应条目。

## 5. 配置 Enable（60 号脚本）

模板默认：`Transmog.Enable` / `Dualspec.Enable` / `Achievements.Enable` / `Immersive.Enable` 为 `0`，`Barber.Enable` 为 `1`。

`60-start-server.sh` 在**首次**从 `.dist` 生成 `.conf` 时，会把前三个的 `Enable` 改成 `1`；immersive 则同时打开 `Enable`、`AccountReputation`、`SharedQuests` 三键（语义与限制见 §8，其余共享开关默认 0、按需自开）；已存在的 `.conf` **不覆盖**。

也可手工：

```bash
cd run/etc
cp transmog.conf.dist transmog.conf       # 再把 Transmog.Enable = 1
cp dualspec.conf.dist dualspec.conf       # Dualspec.Enable = 1
cp achievements.conf.dist achievements.conf
cp barber.conf.dist barber.conf
cp immersive.conf.dist immersive.conf    # Enable=1 + AccountReputation/SharedQuests=1
```

改配置后需**重启 mangosd**（进程内不热加载这些 conf）。

## 6. 启动日志通关

mangosd 启动接近 `CMANGOS: World initialized` 之前应依次（或相近）出现：

```text
Initializing Transmog module
Initializing DualSpec module
Initializing Achievements module
Initializing Barber module
Initializing Immersive module
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
| 跨号共享 | 主号交一个任务（小号以 bot 在线）→ 换登小号应见任务已完成；主号涨声望 → 小号登录后声望对齐——语义与三限制见 §8 |

## 8. immersive：跨号进度共享

来自 ike3/mangosbot-immersive 的移植（playerbots 作者亲做，与 `BUILD_PLAYERBOTS` 深度联动）。典型用法：开门任务做过一次，小号直接受益。

两个共享机制（即 60 号首开的三键中后两个开启的机制）：

- **`Immersive.AccountReputation = 1`（声望全账号共享）**：任一角色获得声望，即按阵营规则合并进同账号所有角色——**离线小号也覆盖**（模块直接查库合并，不要求小号在线）。
- **`Immersive.SharedQuests = 1`（任务完成共享）**：你交任务的瞬间，**当前以 bot 形式带在线的小号**被记为"任务已完成（含奖励标记）"——开门/钥匙类检查的正是这个状态。

三个如实限制（排查见 troubleshooting #37）：

1. 任务共享**只对当时以 bot 在线的小号生效**——交任务前先把要受益的小号组进 bot 队；
2. **带职业限定的任务不共享**（上游刻意防跨职业错发）；
3. **任务奖励物品不共享**——黑上印记（Seal of Ascension）这类"钥匙物品"门，小号仍需自拿（GM 可 `.additem` 补发）。

其它共享类开关默认全 0，按需在 `run/etc/immersive.conf` 自开：`SharedXpPercent` / `SharedRepPercent` / `SharedMoneyPercent`（小号 bot 按比例同步获取，各自带种族/职业/公会/阵营限制与等级门槛）、`DisableOfflineRespawn`（单机下副本中途关服续刷；配套建议见 conf 内注释）等。

SQL（45 号已接）：world 侧为 npc_text 50800-50802 + mangos_string 12100-12129（DELETE+INSERT，可重跑）；characters 侧为模块自建表 `custom_immersive_values`（首装导入、表在位跳过，防重置）。上游小瑕疵：`sql/uninstall/characters/characters.sql` 写的表名 `immersive_values` 与实际不符——卸载时手动 `DROP TABLE custom_immersive_values;`。

下一篇排障：`troubleshooting.md`（水晶不可见、`creature_respawn`、`.npc move` 等）。
