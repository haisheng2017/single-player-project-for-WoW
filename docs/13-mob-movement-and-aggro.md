# 13 · 怪物寻路与仇恨机理（穿墙/飞天/入地/抽搐的病灶图）

> 前置：`docs/04-extract.md`（四数据目录是什么）、`docs/12-playerbots-strategy-testing.md`（GM 造景与单变量纪律——本文的实地复测全部复用它那套手法）。本文与 docs/10-12 分属两个世界：那是 **playerbots 模块**（bot 怎么想），本文是 **服务端核心**（怪怎么走、怎么看上你、怎么打到你）。bot 也是"单位"，行走机制与怪共用——所以 bot 走出诡异路线时，本文同样适用。

**写给谁**：路遇"怪穿过障碍物、飞上高台、遁入地下、上下抽搐、隔层/隔墙被打掉血"想弄清病灶并自己动手修的服主。

**版本边界**：一切断言只对本体系 fork（classic 1.12.1 + playerbots 编入）逐字核实；锚点集中在 §9。

三个读书目标：

1. **看懂病灶**——每个症状在代码里对应哪条通道；修好数据能消掉哪些、哪些是机制本身就会这样；
2. **会做诊断**——容器侧三证 + 游戏内现成的路径可视化器，把"疑似"变"实锤"；
3. **知道修的路**——数据侧重提 / conf 缓解 / 核心补丁三层，各自的代价与边界。

## 1. 三段链：怪的一次移动是怎么发生的

```
 ①想去哪（AI/运动生成器）        ②问路（PathFinder）           ③执行（MoveSpline）
 ─────────────────────────      ───────────────────────      ─────────────────────
 追击/回家/游荡/航点/跟随，        拿 NavMesh（mmaps 里的        把点串连成样条曲线，
 由 MotionMaster 当前挂的         .mmtile 网格）算一条          服务器沿曲线推进位置，
 生成器说了算；每类各有一个       折线：起点→若干中间点；        客户端做插值动画。
 定期器到点就重算一次（§5）       每个点带 (x,y,z)
```

三段各有一个容易想错的真相：

- **② 不是"导航必走"**——它是"导航**尽力**"：任何障碍（没有网格、网格破洞、路径超限、坏数据）都**不报错停车**，而是退成"两点直线"（§2）。直线的终点 Z 就是**目标的原始 Z**——玩家站在高台上，怪的目标点就在高台上，直线的含义就是"从当前位置一路位移过去"：视觉上它"飞"上去。
- **③ 的 Z 基本不贴地**：普通路径点的高度来自 NavMesh 面高度+0.5；而把每个点再贴一次地面的 `NormalizePath` 由 conf 键 `PathFinder.NormalizeZ` 控制，**出厂为 0（关）**（mangosd.conf:273）。地面数据本身再取的是"静态地形高与**动态物件模型高**的较大者"——桥下/棚下位置可能被上面的模型顶面吸上去。
- **① 的雌雄同体**：判"到没到"用**平面距离（2D）**、判"要不要挪窝"用**含高度的立体距离（3D）**——同一只怪两个尺子来回换，是"抽搐"的种子（§5）。

## 2. 降级阶梯："怎么就直线了"

PathType 六种结果码注释了各自的出身（PathFinder.h:61-70）：`NORMAL` 正常、`NOT_USING_PATH` "在飞行/游泳/无 mmap 的地图上"、`SHORTCUT` 按注释原话"travel through obstacles, terrain, air（穿障碍、穿地形、穿空气——老行为）"、`INCOMPLETE` 半程、`NOPATH` 无路、`SHORT` 超限截断。**五个降级口全走同一条出路：两点直线**：

