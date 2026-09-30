# 12 · 策略实测手册（分场景搭台验证）

> 前置：`docs/10-playerbots-principles.md`（装卸语法 §5、文本自定义 §6、副本策略 §8）+ `docs/11-playerbots-engine-actions.md`（每台引擎出厂做什么）。11 讲"应该发生什么"，本文讲**怎么让它按需发生、怎么证明它发生了**。

**版本边界**：一切命令与 token 只对本 fork（classic 1.12.1）逐字核实过（§11 锚点表）。前提环境：你会用 gmlevel 3 管理账号（docs/06 §5 建号时已给 3 级）。

## 1. 实测的四个面 + 单变量纪律

所有手段归四个面，后文按此展开：

| 面 | 回答的问题 | 主力工具 |
|---|---|---|
| **观察** | 它刚才到底做了/想做什么 | `cdebug`、`nc +debug` 播报、服务端日志 |
| **施压** | 这个动作本身能不能做 | 密语 `d <动作名>` |
| **造景** | 把"某个条件"人为造出来 | GM 命令（`.npc tempspawn`、`.damage`…） |
| **复位** | 排除上次试验的残留 | `reset strats`、`.revive`、删试验怪 |

**单一变量纪律**（三条，照做能省一半时间）：

1. 试验前先 `reset strats` 打回出厂基线（否则上次试验的包还挂着污染结果）；
2. 一次只动一个 `+/−`——多包同装时行为对不上号不知道怪谁；
3. 同怪复现——用 `.npc tempspawn <同一编号>` 造"同一只怪"，对比才有意义。

**场景五段模板**（§8 每个场景都按这个骨架）：

```
 搭台（setup）   —— 人/怪/机关/包就位
 触发（provoking）—— 制造待验证的条件
 观察（observe）  —— 用哪个面看、看什么字样
 判定（judge）    —— PASS 的判据是什么
 复位（reset）    —— 收台，别给下次留残留
```

## 2. 观察A：`cdebug` 控制台——问 bot 的一切状态

密语 `/w <bot> cdebug <子命令>`。**先记住第一个陷阱：密语 `debug` 是另一个东西**——那三个字母的密语被截去走"插件数据频道"（预留给 MaNGOSBot 插件界面的协议），你游戏里没有插件就石沉大海。**实测永远敲 `cdebug`**。

策展子命令（公开可用；另有一批管理员/`.bot` 通道专用，见 §11）：

| 子命令 | 看什么 |
|---|---|
| `cdebug help` | 全部子命令清单（以它为准，本文只策展） |
| `cdebug values` / `cdebug values <名>` | bot 眼中的世界状态值（§11 锚点那本"状态值"花名册的实时读数） |
| `cdebug why` | 它对当前目标/选择的自述 |
| `cdebug engine` | 四台引擎各挂着哪些策略（≈ `list ai` 的深度版） |
| `cdebug history` | 最近做过什么动作（回放，见 §3） |
| `cdebug combat` | 战斗状态切面 |
| `cdebug do <动作名>` | 直接执行动作（§5 的静默版） |
| `cdebug setvalueuin32 <名>,<值>` | 改一个整型状态值（做"伪造场景"的高级手段；单参=复位该值） |
| `cdebug position` / `cdebug nodes` | 坐标/路网切面 |

GM 侧等价物：`.bot debug <bot> <子命令>`——同一条通道、外加解锁管理员批子命令。

## 3. 观察B：实况播报——让它边做边讲

两个档位，按需开：

```text
/w <bot> nc +debug          → bot 每执行一个动作,都密语你一条：
                              do: <动作名> (相关度) [事件来源] (预计时长)
/w <bot> nc +debug action   → 追加"未遂"播报：
                              try: <动作名> unknown/useless/… (为何没做成)
```

两个**播报陷阱**（"我开了 debug 怎么没动静"九成是这两条）：

