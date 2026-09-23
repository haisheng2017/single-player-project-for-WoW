#!/usr/bin/env bash
# ==============================================================================
# 80-import-character-data.sh —— 【目标端】导入角色数据（70 号导出的三件套）
#
# 动作（对目标服，需 InstallFullDB 已完成、mangosd/realmd 已停）：
#   1) 前置检查：MySQL 可连、8085/3724 无监听（服务器进程未跑）、四库在位
#   2) 版本守门：比较 manifest 的源 revision 与目标库 character_db_version 的 z 数字
#      —— 源 ≤ 目标 放行（事后 InstallFullDB 3) core updates 推进表结构）
#      —— 源 > 目标 拒绝（数据比核心新，updates 无法回退，mangosd 必启动失败）
#   3) 逐字确认词（风格与 InstallFullDB 一致）
#   4) characters 整库替换：DROP + CREATE DATABASE（utf8）+ 导入
#      realmd 三表：TRUNCATE account/account_banned/realmcharacters 后导入
#      （realmlist 等目标服自身状态不动；种子账号 1-4 被源服账号集取代——预期行为）
#   5) 验证计数打印 + 后续指引
#
# 用法：
#   bash 80-import-character-data.sh <wow-characters-*.sql.gz> <wow-realmd-tables-*.sql.gz> <wow-migration-*.manifest.txt> [--dry-run]
#   或只给目录（自动取目录内最新的三件套）： bash 80-import-character-data.sh <目录> [--dry-run]
# 环境变量：MYSQL_HOST/PORT/USER/PASS 可覆盖；默认优先从 classic-db/InstallFullDB.config
#   读取连接参数（目标机按本指导包部署则该文件必然存在）
# 幂等：重跑 = 再次替换（每次重新走确认词）；--dry-run 只打印动作不执行
# ==============================================================================
set -euo pipefail

WOW_ROOT="${WOW_ROOT:-$(pwd)}"
CONFIG="$WOW_ROOT/classic-db/InstallFullDB.config"
MYSQL_BIN="${MYSQL_BIN:-mysql}"

# ---- 参数收集 ----
CHAR_FILE=""; REALM_FILE=""; MANIFEST=""; DRYRUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRYRUN=1 ;;
    *)  case "$arg" in
          *characters*.sql.gz)  CHAR_FILE="$arg" ;;
          *realmd*.sql.gz)      REALM_FILE="$arg" ;;
          *manifest*)           MANIFEST="$arg" ;;
          *)  if [[ -d "$arg" ]]; then   # 目录：自动配对最新的三件套
                d="$arg"
                CHAR_FILE=$(ls -1t "$d"/wow-characters-*.sql.gz 2>/dev/null | head -1 || true)
                REALM_FILE=$(ls -1t "$d"/wow-realmd-tables-*.sql.gz 2>/dev/null | head -1 || true)
                MANIFEST=$(ls -1t "$d"/wow-migration-*.manifest.txt 2>/dev/null | head -1 || true)
              else echo "[错误] 无法识别的参数：$arg"; exit 1; fi ;;
        esac ;;
  esac
done
[[ -n "$CHAR_FILE" && -n "$MANIFEST" ]] || { echo "用法：bash 80-import-character-data.sh <chars.sql.gz> [realmd.sql.gz] <manifest> [--dry-run]（或传目录自动配对）"; exit 1; }
for f in "$CHAR_FILE" "$REALM_FILE" "$MANIFEST"; do [[ -z "$f" ]] && continue; [[ -e "$f" ]] || { echo "[错误] 文件不存在：$f"; exit 1; }; done

# ---- 连接参数：config 优先，env 覆盖 ----
MYSQL_HOST="${MYSQL_HOST:-}"
MYSQL_PORT="${MYSQL_PORT:-}"
MYSQL_USER="${MYSQL_USER:-}"
MYSQL_PASS="${MYSQL_PASS:-}"
if [[ -z "$MYSQL_USER" && -f "$CONFIG" ]]; then
  # 只提取键值，不执行 config 文件（避免其中任意 shell 内容被执行）
  MYSQL_USER=$(grep -E '^MYSQL_USERNAME=' "$CONFIG" | tail -1 | cut -d'"' -f2)
  MYSQL_PASS=$(grep -E '^MYSQL_PASSWORD=' "$CONFIG" | tail -1 | cut -d'"' -f2)
  MYSQL_HOST=$(grep -E '^MYSQL_HOST='    "$CONFIG" | tail -1 | cut -d'"' -f2)
  MYSQL_PORT=$(grep -E '^MYSQL_PORT='    "$CONFIG" | tail -1 | cut -d'"' -f2)
fi
MYSQL_HOST="${MYSQL_HOST:-localhost}"; MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-mangos}"
if [[ -z "$MYSQL_PASS" ]]; then read -r -s -p "MySQL 密码（${MYSQL_USER}，静默输入）: " MYSQL_PASS; echo; fi
export MYSQL_PWD="$MYSQL_PASS"
DB_PREFIX="${DB_PREFIX:-classic}"
CHAR_DB="${DB_PREFIX}characters"; REALM_DB="${DB_PREFIX}realmd"

MYSQL_CMD=("$MYSQL_BIN" -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -N -s)