| # | 降级口 | 触发条件 | 结果码 | 速度体验 |
|---|---|---|---|---|
| 1 | 无 mesh/无查询器/单位豁免/起终点无 tile | `!m_navMesh \|\| !m_navMeshQuery \|\| !HaveTile(起点) \|\| !HaveTile(终点)` | NORMAL\|NOT_USING_PATH | **常速**直线（数据缺失最常见的形态；且系统认定"可达"，永不逃避） |
| 2 | 网格破洞 | 起/终点落在任何 poly 之外 | 陆行=NOPATH；会游泳=NORMAL | NOPATH 怪干脆停住（追击遇 NOPATH 返回 false 不动） |
| 3 | 折线超限 | 点数==限长 | SHORT | **直线抄近**——副本长途的大敌（下详） |
| 4 | 坏数据/0 长 | findStraightPath 失败/点数<2 | NOPATH | 怪停住；回家场景则触发 §4 的 400 码闪现 |
| 5 | 回家的终点代管 | forceDest 路径实际终点偏差>1 码且剩余路程>30% | NORMAL\|NOT_USING_PATH | 回家全程直线 |

三个加重点的数字：

- **限长是多少**：点数上限 `MAX_POINT_PATH_LENGTH`——上游 74；**本 fork 编入了 playerbots，是 148**（路径点间隔 4 码，即约 592 码）。副本内按起终点直线距离再加成：>100 码 ×2、>200 码 ×3、>300 码 ×4。超限即 #3：怪在巨大副本里被拉扯出的长路径**静默退化为直线**——这正是"副本内穿墙"的主嫌疑之一。
- **追击有个"贪心直线"短线**：目标在 200 码内、\|高低差\|<5、有视线、双方都不在水里→直接走一步一贴的直线掠射；贴墙被 raycast 打断才退回全路径。指挥 bot 或小号站崖沿/门沿时，"高低差<5"最容易踩中——怪沿崖壁"走"上来。
- **tile 是随网格懒加载的**：`mmtile` 和地图网格同生命周期（进图加载、`GridUnload` 卸载）。跨格长追、或长时间无人后首进冷图，"tile 还没就位"的窗口里问路=#1，直线。

> `mmap.ignoreMapIds` 是反向用途：它把列出的地图**关掉**寻路（配置串默认空）；`mmap.preload` 则是把 tile 提前全量压进内存的开关。

## 3. 仇恨与命中：它怎么"看上你"又怎么"够到你"

```
 巡逻脉冲（怪移动/心跳时对周围玩家配对）
   │  视野门：166 码 + 可见性
   ▼
 DetectOrAttack：
   ├─ 3D 距离 ≤ 攻击半径（基础 20 码，±1 码/级差，下限 5）   ← 立体距离，隔着一层楼也照样"近"
   ├─ LOS：IsWithinLOSInMap —— 由 vmaps 数据供                ← vmap 缺/关 ⇒ 恒真（穿墙对视）
   └─ 都过 ⇒ AttackStart ⇒ 追击生成器上线
 战斗中（每拍 SelectHostileTarget）：
   ├─ 仇恨表选头名（110%/130% 切换：近战位 110%、远位 130%）  ← 只看仇恨值+平面 melee，不看可达性/LOS
   ├─ 挥砍四关：够得着(2D!) / 朝向(120°) / 活着 / 可打        ← 【没有 LOS 这道关】
   └─ 打不中：100ms 后重试（不是关攻击）
```

四条"反直觉"（都已在锚点表里对码）：

1. **NPC 的近战够得着=纯平面**：`dx*dx+dy*dy < reach*reach`——**Z 完全不参与**。怪在你正下方隔着地板、或隔一层楼正上/正下方，只要平面坐标进圈，刀刀命中。"隔层被打掉血"的一等解释，**与任何数据缺失无关，机制本来如此**（玩家控制单位——包括 bot——反而带 dz 判定）。朝向那关也是虚的：选目标时每拍把怪面向自动对正你。
2. **近战无 LOS、法术只在起手时查一次 LOS**：起手过了，读完条那发照飞。vmap 缺那个区域时 LOS"过"了→隔墙开怪/隔墙施法。
3. **仇恨切换不看"打不打得着"**：110%/130% 规则只比较威胁值（外加平面 melee 判定偏好）；**宠物攻击还会给主人也挂一条 0 值表项**——宠物把怪拉上高台后，站在台下的主人也进了表，只是值低；每次被抽脸的 taunt 更是无视位置强切。怪不会因为"这个目标在房顶"降权。
4. **站桩互殴会无限续命战斗**：怪每次挥刀尝试都会重置计时——只要你俩都不动，战斗永不因超时结束。

