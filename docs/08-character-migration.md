# 08 · 角色数据迁移（源服 → 本指导包部署的目标服）

> 配套脚本：`scripts/70-export-character-data.sh`（源端执行）+ `scripts/80-import-character-data.sh`（目标端执行）。适用前提：源服务器与目标服务器**同为 mangos-classic 系**（本体系 fork 或 cmangos 上游同栈）。其他 1.12 变体（mangos-zero/getmangos、Trinity 系）不属于本文承诺范围——表结构差异需人工逐表核对，风险自负。

## 1. 迁什么、不迁什么（三库判定）

| 库 | 迁移策略 | 原因 |
|---|---|---|
| `characters`（角色库） | ✅ **整库替换** | 全部是玩家数据与运行时状态（角色、物品 `item_instance`、任务、公会、邮件、bot 的 11 张 `ai_playerbot_*` 动态表等 58+ 张表） |
| `realmd`（账号库） | ✅ **选择性迁三张表**：`account`、`account_banned`、`realmcharacters` | 账号要能登录；`SRP6` 密码材料（`v` = verifier、`s` = salt 两列）随行走，**玩家用原密码直接登录，无需重置**（`sessionkey` 是过期会话键，随行无害，登录时会重写）。**不迁** `realmlist`——那是目标服自己的 realm 注册表（地址/端口/RealmID），迁了会把登录导流到源机器 |
| `mangos`（世界库） | ❌ **不迁** | 目标服由 InstallFullDB 自行生成（Full_DB + Updates + ACID）；版本由 core updates 机制对齐。见下节"唯一例外" |

版本表说明：`character_db_version` 随整库替换一起过来（它是链式改名的 revision 列），导入后用 InstallFullDB `3) Install core updates only` 推进到目标 core 所需版本——这正是官方升级机制设计好的路径。

## 2. playerbots 开发者专节：什么时候才需要动世界库？

**日常开发不需要**。playerbots 的数据分两半：

- **动态数据**（11 张 `ai_playerbot_*`）全在 `characters` 库——bot 角色、名字缓存、`ai_playerbot_custom_strategy`（玩家教 bot 的自定义策略）、随机 bot 记录等——**随角色库迁移自动走**；
- **静态参考数据**（12 张 `ai_playerbot_*`）在 `mangos` 世界库——travel_nodes 寻路节点、weightscales 装备评分、enchants、zone_level 等级映射——它们由 `playerbots/sql/world/` 的 SQL 在装库时进入目标服（InstallFullDB 开 `PLAYERBOTS_DB="YES"` 即自动），**开发迭代时通常不变**。

**唯一需要动世界库的情形**：你在开发中修改了 `playerbots/sql/world/` 下的 SQL（新增/修改静态参考数据）。此时**不要整库迁移 world**，只需把改动的 SQL 文件在目标服重放（InstallFullDB `5) Advanced → 8) Create and fill playerbots db`，或直接 `mysql classicmangos < <改动的.sql>`）。快速判断：

```bash
git -C playerbots diff --name-only | grep "^sql/world/"   # 有输出 = 迁移时要在目标服重放这些文件
```

## 3. 迁移流程四步

```
① 源端：停服（或确保无人在线的低峰）
        bash scripts/70-export-character-data.sh          # 产出三件套（见脚本说明）
② 传输：把三个文件拷到目标机（scp / U 盘均可）
        scp wow-characters-* wow-realmd-tables-* *.manifest.txt user@<目标机>:
③ 目标端前置：InstallFullDB 已完成（步骤 4）且 mangosd/realmd 已停
④ 目标端：bash scripts/80-import-character-data.sh <dump文件...>
        → 版本守门 → 逐字确认词 → 替换导入 → 自动验证计数
   事后：InstallFullDB 选 3) Install core updates only（仅当版本守门提示需要时）
        → scripts/60-start-server.sh 启动 → 拿一个号实测登录
```

## 4. 版本方向与守门（重要，读一遍再动手）

