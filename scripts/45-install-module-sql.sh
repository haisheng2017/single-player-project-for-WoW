#!/usr/bin/env bash
# ==============================================================================
# 45-install-module-sql.sh —— 导入四个外观/天赋模块的世界库 SQL
#
# 前提：InstallFullDB 已完成（四个库在位）；20 号已挂好模块软链接。
# 只导入世界库（例外：immersive 的角色库首装自建表，见下），导入后不做任何
# UPDATE（水晶模型/坐标见 docs/troubleshooting.md）。
# 除 immersive 自建表外不导入角色库：dualspec/achievements 的角色库脚本会
# DROP 进度表，需要时手工导入并先备份。
#
# 导入清单：
#   transmog / dualspec  → sql/install/world/world.sql
#   achievements         → 01_world_data.sql 再 02_world_update.sql
#                          （跳过西班牙文 03_world_locales.sql）
#   barber               → world_classic.sql（不要 world_tbc.sql）
#   immersive            → sql/install/world/world.sql（npc_text/mangos_string，
#                          DELETE+INSERT 可重跑）+ characters 库首装自建表
#                          custom_immersive_values（表在位则跳过，防重置属性值）
#   zhCN supplements     → classic-db/locales/Chinese/supplements/01..05_*.sql
#                          （补缺/纠错 loc4；ON DUPLICATE KEY UPDATE，可重跑）
#
# 连接信息优先取 classic-db/InstallFullDB.config；可用环境变量覆盖：
#   MYSQL_HOST MYSQL_PORT MYSQL_USERNAME MYSQL_PASSWORD WORLD_DB_NAME
#
# 用法：在父目录  bash scripts/45-install-module-sql.sh
# 幂等：上游 SQL 多为 DELETE+INSERT，可重复执行；重跑 dualspec world.sql
#       会把 DisplayId1 写回 11659（见 troubleshooting）
# ==============================================================================
set -euo pipefail

WOW_ROOT="${WOW_ROOT:-$(pwd)}"
CORE="$WOW_ROOT/mangos-classic"
DBREPO="$WOW_ROOT/classic-db"
CONFIG="$DBREPO/InstallFullDB.config"

for folder in transmog dualspec achievements barber; do
  if [[ ! -d "$CORE/src/modules/$folder" ]]; then
    echo "[ERROR] $CORE/src/modules/$folder missing — run scripts/20-prepare-playerbots.sh first"
    exit 1
  fi
done