**"够不到受害目标"的处理链**（追击生成器报告不可达时）：唯一立即掉仇恨的特例是"目标会飞且高度差>3 码"；否则开 10 秒逃脱计时，到期时——仇恨表上**只有一个目标**才真逃（逃=回家路线）；有多个目标则只是**压制当前首选、改打别的**。副本里永远是一群人在表上：怪不回家、继续贴脸直线冲（§4-2）。

## 4. 副本特化病灶（症状"副本内为主"的定向解释）

副本不是普通地图加个入口——核心对副本有四条**不同的规则**，恰好条条都在放大你看到的症状：

| # | 规则 | 锚 | 外显 |
|---|---|---|---|
| 1 | **逃脱回家的特殊通道**：非副本时离家>150 码=原地消失+5 秒后重刷（干净利落）；**副本内不消失**，照走回家线 | HomeMovementGenerator.cpp:52-61 | 副本怪"逃跑成功"后必须真的走回去 |
| 2 | **回家线的飞行速度**：回家路径一旦是 NOPATH/SHORTCUT，spline 速度直接给 **400 码/秒**——直线、穿一切、视觉=瞬移/超音速 | HomeMovementGenerator.cpp:74-75 | 副本名场面："怪闪烁穿墙回家"。注意 #1 口（纯数据缺失）是**常速**直线——"慢慢穿墙"是缺数据、"咻一下"是寻路真失败 |
| 3 | **leash 计时脱战在副本内对非玩家单位停用**（源码注释原话"disabled in instances except for players in BGs"）；仅模板自带 Leash 距离/脚本 leash 仍生效 | CombatManager.cpp:38-39,82-92 + :104-139 | 野外 15 秒追不上就放弃；副本里怪**永不因距离脱战**——拖尸、绕房顶、跳崖都甩不掉，它一直处于"直线冲你"的状态机里 |
| 4 | 限长 ×4 仍然可能不够（§2 重点） | PathFinder.cpp:395-412 | 巨大副本被来回拉扯的长路径照样超限→直线 |

> 把 3+2 连起来看一个高频复合剧本：你在副本里绕柱/跳台甩怪——leash 已停用，追击每 250ms 重算一次拿不到合法路径（NOPATH），10 秒逃脱计时一到期 → 进入回家线 → 回家拿到 NOPATH → **400 码/秒直线起飞**。玩家眼里就是"我明明甩掉它了，它咻地穿到地图另一头回了出生点，然后满血走回来"。

## 5. 垂直抽搐的三台发动机

症状"上下抽搐/原地蹦迪"是**三种节奏的叠加**：

1. **250ms vs 400ms 的错拍**：追击每 250ms 重派一次样条；而位置更新以 400ms 为步长批量提交。且每次新样条启动都会把曲线起点**重新锚定**到"当前计算位置"——两次计算对同一地面高度给出两个值时（vmap 高与地图高合流规则、桥/棚的动态模型顶面），客户端看到的就是往上/往下"闪"一下；
2. **2D/3D 分裂**：判"够得着可以停"是平面 2D（`CanReachWithMeleeAttack`），判"要不要重新找位置"是 3D 距离（`RequiresNewPosition`）。高低差略大于 0 时，两个尺子永远给出相反答案 → 每 250ms 在"停/走"间来回拨动；
3. **贪心直线↔全路径的分支翻转**：贪心分支的准入线是"\|高低差\|<5"；`NormalizeZ=1` 时它还会否决"相邻步高差>1"的路径。高低差在门槛附近抖动时，同一条追击在两种 Z 来源（原始目标 Z vs 网格面高+0.5）间左右横跳。外加崖边"太近了"判 2 秒一次的后撤步（Backpedal 用 3D 判"过近"→后退 0.75 倍→再判）、扇形散开（FanOut）——贴墙/贴崖时表现成侧步抽动。

