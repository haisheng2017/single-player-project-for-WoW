# 14 · 配置语义全解（每份 conf、每个键族的字典）

> 前置：`docs/06`（必检项与启动）、`docs/15`（运维与玩法手册——本文管"是什么、动了会怎样"，15 管"照抄就能用"）。写给我的部署面：四份主 conf（mangosd/realmd/anticheat/aiplayerbot）+ 五份功能模块 conf，全部**以本 fork 出厂模板为基准**（写作时四份主 conf 与 .dist 逐字节一致——你还没改过任何值）。

**版本边界**：所有键名/默认值逐字核自 `run/etc/*.conf` 本体（与 .dist 同源，行号为锚）；行为断言核自源码时会标代码锚。体量先给你个底数：`mangosd.conf` 332 键 / `realmd.conf` 22 / `anticheat.conf` 139 / `aiplayerbot.conf` 55 个通用键 + 概率表 130 键、再往后是 **3206 键的装备进阶巨表** / 五模块 7+2+8+1+43。

## 1. 全景：八份 conf 各归其主，生效方式三六九等

```
 服务器进程（run/bin 起的三口之家）
 ├─ realmd  ──────── realmd.conf（22 键）登录/选服/反爆破
 └─ mangosd ┬─────── mangosd.conf（332 键）世界服务器本体
            ├─────── aiplayerbot.conf（模块会话启动读一次）bot 总管
            ├─────── anticheat.conf ⚠️本 fork 休眠（见 §4）
            └─────── transmog/dualspec/achievements/barber/immersive
                     五份模块 conf（各模块自己读，路径 ../etc/ 解析）
 Docker/宿主形态差异不改变 conf 内容，只改你从哪里编辑（docs/15）
```

**生效方式总表**（最重要的一张——改错地方以为没生效是第一大困惑）：

| 改的是 | 怎么才生效 |
|---|---|
| `mangosd.conf` 的**世界侧键**（rates/视距/Motd/聊天/GM/尸体……几乎全文件） | 游戏内 `.reload config`（管理员级）**热载**，广播 "World config settings reloaded."；或重启 |
| `mangosd.conf` 的端口/DB 连接/线程/网络/Console/Ra/SOAP 键 | **只能重启**（`.reload config` 不触及初始化类） |
| `aiplayerbot.conf` 任何键 | **只能重启**（模块只在启动读一次） |
| 五份模块 conf | **只能重启**（docs/09 §5 同口径） |
| `realmd.conf` 任何键 | **只能重启 realmd 进程**（它无控制命令面） |
| `anticheat.conf` | 见 §4——本 fork 构建里**休眠**，重启也不生效 |

> 环境变量覆盖法（三份 conf 头部注释自述）：`export Mangosd_Rate_Health=1.2`、`Realmd_WrongPass_MaxCount=10`、`Anticheat_Enable=0`——键名规则是把 `.`/`-` 换 `_` 前面冠进程名。改文件之前想临时试一个值时很顺手。

**安全级图例**（贯穿全文的行尾标注）：`【守恒】`默认即正解别动 ／ `【常调】`单机玩家的常规旋钮 ／ `【高风险】`改世界观的键，一次只动一个并记基线。

## 2. mangosd.conf——世界服务器（332 键，17 族）

### 2.1 连接与目录（:81-96）【守恒】

| 键（默认） | 语义 |
|---|---|
| `RealmID = 1` | 本服在 `realmlist` 表里的行号，realmd 按它把人送进"哪个世界" |
| `DataDir = "."` | 四数据目录（maps/vmaps/mmaps/dbc）的根；**必须以 run/bin 为 CWD 启动**才解析对（docs/06 铁律） |
| `*DatabaseInfo = "127.0.0.1;3306;mangos;mangos;<库名>"` ×4 | 四库连接（realmd/mangos/characters/logs）；换库搬家用 |
| `*DatabaseConnections = 1` ×4 | 每库的额外只读连接数；单机 1 够 |
| `WorldServerPort = 8085` | 世界服端口（客户端连的就是它） |
| `BindIP = "0.0.0.0"` | 监听地址；注释原话警告别乱改 |
| `MaxPingTime = 30` | DB 保活 ping 分钟 |
| `LogsDir = ""` | 日志目录前缀；空=写到进程 CWD（run/bin） |
| `SD2ErrorLogFile` / `Spawns.ZoneArea = 0` | 脚本错误日志名 / 启动重建 zone 表 |

### 2.2 性能与地图（:250-279）——单机调优核心区【混：多数常调】

| 键（默认） | 语义与单机视角 |
|---|---|
| `Compression = 1` | 发往客户端的压缩级 1-9；1 最快 9 最省带宽。本机/局域网玩保持 1 |
| `PlayerLimit = 100` | 世界在线上限——**bot 也占用此配额**（bot 是真角色）。单机+千人 bot 环境建议 0（无限制）或负值（-1/-2/-3=仅 Mod/GM/Admin 可进） |
| `MaxOverspeedPings = 2` | 超速嫌疑累计几次踢人；0=关。bot 走位若被误判可临时关 |
| `GridUnload = 1` | 空网格卸载（省内存 ↔ 重进图慢）。大内存机器改 0 常驻 |
| `LoadAllGridsOnMaps = ""` | 指定图开机全载网格（实验性、极耗资源） |
| `GridCleanUpDelay = 300000` / `Autoload.Active = 1` | 网格清理延迟 / 主动加载开关 |
| `MapUpdateInterval = 100` | 地图更新拍长（ms） |
| `MapUpdate.Threads = 3` | 地图线程数——**不得超过 CPU 线程数-1**（注释原话）。度身定制你的机器 |
| `ChangeWeatherInterval = 600000` | 天气步进 |
| `PlayerSave.Interval = 900000` | 角色自动存盘（15 分钟）。怕崩溃丢进度可缩到 5 分钟 |
| `PlayerSave.Stats.MinLevel = 0` / `.SaveOnlyOnLogout = 1` | 外部统计存档的最小等级/仅登出时存——统计用，无游戏影响 |
| `SaveRespawnTimeImmediately = 1` / `UpdateUptimeInterval = 10` / `MaxWhoListReturns = 49` | 重生时间即时写库 / uptime 表刷新（分）/ who 列表返回数 |
| `vmap.enableLOS/enableHeight/enableIndoorCheck = 1` | 视线/高度/室内判定仨开关——**全关=穿墙怪/隔墙施法/贴地判定全坏**【守恒】（机理见 docs/13） |
| `mmap.enabled = 1` / `ignoreMapIds = ""` / `preload = 0` / `PathFinder.OptimizePath = 1` / `NormalizeZ = 0` | 寻路族——字典不重复 docs/13 §7-§8 的语义与代价表 |
| `DetectPosCollision = 1` | 移动/召唤落点碰撞校验；关=省 CPU 换落点不规矩 |
| `MaxCoreStuckTime = 0` | 主循环卡死 N 秒自杀（0=关）。挂机党可设 60 保命 |
| `AddonChannel = 1` | 插件通信通道（关了部分插件失灵） |
| `CleanCharacterDB = 1` / `BeepAtStart`（在 2.4） | 启动清角色库孤儿数据 |
| `UseProcessors = 0` / `ProcessPriority = 1` | 仅 Windows 生效 |

