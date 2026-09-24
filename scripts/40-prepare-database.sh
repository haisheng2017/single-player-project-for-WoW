#!/usr/bin/env bash
# ==============================================================================
# 40-prepare-database.sh —— 数据库环境预备（MySQL 就绪、装库开关兜底、装后自动验收）
#
# 本脚本把"能自动化的"全部做完，把"必须交互的"打印成清单请你照做：
#   InstallFullDB.sh 本身是交互式菜单设计，无法安全无人值守，最终装库一步
#   请按脚本尾部打印的路线在终端里人工完成（详细解释见 docs/05-database.md）。
#
# 覆盖的 Ubuntu 特有大坑：
#   Ubuntu 打包的 mysql-server 8.0 的 root 默认走 auth_socket 插件——只能
#   `sudo mysql` 进入，密码登录一律拒绝，InstallFullDB 的 root 认证必然失败。
#   本脚本会检测并把 root 改为 caching_sha2_password 密码登录（需要 sudo）。
#
# 装库开关兜底（InstallFullDB.config；两个开关都在"全装"流程中静默生效，
# 不存在单独的 bot SQL 步骤，也不进 Advanced 菜单）：
#   PLAYERBOTS_DB="YES" —— playerbots 三组 SQL（world / world/classic / characters）
#                          随全装自动入库；
#   AHBOT="YES"        —— 顺带导入 core 的 sql/base/ahbot/（游戏内 .ahbot 命令的
#                          command 表行，与 30 号默认 BUILD_AHBOT=ON 呼应）。
#
# 自动验收（装库完成后重跑本脚本即触发）：
#   用 config 里的 mangos 应用账号直连 MySQL，自动检查：四个库、playerbots 的
#   12 张 world 表 / 11 张 characters 动态表 / 8 个战利品索引 / 4 条 .ahbot 命令行。
#   全绿后提示进入 60 号；有缺项时给出对应排障指引。
#
# 用法：  sudo bash scripts/40-prepare-database.sh
#   交互中会让你输入希望给 root 设置的密码（只用于当场写入 MySQL，脚本不落盘）
# 幂等：  可重复执行
# ==============================================================================
set -euo pipefail

WOW_ROOT="${WOW_ROOT:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DBREPO="$WOW_ROOT/classic-db"
CONFIG="$DBREPO/InstallFullDB.config"

[[ $EUID -eq 0 ]] || { echo "[ERROR] Run with sudo (needs to act as MySQL root)"; exit 1; }
[[ -d "$DBREPO" ]] || { echo "[ERROR] Repository directory not found: $DBREPO"; exit 1; }

# 尚未装库时打印人工装库路线（装完重跑本脚本即转自动验收）
manual_hint() {
  cat <<'EOF'

==> Next, finish the install manually (interactive menus; full walkthrough in docs/05-database.md):

  cd <classic-db repo>
  bash InstallFullDB.sh

  1) On first run an "ERROR 1045 ... user 'mangos'" settings menu appears -- normal:
       choose 2) Set root access
       Enter MySQL root user: root           (must be typed; plain Enter = empty user, always fails)
       Enter MySQL root password:            (the root password you just set; no echo while typing is normal)
     After validation the menu entry "9) Exit" becomes "9) Go to main menu" -> choose 9
  2) Main menu -> 4) Full installation (root)
  3) Sub-menu -> 1) Full default CMaNGOS-core and Classic-DB installation
  4) The only confirmation word of the whole run:
     "All previous changes will be lost. Type 'DeleteAll' if you are sure"
     -- type the word verbatim, it is not y/N; plain Enter = silently abort the install.
     playerbots and AHBot SQL are applied automatically inside the full install
     (driven by the PLAYERBOTS_DB / AHBOT = "YES" switches this script has set) --
     there is no separate bot-SQL step and no need for the Advanced menu; the full
     install never asks for 'Mangosbots' (that word only exists on the
     5) Advanced -> 8) standalone re-apply path).
  5) After the install, re-run this script with sudo -> it connects to MySQL
     directly and prints the acceptance check (4 DBs + playerbots tables/indexes
     + .ahbot command rows); all green -> next step scripts/60-start-server.sh
     (configuration: docs/06).
EOF
}

echo "==> MySQL service status check"
systemctl is-active mysql >/dev/null 2>&1 || { echo "[NOTE] Starting mysql ..."; systemctl start mysql || service mysql start; }

