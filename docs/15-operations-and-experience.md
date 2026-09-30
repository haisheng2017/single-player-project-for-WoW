# 15 · 运维与玩法手册（照抄就能用的配方）

> 前置：`docs/14`（配置字典——本文每个配方里的键，其"是什么/默认值/风险"都在那边查）；`docs/06`（启动铁律与建号）。本文管"怎么过日子"：开关机、变更、备份、日志、更新、安全、以及把这个服**调得更好玩**的直给配方。

**版本边界**：命令与键名逐字核自本 fork（锚点在 §5）；shell 命令一律以服务器宿主/容器内、工作目录 `run/bin` 为准。

## 0. 一张生命周期图（你每天其实只走这三格）

```
   开机 ──── MySQL(随系统)→ realmd → mangosd（60 号脚本/或手工两条）
     │
   运行 ──── 改配置走 §2 生效面矩阵；排障看 §4 日志；玩累了想爽走 §6-§8
     │
   关机 ──── .server shutdown 30（体面倒计时）→ （docker 形态停容器）
     │
   定期 ──── §3 备份一把（world+characters+realmd 三库）→§5 更新时按顺序
```

## 1. 开关机与部署形态

- **本地/宿主直跑**：`bash scripts/60-start-server.sh`（端口自检 + nohup 双进程）——docs/06 §3-4 的铁律依然全部有效（工作目录必须在 `run/bin`）。
- **Docker 形态**：容器须 `--init`（troubleshooting #26 机理）；端口 `-p 3724:3724 -p 8085:8085`（#27）；MySQL 用 `service mysql start/stop`；进容器干活：`docker exec -it <容器> bash`（docs/13 §7 证一的三查就在里面跑）。
- 一个如实的杂记：core 装了一套 `run/bin/run-mangosd`/`run-realmd` 的 screen 自重启包装器（上游给"进程退出后自动循环重启"的场景用的；**本体系 60 号不用它**——它只在每轮重启时轮转一份时间戳副本日志，且 realmd 侧那脚本有个写错日志名的上游瑕疵）。知道它存在即可，别和 60 号叠着开。

## 2. 变更生效面矩阵 ＋ 命令面

**改了 conf 之后**（与 docs/14 §1 同口径、这里给"动作"）：

| 你改了 | 动作 |
|---|---|
| mangosd.conf 世界侧键 | 游戏里敲 `.reload config`——立即生效并广播；**试验配方首选这条路**（零停机） |
| mangosd.conf 端口/线程/DB/网络/Ra/SOAP 键 | `.server restart 30` 或走关机流程 |
| aiplayerbot.conf / 五模块 conf | 必须重启 mangosd |
| realmd.conf | 只能重启 realmd 进程 |

**`.server` 命令族**（管理员级 unless noted；控制台同样能敲）：

```text
.server info                     当前版本/在线/运行时间（玩家级也可用）
.server shutdown <秒>            体面关机（倒计时中间全服广播）；.server shutdown cancel 反悔
.server restart <秒>              同上但重启；同样有 .server restart cancel
.server idleshutdown / idlerestart   无人在线才触发（睡觉挂机党的保险）
.server motd / .server set motd <文字>   看公告 / 改公告（改的是运行时值，conf 里那份要在改后同步改）
.server log filter <名> 0|1      控制台实时开关某类日志（等价改 LogFilter，无须重启，控制台用）
.server log level <0-3>           控制台实时调日志级（文档级：排障黄金工具）
.server corpses                   清地上的尸体
.server resetallraid              重置所有玩家的副本锁
```

**`.reload` 家族**（数据库表的热载主力，管理员级）：`.reload config` 之外，`.reload all`（主体表全刷）、`.reload creature_template`、`.reload gameobject_template`、`.reload creature_ai_scripts` 等 40+ 个按表热载——做世界侧小实验（改 NPC、改建模、EventAI）不用重启；命令清单在 `.reload` 输出里自列。另 `.ahbot reload` 专为 AHBot（若启用）。