1. **无队伍不播**：播报默认 `AiPlayerbot.LogInGroupOnly=1`——bot 不在队里时口条被关。**先组队再观察**（自己 invited/`.bot add` 后 invite）；
2. **过滤名单**：`AiPlayerbot.DebugFilter` 默认就屏蔽了几个高频琐碎动作名（emote、jump 一类）——你看的动作名若在内，播报会被吞，可临时改 conf 排除。

回放通道：`cdebug history`——不用全程盯屏，事后拉最近动作（条数上限 `ActionHistorySize`，默认 0=不存，要回放先在 conf 里给个条数）。

试完记得关：`nc -debug`（开着的话每拍刷你一脸）。

## 4. 观察C：引擎内档——服务器侧的决策日志

引擎每拍在服务端日志里落字字句句（`A:%s - OK/PREREQ/FAILED/USELESS`、`T:%s`触发器命中、`S:+%s`策略装卸）。看它们的账本：

| 位置 | 条件 |
|---|---|
| mangosd **控制台**（前台跑 60 号脚本的那个终端） | 默认就能看到（`LogLevel≥2`，出厂 3） |
| `run/log/` 里的文件 | **默认看不到**——`mangosd.conf` 的 `LogFileLevel` 出厂为 0，**改成 2** 重启才有 `Server.log` |

选面小结（§2-§4 合并用）：

| 你想判什么 | 用哪面 |
|---|---|
| "它在密语我之外还干了啥" | 播报（B） |
| "它眼里现在是什么世界" | cdebug values（A） |
| "为什么它选了 A 不选 B"（分差原因） | 内档 T:/A: 行 × 前后对比（C） |
| "我上次的修改生效了吗" | 播报前后流差异（B），进阶配内档 |

## 5. 施压面：`d` / `do` 直发动作

密语 `/w <bot> d <动作名>`（或 `do` 同效）：绕过排队与触发器，**直接让 bot 执行那个注册过的动作**。回执四种，一望即知：

| 回执 | 含义 |
|---|---|
| （bot 点头音） | 动作执行成功 |
| `<名>: impossible` | 该动作可行条件不满足（距离/目标/姿态…） |
| `<名>: useless` | "能做但没必要"（当前状态值 判false） |
| `<名>: failed` | 试了，没成 |
| `<名>: unknown action` | **名字拼错了/没注册**——一行就能验名 |

典型用法：验"某动作在本环境到底能不能做"（`d drink`——它到底有没有水）；验名（新写的 custom 行里用的动作名先 `d` 一下）。

**边界**：`d` 只认**动作名**——**触发器没有按名强发的通道**（引擎设计如此）。想验证"某触发器会不会亮"，只能把触发它需要的世界状态造出来——这正是下一节存在的意义。

## 6. 造景面：GM 工具箱（本 fork 逐字核实）

多数为 3 级（Administrator）权限——你的 gmlevel 3 账号全可用。表**右边一列全是坑**，先读再敲：

| 命令 | 用途 | 坑 |
|---|---|---|
| `.npc tempspawn <entry> <秒>` | **试验首选**：出生在你脚边的限时怪 | 精确双参形态；另有一个同名的 `.tempspawn`（管理员级列表命令，在顶层命令表——少见用别混） |
| `.npc add <entry>` | 永久怪（会写库） | 测完记得 `.npc delete`（或选中删） |
| `.npc delete` | 删选中/指定 guid 挡路的 | 有刷新组时会拒删——那是正常保护 |
| `.gobject add 177704` | **岩浆炸弹机关**（测试躲机关的通行证，见场景 2） | 测完 `.gobject delete`（先选中它） |
| `.go xyz <x> <y> <z> [map]` | 传送（可带地图号——进副本图造景） | 只拒战场图；去副本图要坐标（配合 4 号文档或 `.tele`） |
| `.go creature id <entry>` | 跳到指定编号已加载的怪 | `id` 参数形态 |
| `.tele <地名>` / `.lookup tele <词>` | 按名传送/查名 | 名字须在 game_tele 表里，`.reload game_tele` 可刷新 |
| `.cast <spell>` | 选中单位施法 | 施在**当前选中**单位上（含自己人） |
| `.aura <spell>` / `.unaura` | 给选中单位挂/摘真光环 | 用来伪造"身上有某 debuff"的触发条件 |
| **`.damage <数值>`** | **压血利器**：选中目标直伤 | —— |
| `.modify hp/mana <值>` | 改属性 | **大坑：当前值与上限一起改**——**造不出"残血/缺蓝"**！低血只能 `.damage`；缺蓝自己放技能花掉 |
| `.die` | 秒杀选中单位 | **本 fork 没有 `.kill`**（3.3.5 教程看多了会敲空） |
| `.revive [名]` | 复活（复活至满状态） | 后排：它也能救活你的试验 bot |