## 6. 症状 → 根因对照（按你看到的排）

判定口诀：**先用 §7 的两件观测器抓现行，再按本表回位**。每一行都给出"一击确认"的手段。

| 症状 | 根因排序（先查→后查） | 一击确认 |
|---|---|---|
| 追击中**穿过墙/柱/地形** | ① mmaps 该图缺 mesh/tile（§2-1，数据缺失最高嫌疑）→ ② vmap 破洞导致 LOS 恒真喂贪心分支（§2）→ ③ 限长 SHORT（长追，§2-3）→ ④（罕见、未实证）conf 折角优化 `OptimizePath=1` 在几何贴合处的刮蹭——只靠证三 trace 判别 | `Server.log` grep "MMAP:"（§7-证一）；选中怪 `.movement debug on`：密语里 End 点直接是目标位、路径无中间点=直线降级实锤 |
| **飞上高台/崖沿**（缓慢爬） | ① 贪心直线分支命中"\|dz\|<5"（§2 重点）→ ② tile 缺失常态直线（终点=目标原始 Z，§1-②） | 站台沿让怪追：`.movement debug on` 的 Start/End 密语会原样吐出起终点坐标 |
| **咻地瞬移/音速穿墙**（多在逃跑后） | 回家线 NOPATH/SHORTCUT 的 400 码/秒（§4-2）。前提：mmaps 有洞或数据全缺 | 复现"拉怪→甩开→等 10 秒"剧本；`.movement print` 看追击/回家生成器切换 |
| **遁入地下/半埋** | ① 地面高合成被"顶"到错误层（动态物件模型顶面或 vmap 与地图高打架，§1-③）→ ② 网格面本身略低于可见地面（平滑点 +0.5 的缝隙在坡面可见） | 换个平地复测同种怪；若只在特定构造物旁发生=前者 |
| **原地上下抽搐/蹦迪** | §5 三台发动机（机制固有——数据修复只能缓解、断不了根） | 换开阔平地不复现=地形相关；处处复现=机制面 |
| **隔层/隔墙被打掉血**（没看到怪也掉血） | ① NPC 近战 2D 平面判定（§3-1，机制固有）→ ② vmap 缺失→LOS 恒真→隔墙开怪+法术起始通过（§3-2） | 正下方/正上方有怪即中刀=①；隔墙画面外的怪主动开怪=②（证一 grep VMap 串） |
| **怪卡死在**台下面/坡脚不追也不走 | NOPATH（网格洞，§2-2：陆行怪遇 NOPATH 停机） | 该图 mmtile 是否存在（证一） |

## 7. 排障手册

### 证一 · 容器侧三查（服务器宿主或 `docker exec` 进容器执行）

**① 目录体检**——四目录在 `run/bin/` 下（`DataDir="."`，进程从 `run/bin` 启动）：

```bash
ls run/bin/mmaps/*.mmap | wc -l          # 有几个图的导航网格（.mmap 每图一个）
ls run/bin/mmaps | grep -c mmtile        # tile 总数（%03u%02i%02i.mmtile：图号+格坐标）
ls run/bin/mmaps | grep '^036' | head    # 抽查你常去的图（036=死亡矿坑，409=熔火之心…按图号）
ls run/bin/vmaps | grep -c vmtree       # vmaps 每图一个 .vmtree（*.vmtile 为格数据）
```

判读：`mmaps` 目录**不存在**→§8 数据线；存在但某图号**0 命中**→病灶就在该图；`.mmtile` 数量与图规模明显不符（一两百个 tile 对大野外图）→半成品（提取中断过）。

**② 日志纠察**——三串照抄（`run/bin/Server.log`）：

