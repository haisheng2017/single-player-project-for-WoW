#!/usr/bin/env bash
# 85-set-phase.sh —— P1-P6 分阶段开服切换器（2019 官方经典怀旧服六阶段节奏，逐项对齐历史）
#
# 对齐口径（docs/16 §1 的表 + 考据来源）：
#   P1  熔火之心+奥妮克希亚（玛拉顿出厂即开、官方 P1 内容，本脚本不动它）
#   P2  厄运之槌（六入口）+ 卡扎克 + 艾索雷葛斯 + 元素入侵（事件 11/13/38/39）+ 荣誉系统
#   P3  黑翼之巢 + 战歌/奥特兰克两战场 + 战场周(18/19) + 暗月马戏团（AB 属下一幕！）
#   P4  祖尔格拉布 + 阿拉希盆地 + 战场周(20) + 绿龙四王（手工演出）+ 钓鱼大赛(14/15/34)
#   P5  安其拉战争物资全集（游戏内 .worldstate 演出）+ Tier 0.5（无需门控的任务线）
#   P6  纳克萨玛斯 + 天灾入侵（游戏内 .worldstate 演出）
#
# 用法（服务器宿主 / 容器内执行；操作 world 库，需重启生效）：
#   bash scripts/85-set-phase.sh <1-6>                  切到指定阶段（声明式：全量期望状态，幂等）
#   bash scripts/85-set-phase.sh --dry-run <1-6|all>    只打印将执行的 SQL，不落库
#   bash scripts/85-set-phase.sh --restore             从首跑快照完全还原（幂等 INSERT IGNORE）
#
# 重要语义：
#   * 首次真正执行（非 --dry-run）时，先把四张受影响表的相关行快照到
#     run/backup/phase-snapshot.sql（存在则不覆盖），并转一份幂等还原卷
#     run/backup/phase-restore.sql。
#   * 角色库（classiccharacters）零写入：角色/装备/任务/副本进度/荣誉一概不碰；
#     关闭的内容事后照常可还原（--restore），“误拿”的装备不会被剥夺。
#   * BG 模板 / 副本入口条件 / spawn 行在启动时装载 —— 切换后 `.server restart 30`；
#     game_event 的档期改动同样以重启最稳（热启停见 docs/15 §2）。
#   * 事件"开放"= 恢复该族出厂 occurence（各族的出厂值不同：元素 4320 / 战场周 30240 /
#     钓鱼 10080 / 马戏团 86400，核自 classic-db game_event 数据行）；"关闭"= occurence=0
#     （核心把档期推到 2100）。AQ 战争五阶段(120-124 等)与天灾(17/89-99)是 SERVERSIDE
#     核心驱动，本脚本从不动它们 —— 导演命令见 docs/16 §7/§8。
#
# 环境变量（与 40/70 号同风格）：
#   WOW_ROOT（默认当前目录，应含 run/）   WORLD_DB（默认 classicmangos）
#   MYSQL_HOST/MYSQL_PORT（默认 localhost:3306）
#   MYSQL_USER / MYSQL_PASS（不做默认假设——真实执行时逐项交互输入；写脚本/CI 可用环境变量预置）
#   MYSQL_BIN / MYSQL_DUMP_BIN
set -euo pipefail

# bash ≥ 4（关联数组所需）：Ubuntu/容器内置 5.x 天然满足；macOS 自带 3.2 在这里会
# 从"无声哑火"变成"明确指路"——进容器跑，或用 brew 装的新版 bash。
if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
    echo "[错误] 本脚本需要 bash 4+（关联数组）——当前解释器 ${BASH_VERSION:-未知}。"
    echo "       请在服务器/容器内运行(WOW_ROOT 所在处)，或换用新版 bash 再跑。"
    exit 1
fi

WOW_ROOT="${WOW_ROOT:-$(pwd)}"
WORLD_DB="${WORLD_DB:-classicmangos}"
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-}"
MYSQL_PASS="${MYSQL_PASS:-}"
MYSQL_BIN="${MYSQL_BIN:-mysql}"
DUMP_BIN="${MYSQL_DUMP_BIN:-mysqldump}"

BACKUP_DIR="$WOW_ROOT/run/backup"
SNAP_FILE="$BACKUP_DIR/phase-snapshot.sql"
RESTORE_FILE="$BACKUP_DIR/phase-restore.sql"

DRY_RUN=0
PHASE="${1:-}"

if [[ "$PHASE" == "--dry-run" ]]; then
    DRY_RUN=1
    PHASE="${2:-}"
fi