> 三条铁则：① `.reload config` 只吃 mangosd.conf，**模块与 bot 的 conf 不吃**；② 热载是最快的"我改错了也只错一拍"实验路径——**改键前记原值**（本文所有配方块都假设你能回到 .dist 重来：`cp run/etc/mangosd.conf.dist run/etc/mangosd.conf` 再逐键改）；③ realmd 没有任何命令面，纯重启。

## 3. 备份与恢复（本体系原本只有一行 mysqldump，这里补成体系）

**什么必须保**（三库分野）：

| 库 | 内容 | 丢失代价 |
|---|---|---|
| `classiccharacters` | **一切玩家态**：角色、背包、bot 的策略存档与随机 bot 全部角色、副本进度、拍卖挂单 | 灾难——必保 |
| `classicrealmd` | 账号与 SRP6 密钥（迁移三表）、realmlist | 灾难——必保（丢了=全部账号登不上） |
| `classicmangos` | 世界库（含你做过的一切手工 UPDATE——如 troubleshooting #32 幕后改的 DisplayId/坐标） | 重装可回出厂，**你的手工修改全丢**——强烈建议保 |
| `classiclogs` | 运行日志库 | 无所谓，按兴趣 |

**备份一把**（宿主或容器内；停服或低峰更稳，mysqldump 会锁表片刻）：

```bash
cd run && mkdir -p backup
mysqldump -umangos -p --lock-all-tables --default-character-set=utf8 \
  classicrealmd classiccharacters classicmangos > backup/wow-$(date +%F).sql
# 保留策略：清掉 7 天前的（或移去异地）
find backup -name 'wow-*.sql' -mtime +7 -delete
```

**恢复**（对应库重灌）：`mysql -umangos -p classiccharacters < backup/wow-某日.sql`（角色库整库替换语义；**运行中别灌**——先关 mangosd，恢复完再起）。
**分野**：跨机搬整服用 70/80 号迁移包（docs/08，含版本守门与确认词）；本节是同机回滚。**同机恢复前不必动 80 号**——别用迁移工具做回滚，SQL 直灌即可。

## 4. 日志体系（你该看哪个文件、开到几档、会不会撑爆磁盘）

- `run/bin/` 里的成员：`Server.log`（主logfile）、`DBErrors.log`（**库层错误第一入口**）、`Char.log`（角色建删流水）、`EventAIErrors.log`/`SD2Errors.log`（脚本错误）、`Realmd.log`；外加 `YYYY-MM-DD_logSQL.sql`（GM 命令的 SQL 流水，LogSQL=1 常开——**误操作的回滚线索**）。
- **两档必须分清**：控制台吃 `LogLevel`（出厂 1），文件吃 `LogFileLevel`（**出厂 0=只有错误级**）。排障要文件细节：conf 设 `LogFileLevel = 2` + `LogFilter_*` 相应放行（**这套键 1=抑制、0=放行**），重启或 `.reload config`。用完改回——细节档的日志量很大。
- **轮转真相**：mangosd 自身**不做任何轮转**；core 自带的 wrapper 只在你重启进程那一刻轮转一份时间戳副本（见 §1 杂记——而本体系 60 号根本不经过 wrapper）。也就是说**长开的服务器 Server.log 会一直长**。低配方案：每天关机重开自然轮；不关机方案：写一行 cron（`logrotate` 或 `find …-size +100M` 分卷），本文不代编脚本，只立此存照。
- 专用深挖一把梭（配合 docs/13-14）：`grep -n "MMAP:\|VMap" run/bin/Server.log`、`grep -c "LogFilter" run/etc/mangosd.conf` 等。

## 5. 更新与同步（四层各有顺序）