（选中谁？试验 bot 名字打 `/tar <名>` 或在队伍界面点它——大多数 GM 命令默认作用于当前选中。）

## 7. 试验号配方：搭一台"干净"的 bot

```text
.bot add <名>          挂号成 bot（docs/07 讲过）
.bot init <名> blue    装备按"稀有"档整体重掷（干净可控）
.bot train <名>         学技能
.bot prepare <名>        备好消耗品/材料（吃喝、药水就位）
.bot always <名>        保活（不随随机 bot 排班下线）
```

这套流程的可贵处是**可复现**：同一号 + `reset strats` = 完全一致的起点，A/B 对比才有意义。配方之外的 `.bot` 家族备查：`gear/equip`、`potions`、`food`、`consumes`、`regs`、`enchants`、`ammo`、`pet`、`levelup`、`random`（彻底重掷）、`delete`（删号，慎重）。

## 8. 分场景实测目录（核心）

七个场景按搭台成本从低到高排；每个证明一件独立的事。**场景 0 先跑**——仪器自检不过，后面全是白做。

### 场景 0 · 仪器自检（五分钟）

```
搭台：   .bot add/prepare 一台试验号（§7），组队
触发：   /w <bot> nc +debug，随便走两步打个怪
观察：   密语里出现 do: <动作> 行
判定：   有一条 do: = 三面仪器全通（掉了找 §2-§4 的两个陷阱）
复位：   /w <bot> nc -debug
```

### 场景 1 · 战斗脑 A/B：证明 `co ±包` 真的改行为

```
搭台：   试验号基线就位（reset strats），nc +debug 开播报
触发：   .npc tempspawn <某低等级怪entry> 30   ← 同一编号,每次复现同一只
        让 bot 接敌（d attack 或直接拉它去）
观察：   基线 do: 流；然后 /w <bot> co +threat（或别的你盒里想验的）
        再 .npc tempspawn 同一只 → 新 do: 流
判定：   两轮播报集相比有实差（threat 装上后高危动作消失/换序）
复位：   co -threat；reset strats
```

### 场景 2 · 反射层与机关：不进战斗单测"躲"

```
搭台：   把 bot 带到空地，站在 bot 旁边（5 码内）
        /w <bot> react +magmadar                       ← 手工武装反射包
        （自动武装需要真 boss 11982 在打人——这里绕开它）
触发：   .gobject add 177704                           ← 岩浆炸弹砸在你们脚边
观察：   nc +debug 播报 / 控制台 T:"magmadar lava bomb"
判定：   bot 丢下手里的事→ 播报 move away from hazard；读条中的会被打断
复位：   选中炸弹 .gobject delete；react -magmadar
```

（同一套模板可造 `avoid specific creatures` 的名单实验：`avoid creature` 加名单 → `.npc tempspawn` 那只怪 → 看它绕开。）

### 场景 3 · 躺尸脑：`de ±包` 与死亡自理

