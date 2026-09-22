# 07 · 客户端接入与开始游戏

> 走到这里说明：编译 ✅、四库 ✅、playerbots 表 ✅、数据目录 ✅、服务双进程 ✅。最后一步是拿到**客户端本体**（在此之前的一切环节只需要客户端的 Data/ 目录甚至不需要）。

## 1. 客户端版本要求

- **1.12.1 (build 5875) / 1.12.2 (6005) / 1.12.3 (6141)** 任一（core 的 `EXPECTED_MANGOSD_CLIENT_BUILD` 三者兼备，`classicrealmd.realmlist` 的 `gamebuild` 默认 5875；若用 6005/6141，对应列示在 realm 行即可）；
- zhCN / zhTW / enUS / enGB … 任一语言版本均可（build 号一致即可）；
- 客户端需**自备**（版权属 Blizzard，开源社区不分发；本指导仅供个人本地研究）。

## 2. 指向你的服务器

在客户端目录的 `Data/<locale>/`（locale 为 `zhCN` / `enUS` 等）下找到 `realmlist.wtf`，内容改成：

```text
set realmlist <服务器IP>
```

- 客户端与服务器同一台机器：`set realmlist 127.0.0.1`
- 局域网另一台机器：`set realmlist <服务器局域网IP>`（同时服务器防火墙放行 `3724` 与 `8085`，见下）

单机防火墙放行（如 ufw 开启时）：

```bash
sudo ufw allow 3724/tcp     # realmd（登录）
sudo ufw allow 8085/tcp     # mangosd（世界）
```

> 服务器与客户端分离部署时，`classicrealmd.realmlist` 表中 realm 的 `address` 也要写服务器的对外 IP（默认 127.0.0.1，仅本机可用）。

## 3. 启动并登录

1. **直接运行游戏主程序**（Windows：`wow.exe`；不要用 launcher——launcher 试图连官方更新）；
2. 用 `06` 中 `account create` 建的**用户名 + 密码**登录（不是邮箱）；
3. 选服 → 建角色 → 进入艾泽拉斯。

## 4. playerbots 上手三步

（详细指令与配置见 playerbots 仓库内文档）

1. 同一账号的**其他角色自动可成为 bot**——登录后用密语指令操控，例如：

   ```text
   /w <bot角色名> follow        （跟随自己）
   /w <bot角色名> attack        （攻击当前目标）
   /w <bot角色名> stay          （原地待命）
   /w <bot角色名> leave         （下线该 bot）
   ```

2. 世界里也会出现**随机 bot**（由 `aiplayerbot.conf` 的 `MinRandomBots/MaxRandomBots` 决定在线数量）——可邀请组队下副本、配进战场；
3. 首次启动时 bot 需要生成装备/名称等数据（见 06 的提示）。

> 快速入门指令（follow / attack / quest share 等）与 command list 原文：playerbots 仓库 `README.md` 及其链接。

## 5. 日常开关机（单机玩法）

开机顺序：MySQL（systemd 随系统自启）→ `realmd` → `mangosd`；关机反序（见 06 第 6 节）。管理/传送等 GM 指令（`.tele`、`.lookup`、`.npc info` 等）在官效 wiki 的 GM 命令页可查——`account set gmlevel 用户 3` 的号全部可用。

## 6. 版权与用途声明

- 服务端三件套为 GPL 开源项目（core GPL-2.0 / classic-db GPL-3.0 / playerbots GPL）；
- 客户端及全部游戏数据版权归 Blizzard 所有——请自备合法客户端；
- 本项目仅用于个人本地研究与学习，请勿公开运营。