### 2.3 日志系统（:417-453）【常调】——全部只读记录，开了不伤世界

| 键（默认） | 语义 |
|---|---|
| `LogLevel = 1` | **控制台**详略（0/1/2/3=极简/错误/细节/调试）；排障临时拉 2-3 |
| `LogFile = "Server.log"` + `LogFileLevel = 0` | 文件名与文件级（**与控制台级独立**——文件想吃细节必须也把 FileLevel≥2；出厂 0=文件只有错误级） |
| `LogTime = 0` / `LogTimestamp = 0` | 控制台行加时间 / 文件名加启动时戳 |
| `LogColors = ""` | 控制台四色 "normal detail debug error"，0-14 色号，例 `"13 7 11 9"` |
| `LogSQL = 1` | GM 命令产生的 SQL 每日落 `YYYY-MM-DD_logSQL.sql`——**误操作的回滚保险** |
| `LogFilter_*` ×18（多数=1） | 分类刷屏日志闸：**1=抑制 0=放行**（这族语义反直觉）；Pathfinding/MapsLoading 的用法见 docs/13 §7 证三 |
| `DBErrorLogFile` / `EventAIErrorLogFile` / `CharLogFile` | `DBErrors.log`（库层错—排查第一入口）/ `EventAIErrors.log` / `Char.log`（角色操作流水） |
| `CharLogDump = 0` | 删号前把角色全量数据写进 Char.log——**单机强烈设 1**（配合 loadpdump 可救回手滑的删号） |
| `GmLogFile = ""` (+`Timestamp`/`PerAccount`) | GM 命令日志；设个文件名即开 |
| `RaLogFile = ""` / `WorldLogFile = ""` / `PacketLogFile = ""`(+WorldLogTimestamp) | RA 命令日志 / 世界包日志 / 抓包(.pkt)——默认全关 |
| `PidFile = ""` | 写 PID 文件（自管启停脚本用得上） |

### 2.4 服务器规则（:812-877）——六子族

**a) 阵营/语言/命名**【高风险区】

- `GameType = 1`——**本服出厂即 PVP 服**（阵营中立区可被杀）；要 PvE 服改 0；16=FFA。`RealmZone = 1` 命名字符集区域（16=China）；`DBC.Locale = 255`；`DeclinedNames = 0` 俄语名字格位支持。
- `StrictPlayerNames/StrictCharterNames/StrictPetNames = 0`（2=按 RealmZone 严格限制）；`MinPlayerName/MinCharterName/MinPetName = 2`——**想用中文单字名**：最小长度 2 会挡，可改 1（配合 RealmZone 中文区）。

**b) 建号与角色**【常调】

- `CharactersCreatingDisabled = 0`（1=禁联盟 2=禁部落 3=全禁）；`CharactersPerAccount = 50` / `CharactersPerRealm = 10`（客户端硬上限 10）。
- `SkipCinematics = 0`——2=永不放开场动画（单机刷号神器；自定义出生点时还能防 bug）。
- `StartPlayerLevel = 1` / `StartPlayerMoney = 0`——开局等级（铜币单位。100=1银）。
- `MaxPlayerLevel = 60`【守恒】（1-100 可写但注释原话"Change not recommended"，改坏天赋/技能公式与任务链）。

**c) 成长与荣誉**
- `MaxHonorPoints = 75000` / `StartHonorPoints = 0` / `MinHonorKills = 15`（周结算最低击杀） / `MaintenanceDay = 3`（**荣誉周结算发奖日**，0=周日…3=周三；勘误：代码默认是 4（周四），conf 这行 3 才是生效值，见 World.cpp:565 + docs/16 §4）【常调、动前想清楚】。

**d) 便利 QoL**——单机爽点最密的一格【常调】
- `InstantLogout = 1`（0-4：安全等级达 X 及以上可站秒退——非战斗时）；`DisableWaterBreath = 4`（水下呼吸豁免的等级门槛；注释含糊、平常不动）。
- `AlwaysShowQuestGreeting = 0`；`TaxiFlightChatFix = 0`（修复登录续飞时频道丢失的客户端 bug）；`LongFlightPathsPersistence = 0`。
- **`AllFlightPaths = 0`→开号即全航线**（1=开；注释原话"ALL flight paths, not only player's team"=连对面的点也给——注释里 true/false 括号是上游的著名错乱，以语义行为准【爽点】）。
- `AlwaysMaxSkillForLevel = 0`（1=登录/升级自动满武器与防御技能【爽点】）。
- `ActivateWeather = 1` / `CastUnstuck = 1` / `MaxSpellCastsInChain = 20`（连锁触发法术上限，防栈崩）【守恒】。
- `RabbitDay = 0`——愚人节彩蛋日（unix 时间戳，年无关；建议值 954547200=4 月 1 日）。

**e) 副本规则 `Instance.*`**【常调——单机下本钥匙串】
- `IgnoreLevel = 0` / `IgnoreRaid = 0`——各改 1 = 允许越级进本 / **单人进团本**。
- `StrictCombatLockdown = 0`（1=区域交战中禁止用假死等脱战——仿 2.3.0 后行为）；`ResetTimeHour = 4`（每日几点全局重置副本）；`UnloadDelay = 1800000`（图空 30 分钟卸载；0=常驻）；`DisableRelocate = 0`。