1. **core 更新**（fork 同步上游后）：**先跑 20 号（软链与定制在位校验）再跑 30 号（增量编译）**——troubleshooting #21 的顺序是铁的；conf 改动不受影响（.conf 不随安装覆盖——**手册四份 conf 备份后重编译**）。
2. **世界库更新**：core 比库新时启动日志报 `db_version` 不匹配—— `InstallFullDB.sh` 菜单 `3) Install core updates only` 应用 `sql/updates/`（#17 语义；上游菜单重构过的话按 #22 以实跑为准）。
3. **模块更新**：模块代码更新=重链+重编，模块 SQL 以 45 号口径补；immersive 的**角色库自建表不要重复导**（首装唯一）。
4. **数据更新**：客户端数据(maps/vmaps/mmaps)不随任何更新变化；只有你怀疑地形网格与新版不匹配时才重提（docs/04 + docs/13 §8 层一）。

## 6. 安全与公网化清单（从"只有我"到"朋友能连"）

- **端口面**：3724（realmd）+ 8085（世界）对外即可；**3306 绝不对外**；防火墙/安全组只放这两个。Docker 形态注意 `-p 3724:3724 -p 8085:8085` 就够，别顺手 `-p 3306`。
- **realmd 反爆破必改**（出厂默认=永不封禁）：`WrongPass.MaxCount = 10`＋`BanType = 0`（封 IP）＋`BanTime = 600`。改 realmd.conf 后重启 realmd。
- **严版查的双刃**：`StrictVersionCheck = 0` 保持——朋友用汉化/微调客户端会被 1 拒之门外。
- **进服门槛**：`PlayerLimit` 记得**bot 占配额**（本部署随机 bot 出厂 1000——公网前请先按 §8 砍到你想要的活人容量）；负值语义（仅 GM 可进）适合维护窗口。
- **管理面默认全是关的、保持关**：`Ra.Enable = 0`（要远程管理再按 docs/14 §2.17 的三步走：限 IP、改默认端口、防火墙白名单）；`SOAP` 同理仅本机；aiplayerbot 的 `CommandServerPort` **永远别开**（TCP bot 命令面=任何人可指挥你的 bot）。
- **反作弊现状如实说**：anticheat 本 fork 构建是空桩（docs/14 §4 有三处锚点）。给朋友玩的服，安全靠"强密码+realmd 三键+端口最小化"；真正启用反作弊属编译期工程（定义 `USE_ANTICHEAT` 重编），考虑再做。
- **别当公网公益服跑**（README 定位声明）——本文"公网化"上限是"朋友圈"。

## 7. 游戏体验配方（改 mangosd.conf 后 `.reload config` 即刻生效，键语义查 docs/14）

**单机爽点套餐**（一次全上或挑几条）：

```text
SkipCinematics = 2            # 永不放开场动画
AllFlightPaths = 1            # 开号即全航线（两侧的都给）
AlwaysMaxSkillForLevel = 1    # 武器/防御技能自动满
DurabilityLossChance.* = 0    # 永不磨损（四个键全归零）
Death.CorpseReclaimDelay.PvE = 0   # 收尸免排队
Death.Ghost.RunSpeed.World = 1.5   # 灵魂跑快 50%
Quests.LowLevelHideDiff = -1  # 所有可接任务都给我标"!"
Rate.Damage.Fall = 0         # 永不摔伤
AutoDownrank = 1             # buff/治疗给低级目标自动降阶
```

**难度调音台**（动前面三组前记基线，一次一动）：
- 全服变硬：`Rate.Creature.Normal.HP = 1.5` 起步（Elite 族另有十二键，docs/14 §2.6）。
- 怪更凶/更怂：`Rate.Creature.Aggro`（0=全图怪不主动——带小号逛街模式；1.5=野怪警觉）。
- 拉怪连锁收放：`CreatureFamilyAssistanceRadius`/`CheckForHelpRadius`（收小=各打各的）。

