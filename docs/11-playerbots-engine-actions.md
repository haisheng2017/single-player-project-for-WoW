# 11 · 四台引擎的行动目录（出厂策略逐台盘点）

> 前置：`docs/10-playerbots-principles.md`（一拍流水线 §2、四台引擎与反射层 §3、名字体系 §4、`+/−/~` 装卸语法 §5）。本文不再复述原理，逐台引擎回答一个问题：**它出厂到底会做什么、你在游戏里会看见什么**。想验证这些行为是否真的发生 → `docs/12-playerbots-strategy-testing.md`。

**版本边界**：一切断言只对本 fork（classic 1.12.1）有效；逐字 token（策略名等）都在 §9 锚点表复核。

## 1. 这份目录怎么读

一个 bot 此刻的行为是五层叠出来的：

```
 当前行为 =
   ① 通用包      人人一样：mount、avoid mobs、dungeon…
   ② 角色位      近战/远程/坦克/奶 的骨架差异
   ③ 职业包      出生自带：shadow、frost、protection…
   ④ 选装        你用 +/−（或配置/随机 bot 逻辑）加的：stay、guard…
   ⑤ 副本包      进本自动加：molten core…（docs/10 §8）
 —— 底座：四台引擎 × 当前激活的那台（docs/10 §3）
```

全文只写**可观察行为**（"会看见它做什么"），不展开触发器/动作清单。三、四节起每台引擎四个槽位：切台条件 / 出厂通用包 / 角色位变体 / 本台反直觉。

## 2. 什么时候算"打起来了"（四台共同的铺垫）

引擎切换看的**不是**角色身上的"战斗中"旗标，而是一条状态值 **"has attackers"（有攻击者）**——清单里不止"正在打我的怪"，还包括**正在打我队友的怪**。由此推出几个平时解释不清的现象：

- 你还没被点名、但队友已经拉到怪 → 你的 bot 已经切进战斗脑（"组队即共战"）；
- 怪被嘲讽走/脱火后旗标还没消 → bot 可能已经切回平时脑去喝水了；
- 切台的扳道器（combat start / combat end / death / resurrect 四个触发器 → `set combat state` 等）住在**反射层**、由每个职业包装配——所以任何职业的 bot 都自动有这套开关。

```
                  有攻击者（清单非空）
     NON-COMBAT ────────────────────►  COMBAT
         ▲   ◄──────────────────────      │
         │        清单清空                │ 死亡
         │ 复活                           ▼
         └──────────── DEAD ◄───────────┘
   注意：没有 DEAD→COMBAT 直通——躺尸复活先回平时脑，
   谁重新拉怪谁再切战斗脑。
```

## 3. COMBAT 战斗脑：打起来了以后它在忙什么

**切台条件**：有攻击者。管的事：选目标、站位、跟进输出/治疗/拉仇恨；保命类大部分不在它手里（在反射层，§6）。

出厂通用包（每个职业都先挂这些）：

| 策略名 | 装上后你会看到 |
|---|---|
| `mount` | 跨图赶路时上马（与平时脑共用坐骑管理） |
| `avoid mobs` | 路径规划自动绕开没在打的怪群（地图上画"避让区"）——**副本内自动失效**（空间窄，避让会出不来） |
| `dungeon` | 进副本图自动叠副本包（docs/10 §8 的路由器，战斗/平时两侧都挂） |
| `avoid specific creatures` | 名单里有怪才生效——名单出厂是**空的**（§6） |
| `racials` `default` `duel` `pvp` | 种族技能自动掺入、常规兜底、决斗应对（非战场时挂——进了战场另有战场包体系管） |

角色位骨架（职业包差异都叠在这层上）：

| 策略名 | 装/默认 | 装上后你会看到 |
|---|---|---|
| `close` | 近战系默认 | 贴到脸打；怪跑远就追进近战距离 |
| `behind` | 近战输出位默认 | 绕到目标**背后**输出（正面招架/格挡少） |
| `ranged` | 施法系默认 | 与怪拉开施法距离；被贴脸→退到射程（配合通用 `flee`） |
| `dps assist` | 输出位默认 | 目标锁定**队伍当前的输出目标**（不乱打） |
| `tank assist` | 坦克位默认 | 目标锁定**坦克的目标**（帮拉/帮控） |
| `pull` `pull back` | 坦克位默认 | 开怪前的拉怪编排（远程武器/法术拉，拉完退回队伍） |
| `wait for attack` | 选装 | 组真人队时开战后**憋几秒**再动手（等坦克站稳） |
| `kite` | 选装 | 有仇恨时边退边打（风筝） |