usage() {
    cat <<'EOF'
用法: bash scripts/85-set-phase.sh <1-6>            切阶段（需随后 .server restart 30）
      bash scripts/85-set-phase.sh --dry-run <1-6|all>     预演（只打印 SQL）
      bash scripts/85-set-phase.sh --restore          从首跑快照完全还原
阶段: 1=MC+奥妮          2=+厄运之槌/双世界boss/元素入侵/荣誉   3=+BWL/战歌+奥特兰克/马戏团
      4=+祖格/阿拉希盆地/绿龙/钓鱼大赛   5=+安其拉战争   6=+纳克萨玛斯/天灾入侵
（绿龙四王的 P4 演出与 P5/P6 的 .worldstate 导演戏不在本脚本内，见 docs/16）
EOF
}

# ---- 常量表（默认值即出厂值：classic-db z2815，全部亲验，docs/16 §10 锚点表） ----
# ① 副本入口 areatrigger_teleport.id -> 原生 required_level
#    关闭手段 = required_level 抬到 61（60 封顶世界无人能过，可逆）；开放 = 回原值
#    出厂常开、本脚本从不改的入口：2848 奥妮(lvl50+护符16309)、2886/3528/3529 熔火之心(lvl50+任务7848)、
#    3133/3134 玛拉顿(lvl35，官方 P1 内容)、其余全部 5 人本
declare -A AT_LEVEL=( [3928]=50 [4008]=50 [4010]=50 [3726]=50 [4156]=51
                      [3183]=45 [3184]=45 [3185]=45 [3186]=45 [3187]=45 [3189]=45 )
#    3183-3189 中带 required_level 的六个 = 厄运之槌六入口（东主门/东后门/西主门/西便门…，全 lvl45）
# ② 战场模板（整表出厂恰三行；AB 与另两个分属不同阶段）
BG_ROWS_AV_WSG="(1,20,40,51,60,611,610,100,1),(2,5,10,10,60,769,770,75,0)"
BG_ROWS_AB="(3,8,15,20,60,890,889,75,0)"
# ③ 世界boss creature 行（快照还原；guid 集合）
BOSS_GUIDS="2723,52349"                     # 卡扎克 / 艾索雷葛斯
# ④ 事件族（名 -> 条目集 + 出厂 occurence）
declare -A EV_IDS=( [elemental]="11 13 38 39"   [fishing]="14 15 34"
                    [cta_wsgav]="18 19"          [cta_ab]="20"
                    [dmf]="4 5 23 26 28 37" )
declare -A EV_OCC=( [elemental]=4320   [fishing]=10080
                    [cta_wsgav]=30240  [cta_ab]=30240  [dmf]=86400 )

# ---- 阶段 -> 期望状态（声明式四维） ----
# AT_CLOSED: 该阶段应关闭的入口集合
declare -A AT_CLOSED=(
    [1]="3183 3184 3185 3186 3187 3189 3928 4008 4010 3726 4156"
    [2]="3928 4008 4010 3726 4156"
    [3]="3928 4008 4010 4156"
    [4]="4008 4010 4156"
    [5]="4156"
    [6]="" )
# BG_AVWSG_ON / BG_AB_ON: 战场模板应在否（1=AV 2=WSG 自 P3；3=AB 自 P4）
declare -A BG_AVWSG_ON=( [1]=0 [2]=0 [3]=1 [4]=1 [5]=1 [6]=1 )
declare -A BG_AB_ON=(    [1]=0 [2]=0 [3]=0 [4]=1 [5]=1 [6]=1 )
# BOSS_ON: 世界boss 行应在否（P2 起）
declare -A BOSS_ON=(  [1]=0 [2]=1 [3]=1 [4]=1 [5]=1 [6]=1 )
# EV_CLOSED: 该阶段应保持禁用的事件族列表
declare -A EV_CLOSED=(
    [1]="elemental fishing cta_wsgav cta_ab dmf"
    [2]="fishing cta_wsgav cta_ab dmf"
    [3]="fishing cta_ab"
    [4]=""
    [5]=""
    [6]="" )

# ---- 阶段便签（尾声打印） ----
declare -A PHASE_NOTE=(
    [1]="只剩 MC+奥妮——战场/厄运/元素入侵/其余团本/马戏团全闭（历史上玛拉顿随 P1 在场，未动）"
    [2]="厄运之槌开门、双世界boss+元素入侵回归、荣誉开张（战场仍闭——P2 的历史形态）"
    [3]="BWL + 战歌/奥特兰克两战场（注意：AB 是下一幕的事）+ 战场周 + 马戏团从此按月自开"
    [4]="祖格 + 阿拉希盆地（此刻三战场才齐）+ 钓鱼大赛开张；绿龙四王按 docs/16 §6 在四处梦境之门手工放出"
    [5]="安其拉之门待敲——真实物资路或 .worldstate wareffort phase 3 二选一，见 docs/16 §7"
    [6]="纳克萨玛斯开门（附魔=任务 9378+银色黎明）；天灾入侵按 docs/16 §8 用 .worldstate 导演" )