echo "==> Checking root auth plugin (Ubuntu default auth_socket pitfall)"
PLUGIN=$(sudo mysql -N -s -e "SELECT plugin FROM mysql.user WHERE user='root' AND host='localhost';" 2>/dev/null || true)
if [[ "${PLUGIN:-}" == "auth_socket" ]]; then
  echo "[NOTE] root uses the auth_socket plugin (password login unavailable) -- switching to password auth"
  read -r -p "Enter a new password for MySQL root (visible while typing, do not leave empty): " ROOT_PASS
  [[ -n "$ROOT_PASS" ]] || { echo "[ERROR] Password is empty, exiting"; exit 1; }
  sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${ROOT_PASS}'; FLUSH PRIVILEGES;"
  echo "[OK]  Switched to password auth, verifying ..."
  # 验证（仅环境变量传参，不落任何文件）
  if MYSQL_PWD="$ROOT_PASS" mysql -uroot -h127.0.0.1 -e "SELECT 1;" >/dev/null 2>&1; then
    echo "[OK]  root password login verified (use this password in the InstallFullDB menus)"
  else
    echo "[ERROR] Password login verification failed; fix manually -- after 'sudo mysql' run:"
    echo "       ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '<password>';"
    exit 1
  fi
else
  echo "[SKIP] root does not use auth_socket (current: ${PLUGIN:-unknown}) -- nothing to do"
fi

echo "==> Install switch: ensure PLAYERBOTS_DB=\"YES\" in InstallFullDB.config (playerbots SQL rides the full install)"
if [[ ! -f "$CONFIG" ]]; then
  echo "[NOTE] InstallFullDB.config does not exist yet -- it is generated on the first run of InstallFullDB.sh."
  echo "       Run that once manually (choose 9 at the menu to exit), then re-run this script:"
  echo "         cd $DBREPO && bash InstallFullDB.sh && sudo bash $SCRIPT_DIR/40-prepare-database.sh"
  exit 0
fi
if grep -q '^PLAYERBOTS_DB="YES"' "$CONFIG"; then
  echo "[SKIP] PLAYERBOTS_DB already YES"
elif grep -q '^PLAYERBOTS_DB=' "$CONFIG"; then
  sed -i 's/^PLAYERBOTS_DB=.*/PLAYERBOTS_DB="YES"/' "$CONFIG"
  echo "[OK]  Set PLAYERBOTS_DB to \"YES\" in InstallFullDB.config"
else
  echo 'PLAYERBOTS_DB="YES"' >> "$CONFIG"
  echo "[OK]  Appended PLAYERBOTS_DB=\"YES\" at the end of InstallFullDB.config"
fi

echo "==> Install switch: ensure AHBOT=\"YES\" in InstallFullDB.config (imports sql/base/ahbot/ -- the in-game .ahbot command rows)"
if grep -q '^AHBOT="YES"' "$CONFIG"; then
  echo "[SKIP] AHBOT already YES"
elif grep -q '^AHBOT=' "$CONFIG"; then
  sed -i 's/^AHBOT=.*/AHBOT="YES"/' "$CONFIG"
  echo "[OK]  Set AHBOT to \"YES\" in InstallFullDB.config"
else
  echo 'AHBOT="YES"' >> "$CONFIG"
  echo "[OK]  Appended AHBOT=\"YES\" at the end of InstallFullDB.config"
fi

# ---------- 自动验收：连接信息全部取自 InstallFullDB.config 的 mangos 应用账号 ----------
# 该账号（含密码）由 InstallFullDB 全装时创建，权限恰好覆盖四个库；
# 尚未装库时连不上属正常（落到人工装库指引分支，不会误报）。
if ! source "$CONFIG" 2>/dev/null; then
  echo "[NOTE] Failed to parse InstallFullDB.config -- skipping the auto-check; manual instructions follow"
  manual_hint
  exit 0
fi
WORLD_DB_NAME="${WORLD_DB_NAME:-classicmangos}"
REALM_DB_NAME="${REALM_DB_NAME:-classicrealmd}"
CHAR_DB_NAME="${CHAR_DB_NAME:-classiccharacters}"
LOGS_DB_NAME="${LOGS_DB_NAME:-classiclogs}"