```
搭台：   选中 bot（/tar）
触发：   .die                                            ← 一步成"躺"
观察：   看它自动放魂/跑尸（§5 行为表对照）；
        验你自己的包：de +<名> 后有何不同
判定：   期望行为出现（如 accept resurrect：你复活它,它秒接受）
复位：   .revive                         ← 复活直接回平时脑（§2 链条亲证一次）
```

### 场景 4 · 平时脑：把"饿与渴"造出来

```
搭台：   nc +debug；站在城里
触发：   选中 bot → .damage <打掉大半血>          ← 这就是 .modify hp 被封的原因
        缺蓝：让 bot 连放大法亲手花掉（.modify mana 会连上限一起改,同样指望不上）
观察：   do: food / do: drink 相继出现,坐下吃喝
判定：   低血触发吃、缺蓝触发喝；与反射层 potions 不打架（§11 的层级）
复位：   等回满即可
```

### 场景 5 · 副本/Boss 链条排演（docs/10 §8 亲手走一遍）

```
搭台：   带队 bot 一起 .go xyz <MC进门坐标> 409
        （或 .tele 名字——.lookup tele 查"molten"）
触发A:  靠路由——什么都不做,踩图自动 all +molten core（list ai 验证）
触发B:  手动——all +molten core,造 boss：.npc tempspawn 11982 60
        让谁去打一下 boss → start magmadar fight 自锁
观察：   boss 包生效期间：贴脸的远程/奶被拉开 31 码;
        贴着 boss 放 .gobject add 177704 → 全员躲
判定：   与 docs/10 §8 接力图五站逐一对上
复位：   离图自动卸;试验怪超时自灭（tempspawn 的秒数就是干这个的）
```

### 场景 6 · custom 文本策略闭环（零重启外交互）

```
搭台：   想一个小目标,例如"低血时喊救命"（讲究:出厂 say 已有类似——换你的词）
        /w <bot> cs myrescue 1 critical health > say::救我!99
        /w <bot> nc +custom::myrescue        ← 首次启用(之后改行即时热生效)
触发：   选中 bot → .damage <打残>
观察：   播报 do: say… + 屏幕上它真密语你"救我"
判定：   触发词吻合（critical health）、行为生效、改行再 .damage 立刻变
复位：   nc -custom::myrescue;cs 行传空即删
```

## 9. 判定与假阴性（把"没生效"拆开查）

**PASS 的唯一标准：前后播报流有实差**——不是"看起来好像聪明了"。四个常见假阴性（明明生效了却以为没生效）：

1. **没组队** → LogInGroupOnly 吞播报（§3 陷阱 1）；
2. **DebugFilter 命中** → 你盯的动作名在过滤表里（§3 陷阱 2）；
3. **前缀发错台** → 想验平时的事发成了 `co +`；想验反射发成了 `nc +`（四台的包不共享）；
4. **拿 `d` 测触发器** → `d` 只打动作。触发器只能造景。

**失败时的回滚梯队**（从轻到重，依次试）：

```text
co/nc/de/react -肇事包        单拆
reset strats                  回出厂四台配置（你教的策略全没——重教）
reset ai                      连 AI 记忆/存档一起清（最后手段,见 docs/10 §5 命令族）
```

## 10. 一页速查

```text
观察：cdebug help/values/why/engine/history/do/setvalueuin32 ┊ nc +debug / +debug action ┊ 控制台/Server.log(LogLevel/LogFileLevel)
施压：/w <bot> d <动作名>        （impossible/useless/failed/unknown 四态回执）
造景：.npc tempspawn <entry> <秒>┊ .gobject add 177704 ┊ .damage <n> ┊ .aura <spell> ┊ .die ┊ .go xyz / .tele ┊ .cast
复位：co/nc/de/react -包 ┊ reset strats ┊ .revive ┊ 删怪/删机关 ┊ cs 置空
装备：.bot add/init blue/train/prepare/always
```