**本台反直觉**：

- **`threat` 不是嘲讽系统**——它是一个纯倍率器：自身仇恨爬到坦克的约 80% 以上时，把高危动作**清零**（宁可站着也不放大招）。真正的嘲讽在坦克职业包里（仇恨丢失 → 嘲讽）。
- **随机 bot 出厂自带 `-threat`**（配置默认把 threat 拆了，还挂上 `+custom::say`）；**小号 bot 的战斗追加清单出厂为空**。想看"会克制仇恨的随机 bot"，得自己 `co +threat` 加回去。
- 嘲讽/打断/驱散这些"教科书动作"都不在通用层——全在职业包里，所以职业错包=行为残缺（§7 表）。

## 4. NON-COMBAT 平时脑：没打架的时候它在忙什么

**切台条件**：没有攻击者。出厂挂的（逐字）：

| 策略名 | 装上后你会看到 |
|---|---|
| `wbuff` | 世界 buff（屠龙者的呐喊那类）缺了会去取；拆掉会主动洗掉 |
| `avoid mobs` | 同战斗脑（副本内失效） |
| `dungeon` | 副本路由平时侧（进本/离本装卸副本包） |
| `racials` | 种族技能兜底 |
| `food` | 低血→坐下**吃**；缺蓝→坐下**喝**（衔接 §6 反射层急救，两回事） |
| `follow` 或 `wander` | 跟主人（不脱离跟随半径）/没主人时附近溜达，二选一（互斥） |
| `default` | 兜底动作 |
| `quest` | 靠近任务 NPC 自动对话/接/交 |
| `loot` | 有战利品→捡；远了→走过去捡 |
| `gather` | 路过尸体/草/矿→顺手采集 |
| `duel` `emote` | 被邀决斗会应战；闲时做表情 |
| `buff` | 有人申请 buff 会补；出门先上增益 |
| `mount` | 距离拉远时先上马再说 |

随机器人身份另选装一批（自由 bot 按配置与概率）：`roll`（需求贪婪自动掷）、`lfg`、`collision`（跟人挤一起时挪开）、`grind`（闲就找怪练级）、`group` `guild`（凑队/进会/做公会订单）、`travel` `tfish`（跨图办事、钓鱼）、`rpg`（NPC 间"过日子"：找商人修理、闲逛、闲聊）、`bg`（进战场）、`maintenance`（清任务栏、销毁垃圾、拆装附魔等家务批量）。

**本台反直觉**：

- **奶妈独身挂 `grind` 也不打怪**——"主动攻击"这个动作对奶位（未装战斗 `offdps`）是关闭的。想让牧师 bot 出门自己练级：`co +offdps`（该名字是否可装取决于配置项 enableOffSpecStrategies，§7）；
- 出厂清单里源码还喊了一声挂 `"nc"`——这个**名字在 classic 根本没注册过**（只有 DK 版注册），挂载是**静默空操作**。看 `list ai` 时别在这上面浪费时间；
- **默认没装的常用品**：`stay`（原地待命）、`guard`（守点）、`sit`、`explore`、`map`、`return`、`lfg`（小号侧想排本要自己加）、`attack tagged`、`fish`——都要 `nc +名字` 亲手装。

## 5. DEAD 躺尸脑：躺下以后它在忙什么

出厂挂：`dead,stay,default,follow,group,dungeon`（free 且无队的把 follow 拆了——没人可跟）。行为上：

| 行为 | 你会看到 |
|---|---|
| 自动放魂（auto release） | 死了过几秒自动变鬼（组着真人且同在副本时会等一等） |
| 找尸/捡尸 | 幽灵自动跑尸（`find corpse`→`revive from corpse`） |
| 灵魂石自起 | 有绑灵魂石就用（`self resurrect`） |
| 应急复活 | 情况急（躺太久/卡死）走墓地天使（`spirit healer`） |
| 连死撤离 | 连续死亡到门槛（约 15 次）→ 直接大复活+传送回主城（repop，free 角色） |
| 应答复活 | 有人复活它自动接受（`accept resurrect`） |
| 组队规矩 | 组着队时鬼魂跟主人飘；队长长期掉线会退队 |

§2 说过：复活瞬间直落平时脑——没有"跳起来就打"的路径。

## 6. REACTION 反射层：值夜的那几个包

出厂挂（逐字）：`react,chat,avoid aoe,avoid specific creatures,potions,dungeon`。**classic 真相：`react` 这个名字只有 DK 版注册——本栈没有 DK，这一声挂载是空操作**；起作用的是其余几位：

