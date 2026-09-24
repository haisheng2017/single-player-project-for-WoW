# 05 · 数据库：MySQL 就绪与 InstallFullDB 全流程

> 预备脚本：`scripts/40-prepare-database.sh`（需 sudo）。本篇是坑最密集的一篇——三仓库里 `classic-db` 的 `InstallFullDB.sh` 是交互式菜单设计，菜单流转的每一步陷阱都有实名记录在案。

## 1. MySQL 就绪与 Ubuntu 特有大坑（auth_socket）

Ubuntu 打包的 `mysql-server`（8.0.x）的 root 账号默认使用 **`auth_socket`** 插件：

- `sudo mysql` 能进（凭 Linux root 身份）；
- `mysql -uroot -p` 一律拒绝（socket 插件不认密码）——**`InstallFullDB.sh` 的 root 认证因此必然失败**。

处理（把 root 改回密码登录）：

```bash
sudo mysql
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '<你的新密码>';
FLUSH PRIVILEGES;
exit
mysql -uroot -p -e "SELECT 1;"    # 验证：密码登录应通过
```

> root 密码忘了的重置法（简版）：`systemctl stop mysql` 后 `mysqld --skip-grant-table --skip-networking &` → 免密 `mysql -uroot` → `FLUSH PRIVILEGES;` + `ALTER USER ...` → `kill` 手动进程 → `systemctl start mysql`。

脚本 `40-prepare-database.sh` 会自动检测 auth_socket 并引导完成上述转换。

## 2. classic-db 的一键流（交互菜单）

```bash
cd <classic-db 仓库>
bash InstallFullDB.sh
```

**首跑**：生成 `InstallFullDB.config` 后进入设置菜单。Ubuntu 自带 bash 5.x 直接跑（脚本对老 bash 有降级检测分支，无需换 bash）。

### 关键配置变量（`InstallFullDB.config`）

| 变量 | 默认 | 说明 |
|---|---|---|
| `MYSQL_HOST / MYSQL_PORT` | `localhost` / `3306` | MySQL 连接位置 |
| `MYSQL_USERNAME / MYSQL_PASSWORD` | `mangos` / `mangos` | 装库使用的应用账号（脚本会用 root 建）——**公开默认值，建议改掉**并同步到 `mangosd.conf`/`realmd.conf`（见 06） |
| `WORLD_DB_NAME` 等 4 个库名 | `classicmangos` / `classiccharacters` / `classicrealmd` / `classiclogs` | 与 core 配置文件默认值一致，一般不动 |
| `CORE_PATH` | 自动探测 | 脚本会在自身及上级 5 层内找名字含 `classic` 的核心目录——三仓库同级摆放即自动命中 `../mangos-classic` |
| `PLAYERBOTS_DB` | `NO` | **改成 `"YES"`** 才会顺带导入 playerbots 的 SQL（脚本 `40` 号会自动追加/改写；手动即在文件**末尾**加一行 `PLAYERBOTS_DB="YES"`——后写的同名行覆盖先生成的默认） |
| `AHBOT` | `NO` | 改成 `"YES"` 会顺带导入 core 的 `sql/base/ahbot/`（游戏内 `.ahbot` 命令的 `command` 表行，配合 30 号默认的 `BUILD_AHBOT=ON`）——同样由脚本 `40` 号兜底 |

### 菜单流转（实机逐步记录）

```
InstallFullDB 首跑
└─ 设置菜单：报 ERROR 1045 (Access denied for user 'mangos') —— 正常！mangos 用户此刻还不存在
   ├─ 选 2) Set root access
   │    Enter MySQL root user...........  root        （要手敲，直接回车=空用户名必失败）
   │    Enter MySQL root password.......  <root 密码>  （静默输入，屏幕无任何回显，输完回车）
   │    → 校验通过，回到菜单；"9) Exit" 变为 "9) Go to main menu"
   └─ 选 9
      （有的脚本版本此处先出现引导菜单：
         1) Full default CMaNGOS-core and Classic-DB installation ...
         Info: If its your first DB installation you can safely choose option 1 ...
       新装机可以选 1；按编号选项走完整控制则选 9) Return to main menu）
      → 主菜单：
         选 4) Full installation (root)
            → 子菜单：选 1) Full default CMaNGOS-core and Classic-DB installation (all DB with MySQL user)
            确认提示（全程唯一）："All previous changes will be lost. Type 'DeleteAll' if you are sure"
            —— 逐字敲提示词，不是 y/N！
            随后自动串行完成，全程再无任何确认：
              创建四个库 → 创建 mangos 用户授权 → 全量 Full_DB → 增量 Updates
              → core 侧 sql/updates → playerbots SQL（world、world/classic、characters 三组，
              由 config 的 PLAYERBOTS_DB="YES" 静默并入）→ .ahbot 命令表（由 AHBOT="YES" 并入）
```

⚠️ **确认词的真坑（实战出现过）**：