## 11. 术语表与出处（锚点）

| 断言 | 出处 |
|---|---|
| `cdebug` 装线（命令→动作） | playerbots/playerbot/strategy/triggers/ChatTriggerContext.h:120 + actions/ChatActionContext.h:185 |
| cdebug 分发（子命令总闸） | playerbots/playerbot/strategy/actions/DebugAction.cpp:37 起 |
| `setvalueuin32` 三形态（设置/按名设置/复位） | playerbots/playerbot/strategy/actions/DebugAction.cpp:77-78 |
| 密语 `debug` 走插件协议（与 cdebug 两码事） | playerbots/playerbot/PlayerbotAI.cpp:1628-1635 |
| "do: " 播报字面 | playerbots/playerbot/strategy/Engine.cpp:709 + ReactionEngine.cpp:230 |
| "try: " 未遂播报 | playerbots/playerbot/strategy/Engine.cpp:166-182,285-296 |
| 播报门槛=cdebug 策略 `debug`/`debug action`（平时脑） | playerbots/playerbot/PlayerbotAIConfig.cpp:1107-1126 + strategy/StrategyContext.h:131-136 |
| LogInGroupOnly 默认吞无队播报 | playerbots/playerbot/strategy/Engine.cpp:779-780 + PlayerbotAIConfig.cpp:253 |
| DebugFilter 默认过滤表 | playerbots/playerbot/PlayerbotAIConfig.cpp:464 |
| ActionHistorySize 默认 0 | playerbots/playerbot/PlayerbotAIConfig.cpp:255 |
| `d `/`do ` 前缀截获 | playerbots/playerbot/PlayerbotAI.cpp:1648-1652 |
| 直发动作四态回执 | playerbots/playerbot/PlayerbotAI.cpp:2550-2622 |
| `.bot` 管理命令族（含 init/train/prepare/always/do/debug） | playerbots/playerbot/PlayerbotMgr.cpp:43-83 |
| `.bot init` 品质档（空/white/green/blue/epic/legendary/sync） | playerbots/playerbot/PlayerbotMgr.cpp:2622-2663 |
| `.bot prepare` 加消耗品 | playerbots/playerbot/PlayerbotMgr.cpp:2614-2620 |
| `.npc tempspawn`（生成器）与顶层 `.tempspawn`（列表）两码事 | mangos-classic/src/game/Chat/Chat.cpp:561 及 :230 |
| `.gobject add` 可造 177704 岩浆炸弹 | mangos-classic/src/game/Chat/Chat.cpp:329 + Level2.cpp:1123 |
| `.modify hp` 连上限一起改（造不出残血） | mangos-classic/src/game/Chat/Level1.cpp:672-709 |
| `.die`/`.revive`/`.damage`/`.cast`（均 3 级） | mangos-classic/src/game/Chat/Chat.cpp:965-966,1010 |
| `.go xyz` 仅拒战场图 | mangos-classic/src/game/Chat/Level1.cpp:1771-1804 |
| 命令表三列字段=AllowConsole（允许从控制台用,非仅控制台） | mangos-classic/src/game/Chat/Chat.h（ChatCommand 结构体） + Chat.cpp:3498 |
| Server.log 需 LogFileLevel≥2（默认 0） | mangos-classic/src/shared/Log/Log.cpp:653-678 + mangosd.conf |
| magmadar 反射包手工武装路径 | playerbots/playerbot/strategy/triggers/TriggerContext.h:322 + triggers/MoltenCoreDungeonTriggers.h:34 |

**上手三连**：场景 0 自检（五分钟）→ 场景 1 用 `co ±threat` 感受 A/B → 场景 6 写下你的第一条自定义策略。

**和其他篇的关系**：docs/10 给原理与语法；docs/11 给"应该发生什么"的行动目录；本文管"怎么证明它发生了"。脚本与运行环境（docs/06）不再在此重复。