**f) 组队/生活/杂项**：`Quests.LowLevelHideDiff = 5` / `HighLevelHideDiff = 7`（改 -1=永远显示所有"!"【爽点】）；`Quests.IgnoreRaid = 0`（1=团内可做普通任务）；`Group.OfflineLeaderDelay = 300`；`Guild.EventLogRecordsCount = 100`；`MirrorTimer.{Fatigue,Breath}.Max = 60`（呼吸/疲劳条的秒数上限）；`EnvironmentalDamage.Min/Max = 605/610`（岩浆每跳伤害）；`InteractionPauseTimer = 180000`（NPC 被对话后暂停走点 ms——**bot 密集世界建议调大**避免 NPC 永远停在玩家堆里）；`MaxPrimaryTradeSkill = 2`（主专业数上限；单机想全专业改 9）；`TradeSkill.GMIgnore.* = 4`×3（GM 无视商业技能限制的等级线）；`MinPetitionSigns = 9`；`MaxGroupXPDistance = 74`；`MailDeliveryDelay = 3600`（**邮件延迟 1 小时。配合 AHBot/自寄想秒到的改 0**）；`MassMailer.SendPerTick = 10`；`PetUnsummonAtMount = 0` / `PetAttackFromBehind = 0` / `AutoDownrank = 0`（1=给低级目标自动降阶 buff，爽点）；`Event.Announce = 0`；`BeepAtStart = 1` / `ShowProgressBars = 0` / `WaitAtStartupError = 0`；**`Motd`**（登录公告，`@` 换行——运行时也可 `.server set motd`）；`PlayerCommands = 1`（聊天是否解析 GM 命令——安全键）。

### 2.5 双阵营互动（:923-933）【常调】
`AllowTwoSide.Accounts`、`Interaction.{Chat,Channel,Group,Guild,Trade,Auction,Mail}`、`WhoList`、`AddFriend` 全=0——把 0 改 1 即解禁对应跨阵营行为。单机"两端号互寄钱/交易"需求就是把 `Trade`+`Mail` 开 1。`TalentsInspecting = 1`（他人能否看你的天赋——**单机锁定什么都行**）。

### 2.6 生物与尸体（:1058-1096）——仇恨助援与"世界难度调音台"
- 进攻面：`Rate.Creature.Aggro = 1`（仇恨半径倍率；**0=全图怪不主动**——单机"逛街模式"或带小号神器）；`CreatureRespawnAggroDelay = 5000`；`LeashRadius = 30`（与 docs/13 §3-4 的 leash 机制联动）。
- 助援面【改世界感】：`CreatureFamilyAssistanceRadius = 5` / `FleeAssistanceRadius = 30` / `AssistanceDelay = 1500` / `FleeDelay = 10000` / `CheckForHelpRadius = 5` / `CheckForHelpAggroDelay = 2000`——喊帮手的半径/延迟族。
- `WorldBossLevelDiff = 3`（队伍等级高于它多少时世界 boss 也拉平等级）。
- 尸体：`EmptyLootShow = 1` / `AllowAllItemsShowInMasterLoot = 1` / `Corpse.Decay.{NORMAL,RARE,ELITE,RAREELITE,WORLDBOSS} = 300/900/600/1200/3600`（未拾取尸体存留秒）/ `Rate.Corpse.Decay.Looted = 0`。
- **难度倍率族【高风险/改前记基线】**：`Rate.Creature.Normal.{Damage,SpellDamage,HP} = 1` ×3 + `Rate.Creature.Elite.{Elite,RARE,RAREELITE,WORLDBOSS}.{Damage,SpellDamage,HP} = 1` ×12——按稀有度给全服怪调攻击/法伤/血量（单机"让世界硬一点"的官方旋钮）。
- 其他：`ListenRange.Say/TextEmote = 25` / `Yell = 300`（NPC 说话可闻半径）；`GuidReserveSize.Creature/GameObject = 10000`（`.npc add` 预留 guid——用尽了要重启）；`CreaturePickpocketRestockDelay = 600`（偷窃补货秒）。

### 2.7 聊天与防水（:1155-1163）【常调】
`ChatFakeMessagePreventing = 0`；`ChatStrictLinkChecking.Severity/Kick = 0`（伪装链接 0-3 逐级严查+踢人）；`ChatFlood.{MessageCount,MessageDelay,MuteTime} = 10/1/10`（N 条/秒 spam → 禁言 M 秒；Count=0 关）——**bot 密集可调大 Count** 或关掉；`Chat.RestrictedRaidWarnings = 1`；`Channel.RestrictedLanguageMode = 0`；`Channel.StaticAutoTreshold = 0`。

### 2.8 GM 设置（:1268-1283）【守恒】
`GM.LoginState/Visible/Chat/WhisperingTo/AcceptTickets = 2`（2=记住上次）；`AcceptTicketsLevel/ChatLevel = 2/1`；`ChannelModerationLevel = 1` / `ChannelSilentJoinLevel = 0`；`InGMList.Level/InWhoList.Level = 3`（几级以上的 GM 不出现在 GM 列表/who 列表——**隐身 GM 仪**）；`LogTrade = 1`；`StartLevel = 1`（GM(.start) 回城等级）；`LowerSecurity = 0`；`InvisibleAura = 31748`（GM 隐身光环号）；`TicketsQueueStatus = 1`。

### 2.9 视距（:1324-1331）【中调】
`Visibility.Distance.{Continents,Instances,BGArenas} = 100/170/533`——视野半径。降=省 CPU，升=更像真服但要权衡（下限=aggro 半径×倍率，上限 533）；`RelocationLowerLimit = 10`（移动过几码才触发可见性更新）【爽点：单机拉大 Continents 到 ~200 看更远】；`AIRelocationNotifyDelay = 1000`（怪对附近移动的反应延迟 ms）【单机务必与 docs/13 §4 的副本追击链一起想】；`FogOfWar.{Stealth,Health,Stats} = 0`（队内可见站位/血条——保持 0 就行）。

