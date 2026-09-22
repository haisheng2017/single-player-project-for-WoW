#!/usr/bin/env bash
# ==============================================================================
# 40-prepare-database.sh —— 数据库环境预备（MySQL 就绪、root 密码法、playerbots 开关）
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
# 用法：  sudo bash scripts/40-prepare-database.sh
#   交互中会让你输入希望给 root 设置的密码（只用于当场写入 MySQL，脚本不落盘）
# 幂等：  可重复执行
# ==============================================================================
set -euo pipefail

WOW_ROOT="${WOW_ROOT:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DBREPO="$WOW_ROOT/classic-db"
CONFIG="$DBREPO/InstallFullDB.config"

[[ $EUID -eq 0 ]] || { echo "[错误] 请用 sudo 运行（需要操作 MySQL root）"; exit 1; }
[[ -d $DBREPO ]] || { echo "[错误] 仓库目录不存在：$DBREPO"; exit 1; }

echo "==> MySQL 服务状态检查"
systemctl is-active mysql >/dev/null 2>&1 || { echo "[提示] 启动 mysql ..."; systemctl start mysql || service mysql start; }

echo "==> 检查 root 的认证插件（Ubuntu 默认 auth_socket 的坑）"
PLUGIN=$(sudo mysql -N -s -e "SELECT plugin FROM mysql.user WHERE user='root' AND host='localhost';" 2>/dev/null || true)
if [[ "${PLUGIN:-}" == "auth_socket" ]]; then
  echo "[发现] root 使用 auth_socket 插件（密码登录不可用），现在改为密码登录"
  read -r -p "请输入要为 MySQL root 设置的新密码（输入时可见，请勿留空）: " ROOT_PASS
  [[ -n "$ROOT_PASS" ]] || { echo "[错误] 密码为空，退出"; exit 1; }
  sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${ROOT_PASS}'; FLUSH PRIVILEGES;"
  echo "[OK]  已切换为密码登录，正在验证 ..."
  # 验证（仅环境变量传参，不落任何文件）
  if MYSQL_PWD="$ROOT_PASS" mysql -uroot -h127.0.0.1 -e "SELECT 1;" >/dev/null 2>&1; then
    echo "[OK]  root 密码登录验证通过（后续 InstallFullDB 菜单中就输入这个密码）"
  else
    echo "[错误] 密码登录验证失败，请人工排查：sudo mysql 后执行"
    echo "       ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '<密码>';"
    exit 1
  fi
else
  echo "[跳过] root 非 auth_socket 插件（当前：${PLUGIN:-未知}），无需处理"
fi

echo "==> 安装开关：确保 InstallFullDB.config 里 PLAYERBOTS_DB=\"YES\""
if [[ ! -f "$CONFIG" ]]; then
  echo "[提示] InstallFullDB.config 尚不存在——它由 InstallFullDB.sh 首次运行时生成。"
  echo "       请先手动跑一次（出现菜单后选 9 退出即可），再重跑本脚本："
  echo "         cd $DBREPO && bash InstallFullDB.sh && sudo bash $SCRIPT_DIR/40-prepare-database.sh"
  exit 0
fi
if grep -q '^PLAYERBOTS_DB="YES"' "$CONFIG"; then
  echo "[跳过] PLAYERBOTS_DB 已是 YES"
elif grep -q '^PLAYERBOTS_DB=' "$CONFIG"; then
  sed -i 's/^PLAYERBOTS_DB=.*/PLAYERBOTS_DB="YES"/' "$CONFIG"
  echo "[OK]  已把 InstallFullDB.config 中的 PLAYERBOTS_DB 改为 \"YES\""
else
  echo 'PLAYERBOTS_DB="YES"' >> "$CONFIG"
  echo "[OK]  已在 InstallFullDB.config 末尾追加 PLAYERBOTS_DB=\"YES\""
fi

cat <<'EOF'

==> 接下来请在终端人工完成（交互式菜单，路线全程可对照 docs/05-database.md）：

  cd <classic-db 仓库>
  bash InstallFullDB.sh

  ① 首次会出现 "ERROR 1045 ... user 'mangos'" 的设置菜单 —— 正常现象：
       选 2) Set root access
       Enter MySQL root user: root
       Enter MySQL root password:（输入你刚设置的 root 密码；输入时无回显，属正常）
     验证通过后菜单的 "9) Exit" 变为 "9) Go to main menu" → 选 9
  ② 若出现引导菜单（1) Full default ... / 8) Advanced ...）→ 选 9) Return to main menu
  ③ 主菜单选 4) Full installation
     过程中的确认提示 "All previous changes will be lost. Type 'XXX' if you are sure"
     不是 y/N —— 必须逐字敲提示词（'DeleteAll'、'Mangosbots'），
     其中 'Mangosbots' 那一条专门控制 playerbots 数据是否入库，
     直接回车会被当作"否"并静默跳过（漏装后需 5) Advanced → 8) 补装）。
  ④ 完成后验证四个库都在：
     mysql -uroot -p -e "SELECT table_schema, COUNT(*) FROM information_schema.tables
                         WHERE table_schema LIKE 'classic%' GROUP BY table_schema;"
     并确认 playerbots 表已入库：
     mysql -uroot -p -e "SELECT COUNT(*) FROM information_schema.tables
                         WHERE table_schema='classicmangos'    AND table_name LIKE 'ai_player%';
                            SELECT COUNT(*) FROM information_schema.tables
                            WHERE table_schema='classiccharacters' AND table_name LIKE 'ai_player%';"
EOF