| 包名 | 触发时它做什么 |
|---|---|
| `chat` | 你那整张密语命令表（docs/10 §5）在引擎侧的承载体——每个命令字都是"触发器→动作" |
| `avoid aoe` | 脚下出现伤害性地面效果（法师的暴风雪那类）→ **立刻拔腿躲**；躲开前**封住自己一切需要读条的施法**（只许瞬发/移动） |
| `avoid specific creatures` | 名单里指定的怪出现在 10 码内 → 拉开 15 码。名单出厂**空**——密语 `avoid creature` 命令（或角色库存档）才往名单里添 |
| `potions` | 濒死→**治疗石→治疗药水→绷带**链式自救；缺蓝→黑暗符文→法力药水；vanilla 还认鞭根块茎；中了毒→解毒剂 |
| `dungeon` | 副本路由的反射侧（进本一瞬间的切包由它拍板） |

外加：切台扳道器（§2 的四个触发器）也由职业包装配在这层——宁可说反射层是**"中枢神经"**：既要值夜自救，也负责按时把大伙儿叫醒换台。

**本台反直觉**："躲 AoE"只认**地面效果型**（画在地上的那类圈）；"点名朝谁读条"不属于它管——那是职业包内打断技能的活。

## 7. 角色位与九职业出厂表

角色位不是固定档案——**bot 是近战还是远程、是坦还是奶，读的是当前装的策略自带的角色旗标**。这带来一个强力事实：`+/−` 切包 = 换角色位。例：给法师发 `co -ranged +close` 就是逼它转近战莽夫打法（不推荐，但引擎支持）。

天赋路（spec）判定 = 投点最多的天赋 tab；**10 级以下/未投天赋**走固定默认（法师、牧师→1；圣骑、战士→2；其余→0）。

出厂战斗包一览（职业各行末的"公共尾包"是该职业全天赋共用的那一串；`off*` 仅当配置 enableOffSpecStrategies 开时加装）：

| 职业 | 天赋路 | 出厂 co 包（逐字） |
|---|---|---|
| 战士 | 防（tab2） | `protection,tank assist,pull,pull back,close` |
| 战士 | 武器（<30 级或 tab0） | `arms,dps assist,behind` |
| 战士 | 狂怒（其余） | `fury,dps assist,behind` |
| 战士 | 公共尾 | `aoe,cc,buff,boost` |
| 牧师 | 戒律/神圣/暗影 | `discipline`(+offheal) / `holy`(+offdps) / `shadow`(+offheal)；尾 `dps assist,flee,cure,ranged,cc,buff,aoe,boost` |
| 法师 | 奥术/火焰/冰霜 | `arcane`/`fire`/`frost`；尾同牧师 |
| 萨满 | 元素（tab0） | `elemental,aoe,cc,flee,ranged`(+offheal) |
| 萨满 | 恢复（tab2） | `restoration,flee,ranged`(+offdps) |
| 萨满 | 增强（其余） | `enhancement,aoe,cc,close`(+offheal)；尾 `dps assist,cure,totems,buff,boost` |
| 盗贼 | 刺杀/敏锐/战斗 | `assassination`/`subtlety`/`combat`；尾 `dps assist,aoe,close,cc,behind,stealth,poisons,buff,boost` |
| 术士 | 痛苦/恶魔/毁灭 | `affliction`/`demonology`/`destruction`；尾 `dps assist,flee,ranged,cc,pet,aoe,buff,boost,curse` |
| 德鲁伊 | 坦野（tab1 且带坦克判定天赋） | `tank feral,tank assist,pull,pull back,close` |
| 德鲁伊 | 猫（tab1 无厚皮） | `dps feral,dps assist,close,behind`(+offheal) |
| 德鲁伊 | 恢复/平衡 | `restoration`(+offdps)/`balance`(+offheal) + `dps assist,flee,ranged`；尾 `cure,aoe,cc,buff,boost` |
| 圣骑 | 防（tab1） | `protection,tank assist,pull,pull back,close` |
| 圣骑 | 神圣（tab0）/惩戒（其余） | `holy,dps assist,flee,ranged`(+offdps) / `retribution,dps assist,close`(+offheal)；尾 `cure,aoe,cc,buff,boost,aura,blessing` |
| 猎人 | 兽王/生存/射击 | `beast mastery`(tab0)/`survival`(tab2)/`marksmanship`(其余)；尾 `dps assist,ranged,cc,aoe,buff,boost,aspect,sting,pet` |