MYSQL_BIN="${MYSQL_PATH:-mysql}"
if ! command -v "$MYSQL_BIN" >/dev/null 2>&1; then
  echo "[NOTE] mysql client not found (config MYSQL_PATH=$MYSQL_BIN) -- skipping the auto-check"
  manual_hint
  exit 0
fi
export MYSQL_PWD="${MYSQL_PASSWORD:-}"
MYDB=("$MYSQL_BIN" -h"${MYSQL_HOST:-localhost}" -P"${MYSQL_PORT:-3306}" -u"${MYSQL_USERNAME:-mangos}" -N -s)

if ! "${MYDB[@]}" -e "SELECT 1" >/dev/null 2>&1; then
  echo "[NOTE] Cannot connect to MySQL with the config's mangos account yet (normal before the DB install)"
  manual_hint
  exit 0
fi

NDB=$("${MYDB[@]}" -e "SELECT COUNT(*) FROM information_schema.schemata
    WHERE schema_name IN ('$WORLD_DB_NAME','$CHAR_DB_NAME','$REALM_DB_NAME','$LOGS_DB_NAME');" 2>/dev/null || echo 0)
if [[ "${NDB:-0}" != "4" ]]; then
  echo "[NOTE] The four databases are not all present yet (expected: $WORLD_DB_NAME / $CHAR_DB_NAME / $REALM_DB_NAME / $LOGS_DB_NAME; found ${NDB:-0}/4)"
  manual_hint
  exit 0
fi

# 四库都在：直连验收（playerbots 入库状态）
report() {  # <期望值> <实际值> <检查项> <未达标时的指引>
  local exp="$1" got="$2" what="$3" hint="$4"
  if [[ "$got" == "$exp" ]]; then
    echo "[OK]  $what: $got/$exp"
  else
    echo "[MISSING] $what: ${got:-query failed}/$exp -- $hint"
    FAIL=1
  fi
}
FAIL=0

echo ""
echo "==> All four databases present ($WORLD_DB_NAME / $CHAR_DB_NAME / $REALM_DB_NAME / $LOGS_DB_NAME) -- acceptance check:"

WT=$("${MYDB[@]}" -e "SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema='$WORLD_DB_NAME' AND table_name LIKE 'ai_player%';" 2>/dev/null || echo -1)
CT=$("${MYDB[@]}" -e "SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema='$CHAR_DB_NAME' AND table_name LIKE 'ai_player%';" 2>/dev/null || echo -1)
IX=$("${MYDB[@]}" -e "SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema='$WORLD_DB_NAME' AND index_name IN (
      'idx_gameobject_loot_template_item','idx_disenchant_loot_template_item','idx_fishing_loot_template_item',
      'idx_item_loot_template_item','idx_pickpocketing_loot_template_item','idx_reference_loot_template_item',
      'idx_skinning_loot_template_item','idx_creature_loot_template_item');" 2>/dev/null || echo -1)
AH=$("${MYDB[@]}" -e "SELECT COUNT(*) FROM \`command\`
    WHERE name LIKE 'ahbot%';" "$WORLD_DB_NAME" 2>/dev/null || echo -1)

report 12 "$WT" "playerbots world static tables ($WORLD_DB_NAME)" \
  "0 = playerbots not installed (PLAYERBOTS_DB not YES, or a dead symlink -- see troubleshooting #6; re-apply via 5) Advanced -> 8); if playerbots was applied before, first DROP the 8 indexes per the list in docs/05); other values = a previous install stopped halfway"
report 11 "$CT" "playerbots characters dynamic tables ($CHAR_DB_NAME)" \
  "0 = not installed (see above); other values = a previous install stopped halfway (a 5) Advanced -> 8) re-apply completes it)"
report 8  "$IX" "playerbots loot indexes (world loot_template tables)" \
  "present but incomplete = ai_playerbot_indexes.sql aborted midway -- DROP the existing ones first (docs/05 list), then re-apply"
report 4  "$AH" ".ahbot command rows (world 'command' table)" \
  "AHBOT was not YES at install time (upstream config default is NO) -- this script has set it to YES; to backfill the existing DB run once manually: mysql -u<config-user> -p $WORLD_DB_NAME < <core>/sql/base/ahbot/mangos_command_ahbot.sql"

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "[OK] Database acceptance checks all green. Next: strip .dist in run/etc (docs/06) -> scripts/60-start-server.sh"
else
  echo "[ERROR] Some items are not in place (see the [MISSING] lines above); fix them, then re-run this script"
  exit 1
fi