**倍率全家**（"改 >3 即改世界"——整个 progression 曲线要重想）：
- 练级：`Rate.XP.Kill/Quest/Explore`；休闲推荐 2×，怀旧原味 1×。
- 掉落：按品质分键（想"蓝紫多点绿装别烦"就 Rare/Epic 2、Poor 0.5）；金钱 `Rate.Drop.Money`。
- 手工党：`SkillGain.Crafting/Gathering = 2`；`SkillFail.Gain.Fishing = 1`（钓空也涨点）；`SkillChance.Orange/Yellow/Green` 顺手全上调。
- 声望/天赋：`Rate.Reputation.Gain = 2`、`Rate.Talent` 原样=标准 61 点。

**bot 同行体验**（aiplayerbot.conf，**改后要重启 mangosd**——不热载）：
- 同进度伙伴：`SyncQuestWithPlayer = 1`（你交任务 bot 跟着完成——docs/10 §5 的密语控制互补：`/w <bot> q`）。
- 邀请门：**你邀 bot 被拒**＝`LevelCheck = 30` 在挡（级差>30 拒；单机想跨级带 bot 改小或 0）；`GearScoreCheck` 默认关。
- 紫装不跑：`BotsSaveEpics = 1` 保持（bot 绝不卖/拆紫色+）；想让 bot 附魔别忘 `minEnchantingBotLevel = 60`（出厂 81 事实禁用）。
- 装备真实感：`RandomGearMaxLevel` 按你的阶段压 66/76/81/99；想要"bot 装备跟着你成长"→ §9 的装备进阶系统。

## 8. 性能优化（sizing 三档——先把 bot 数定下来再谈一切）

| 档 | 适合 | Min/MaxRandomBots | AccountCount | 附加 |
|---|---|---|---|---|
| **轻量档** | 单人玩、小机器/容器 | 100 / 200 | 25 左右（÷9 后≈220 池） | `RandomBotMaps = "0,1"`；`botActiveAlone = 10` 默认；`PreloadHolders` **绝对不开**（注释自述 2GB/千号） |
| **标准档** | 常规家用机 | 300 / 500 | 60 | 维持出厂手感；村子更热闹可把 `RandomBotRpgChance` 0.20 提到 0.35 |
| **满街档** | 沉浸都市感 | 800 / 1000 | 120 | 接近出厂；盯 §4 日志与 tick |

- **调谁不调谁**：先动"数量+池"，再动 `ReactDelay`（思考拍 100→200ms 省一半脑子），**别动** `DisableActivityPriorities/DisableBotOptimizations`（两颗"全员全活跃不惜代价"按钮，注释劝你卡就减人数）；`DiffWithPlayer/DiffEmpty` 是活跃度自调的旋钮（docs/14 §5.9），动它们前先记录当前 tick 耗时。
- **CPU 线程**：`MapUpdate.Threads`（≤核数-1）；`Visibility.Distance.Continents` 100 出厂，卡顿先降它、流畅想看得远再升。
- **启动提速**：小池子（AccountCount↓）本身就是最好的启动提速——bot 号多寡决定"Creating random bot characters"时长（docs/06 的首次启动提示）。

## 9. 特色功能宝库（都藏着，每条=一小节）

### 9.1 bot 接大语言模型聊天
**开箱即"半开"**：代码默认 `LLMEnabled = 1`，但没有端点就无动作。给键 `LLMApiEndpoint`（默认指向本机 5001 端口的 generate 接口形态）填上任何兼容服务，bot 聊天开始"有脑子"：域内打字它接话（密语/说/喊），`LLMPrePrompt` 是角色扮演总提示（上游自带一版很讲究的），`LLMDefaultPromptsFile = "llm_character_card.txt"` 是**性格卡**：一行 `角色名::人设`，点名给谁立人设。上限/上下文长度键面 docs/14 §5.12。坑：公开端点会把对话送出去——自建端点才私密；没接上时聊天行为退回默认模板。