### 2.10 世界倍率 SERVER RATES（:1491-1552）——"fun rates" 主旋钮区【常调/高风险记基线】
- 资源：`Rate.{Health,Mana,Rage.Income,Rage.Loss,Focus,Loyalty,Energy} = 1`；`Rate.Skill.Discovery = 1`。
- 掉落：`Rate.Drop.Item.{Poor,Normal,Uncommon,Rare,Epic,Legendary,Artifact,Referenced,Quest} = 1` ×9 + `Rate.Drop.Money = 1`。
- 成长：**`Rate.XP.{Kill,Quest,Explore} = 1` 三键**（低倍/高倍服第一改处）；`Rate.Pet.XP.Kill`；`Rate.Rest.{InGame,Offline.×2} = 1`（双倍经验积累速度）；`Rate.Talent = 1`；`Rate.Reputation.Gain = 1`（+`LowLevel.{Kill,Quest} = 0.2` 低等级声望衰减下限）。
- 拍卖：`Rate.Auction.{Time,Deposit,Cut} = 1` + `Auction.Deposit.Min = 0`。
- 其他：`Rate.Honor = 1`（**⚠️ 本 fork 死键**——解析后无任何消费点，荣誉倍率改了无效；增益走游戏内 `.honor add`，机理见 mangos-classic World.cpp:456 + docs/16 §4）；`Rate.Mining.{Amount,Next} = 1`；`Rate.Damage.Fall = 1`（摔伤倍率。【爽点】改 0=永不摔伤）；`Rate.InstanceResetTime = 1`（团本重置日倍率）。
- 技能【手工党福音】：`SkillGain.{Crafting,Defense,Gathering,Weapon} = 1`；`SkillChance.{Orange,Yellow,Green,Grey} = 100/75/25/0`（升级成功率按难度档）；`SkillChance.{MiningSteps,SkinningSteps} = 0`（随技能衰减次数）；`SkillFail.Loot.Fishing = 0` / `SkillFail.Gain.Fishing = 0`（钓鱼失败给垃圾 / 失败也能涨点）；`SkillFail.Possible.FishingPool = 1`（鱼点必出）。
- 耐久与死亡：`DurabilityLossChance.{Damage,Absorb,Parry,Block} = 0.5/0.5/0.05/0.05`（**全 0=永不磨损**【爽点】）；`Death.SicknessLevel = 11`（≥X 级复活才有虚弱；61=永不）；`Death.CorpseReclaimDelay.{PvP,PvE} = 1`（**改 0=免收尸排队**【单机强推】）；`Death.Bones.World/Battleground = 1`；`Death.Ghost.RunSpeed.World/Battleground = 1.0`（**灵魂跑速可>1**【爽点 1.5】）。

### 2.11-2.17 小族速览
- **战场**（:1595-1601）【守恒】：`CastDeserter = 1`、`QueueAnnouncer.Join/Start = 0`、`ScoreStatistics = 0`、`InvitationType = 0`、`PrematureFinishTimer = 300000`、`PremadeGroupWaitForMatch = 0`。
- **野外 PvP**（:1613-1614）：`OutdoorPvp.{SI,EP}Enabled = 1`——希利苏斯/东瘟疫野外 PvP 开关；Bot 打法单机建议不动。
- **聚会石 LFG**（:1631-1632）：`LFG.Matchmaking = 0`（1=按天赋配坦奶）、`MatchmakingTimer = 600`。
- **网络**（:1661-1665）【守恒】：`Threads = 1`（千连接一线程）、`OutKBuff = -1`、`OutUBuff = 65536`、`TcpNodelay = 1`（关 Nagle 低延迟）、`KickOnBadPacket = 0`。
- **控制台与远管**（:1716-1726）：`Console.Enable = 1`【本机常开即正解】；`Ra.Enable = 0`/`IP = "0.0.0.0"`/`Port = 3443`/`MinLevel = 3`/`Secure = 1`/`Restricted = 1`——telnet 式远端管理，默认关；启用必须限 IP+改端口+防火墙详见 docs/15 安全清单；`SOAP.enabled = 0`/`IP = "127.0.0.1"`/`Port = 7878`——HTTP 管理接口，默认仅本机。
- **删号**（:1751-1753）：`CharDelete.Method = 0`（1=软删链保留名字）、`MinLevel = 0`、`KeepDays = 30`（0=永不物理清除）。
- **监控**（:1785-1790）与 `Dummy.Debug1/2 = 0`：InfluxDB 指标（需 BUILD_METRICS 编译）与两个占位键——【守恒】。

## 3. realmd.conf——登录守门人（22 键，:129-149）

| 键（默认） | 语义 |
|---|---|
| `LoginDatabaseInfo` | 账号库连接 |
| `RealmServerPort = 3724` / `BindIP` / `ListenerThreads = 1` | 登录端口/监听/接线线程 |
| `LogsDir` / `MaxPingTime = 30` / `PidFile` | 日记目录/保活/PID |
| `LogLevel = 0` + `LogFile = "Realmd.log"` + `LogFileLevel = 0` + LogColors/LogTime/LogTimestamp | 与 mangosd 同构的日志四件套 |
| `RealmsStateUpdateDelay = 20` | realm 列表刷新节流（秒） |
| `StrictVersionCheck = 0` | **1=拒绝被修改过的客户端**——汉化/魔改客户端党务必保持 0 |
| `WrongPass.MaxCount = 0` | **密码错 N 次封禁——默认 0=永不**。公网部署必改 10+ |
| `WrongPass.BanTime = 600` / `BanType = 0` | 封禁秒数（0=永久）/ 0=封 IP、1=封账号 |
| `UseProcessors/ProcessPriority/WaitAtStartupError` | Windows 老三样 + 启动报错等待 |

单机四句话：本机玩只关心 `LoginDatabaseInfo`；公网化四连改 = MaxCount>0 + BanType=0 + BindIP 收紧 + 防火墙；`WaitAtStartupError = -1` 用于调试"启动即闪退"（停下等回车）。

## 4. anticheat.conf——本 fork 里它睡着了（139 键）