mangosd 启动时对 `character_db_version` 的校验是 **FATAL**（core `src/mangosd/Master.cpp`：校验失败直接退出进程；revision 列由每次 update 链式改名，等价于精确版本匹配）。因此方向必须满足：

- **源版本 ≤ 目标 core 版本** → 可迁：导入后 InstallFullDB `3)` 会沿 update 链把表结构推进到目标所需版本（数据比核心旧是官方支持的升级方向）；
- **源版本 > 目标 core 版本** → **80 号脚本拒绝导入**（数据比核心新，update 链无法回退，强行导入后目标 mangosd 必然启动失败）。此时正确做法是先升级目标服 core（`git pull` + 重编译）再迁移。

80 号脚本的守门就是解析两侧 revision 列名中的 `z数字` 做这个比较（例：源 `required_z2819_…` vs 目标 `required_z2837_…`，z2819 ≤ z2837 → 绿灯）。

## 5. 替换语义与种子账号（预期行为，不是 bug）

目标服装库后自带的 4 个**种子账号**（`ADMINISTRATOR` / `GAMEMASTER` / `MODERATOR` / `PLAYER`，id 1-4，密码同用户名小写）会被 `80` 号导入前的 TRUNCATE 清掉、由源服账号集取代——**登录名与密码一律以源服为准**。`realmcharacters`（账号-角色计数）随迁重建计数；`realmlist` 保持目标服不动（realm 名称、地址与 `mangosd.conf` 的 `RealmID` 对应关系不受迁移影响）。

## 6. 导入后的验证清单

80 号脚本会自动跑前四条；后两条人工：

```bash
mysql -uroot -p -N -e "SELECT COUNT(*) FROM classicrealmd.account;"                 # ≈ 源服账号数
mysql -uroot -p -N -e "SELECT COUNT(*) FROM classiccharacters.characters;"          # ≈ 源服角色数
mysql -uroot -p -N -e "SELECT COUNT(*) FROM information_schema.tables \
  WHERE table_schema='classiccharacters' AND table_name LIKE 'ai_player%';"          # 11
# —— 人工 ——
# 启动后用任意一个源服账号的原密码登录一次
# 上号后抽查：背包物品、任务日志、bot（/w <bot> follow）
```

## 7. 注意事项汇总

- **mangosd/realmd 运行中禁导入**（80 号会检测 8085/3724 端口并拒绝——运行中替换库等于给活进程抽地板）；
- 导出参数 `mysqldump --lock-all-tables --default-character-set=utf8 --hex-blob`：混合引擎（InnoDB+MyISAM）决定用全局读锁（导出期间源服写入阻塞，选低峰/停服）；`--hex-blob` 保护 `item_instance` 等二进制列不因文本化损坏；
- 两库均 `utf8`（MySQL 8 显示为 utf8mb3，同一物）；**零外键、零视图、零触发器**——导入无顺序依赖，mysqldump 默认行为即可；
- 若源服与目标服的 `playerbots`/core 同为最新 master，版本守门将直接打"相等、无需 core updates"。

## 8. 坑位速查（迁移相关）

| 现象 | 处置 |
|---|---|
| 迁移后账号登录被拒 | 80 号是按"表级 dump + TRUNCATE"迁的 `account`——检查源 dump 是否含 `v`/`s` 两列（同栈必然含）；若源服密码曾被玩家改过而 dump 早于该变更，重导一次新 dump |
| mangosd 启动报 `You have ... You need ...`（db_version 不匹配） | 版本方向问题——按第 4 节：源旧于目标跑 `InstallFullDB 3)`；源新于目标先升级目标 core |
| 导入后 bot 不动/缺表 | `ai_playerbot_*` 应有 11 张（characters 库）——少了说明源服 dump 早于 playerbots 安装，目标补跑 InstallFullDB `5) Advanced → 8` 后重导 |
| 登录选服列表空/指到源机 | 误迁了 `realmlist`（本文策略不会发生——按本脚本迁移则检查是否手动动过 realmd） |