1. 所有 `Type 'XXX' if you are sure:` 提示必须**逐字敲提示词**——直接回车被视为"否"，而且**静默跳过该环节、周围其他环节照常继续**；
2. **playerbots 的"静默跳过"风险不在确认词**（全装路径没有 'Mangosbots' 一词——它只存在于下述补装路径），而在 `PLAYERBOTS_DB` 当时不是 `YES`（例如 40 号没跑过、config 被还原）：跳过时**无任何报错**，四库看似完美，实际 `ai_playerbot_*` 表数为 0——症状极隐蔽。40 号重跑后的自动验收（见下节）或手工验证查询能查出。补装：`5) Advanced DB management → 8) Create and fill playerbots db`（该路径才有 `'Mangosbots'` 确认词）——注意：对**已经装过** playerbots 的库二次重放会撞 `ERROR 1061` 索引重名，先执行下面的 DROP 再重放：

```sql
-- world 库（classicmangos）执行：回收上一次 playerbots 加在核心表上的 8 个索引
-- （重放步骤只重建模块自己的表、从不回收这些索引；此清单与
--   playerbots/sql/world/ai_playerbot_indexes.sql 的 8 条 create index 一一对应）
DROP INDEX idx_gameobject_loot_template_item     ON gameobject_loot_template;
DROP INDEX idx_disenchant_loot_template_item    ON disenchant_loot_template;
DROP INDEX idx_fishing_loot_template_item       ON fishing_loot_template;
DROP INDEX idx_item_loot_template_item          ON item_loot_template;
DROP INDEX idx_pickpocketing_loot_template_item ON pickpocketing_loot_template;
DROP INDEX idx_reference_loot_template_item     ON reference_loot_template;
DROP INDEX idx_skinning_loot_template_item      ON skinning_loot_template;
DROP INDEX idx_creature_loot_template_item      ON creature_loot_template;
```

### 完成后的验证

装库完成后 **`sudo` 重跑 `scripts/40-prepare-database.sh` 即自动验收**：脚本用 `InstallFullDB.config` 里的 mangos 账号直连 MySQL，逐项检查并打印 `[OK]/[MISSING]`，全绿后提示进入 60 号。等价的手工检查（数字口径与脚本一致）：

```bash
# 四库表数量（供参照的量级：world 数百张、characters 数十张、realm 十余张、logs 3 张）
mysql -uroot -p -e "SELECT table_schema, COUNT(*) FROM information_schema.tables \
                    WHERE table_schema LIKE 'classic%' GROUP BY table_schema;"
# world 内容抽查（应为上万行量级）
mysql -uroot -p -e "SELECT COUNT(*) FROM classicmangos.creature_template;"
# playerbots：world 静态表应 12 张、characters 动态表应 11 张（0 = 上面第 2 坑）
mysql -uroot -p -N -e "SELECT table_schema, COUNT(*) FROM information_schema.tables \
    WHERE (table_schema='classicmangos'    AND table_name LIKE 'ai_player%') \
       OR (table_schema='classiccharacters' AND table_name LIKE 'ai_player%') \
    GROUP BY table_schema;"
# 8 个战利品索引应 8（不全 = 索引文件中途失败，按上面"确认词的真坑"第 2 条的 DROP 清单先回收再重放）
mysql -uroot -p -N -e "SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema='classicmangos' \
    AND index_name IN ('idx_gameobject_loot_template_item','idx_disenchant_loot_template_item','idx_fishing_loot_template_item', \
    'idx_item_loot_template_item','idx_pickpocketing_loot_template_item','idx_reference_loot_template_item', \
    'idx_skinning_loot_template_item','idx_creature_loot_template_item');"
# .ahbot 命令行应 4（0 = 装库时 AHBOT 未 YES；可单独补：mysql classicmangos < mangos-classic/sql/base/ahbot/mangos_command_ahbot.sql）
mysql -uroot -p -N -e "SELECT COUNT(*) FROM classicmangos.command WHERE name LIKE 'ahbot%';"
```

> 表数量的实测口径：playerbots 入库共 **world 12 + characters 11 = 23 张 `ai_playerbot_*`**（world = `ai_playerbot_texts.sql` 3 + `rpg_races` 1 + `world/classic/` 8；characters = `sql/characters/` 6 个文件，其中 `ahbot_*` 3 张表不带 `ai_player` 前缀、另计）+ `command` 表 4 行 `.ahbot` 命令。

## 3. 版本对应关系（原理，理解后可自查）

- core 构建时把所需的数据库 revision 打进二进制；启动时校验各库 `db_version` 表；
- `InstallFullDB.sh` 装好的库与其安装日的 core 修订号对齐；**先装库后取源码更新**的场景，菜单 `3) Install core updates only`（或重跑脚本）会把 core `sql/updates/` 增量补齐；
- 正常情况下无需关心；看到 `db_version` 不匹配的报错时，按提示跑 core updates 即可。

## 4. 版权与替代品

classic-db 由社区多年整理（GPL v3 + 内容版权声明见其 `COPYRIGHT.md`）；MariaDB 与 MySQL 8.0 可互换使用（apt 中把 `mysql-server` 换成 `mariadb-server` 即可，客户端工具同名兼容）。

下一篇：`06-configure-and-run.md` —— 配置、启动、建号。