### 9.2 装备进阶系统（GearProgressionSystem，出厂休眠）
`aiplayerbot.conf` 末尾 3206 键就是它：六档（Base→Naxxramas）× 每职业 × 每天赋 × 每部位一套装备清单。`GearProgressionSystem.Enable = 1` 后，**你组/团起 bot 时，它们的装备按"你当前的装备进度档"穿戴**——练级/开荒带 bot 团的养眼开关。坑：档判定看的是你的 ilvl，跨档混穿时 bot 装备偶尔"跳变"。

### 9.3 self-bot：把自己也变成 bot
`SelfBotLevel`（出厂=仅 GM 账号）放开后 `.bot self`——**把你自己的号也交给 AI 接管**：挂机自动接/交任务、你下线后角色还能跟团推本。上游注释警告原话："**Your epic mount will be sold to a vendor!**"（bot 的背包管理真的会卖你的坐骑）——开之前先把贵重物自留，把背包的最终决定权想想清楚。改后重启。

### 9.4 bot 作弊层（出厂就开的公开外挂）
`BotCheats = "taxi,item,breath"`（随从 bot）与 `RndBotCheats`（随机 bot）——**默认三者**：taxi 免费飞点、item 免费弹药物品、breath 水下呼吸。可加码：`gold/health/cooldown/movespeed/quest`（quest=任务瞬完成——单机加速剧情向；健康度自负）。密语等价物：`/w <bot> cheat <码>`——docs/10 §5 控制面。

### 9.5 WorldBuff 处方：给"某群人"上常驻 buff
键式 `WorldBuff.<阵营>.<职业>.<min>/<max>[.<event>] = <spellId>`（示例原文：全阵营全职业 60 满级 bot 常挂屠龙者的呐喊 22888）。用法即"人群处方"：想让你的 bot 军团进场自带世界 buff？三行搞定。改后重启。

### 9.6 把人气拉到你身边
`RandomBotTeleportNearPlayer = 1` + `MaxAmount`（量）+ `MaxAmountRadius`（半径）——随机 bot 直接传送到你的区域"贴身陪玩"（撞门赴死也陪你）。单机沉浸神器；注意与你所在图的 bot 上限叠加效应。

### 9.7 常驻在线号（always）
`ToggleAlwaysOnlineAccounts/Chars`——指定账号永远作 bot 在线（或者反向拉黑某些号）；游戏内等价命令族 `.bot always <名>`（docs/12 §7 试验号配方用的是同一条）。适合"固定队友永远在"。

### 9.8 随机 bot 的社会化行为（出厂全开，想关哪个解开哪个）
它们会主动邀你入队（用 DND 状态屏蔽）、自己组队/成团进战场、**自己买公会表收签名建公会**（`RandomBotFormGuild = 1`）、对你发来的装备链接回一句"gnomes [链接]"（`ToxicLinksPrefix="gnomes"`），以及著名的**风剑回复链**（你一提 Thunderfury 就有 bot 接梗——`ThunderfuryRepliesChance = 40` 独立于全局播报概率）。嫌吵：相关的 BroadcastChance 族与 EnableBroadcasts 全在 docs/14 §5.7。

### 9.9 immersive 的跨号养成配方（模块 conf，改后重启 mangosd）
- 想要"大号养小号"：`Immersive.AccountReputation = 1`（小号继承声望）＋ `SharedQuests = 1`（任务态共享）＋ `SharedXpPercent/SharedMoneyPercent = 50` 左右起步（经验/金币对半共享），限制键（职业/种族/阵营）默认全 0 不拦。语义总表 docs/09 §8。
- 想要"无限练级"：`InfiniteLeveling = 1` 配它的九个倍率键（副本/团本/野外各三档——出厂 10/5/0.25 那组不是定值，按你的强度口味重定）。

## 10. 一页速查