**先说结论**：这份 conf **当前构建不会被消费**。anticheat 是 core 内置模块（模板 `mangos-classic/src/game/Anticheat/module/anticheat.conf.dist.in`），但其**真实现由编译宏 `USE_ANTICHEAT` 门控**——本 fork 全仓没有任何地方定义它（门控在 `src/game/CMakeLists.txt:27-29`，桩实现 `Anticheat.cpp:1` 的 `#error` 守卫可证，构建产物宏零命中）。于是启动日志里那句 "Loading anticheat library" 加载的是**空桩**，warden_modules 目录虽然拷了也不用。键表照录于此，供将来启用专案或了解各键语义；启用属于编译期工程（改 CMake 定义宏 + 整编），不在 conf 单侧能解决。

- **总开关与惩罚节奏（§ 前段）**：`Enable = 1`、`FingerprintHistory/Level = 30/6`、`KickDelay.Min/Max`、`BanDelay.Min/Max`、`IPBanDelay.Min/Max = 30/90`、**`BanWave.Day/Hour/Minute = 1/10/0`**（定点"爆破"波时间）；动作常量 0x01 通知\|0x02 提示 GM\|0x04 踢\|0x08 封号\|0x10 封 IP\|0x20 禁言，可位或（24=封号+封 IP）。
- **Movement 启发式（24 项）**：每项四件套 `TickCount/TickAction/TotalCount/TotalAction`；覆盖 SpeedHack 总闸、WaterWalk、SlowFall、FlyHack、Forbidden、MultiJump、TimeBack、FastJump、JumpSpeedChange、NullClientTime、RootMove、OverspeedZ、HeartbeatSkip、ClockDesync、Explore×3、ExploreHigh、FixedZ、FakeTransport、TeleToTransport、Tele、TeleportFar、BadOrderAck、BadFallReset，附录一句：`WallClimb` 注释自认**尚未实现**；`UseExtrapolation = 1` 更准更费 CPU。
- **Antispam 反垃圾**：`Enable = 1`、`MaxLevel = 25`（此级以下不查）、`MaxRate = 30` 条/分、`RateGracePeriod = 45`、`MinUniqueMessages = 100`（**配 0 不等于关闭**）、`UniquenessThreshold = 5`（编辑距离判"同一句"）、黑名单/禁言族、Repetition 族（含 `RepetitionSilence = 0`）。
- **Warden 客户端扫描**：`Enable = 1`、`ModuleDir/Timeout = 30/ScanFrequency = 15/ScanCount = 10`、`MinimumLevel = 25`（此级以下只记不罚）、`MinimumAdvancedLevel = 18`、`SuspiciousEndSceneHookAction = 1`（EndScene 钩子=绘图外挂常见注入点）。

**若将来启用**最要注意的是 bot：启发式对 bot 的瞬移/走位误判会真踢真封（Movement 族默认动作码即含踢）。启用前先全族降为仅记录（动作位只留 0x01/0x02），观日志几周再谈惩罚。

## 5. aiplayerbot.conf——bot 总管（55 通用键 + 概率表 + 巨装备表）

体量结构（先看清地形再走）：**L1-1159 通用配置**（其中大多键注释着=用内置默认，改哪个解开哪个）；**L497-760 概率表**（ClassRaceProb ~57 键 + PremadeSpec ~130 键——天赋配装命名表）；**L1160-4866 = `GearProgressionSystem` 一张 3206 键的装备进阶巨表**（默认 `Enable = 0` 整表休眠）。

> **通用阅读法**：本 conf 的"注释值 ≠ 代码默认"有 8 处已证不符（§5.9 勘误表）；凡本文给出"代码默认"，依据是 `PlayerbotAIConfig.cpp` 的解析行，不是注释。

### 5.1 总开关与模式
`AiPlayerbot.Enabled = 1`（0=整个模块停摆，启动日志 "AI Playerbot is Disabled"）；`RandomBotAutologin = 1`（随机 bot 体系启停）；`RandomBotLoginAtStartup = 1`（开机即拉人）；`RandomBotLoginWithPlayer = 0`（只在你上线时才拉）；`RandomBotAutoCreate = 1`（自动建号补池）；`ExplicitDbStoreSave = 0`（禁自动 DBStore 存档）【守恒】。

### 5.2 人口与在场——THE 成本旋钮【常调/性能篇主力】
- **`MinRandomBots = MaxRandomBots = 1000`**：在线 bot 数维持区间（**代码默认 50/200，本部署预调 1000**——轻量机器第一改处，如 100/200）。
- `RandomBotAccountCount = 200`：bot **账号池**（代码默认 50）——池上限 = 账号数×9 角色（vanilla 每号 10 角中的 9。**必须 ≥ MaxRandomBots**，否则目标人数永远达不到）。
- `RandomBotAccountPrefix = "RNDBOT"`：账号名前缀——**改前缀=弃掉你现有池**（新前缀全新建号，旧号成孤儿）。
- `RandomBotMaps = "0,1,530,571"`：bot 活动地图——**530/571 是外域图，本 1.12 服不存在**；清爽化改 "0,1"。
- `RandomBot{Min,Max}Level = 1/60`、`RandomBotMaxLevelChance = 0.15`、`randombotStartingLevel = 5`+`DisableRandomLevels = 0`。
- 生命周期（大多注释态）：`TimedLogout/TimedOffline`、`Min/MaxRandomBotInWorldTime`（注释值 1h/14d，**代码默认 30min/6h**）、`RandomBotCountChangeMin/MaxInterval = 1800/7200`（人数调整节奏）、`TeleportTeleportMin/MaxInterval = 7200/172800`（跨图传送节奏）、`RandomBotUpdateInterval`（默认 1s）、`RandomBotsMaxLoginsPerInterval = 10`（每区间登录数上限=开机洪峰闸）。

### 5.3 人口构成（概率表族——想控制就动这）
`ClassRaceProb.<职业>.<种族>` 权重表；`ClassRace.UseFixedClassRaceCounts`（改用**固定数量**模式——则只认 class+race 复合键）；`LevelProbability.<等级>` 每级上线偏好（默认全 100）；`PremadeSpec{Name,Prob,Link}.<职业>.<配装>` 130 键天赋表。要点：**满级偏好把 `LevelProbability.60` 抬高**；固定数量模式可精确造"我要 3 坦 3 奶 4 输出"的常驻 bot 队。