```bash
grep -n "MMAP:loadMapData" run/bin/Server.log   # "Could not open mmap file"=该图整个网格没生成（ERROR 级、有人进图那一刻才打）
grep -n "MMAP:loadMap:" run/bin/Server.log      # "Bad header"/"generator v"=tile 与核心版本不匹配（需要重提）
grep -n "is missing or point to wrong version" run/bin/Server.log   # 同症状的 vmaps 版（整段区域 LOS 变恒真）
```

**③ conf 四键核对**（`run/etc/mangosd.conf`，出厂即正确——错了才是问题）：`vmap.enableLOS/enableHeight/enableIndoorCheck = 1`、`mmap.enabled = 1`、`PathFinder.OptimizePath = 1`、`PathFinder.NormalizeZ = 0`（:265-273）。另记住：**`WORLD: MMap pathfinding enabled` 这行只证明配置开了，不证明数据在**——它读的是 conf，不是磁盘。

### 证二 · 游戏内两件现成观测器

```text
.movement debug on      ← 选中一只怪。此后它每次重算追击都密语你：
                          Start X:… Z:… / End X:… Z:…（外加一行可回放的 .go xyz 坐标）
                          并沿途召唤"脚印怪"标记实际走的线（每 5 秒一枚可视标记）
.movement print         ← 打印选中怪当前追击生成器的内部判定
```

用法即 docs/12 的五段模板：先复位环境 → 选中肇事怪 `.movement debug on` → 按症状表 §6 造景（`.npc tempspawn` 造同种怪、`.go xyz` 把自己放上/放台下、`.damage` 压血诱发逃跑链）→ 收密语判读 → `.movement debug off` 收台。Start→End 若直线穿墙=降级实锤；走位乱序=样条起点重锚抖动。

### 证三 · 深度日志（需要重启，诊断期再开）

`mangosd.conf`：`LogFilter_Pathfinding = 0`（注意这套键 **1=抑制、0=放行**）+ `LogLevel ≥ 2`；想看 tile 逐个装载记录再把 `LogFilter_MapsLoading = 0`（:425-441 一族）。此后 Server.log 会出现 `++ PathFinder::…` 全家桶：`BuildShortcut :: making shortcut`（直线降级）、`BuildPolyPath`（正常路径）、`path … size`（超限判定）。**看到大片的 `making shortcut` = 该区域网格没就位；零星出现在长途 = 限长降级**。测完全部改回 1，debug 日志量很大。

## 8. 修复路线（按此分层动手，本文不代执行）

### 层一 · 数据（治本，90% 的情况查完就到这）

**只补 mmaps**（vmaps 尚在）：到放着工具和客户端 `Data/` 的目录重跑生成器，产物拷回 `run/bin/mmaps/` 重启。两条路：

```bash
bash ./ExtractResources.sh            # 交互式全量；对 mmaps 问答敲 y（提示原文就警告"数小时"）
bash ./MoveMapGen.sh maps              # 只生成 mmaps（等价做法，直接跑生成器脚本）
```

两个坑再念一遍（docs/04 已提）：**上游提取器默认参数全为 0**（`ExtractResources.sh:26` 的 `USE_MMAPS="0"`），一路回车=只有 maps/dbc 没跑完就退出=半成品照拷不误（生成器目录是先行 `mkdir` 的、失败时中断不回滚）；所以回填后**务必回证**：重跑 §7-证一的目录体检+日志纠察，且 `MMAP:loadMapData` 一条都不能剩。arm64 宿主按 docs/04 的说法：数据文件跨平台，可在任意 x86_64 环境生成后拷回。

### 层二 · conf 缓解（不动数据，压症状）