# 连接信息：config → 环境变量 → 本体系默认
if [[ -f "$CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG"
fi
MYSQL_BIN="${MYSQL_PATH:-mysql}"
MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USERNAME="${MYSQL_USERNAME:-mangos}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-mangos}"
WORLD_DB_NAME="${WORLD_DB_NAME:-classicmangos}"
CHAR_DB_NAME="${CHAR_DB_NAME:-classiccharacters}"

if ! command -v "$MYSQL_BIN" >/dev/null 2>&1; then
  echo "[ERROR] mysql client not found (MYSQL_PATH=$MYSQL_BIN)"
  exit 1
fi

export MYSQL_PWD="$MYSQL_PASSWORD"
MY=("$MYSQL_BIN" -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USERNAME" --default-character-set=utf8mb4 "$WORLD_DB_NAME")

if ! "${MY[@]}" -e "SELECT 1;" >/dev/null 2>&1; then
  echo "[ERROR] Cannot connect to $WORLD_DB_NAME as $MYSQL_USERNAME@$MYSQL_HOST:$MYSQL_PORT"
  echo "        Check InstallFullDB.config or MYSQL_* / WORLD_DB_NAME env vars"
  exit 1
fi
echo "==> Connected to $WORLD_DB_NAME ($MYSQL_USERNAME@$MYSQL_HOST:$MYSQL_PORT)"

import_sql() {
  local label="$1"
  local file="$2"
  if [[ ! -f "$file" ]]; then
    echo "[ERROR] Missing SQL: $file"
    exit 1
  fi
  echo "==> Importing $label: $file"
  "${MY[@]}" < "$file"
  echo "[OK]  $label"
}

MOD="$CORE/src/modules"

import_sql "transmog world"     "$MOD/transmog/sql/install/world/world.sql"
import_sql "dualspec world"     "$MOD/dualspec/sql/install/world/world.sql"
import_sql "achievements 01"    "$MOD/achievements/sql/install/world/01_world_data.sql"
import_sql "achievements 02"    "$MOD/achievements/sql/install/world/02_world_update.sql"
# barber SQL 非完全幂等（npc_text / 椅子 INSERT）；已装则跳过。
BARBER_ENTRY=190012
BARBER_N=$("${MY[@]}" -N -e "SELECT COUNT(*) FROM creature_template WHERE entry=$BARBER_ENTRY;" 2>/dev/null || echo 0)
if [[ "${BARBER_N//[^0-9]/}" -gt 0 ]]; then
  echo "[SKIP] barber classic (creature_template entry $BARBER_ENTRY already present)"
else
  import_sql "barber classic"     "$MOD/barber/sql/install/world/world_classic.sql"
fi

# immersive：world 侧直接导（DELETE+INSERT，可重跑）；characters 侧是模块自建表
# （不碰标准表）——首装导入，已存在则跳过（避免重跑时重置已配置的属性值）。
# 注意：immersive 的 uninstall/characters.sql 表名写的是 immersive_values，与
# 实际建的 custom_immersive_values 不符（上游小瑕疵）——卸载时手动 DROP 后者。
import_sql "immersive world"     "$MOD/immersive/sql/install/world/world.sql"
MYC=("$MYSQL_BIN" -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USERNAME" --default-character-set=utf8mb4 "$CHAR_DB_NAME")
if ! "${MYC[@]}" -e "SELECT 1;" >/dev/null 2>&1; then
  echo "[ERROR] Cannot connect to $CHAR_DB_NAME as $MYSQL_USERNAME@$MYSQL_HOST:$MYSQL_PORT"
  echo "        Check CHAR_DB_NAME or MYSQL_* env vars / InstallFullDB.config"
  exit 1
fi
import_sql_chars() {
  local label="$1"
  local file="$2"
  if [[ ! -f "$file" ]]; then
    echo "[ERROR] Missing SQL: $file"
    exit 1
  fi
  echo "==> Importing $label: $file"
  "${MYC[@]}" < "$file"
  echo "[OK]  $label"
}
IMM_N=$("${MYC[@]}" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='custom_immersive_values';" 2>/dev/null || echo 0)
if [[ "${IMM_N//[^0-9]/}" -gt 0 ]]; then
  echo "[SKIP] immersive characters (custom_immersive_values already present)"
else
  import_sql_chars "immersive characters" "$MOD/immersive/sql/install/characters/characters.sql"
fi

# 主中文包由 40 号在库空时导入 locales/Chinese/*.sql；此处补缺/纠错（含任务 707）。
SUPP="$DBREPO/locales/Chinese/supplements"
if [[ -d "$SUPP" ]]; then
  echo ""
  echo "==> zhCN locale supplements ($SUPP)"
  import_sql "zhCN quest fixup"       "$SUPP/01_locales_quest_zhCN_fixup.sql"
  import_sql "zhCN creature fixup"    "$SUPP/02_locales_creature_zhCN_fixup.sql"
  import_sql "zhCN item fixup"        "$SUPP/03_locales_item_zhCN_fixup.sql"
  import_sql "zhCN gameobject fixup"  "$SUPP/04_locales_gameobject_zhCN_fixup.sql"
  import_sql "zhCN page_text fixup"   "$SUPP/05_locales_page_text_zhCN_fixup.sql"
else
  echo ""
  echo "[WARN] zhCN supplements missing: $SUPP — skip (clone classic-db with locales/Chinese/supplements)"
fi

echo ""
echo "Done (five modules' world SQL + immersive characters table only; no DisplayId/coord patches)."
echo "Config Enable: scripts/60-start-server.sh (first-time .conf from .dist)."
echo "Dual-spec crystal invisible? See docs/troubleshooting.md (DisplayId / wall coords / creature_respawn)."
echo "Next: docs/09-modules.md verify steps, then scripts/60-start-server.sh"