### 5.4 装备（bot 穿什么样）
`RandomGearMaxLevel = 500`（bot 装备品质上限——**500 是外域量级**：vanilla 建议按版本阶段压到 66/76/81/99）；`RandomGearLoweringChance = 0.15`；`RandomGearMaxDiff = 9`；`RandomGearUpgradeEnabled = 0`；`RandomGearBlacklist = 0`（**注释原值 0 不是物品号，清空更对**）；战绩约束 `RollBadItemsWithPlayer = 0`；**`minEnchantingBotLevel = 81`**：附魔开启的 bot 等级门（"MaxLevel+1 即禁"）——**代码默认 60，本 conf 把它写成 81=事实禁用了 bot 附魔**（wlk 遗留值），想吃 bot 附魔回调 60；`RandomGearProgression`（默认 true，键未在 conf 中）。

### 5.5 AI 时序与距离（bot 反应手感）
`ReactDelay = 100`（**bot 思考拍长 ms。调大=变笨省 CPU**）；`IterationsPerTick`（**代码默认 100，注释里的 10 是陈旧值**）；`GlobalCooldown = 1500`（给 bot 的短施法之间强制公共冷却——**代码默认 500，conf 主动上调**）；`PassiveDelay = 10000` / `RepeatDelay = 5000` / `RpgDelay = 10000` / `SitDelay = 20000` / `LootDelayDelay = 1000`；`MaxWaitForMove = 5000`。距离族：`SightDistance = 60` / `SpellDistance = 26` / `ShootDistance = 26` / `RpgDistance = 200`（注释族里 React 150/Grind 75/Loot 25/Contact 0.5/Follow 1.5/Whisper 6000/AoeRadius 10——docs/12 的 LogInGroupOnly 也在此族）；血线阈值注释 25/45/65/85/15/40（**代码默认 20/50/70/90/15/40**——触发吃喝/绷带的档位）；跳跃族 `JumpRandomChance = 0.20` + `JumpFollow/JumpChase/JumpInBg`（几时允许跳跃）+ `UseKnockback = 1`。

### 5.6 行为策略与自动化（与 docs/10 §7 的六族总览相接，此处给键名与实际默认）
随机 bot 战斗/平时出厂 = **`-threat, +custom::say` / `+custom::say`**（conf 注释里那串 +dps/+grind 是摆设，代码默认为准）；`EnableOffSpecStrategies = 1`（twin offheal/offdps 开）；`BotCheats = "taxi,item,breath"` / `RndBotCheats = "taxi,item,breath"`——**bot 默认自带的作弊层**（详见 §5.8 特性键）；`FleeingEnabled = 1` / `UsePotionChance = 1.0` / `EnableMinimalMove = 1` / `UseWanderAsDefaultFollowStrategy`（注释态）/ `DefaultFormation = "near"` / `MaxFreeMoveDistance = 150` / `FreeMoveDelay = 30` / `BoostFollow = 1`。
自动化族：`AutoPickReward = "yes"` / `AutoEquipUpgradeLoot = 1` / `AutoEnchantUpgradeLoot = 0` / **`SyncQuestWithPlayer = 0`**（1=你交任务 bot 同步完成——bot 同进度伙伴键）/ `AutoTrainSpells = "yes"` / `AutoPickTalents = "full"` / `AutoLearnTrainerSpells/QuestSpells/DroppedSpells = 0×3` / `AutoDoQuests = 1` / `PreQuests = 0`（批造号时预补任务史——代码默认 true，conf 主动关以提速）。

### 5.7 社交、聊天与组队门
口味键：`EnableGreet = 1`（bot 主动打招呼）；`GuildRepliesRate = 100`；`RandomBotSayWithoutMaster = 0`；`BotAcceptDuelMinimumLevel = 10`。播报族（全注释态=默认开）：`EnableBroadcasts = 1` + `BroadcastChance<事件> = 0-30000`（如 LootingItemPoor = 30、LevelupTenX = 30000……比率单位万分位）+ 每频道全局 Chance。梗键：**`ToxicLinksPrefix = "gnomes"`**（bot 分享装备时喊"gnomes [装备链接]"）；`BroadcastChanceSuggestThunderfury = 1`（风剑梗独立性 = "不依赖全局概率"）；`ToxicLinksRepliesChance = 30` / `ThunderfuryRepliesChance = 40`；`BroadcastChanceSuggestSomethingToxic = 0`（"Very rude speeches"，默认关）。
社交行为键（全注释态=默认 ON）：`RandomBotInvitePlayer = 1`（bot 会主动邀你——注释教你用 DnD 屏蔽）、`RandomBotGroupNearby/RaidNearby/GuildNearby = 1`、**`RandomBotFormGuild = 1`**（bot 自己买表建会收签名）、`InviteChat = 1`、`TalentsInPublicNote = 0`、`guildMaxBotLimit = 1000`、`NonGmFreeSummon = 0`。
组队邀请门：`GearScoreCheck = 0` / `LevelCheck = 30`（bot 用它拒你的人物等级差/装备分——**你邀不动 bot 时先看这两键**）；`AllowGuildBots = 1` / `AllowMultiAccountAltBots = 1`。

### 5.8 战斗环境与战斗 nuance
`RespawnMod` 族（注释态，默认 10/5/10/18/0/0）：**随机 bot** 杀的怪在附近有真人时**加速重生**（倍率门限可调；对随从 bot 与副本图默认不生效——族内 `RespawnModForPlayerBots/ForInstances` 两键即此意）——专治"bot 活跃导致刷点过快"的平衡旋钮；`TransportTeleportType = 2`；**`RandomBotTeleportDistance = 100`**（代码默认 1000，本 conf 主动压到 100——bot 死后复活传送半径）；`RandomBotRpgChance = 0.20`（进村过日子 vs 刷怪比；代码默认 0.35）；`RandomBotTeleportNearPlayer` + `MaxAmount`/`MaxAmountRadius`（注释态默认关——**开了 bot 会直接传送到你附近"贴身陪玩"**，单人玩大特性，传送量/半径由后两键控）；`RandomBotTeleLevel = 3`、`EnableRandomTeleports = 1`、`XPRate = 1`（bot 乘区，与 mangosd 的 Rate.XP 相乘）、`SyncLevelWithPlayers = 0` / `SyncAltLevelToMaster = 0`；`PvpProhibitedZoneIds`、`RandomBotQuestItems`、**`BotsSaveEpics = 1`**（"alt bot 绝不卖/拆紫色及以上"——想让 bot 帮你攒紫装保持 1）、`RandomBotQuestIds = "7848,3802,5505,6502,7761,9378"`（**全随机 bot 直接完成的任务清单，改错影响面大**）、`ImmuneSpellIds = "19428"`（bot 免疫的法术号，动错 boss 技能机制可能抖）。