（每个职业都还有 §3 开头的通用前缀那一份；罕见差异以游戏内 `list ai` 实测为准——它就是"这号当前真挂了什么"的权威。）

## 8. 出厂没装、常被以为装了的（神话粉碎）

| 你以为 | 实际 |
|---|---|
| "bot 会自动标怪" | `mark rti` 选装——默认不标 |
| "远程会被贴脸拉开" | 是的，但要装着 `ranged`（施法系出厂有）；坦克/近战没有这个反射 |
| "组真人队 bot 会等坦克" | `wait for attack` 选装，默认不装 |
| "牧师小号也会自己练级" | 奶位无战斗 `offdps` 不主动攻怪 |
| "随机 bot 会控仇恨" | 出厂配置是 **-threat**（拆掉了） |
| "平时它待在原地" | 出厂是 `follow`/`wander`；`stay` 要自己装 |

## 9. 术语表与出处（锚点）

正文不引文件，可验性集中于此。锚点为两仓相对路径；行号以当前 fork 为准，同步上游后漂移则按术语 grep。

| 断言 | 出处 |
|---|---|
| 四态枚举 | playerbots/playerbot/BotState.h:5-8 |
| 战斗脑通用前缀（mount/avoid mobs/dungeon/avoid specific creatures + 非战场 racials,default,duel,pvp） | playerbots/playerbot/AiFactory.cpp:296-304 |
| 九职业出厂包逐字 | playerbots/playerbot/AiFactory.cpp:306-528 |
| 天赋路判定（最高 tab；<10 级固定默认） | playerbots/playerbot/AiFactory.cpp:52-90 |
| 平时脑出厂（wbuff/avoid mobs/dungeon + racials,nc,food,follow|wander,…） | playerbots/playerbot/AiFactory.cpp:900-935 |
| 躺尸脑出厂（dead,stay,default,follow,group,dungeon） | playerbots/playerbot/AiFactory.cpp:1119-1125 |
| 反射层出厂（react,chat,avoid aoe,avoid specific creatures,potions,dungeon） | playerbots/playerbot/AiFactory.cpp:1319 |
| `nc` 在 classic 无策略注册（DK 版才有） | playerbots/playerbot/strategy/deathknight/DKAiObjectContext.cpp:31 |
| 切台看 "has attackers"（含打队友的怪） | playerbots/playerbot/strategy/triggers/BotStateTriggers.cpp:8-39 |
| 切台扳道器走反射层、由职业包装配 | playerbots/playerbot/strategy/generic/ClassStrategy.cpp:62-78 |
| threat 是倍率器（≥80% 清零高危） | playerbots/playerbot/strategy/generic/ThreatStrategy.cpp:9-49 |
| 嘲讽在坦克包（lose aggro→taunt） | playerbots/playerbot/strategy/warrior/ProtectionWarriorStrategy.cpp:87-89 |
| 随机 bot 默认 `-threat,+custom::say`；小号清单为空 | playerbots/playerbot/PlayerbotAIConfig.cpp:266-273 |
| 喝水触发器注册名 "high mana"（实际蓝<65% 才亮） | playerbots/playerbot/strategy/generic/UseFoodStrategy.cpp:7-19 + triggers/GenericTriggers.cpp:28-31 |
| 奶位无 `offdps` 不主动攻击 | playerbots/playerbot/strategy/actions/ChooseTargetActions.cpp:27-32 |
| avoid mobs 副本内失效 | playerbots/playerbot/strategy/actions/SetAvoidAreaAction.cpp:59（`if (bot->GetInstanceId())` 一票否决） |
| avoid aoe 封读条施法 | playerbots/playerbot/strategy/generic/CombatStrategy.cpp:35-73 |
| avoid specific creatures 名单出厂为空 | playerbots/playerbot/strategy/actions/DungeonTriggers.cpp:252-286 |
| potions 自救链 | playerbots/playerbot/strategy/generic/UsePotionsStrategy.cpp:30-58 |
| 躺尸行为全表 | playerbots/playerbot/strategy/generic/DeadStrategy.cpp:9-48 |
| `react` 仅 DK 注册 | playerbots/playerbot/strategy/deathknight/DKAiObjectContext.cpp:31-32 |

**上手三连**：`list ai` 对照 §7 表逐个号核包名 → 挑一个 `co -名` 拆掉看行为差 → `reset strats` 回出厂再来一遍。

**和其他篇的关系**：docs/10 讲"怎么想"与装卸语法；**docs/12** 讲本文每条行为怎么实测验证；docs/09 是另装的五个功能模块，与 bot 策略体系不相干。