```text
体面关机：.server shutdown 30（反悔 .server shutdown cancel）
热载conf：改 mangosd.conf 世界键 → .reload config
表热载： .reload creature_template / all / …（40+ 族）
备份一把：cd run && mysqldump …三库 > backup/wow-$(date +%F).sql
排障线： DBErrors.log（库）→ Server.log（Values: LogFileLevel=2 才有细节）→ docs/13 §7（怪）
性能三步：先砍 Min/MaxRandomBots → 再 AccountCount → 别碰 Disable*Optimizations
公网三键：realmd WrongPass.* → 端口面 3724/8085 → PlayerLimit（bot 占额）
```

## 11. 锚点表（运维侧断言）

| 断言 | 出处 |
|---|---|
| `.reload config` 存在＋覆盖面（世界键/不吃模块与 bot conf/广播语） | mangos-classic/src/game/Chat/Chat.cpp:619 + src/game/Chat/Level3.cpp:314-323 |
| `.server` 族命令与权限（info 玩家级；shutdown/restart/idle+cancel 管理员级；exit/log 子命令控制台级） | mangos-classic/src/game/Chat/Chat.cpp:793-807, 752-778（各 cancel 为子命令非顶层） |
| `.reload` 家族 40+ 表载（含 .ahbot reload） | Chat.cpp:605-645, :100 |
| realmd 无命令面、改 conf 只能重启 | realmd 全功能面（149 行 conf + 进程形态） |
| Motd 的 '@' 换行与运行时改法（.server set motd） | mangosd.conf:802-803, 876 + Chat.cpp:787 + src/game/Server/WorldSession.cpp:869-894 |
| 备份三库分野（characters/realmd 必保、world 含手工改动） | 本仓 docs/troubleshooting.md #20 + docs/08 §3-7 + #32 的 world 侧修改先例 |
| 两档日志（控制台 LogLevel=1 出厂 / 文件 LogFileLevel=0 出厂）＋ LogFilter 1=抑制 | mangosd.conf:417-441 + docs/13 §7 证三 |
| 轮转真相（mangosd 无自轮转；wrapper 仅重启轮转一份；60 号不走 wrapper） | run/bin/run-mangosd 脚本 + scripts/60-start-server.sh（nohup 路线） |
| wrapper 的不在场证据 + realmd 侧日志名瑕疵 | run/bin/run-realmd 中 mv Server.log 但 touch Realmd.log |
| 同步上游先 20 后 30；库更新菜单 3 | troubleshooting #21 / #17（docs/02 §2 fork 策略） |
| anticheat 空桩三证（USE_ANTICHEAT 未定义） | docs/14 §4 转引 src/game/CMakeLists.txt:27-29 + Anticheat.cpp:1 |
| 帐号池=账号×9；Min/MaxRandomBots 代码默认 | playerbots RandomPlayerbotFactory.cpp:755-759 + PlayerbotAIConfig.cpp:212-213 |
| LLM/作弊/self/GearProgression/ToggleAlwaysOnline 默认值 | PlayerbotAIConfig.cpp:459-461, 503, 655-670, 780 + conf 采集（docs/14 §5 各键行号） |
| immersive 键面与语义 | cmangos-immersive/src/immersive.conf.dist.in:189-231 + docs/09 §8 |

**上手三连**：

```text
① 备份一把（§3 三行命令）——从今天起你改坏什么都能救
② Motd 写句欢迎词 → .reload config → 重登看一眼（热载体感一秒到手）
③ 挑 §7 爽点套餐三件上号试玩——体验"配置即玩法"
```

**和其他篇的关系**：docs/06=启动与建号第一课；docs/09=五模块安装与语义；docs/10-13=playerbots 玩法与核心疑难；**docs/14=本文每把配方背后的键义字典**。troubleshooting 仍是"踩坑了再翻"的索引——本文把"没踩坑之前就该做"的事补齐了。