### 5.9 性能与活跃度（sizing 篇的键面）
`botActiveAlone = 10`（无人区只有 10% bot 真活跃）；`DisableBotOptimizations = 0` / `DisableActivityPriorities = 0`（两颗按钮"全员全活跃，不惜代价"——注释劝你"卡就先降人数"）；`ForceActiveWhenNearPlayer = 0` / `GuildOrderAlwaysActive = 1` / `LimitCombatActivity = 0`；`DiffWithPlayer = 100` / `DiffEmpty = 200`（以目标 tick 耗时反推活跃度的自调参数）；`LoginCriteria.N` + `DefaultLoginCriteria`（**conf 里写 `DefaultLoginCriteria1` 是陈键，代码读单键名**）+ `FreeRoomForNonSpareBots = 0` + `LoginBotsNearPlayerRange = 1000`（只登你 1000 码内的 bot）；**`TweakValue = 0`**——异步寻路试验开关，注释原话 "Rarely crashes the server"（罕见宕机）【慎开】。

### 5.10 经济与拍卖
`ShouldQueryAHListingsOutsideOfAH`：注释口径"性能考虑默认关"，**代码默认 true**（bot 会查 AH 报价再挂货）；`AhOverVendorItemIds` / `VendorOverAHItemIds`（键离子路由例外品，空=不用）；`BotCheckAllAuctionListings = 0`（默认只抽查少量挂单）；`Min/MaxRandomBotsPriceChangeInterval`（默认 2h-48h 调价周期）。

### 5.11 调试与运维键
`CommandPrefix =""`（密语命令前缀，默认裸发）+ `CommandSeparator`（代码默认反斜杠）；**`CommandServerPort = 8888`（默认 0=关）**——开一个 **TCP bot 命令服务器=网络攻击面**，单机别开；`LogInGroupOnly = 1` / `LogValuesPerTick = 0` / `SpellDump = 0`（docs/12 已述）；`ActionHistorySize = 0`（内存换回放）；`PerfMonEnabled = 0`；`AllowedLogFiles`（日志 ACL）；`DebugFilter`（默认过滤动作名清单）；`RandomBotRandomPassword = 1`（bot 账号随机密码）；`ShowProgressBars = 1`（约等于控制台的 BarGoLink）。

### 5.12 巨表与隐藏键族（只给结构与总闸）
- **`GearProgressionSystem.Enable = 0`**——开 1 后，**你组/团 bots 的装备会按"你的装备进度档"升级**（进组时套六档装备表：Base→Naxxramas 的逐档每职业每天赋每部位装备清单，表体 L1176-4866 恰 3206 键）。开它=**bot 装备跟着你的人物成长**，单机练级团利器；代价是装备"跳档"（偶尔超现实）。
- `WorldBuff.<阵营>.<职业>.<minLvl>.<maxLvl>[.<event>] = <spellId>`——**给任意人群开常驻 buff 的处方键**（例：给全阵营 60 级 bot 常挂屠龙者的呐喊 22888）。
- `LLMEnabled = 1`（**代码默认即 1**）+ `LLMApiEndpoint`/`LLMApiKey`/`LLMPrePrompt`/`LLMMaxSimultaniousGenerations`（上游原拼即如此，少个 e）/`LLMContextLength`/`LLMDefaultPromptsFile = "llm_character_card.txt"`——**bot 接大语言模型聊天**：性格卡文件按 `角色名::人设` 一行一卡。无端点时聊天不生效，配法见 docs/15 特色篇。
- `SelfBotLevel = 1`（代码默认 GM ONLY）——`.bot self` 把**你自己**变成 bot（双开式挂机）。它的注释警告原话值得裱起来：“**Your epic mount will be sold to a vendor!**”
- `DeleteRandomBotAccounts/Guilds/ArenaTeams = 0`——**下次启动时清池/清会/清竞技队**（=一键核弹，重置专用）。
- `AsyncBotLogin = 0` / `PreloadHolders = 0`——登录提速开关（注释自述按 1000 号吃 2GB 内存+启动猛敲库）【单机勿开】。
- `ToggleAlwaysOnlineAccounts/Chars`——把指定号**常驻在线**当 bot（或反向拉黑）。

### 5.13 勘误表：**注释与代码不符八处**（引用一律以代码为准）
| 键 | conf 注释口径 | 代码实际（PlayerbotAIConfig.cpp） |
|---|---|---|
| `IterationsPerTick` | 10 | **100**（:189） |
| `GlobalCooldown` | 500 | **500 是默认；conf 实写 1500=主动上调**（:108） |
| `minEnchantingBotLevel` | ——（写着 81） | 默认 **60**；81=禁用附魔（:531） |
| `Min/MaxRandomBotInWorldTime` | 1h/14d | **30min/6h**（:219-220） |
| `ShouldQueryAHListingsOutsideOfAH` | "默认关（性能）" | **默认开**（:242） |
| `ShowProgressBars` | "默认关" | **默认关（false）**——conf 实写 1=主动开（:107） |
| 血线阈值族（:151-156） | 25/45/65/85/15/40 | **20/50/70/90/15/40** |
| `DefaultLoginCriteria1`（conf 示例键） | 单键名 | 代码读 **`DefaultLoginCriteria`**（:290） |

## 6. 五份模块 conf——机制先说清，键极简

**机制（三行掌握）**：① 模块在构建期由 `BUILD_MODULE_<名>` 开关决定编不编（docs/09 §3）；② 运行时每个模块读**自己进程相对路径** `../etc/<模块名>.conf`（代码 `ModuleConfig.cpp:16` + SYSCONFDIR 编译定义）——即 `run/etc/`；③ `cmangos-modules/modules.conf` **不是运行时配置**，它是上游流程的 git URL 清单，本 fork 构建零引用。改任何模块 conf 均需重启，无热载。

