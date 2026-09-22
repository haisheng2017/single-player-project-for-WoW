# 06 · 配置、启动与建号

> 启动脚本：`scripts/60-start-server.sh`（realmd 后台 + mangosd 前台控制台）。

## 1. 生成正式配置文件（去 `.dist` 后缀）

```bash
cd <WOW_ROOT>/run/etc
cp mangosd.conf.dist   mangosd.conf
cp realmd.conf.dist     realmd.conf
cp anticheat.conf.dist  anticheat.conf
cp aiplayerbot.conf.dist aiplayerbot.conf    # playerbots 模块已随 make install 装入本目录
```

## 2. 必要检查项

`mangosd.conf`（其余保持默认即可单机运行）：

- **数据库连接**（三/四条 `*DatabaseInfo`，分号分隔：`地址;端口;用户;密码;库名`）：

  ```text
  LoginDatabaseInfo     = "127.0.0.1;3306;mangos;mangos;classicrealmd"
  WorldDatabaseInfo     = "127.0.0.1;3306;mangos;mangos;classicmangos"
  CharacterDatabaseInfo = "127.0.0.1;3306;mangos;mangos;classiccharacters"
  LogsDatabaseInfo      = "127.0.0.1;3306;mangos;mangos;classiclogs"
  ```

  若装库时改过 `MYSQL_USERNAME/MYSQL_PASSWORD`（建议改），这里与 `realmd.conf` 的 `LoginDatabaseInfo` 要同步；
- `DataDir = "."`——相对进程工作目录；**从 `run/bin` 启动时即指向 `run/bin`**，四个数据目录正是放在这里（默认值即正确，一般无需改动）；
- `RealmID = 1`——须与 `classicrealmd.realmlist` 中 `id=1` 的行对应（默认一致）。

`aiplayerbot.conf`：

- `AiPlayerbot.Enabled = 1`（模板默认已开）；bot 数量/行为的海量可调项（`MinRandomBots/MaxRandomBots` 等）参考 playerbots 仓库的 README 与官方 wiki 的 Playerbots 章节，先用默认体验即可。

## 3. 启动（两条铁律）

**铁律一：必须以 `run/bin` 为工作目录启动。** `aiplayerbot.conf`/`realmd.conf` 由各进程按"工作目录相对路径"（`../etc/`）自动加载（core 顶层 `if(UNIX)` 定义的 `SYSCONFDIR`；playerbots 源码 `PlayerbotAIConfig.h` 同理）——别的目录启动时配置静默失效、playerbots 静默关闭。没有（也不需要）为 aiplayerbot 传配置的命令行参数；顺带消除一个常见误配：`-a` 参数是给 `ahbot.conf` 用的，与 playerbots 无关。

**铁律二：realmd 先起、mangosd 后起**（mangosd 上线时要向 realmd 后的 realm 列表注册自己）。

```bash
cd <WOW_ROOT>/run/bin
./realmd  -c ../etc/realmd.conf     # 终端 1（安静挂着即正常）
# 新开终端 2：
ss -ltnp 'sport = :3724'           # 验证 realmd 监听
./mangosd -c ../etc/mangosd.conf   # 前台运行，控制台可用
```

`60-start-server.sh` 内置了上述顺序与端口自检，并以 `nohup` 后台拉起 realmd（日志 `run/log/realmd.log`）。

## 4. 启动日志的检查点（判断"一切正确"）

`mangosd` 开机输出应依次出现：

```text
四个库各 2 条连接全部成功（World / Character / Login / Logs，含 MySQL 客户端/服务端版本行）
Realm running as realm ID 1
Using World DB: Classic DB version 1.12.1 "Melting Pot v2" ...
（ScriptDev2 / ACID 脚本加载）
```

然后分两种结局：

| 结局 | 含义 | 动作 |
|---|---|---|
| `Check existing of map file './maps/XXXX.map': not exist!` + **"Correct \*.map files not found"** + 10 秒倒计时后退出 | **服务器其余全部正确的标志**（编译产物、数据库链路、配置解析、realm 注册）——缺的只是四个数据目录 | 回 `04-extract.md` 补数据 |
| 继续加载地图与副本模板，最后进入控制台待命 | 数据齐备，正式开工 | 下一步建号 |

> 首次带随机 bot 启动时，前几分钟在批量生成/装备 bot 角色（磁盘/CPU 有持续活动），属正常现象，等它忙完。

## 5. 建号（mangosd 控制台）

```text
account create <用户名> <密码>
account set gmlevel <用户名> 3     # 0 玩家 / 1 Moderator / 2 GM / 3 Administrator
```

playerbots 的进阶用法（把小号带成 bot、随机 bot 组队、指令表等）见 playerbots 仓库 README——先建一个号、进一次游戏，角色相关的 bot 玩法再展开。

## 6. 关服顺序

mangosd：控制台 `.server shutdown 30`（或 Ctrl-C）；realmd：`pkill realmd`。玩家数据实时落库（`classiccharacters`），关服即已保存；备份用 `mysqldump`（见 `troubleshooting.md`）。

下一篇：`07-client.md` —— 客户端接入与开始游戏。