run_sql()  { if [[ $DRYRUN -eq 1 ]]; then echo "[dry-run] SQL: $*"; else "${MYSQL_CMD[@]}" -e "$*"; fi; }
run_file() { if [[ $DRYRUN -eq 1 ]]; then echo "[dry-run] 导入文件: $1"; else gunzip -c "$1" | "$MYSQL_BIN" -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" "$2"; fi; }

# ---- 前置检查 ----
echo "==> 前置检查"
"${MYSQL_CMD[@]}" -e "SELECT 1;" >/dev/null || { echo "[错误] 无法连接目标数据库"; exit 1; }
for port in 8085 3724; do
  if ss -ltn "sport = :$port" 2>/dev/null | grep -q LISTEN; then
    echo "[错误] $port 端口有监听（mangosd/realmd 还在运行）——必须先停服再导入"; exit 1
  fi
done
for db in "$CHAR_DB" "$REALM_DB"; do
  "${MYSQL_CMD[@]}" -e "USE \`$db\`;" >/dev/null 2>&1 || { echo "[错误] 目标库 $db 不存在——请先完成 InstallFullDB（docs/05）"; exit 1; }
done
echo "[OK]  MySQL 可连、服务进程已停、目标库在位"

# ---- 版本守门 ----
echo "==> 版本守门（源 dump vs 目标库）"
src_rev=$(grep -oE 'required_z[0-9]+[^ ]*' "$MANIFEST" | head -1)
tgt_rev=$("${MYSQL_CMD[@]}" -e "SHOW COLUMNS FROM \`$CHAR_DB\`.character_db_version;" 2>/dev/null | awk '$1 ~ /^required_/ {print $1; exit}')
src_z=$(echo "${src_rev:-}" | grep -oE 'z[0-9]+' | head -1 | tr -d 'z'); src_z=${src_z:-0}
tgt_z=$(echo "${tgt_rev:-}" | grep -oE 'z[0-9]+' | head -1 | tr -d 'z'); tgt_z=${tgt_z:-0}
echo "    源（manifest）: ${src_rev:-未知}  |  目标（当前库）: ${tgt_rev:-未知}"
if (( src_z > tgt_z )); then
  echo "[拒绝] 源数据（z${src_z}）比目标 core（z${tgt_z}）新：updates 无法回退、导入后 mangosd 必启动失败。"
  echo "        先升级目标服 core（git pull + 30 号脚本重编译）再迁移。详见 docs/08 第 4 节。"
  exit 1
elif (( src_z == tgt_z )); then
  echo "[OK]  版本相同，导入后无需 core updates"
else
  echo "[OK]  源旧于目标（正常方向）——导入完成后需跑 InstallFullDB 3) Install core updates only"
fi

# ---- 确认（逐字敲提示词，与 InstallFullDB 风格一致；--dry-run 跳过交互） ----
echo
echo "即将执行（不可逆）：DROP DATABASE $CHAR_DB 重建并导入；TRUNCATE $REALM_DB 的 account/account_banned/realmcharacters 后导入（种子账号 1-4 将被源服账号取代）。"
if [[ $DRYRUN -eq 1 ]]; then
  echo "[dry-run] 跳过确认词（预演模式不执行任何写操作）"
else
  read -r -p "All previous changes will be lost. Type 'Migrate' if you are sure : " CONFIRM
  [[ "$CONFIRM" == "Migrate" ]] || { echo "已取消（未输入 Migrate）"; exit 0; }
fi

# ---- 导入 ----
echo "==> characters 整库替换"
run_sql "DROP DATABASE IF EXISTS \`$CHAR_DB\`;"
run_sql "CREATE DATABASE \`$CHAR_DB\` DEFAULT CHARACTER SET utf8;"
run_file "$CHAR_FILE" "$CHAR_DB"

if [[ -n "$REALM_FILE" ]]; then
  echo "==> realmd 三表（TRUNCATE + 导入；realmlist 不动）"
  run_sql "TRUNCATE TABLE \`$REALM_DB\`.account;"
  run_sql "TRUNCATE TABLE \`$REALM_DB\`.account_banned;"
  run_sql "TRUNCATE TABLE \`$REALM_DB\`.realmcharacters;"
  run_file "$REALM_FILE" "$REALM_DB"
else
  echo "[提示] 未提供 realmd dump（--no-realmd 导出？）——账号未迁移，角色可能登录不上，见 docs/08 第 1 节"
fi

# ---- 验证 ----
echo "==> 导入后验证"
for q in "SELECT CONCAT('账号行数: ', COUNT(*)) FROM \`$REALM_DB\`.account" \
         "SELECT CONCAT('角色行数: ', COUNT(*)) FROM \`$CHAR_DB\`.characters" \
         "SELECT CONCAT('bot表数: ', COUNT(*)) FROM information_schema.tables WHERE table_schema='$CHAR_DB' AND table_name LIKE 'ai_player%'"; do
  if [[ $DRYRUN -eq 1 ]]; then echo "[dry-run] SQL: $q"; else "${MYSQL_CMD[@]}" -e "$q"; fi
done

cat <<'EOF'

后续步骤：
  1) 若版本守门提示"源旧于目标"：cd classic-db && bash InstallFullDB.sh → 选 3) Install core updates only
  2) 启动：bash scripts/60-start-server.sh
  3) 用任意一个源服账号的【原密码】实测登录（SRP6 v/s 已随行迁移）
  4) 上号抽查背包/任务/bot（/w <bot名> follow）——详见 docs/08 第 6 节
EOF