| conf（全键） | 备注 |
|---|---|
| **transmog**：`Enable = 0`、`CostFee = 0`、`CostMultiplier = 1.0`、`TokenRequired = 0`、`TokenEntry = 0`、`TokenAmount = 1` | 幻化费也可改为"收凭证物品"模式（TokenRequired=1+凭证号+数量） |
| **dualspec**：`Enable = 0`、`Cost = 100000` | Cost 单位铜币=10g，双开价 |
| **achievements**：`Enable = 0`、`SendMessage = 1`、`SendAddon = 1`、`SendVisual = 1`、`RandomBots = 0`、`RandomBotsRealmFirst = 0`、`AccountAchievenemts = 0`、`EffectId = 146` | `RandomBots = 1`=bot 也刷成就；`AccountAchievenemts` 是上游的原键名拼写（保持原样勿"修正"）；EffectId=达成时的粒子表现号 |
| **barber**：`Enable = 1` | 一个键的开与关，默认即开 |
| **immersive**：43 键（:189-231）见下 | |

**immersive 键面**（跨号进度共享——语义详述在 docs/09 §8）：
- `Enable = 0`；`ManualAttributes = 0` 族 6 键（手改属性系统：Increase/Percent/CostMult/MaxPoints/BaseAttributes）；
- `AccountReputation = 0`（**账号内小号继承已获声望**——声望级共享）；
- `SharedXpPercent / SharedRepPercent / SharedMoneyPercent = 0`（**三类跨号经验/声望/金币分享比率**）+ `SharedQuests = 0` + `FishingBaubles = 0` + `SharedRandomPercent = 0`；分享限制族：`SharedPercent{Race,Class,Guild,Faction}Restriction = 0`×4 + `SharedPercentMinLevel = 1` + `SharedXpPercentLevelDiff = 0`；
- `AttributeLossPerDeath = 2`（死亡掉多少点共享属性）；`FallDamageMultiplier = 1.0`；`ScaleModifierWorkaround = 0`（体型放缩补丁兼容）；
- `DisableOfflineRespawn = 0` / `DisableInstanceRespawn = 0`（插件自带的"离线/副本内不涨重生计时"——注释建议搭配 mangosd 的 `PlayerSave.Interval/Instance.ResetTimeHour`）；
- **`InfiniteLeveling = 0`** 九键族（InfiniteLeveling/Max=100 + Raid{Boss,Elite,NonElite}Mult/ Dungeon{Boss,Elite,NonElite}Mult/ World{Elite,NonElite}Mult=10/1/0.25,5/1/0.25,1/0.25）——**"无限练级"模式**：副本怪血量经验随等级滚起来；
- `GiveXPOnPvp = 0` 族（Bg/Arena/World Mult=2/1/1）+ `GiveXPOnGathering = 0` 族（Orange/Yellow/Green Pct=0.5/0.25/0.125）——pvp 与采集也给经验。

## 7. 术语表与出处（锚点集）

conf 键与行号以 `run/etc/*.conf`（==.dist）为准；行为断言配代码锚。

| 断言 | 出处 |
|---|---|
| 全景"三六九等"生效矩阵 | mangos-classic/src/game/Chat/Chat.cpp:619（.reload config 挂载）+ Level3.cpp:314-323（实现：LoadConfigSettings(true)+视距重初始化+PacketLog） |
| .reload config 不触及模块/aiplayerbot/realmd | docs/09 §5 同口径 + playerbots 无 reload 命令 + realmd 无命令面 |
| 环境变量覆盖法 | mangosd.conf:4-13 / realmd.conf:4-12 / anticheat.conf:8-14 头部注释 |
| Server.log 无 Message.log（仅本断言涉及） | mangosd.conf L421 + run/bin 实测文件清单 |
| anticheat 休眠三证 | src/game/CMakeLists.txt:27-29 + src/game/Anticheat/Anticheat.cpp:1（#error 守卫）+ 构建产物宏零命中（agent 三次独立核实） |
| aiplayerbot "注释≠代码" 八条 | playerbots/playerbot/PlayerbotAIConfig.cpp:108,151-156,189,219-220,242,290,502,531 + conf:781,790,855-860,1137 |
| Min/MaxRandomBots 代码默认 50/200 | PlayerbotAIConfig.cpp:212-213 |
| 账号池=账号×9 | playerbots/playerbot/RandomPlayerbotFactory.cpp:755-759 |
| 模块 conf 读取路径（SYSCONFDIR 相对） | cmangos-modules/src/ModuleConfig.cpp:16 + ModuleMgr.cpp:29-38 + 构建定义 `SYSCONFDIR="../etc/"` |
| modules.conf 是 URL 清单非运行时配置 | cmangos-modules/modules.conf 全文 13 行 + 本仓构建零引用 |
| GearProgressionSystem 关/开与结构 | aiplayerbot.conf:1166-1176 表头 + PlayerbotAIConfig.cpp:753 |
| LLM/作弊/self/删除族默认值 | PlayerbotAIConfig.cpp:459-461,503,655-670,780 |
| mangosd 全键族行号 | mangosd.conf:81-96,250-279,417-453,812-877,923-933,1058-1096,1155-1163,1268-1283,1324-1331,1491-1552,1595-1601,1613-1614,1631-1632,1661-1665,1716-1726,1751-1753,1785-1793 |
| realmd 全键 | realmd.conf:129-149 |
| 五模块 conf 全键 | cmangos-{transmog,dualspec,achievements,barber}/src/*.conf.dist.in 全文 + cmangos-immersive/src/immersive.conf.dist.in:189-231 |

**上手三连**（和 docs/15 的热载实验对接）：

```text
grep -n "Motd" run/etc/mangosd.conf        → 找到你想说的话
改值 → 游戏内 .reload config             → 立刻重登看公告（或 .server motd 查看）
然后试一个 Rate.XP.Kill=2 → .reload config → 打一只怪验倍率 → 记住哪些键真的热载
```

**和其他篇的关系**：docs/06 §2 是出厂必查的三个键；docs/09 §5 是五模块 Enable 的安装面；docs/10 §7 是 aiplayerbot 的六族速览；docs/13 §7-8 是寻路键的代价表；docs/15 是把本字典的键配成"直接抄的套餐"的玩法手册。