# ---- DB 连接（凭据不进命令行；账号密码都交给交互输入，不替你假设） ----
# 不知道账号密码？它们就写在服务器配置里：grep DatabaseInfo run/etc/mangosd.conf
# ——四条数据线的格式是 主机;端口;用户;密码;库（docs/06 §2）。
if [[ $DRY_RUN -eq 0 ]]; then
    [[ -z "$MYSQL_USER" ]] && read -r -p "MySQL 用户（mangos 或 root 等）: " MYSQL_USER
    [[ -z "$MYSQL_PASS" ]] && { read -r -s -p "MySQL 密码（静默输入）: " MYSQL_PASS; echo; }
fi
export MYSQL_PWD="$MYSQL_PASS"
MYDB=("$MYSQL_BIN" -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER")

run_sql() { # dry 则打印，否则落库
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "  [SQL] $1;"
    else
        "${MYDB[@]}" "$WORLD_DB" -e "$1" || { echo "[错误] SQL 执行失败：$1"; exit 1; }
    fi
}

make_snapshot() { # 四张受影响表的行片快照（首跑一次；存在则跳过）
    [[ -e "$SNAP_FILE" ]] && { echo "[OK]  快照已存在，不覆盖：$SNAP_FILE"; return 0; }
    mkdir -p "$BACKUP_DIR"
    echo "[前置] 生成出厂快照（四表行片）→ $SNAP_FILE"
    {
        echo "-- phase-snapshot：85 号首跑时自动生成；还原请用 phase-restore.sql"
        "$DUMP_BIN" --no-create-info --no-tablespaces \
            -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" "$WORLD_DB" battleground_template
        "$DUMP_BIN" --no-create-info --no-tablespaces \
            --where="guid IN ($BOSS_GUIDS)" \
            -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" "$WORLD_DB" creature
        "$DUMP_BIN" --no-create-info --no-tablespaces \
            --where="entry IN (4,5,11,13,14,15,18,19,20,23,26,28,34,37,38,39)" \
            -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" "$WORLD_DB" game_event
        "$DUMP_BIN" --no-create-info --no-tablespaces \
            --where="id IN (2848,2886,3184,3183,3185,3186,3187,3189,3528,3529,3726,3728,3928,4008,4010,4055,4156)" \
            -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" "$WORLD_DB" areatrigger_teleport
    } > "$SNAP_FILE" || { echo "[错误] 快照失败"; exit 1; }
    sed 's/^INSERT INTO /INSERT IGNORE INTO /' "$SNAP_FILE" > "$RESTORE_FILE"
    echo "[OK]  幂等还原卷就绪：$RESTORE_FILE"
}

restore_all() {
    if [[ ! -e "$RESTORE_FILE" ]]; then
        echo "[错误] 未找到 $RESTORE_FILE —— 先真正执行过一次 85 号才会生成快照"
        exit 1
    fi
    echo "[还原] 将把快照内容 INSERT IGNORE 回 $WORLD_DB（BG 三行 / boss 行 / 十六事件 / 十七个入口行）"
    "${MYDB[@]}" "$WORLD_DB" < "$RESTORE_FILE" || { echo "[错误] 还原失败"; exit 1; }
    echo "[OK]  还原完成 —— 请 .server restart 30 使其生效"
    echo "[提示] 还原的是首跑时刻的状态；期间的手工演出（如 P4 放的绿龙）另行 mysqldump（docs/15 §3）"
    exit 0
}

do_phase() {
    local p="$1"
    # 用便签表做合法性校验（AT_CLOSED[6]/EV_CLOSED[4..6] 恰是空集，不能拿它们当依据）
    [[ -n "${PHASE_NOTE[$p]:-}" ]] || { echo "[错误] 无此阶段：$p"; usage; exit 1; }

    echo "=== 目标阶段 P$p：${PHASE_NOTE[$p]} ==="
    [[ $DRY_RUN -eq 0 ]] && make_snapshot

    # ① 副本入口：关闭集合抬 61，其余五个团本+厄运六门回原生等级
    echo "[1/5] 副本入口（areatrigger_teleport）"
    if [[ -n "${AT_CLOSED[$p]}" ]]; then
        local closed_ids
        closed_ids="$(echo "${AT_CLOSED[$p]}" | tr ' ' ',')"   # 空格清单→SQL 逗号清单
        run_sql "UPDATE areatrigger_teleport SET required_level=61 WHERE id IN ($closed_ids)"
        echo "      关闭（门槛抬 61，60 封顶即无人可进）：${AT_CLOSED[$p]}"
    fi
    local id lvl
    for id in "${!AT_LEVEL[@]}"; do
        lvl="${AT_LEVEL[$id]}"
        case " ${AT_CLOSED[$p]} " in *" $id "*) ;; *)
            run_sql "UPDATE areatrigger_teleport SET required_level=$lvl WHERE id=$id"
            echo "      开放至原生门槛：AT $id = level $lvl" ;;
        esac
    done

    # ② 战场：AV+WSG 自 P3、AB 自 P4（分幕对齐历史，三行各归各的幕）
    echo "[2/5] 战场（battleground_template 1=AV/2=WSG/3=AB —— 模板缺失则玩家与 bot 双侧干净关闭）"
    if [[ "${BG_AVWSG_ON[$p]}" == 1 ]]; then
        run_sql "INSERT IGNORE INTO battleground_template VALUES $BG_ROWS_AV_WSG"
        echo "      确保奥特兰克+战歌在场（已存在则跳过）"
    else
        run_sql "DELETE FROM battleground_template WHERE id IN (1,2)"
        echo "      移除奥特兰克+战歌（P3 回归）"
    fi
    if [[ "${BG_AB_ON[$p]}" == 1 ]]; then
        run_sql "INSERT IGNORE INTO battleground_template VALUES $BG_ROWS_AB"
        echo "      确保阿拉希盆地在场（已存在则跳过）"
    else
        run_sql "DELETE FROM battleground_template WHERE id=3"
        echo "      移除阿拉希盆地（P4 回归——历史如此，别嫌晚）"
    fi

    # ③ 世界boss 两行
    echo "[3/5] 世界 boss（creature 行：卡扎克/艾索雷葛斯）"
    if [[ "${BOSS_ON[$p]}" == 1 ]]; then
        if [[ $DRY_RUN -eq 0 && -e "$RESTORE_FILE" ]]; then
            grep -E '^INSERT IGNORE INTO `creature`' "$RESTORE_FILE" | "${MYDB[@]}" "$WORLD_DB" \
                || { echo "[错误] boss 行还原失败"; exit 1; }
            echo "      确保两行在场（INSERT IGNORE，已存在则跳过）"
        else
            echo "  [SQL] -- 从 $RESTORE_FILE 幂等还原 creature 两行（卡扎克/艾索雷葛斯）"
        fi
    else
        run_sql "DELETE FROM creature WHERE guid IN ($BOSS_GUIDS)"
        echo "      移除两行（P2 回归；快照随时可还原）"
    fi

    # ④ 事件族：各族要么禁用（occ=0）要么回出厂档（occ 各族不同）
    echo "[4/5] 事件族（game_event 档期）"
    local fam ids occ
    for fam in elemental fishing cta_wsgav cta_ab dmf; do
        ids="$(echo "${EV_IDS[$fam]}" | tr ' ' ',')"
        occ="${EV_OCC[$fam]}"
        case " ${EV_CLOSED[$p]} " in *" $fam "*)
            run_sql "UPDATE game_event SET occurence=0 WHERE entry IN ($ids)"
            echo "      禁用 $fam（条目 [$ids]，档期推到 2100）" ;;
        *)
            run_sql "UPDATE game_event SET occurence=$occ WHERE entry IN ($ids)"
            echo "      恢复 $fam 出厂档（occurence=$occ）" ;;
        esac
    done

    # ⑤ 收尾
    echo "[5/5] 尾声"
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[预演] 未落库。去掉 --dry-run 前请先对照 docs/16 §1 的阶段表核对上方 SQL。"
    else
        echo "[OK]  P$p 已落库。入口条件/BG 模板/spawn/事件档期均在启动时装载 —— 请 .server restart 30"
        echo "[下一步] ${PHASE_NOTE[$p]}"
    fi
}

if [[ "$PHASE" == "--restore" ]]; then
    restore_all
fi

if [[ $DRY_RUN -eq 1 && "$PHASE" == "all" ]]; then
    for p in 1 2 3 4 5 6; do do_phase "$p"; echo; done
    exit 0
fi

[[ -z "$PHASE" ]] && { usage; exit 0; }
[[ "$PHASE" =~ ^[1-6]$ ]] || { echo "[错误] 阶段必须是 1-6"; usage; exit 1; }
"$MYSQL_BIN" --version >/dev/null 2>&1 || { echo "[错误] 找不到 ${MYSQL_BIN}（可 MYSQL_BIN=... 指定）"; exit 1; }
if [[ $DRY_RUN -eq 0 ]]; then
    "${MYDB[@]}" -N -s -e "SELECT 1;" >/dev/null 2>&1 \
        || { echo "[错误] 无法连接 MySQL（账号/密码/端口核对 docs/15 §2）"; exit 1; }
fi
do_phase "$PHASE"
