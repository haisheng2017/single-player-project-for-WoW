#!/usr/bin/env bash
# ==============================================================================
# 70-export-character-data.sh —— 【源端】导出角色数据（characters 整库 + realmd 三表）
#
# 产出三件套（当前目录）：
#   wow-characters-<时间戳>.sql.gz        角色库表级 dump（58+ 张表：角色/物品/任务/公会/
#                                        邮件/bot 的 11 张 ai_playerbot_* 动态表等）
#   wow-realmd-tables-<时间戳>.sql.gz     账号三表：account（含 SRP6 v/s，原密码可登录）、
#                                        account_banned、realmcharacters（不迁 realmlist!）
#   wow-migration-<时间戳>.manifest.txt    时间、revision 列名、行数计数 —— 80 号脚本的
#                                        版本守门依据
#
# 迁移适用面：源服与目标服同为 mangos-classic 系（详见 docs/08）。
# 导出期间 mysqldump --lock-all-tables 全局读锁 → 建议停服或低峰执行。
#
# 用法（在源服的任意 bash 环境，不依赖本指导包的其余部分）：
#   bash 70-export-character-data.sh [--no-realmd]
# 可用环境变量：
#   MYSQL_HOST（默认 localhost） MYSQL_PORT（默认 3306）
#   MYSQL_USER / MYSQL_PASS（未设则交互提示，密码静默输入）
#   MYSQL_BIN / MYSQL_DUMP_BIN（默认 PATH 中的 mysql/mysqldump；macOS 的
#     keg-only 客户端可用如 MYSQL_DUMP_BIN=/opt/homebrew/opt/mysql-client@8.4/bin/mysqldump）
#   DB_PREFIX（默认 classic —— 对应 classiccharacters/classicrealmd）
# 幂等：纯导出，可重复执行（每次生成新时间戳文件）
# ==============================================================================
set -euo pipefail

NO_REALMD=0
[[ "${1:-}" == "--no-realmd" ]] && NO_REALMD=1

MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
DB_PREFIX="${DB_PREFIX:-classic}"
CHAR_DB="${DB_PREFIX}characters"
REALM_DB="${DB_PREFIX}realmd"
MYSQL_BIN="${MYSQL_BIN:-mysql}"
DUMP_BIN="${MYSQL_DUMP_BIN:-mysqldump}"

MYSQL_USER="${MYSQL_USER:-}"
if [[ -z "$MYSQL_USER" ]]; then
  read -r -p "MySQL 用户（源服，需能读 $CHAR_DB / ${REALM_DB}）: " MYSQL_USER
fi
MYSQL_PASS="${MYSQL_PASS:-}"
if [[ -z "$MYSQL_PASS" ]]; then
  read -r -s -p "MySQL 密码（静默输入）: " MYSQL_PASS; echo
fi
export MYSQL_PWD="$MYSQL_PASS"          # 只经环境变量传递，不进命令行/历史/manifest

$MYSQL_BIN --version >/dev/null 2>&1 || { echo "[错误] 找不到 ${MYSQL_BIN}（可用 MYSQL_BIN 指定路径）"; exit 1; }
$DUMP_BIN  --version >/dev/null 2>&1 || { echo "[错误] 找不到 ${DUMP_BIN}（可用 MYSQL_DUMP_BIN 指定路径）"; exit 1; }

MYSQL_CMD=($MYSQL_BIN -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -N -s)

echo "==> 连通性检查"
"${MYSQL_CMD[@]}" -e "SELECT 1;" >/dev/null || { echo "[错误] 无法连接源数据库"; exit 1; }

for db in "$CHAR_DB" $([[ $NO_REALMD -eq 0 ]] && echo "$REALM_DB"); do
  "${MYSQL_CMD[@]}" -e "USE \`$db\`;" >/dev/null 2>&1 || { echo "[错误] 库不存在或无权限：$db"; exit 1; }
done
echo "[OK]  库可访问：$CHAR_DB$([[ $NO_REALMD -eq 0 ]] && echo "、$REALM_DB")"

TS="$(date +%Y%m%d-%H%M%S)"
CHAR_FILE="wow-characters-${TS}.sql.gz"
REALM_FILE="wow-realmd-tables-${TS}.sql.gz"
MANIFEST="wow-migration-${TS}.manifest.txt"

# ---- 版本与计数快照（manifest 素材） ----
char_rev=$("${MYSQL_CMD[@]}" -e "SHOW COLUMNS FROM \`$CHAR_DB\`.character_db_version;" | awk '$1 ~ /^required_/ {print $1; exit}')
realm_rev=$("${MYSQL_CMD[@]}" -e "SHOW COLUMNS FROM \`$REALM_DB\`.realmd_db_version;" 2>/dev/null | awk '$1 ~ /^required_/ {print $1; exit}' || echo "未知")
char_cnt=$("${MYSQL_CMD[@]}" -e "SELECT COUNT(*) FROM \`$CHAR_DB\`.characters;" 2>/dev/null || echo 0)
acct_cnt=$("${MYSQL_CMD[@]}" -e "SELECT COUNT(*) FROM \`$REALM_DB\`.account;" 2>/dev/null || echo 0)

DUMP_ARGS=(--lock-all-tables --default-character-set=utf8 --hex-blob -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER")

echo "==> 导出角色库 ${CHAR_DB}（表级 dump，全局读锁中…）"
"$DUMP_BIN" "${DUMP_ARGS[@]}" "$CHAR_DB" | gzip > "$CHAR_FILE"
echo "[OK]  $CHAR_FILE ($(du -h "$CHAR_FILE" | cut -f1))"

if [[ $NO_REALMD -eq 0 ]]; then
  echo "==> 导出账号三表（account / account_banned / realmcharacters；不动 realmlist）"
  "$DUMP_BIN" "${DUMP_ARGS[@]}" "$REALM_DB" account account_banned realmcharacters | gzip > "$REALM_FILE"
  echo "[OK]  $REALM_FILE ($(du -h "$REALM_FILE" | cut -f1))"
fi

# ---- manifest（不含任何用户名/密码/host 之外的敏感信息） ----
{
  echo "wow-migration manifest"
  echo "exported_at      = $(date '+%Y-%m-%d %H:%M:%S')"
  echo "db_prefix        = $DB_PREFIX"
  echo "characters_db    = $CHAR_DB"
  echo "realmd_db        = $([[ $NO_REALMD -eq 0 ]] && echo "$REALM_DB (tables: account account_banned realmcharacters)" || echo "未导出(--no-realmd)")"
  echo "char_revision    = ${char_rev:-未知}（character_db_version 当前列名）"
  echo "realm_revision   = ${realm_rev}"
  echo "characters_rows  = $char_cnt"
  echo "accounts_rows    = $acct_cnt"
  echo "files            = $CHAR_FILE $([[ $NO_REALMD -eq 0 ]] && echo "$REALM_FILE")"
} > "$MANIFEST"
echo "[OK]  $MANIFEST"

cat <<EOF

完成。把以下三件拷到目标机后运行 scripts/80-import-character-data.sh：
  $CHAR_FILE $([[ $NO_REALMD -eq 0 ]] && echo "$REALM_FILE") $MANIFEST
（迁移原理、版本方向守门、种子账号替换语义等详见 docs/08-character-migration.md）
EOF