| 改动 | 语义 | 代价 |
|---|---|---|
| `PathFinder.NormalizeZ = 1` | 每个路径点都贴一次地面高：消灭"悬空走直线/面高-地形缝" | 耗 CPU（源码注释自身的警告）；对贪心分支还会更频繁否决直线、回退全路径——CPU 交换 Z 正确 |
| `PathFinder.OptimizePath = 0` | 不做折线抽点：墙角/垛口不再被"抄近道"刮穿 | 路径更绕、整体更钝；多数症状不建议先动它 |
| `mmap.preload = 1` | 开机全量压 tile 入内存：消灭"跨格冷启动窗口"的直线 | 内存+开机时长；副本场景收益有限（图小） |

注意：`mmap.ignoreMapIds` 别当成修复键——它**关**寻路，是反向用途（用于排查对照）。**近战 2D 打人、副本无 leash、逃脱 400 码这三件不是 conf 能治的**（机制面）。

### 层三 · 核心补丁候选（数据完好仍高发才考虑）

按体系约定：core fork 我改代码、提交你自己打。三处候选（只列锚点与思路，均待真动手前先在副本对照测试）：

1. **逃脱飞行限速**：HomeMovementGenerator.cpp:74-75 的 `SetVelocity(400.f)` 改回常规跑速，或做成玩家看得见的显式传送——治"穿墙闪现"。改动一行级、上游偏离最小；
2. **贪心分支增设网格就位门槛**：TargetedMovementGenerator.cpp:502 的准入条件追加"起终点 tile 已载"——治"慢慢爬上崖"（限长 SHORT 的直线同样被约束）。行为偏离中等：绕路变多，注意拉怪手感变化；
3. **NPC 近战 2D→3D**：Unit.cpp:791-810 的 NPC 分支补 dz——治"隔层打人"。**偏离最重**：改变普天下所有怪的近战边界，会大面积改变野外/副本打法（河道边、高差地形处一大批怪将摸不到人）；做也只建议做成"高度差>某阈值才失手"的软化版。

## 9. 术语表与出处（锚点）

正文不引文件，可验性集中于此。锚点为 `mangos-classic/` 仓库相对路径（playerbots/… 前缀除外）；行号以当前 fork 为准。

| 断言 | 出处 |
|---|---|
| PathType 六值（含 SHORTCUT="穿障碍穿地形穿空气"） | src/game/MotionGenerators/PathFinder.h:61-70 |
| 无 mesh/无 tile → 两点直线、照常速、标 NOT_USING_PATH | src/game/MotionGenerators/PathFinder.cpp:162-174 |
| 直线两点的模板与"终点=原始终点 Z" | src/game/MotionGenerators/PathFinder.cpp:1005-1021 + PathFinder.h PathType 注释 |
| 追击仅 NOPATH 停手（其余照走直线派发） | src/game/MotionGenerators/TargetedMovementGenerator.cpp:538-543 |
| 追击贪心直线分支（200 码内+\|dz\|<5+LOS+无水）与 NormalizeZ 否决线 | src/game/MotionGenerators/TargetedMovementGenerator.cpp:502-518 |
| 网格洞→NOPATH（会游者仍直线） | src/game/MotionGenerators/PathFinder.cpp:420-450 |
| 折线超限→PATHFIND_SHORT 直线；限长 148（编入 playerbots 档）/副本 ×2/×3/×4 | src/game/MotionGenerators/PathFinder.cpp:953-958 + PathFinder.h:34-45 + PathFinder.cpp:395-412 |
| 路径点贴地开关（NormalizeZ 默认 0） | src/game/MotionGenerators/PathFinder.cpp:988-1003 + mangosd.conf.dist.in:273 |
| 平滑路径点 Z=面高+0.5；回家 forceDest 直线化 | src/game/MotionGenerators/PathFinder.cpp:1285-1290, 964-981 |
| tile 随地图网格懒加载/同卸载 | src/game/Maps/GridMap.cpp:1299-1303, 786-790 |
| 进战判定=3D 距离+LOS | src/game/AI/BaseAI/UnitAI.cpp:524-530 |
| LOS 供给链 & LOS 关/缺恒真 | src/game/Maps/Map.cpp:2667-2672 + src/game/vmap/VMapManager2.cpp:187-202 |
| vmap.enableLOS 代码默认 false（conf 模板 1 覆盖） | src/game/World/World.cpp:820-840 + mangosd.conf.dist.in:265-273 |
| 启动只查六个出生地（其余图数据残缺不设防） | src/game/World/World.cpp:862-876 |
| NPC 近战=平面 2D（玩家侧才带 dz） | src/game/Entities/Unit.cpp:791-810 |
| 挥砍四关无 LOS、100ms 重试 | src/game/Entities/Unit.cpp:668-712 |
| 施法 LOS 只在起手查一次 | src/game/Spells/Spell.cpp:4860-4864 |
| 站桩互殴重置战斗计时 | src/game/Entities/Unit.cpp:2638-2648 |
| 110%/130% 切换（平面 melee 偏好+taunt 强权） | src/game/Combat/ThreatManager.cpp:331-424 |
| 宠物伤替主人挂 0 值表项 | src/game/Combat/ThreatManager.cpp:484-486 |
| 不可达链：飞高目标特例/10 秒逃脱计时/单目标才真逃 | src/game/Entities/Unit.cpp:8808-8830 + src/game/Combat/CombatManager.h:46 + Unit.cpp:630-644 |
| 副本停用 leash（模板 Leash/脚本 leash 仍生效） | src/game/Combat/CombatManager.cpp:38-39, 82-139 |
| 回家 >150 码非副本消失；副本不消失 | src/game/MotionGenerators/HomeMovementGenerator.cpp:52-61 |
| NOPATH/SHORTCUT 回家=400 码/秒直线 | src/game/MotionGenerators/HomeMovementGenerator.cpp:74-75 |
| 250ms/1000ms/2000ms 追击计时器与 Backpedal 3D"过近" | src/game/MotionGenerators/TargetedMovementGenerator.cpp:35, 176-177, 197-242, 400-415 |
| 位置更新 400ms 步进、样条起点每次重锚 | src/game/Entities/Unit.cpp:11052-11081 + src/game/Movement/MoveSplineInit.cpp:63-74 |
| 停/走 2D-3D 分裂 | src/game/MotionGenerators/TargetedMovementGenerator.cpp:616-636 |
| 地面高=静态地形高与动态物件模型高取 max | src/game/Maps/Map.cpp:2752-2765 |
| `.movement debug`/`print`（管理员级）及其脚怪+密语机制 | src/game/Chat/Chat.cpp:735-746, 1009 + src/game/Chat/Level3.cpp:5720-5756 + src/game/MotionGenerators/TargetedMovementGenerator.cpp:487-495, 520-535 |
| MMAP/VMap 数据缺失与版本不匹配的日志六串 | src/game/MotionGenerators/MoveMap.cpp:117, 227-270 + src/game/Maps/GridMap.cpp:680-686 |
| debug 日志门槛（LogFilter 家族 1=抑制） | src/shared/Log/Log.h:268-272 + mangosd.conf.dist.in:425-441 |
| 提取器默认 USE_MMAPS=0 / mmaps 中断不回滚 / 50 号静默拷贝 | mangos-classic/contrib/extractor_scripts/ExtractResources.sh:26, 73-95 + MoveMapGen.sh:78-100 + 本指导包 scripts/50-extract-client-data.sh:46-62 |

**上手三连**（顺着做，十分钟内有结论）：

```text
证一·三查     ≈ 三分钟看清数据家底（尤其 grep "MMAP:loadMapData"）
.movement debug on + 造景  ≈ 目击一次"直线降级"的密语实锤
回 §6 对照表定位 → §8 按层动手
```

**和其他篇的关系**：docs/04 管数据从哪来（本文不断回头引用它的提取路径）；docs/12 提供 GM 造景与单变量纪律（证二就是按它搭的台）；docs/10-12 是 playerbots 模块的行为层——单位怎么走路是本文的核心侧职责。bot 走位异常同样先查本文证一：bot 与怪共用同一条 PathFinder，数据病两边一起治。
