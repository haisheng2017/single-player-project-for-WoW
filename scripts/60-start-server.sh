#!/usr/bin/env bash
# ==============================================================================
# 60-start-server.sh —— 启动：realmd 后台守护，mangosd 前台接管（保留控制台）
#
# 为什么要以 run/bin 为工作目录启动（重要）：
#   mangosd 的 aiplayerbot.conf 是按"进程工作目录相对路径"（../etc/）自动加载
#   的（playerbots 模块源码 PlayerbotAIConfig.h 的 SYSCONFDIR 定义），realmd 同理
#   （mangos-classic 顶层 CMakeLists 的 if(UNIX) 分支）。别处启动会因找不到配置
#   而使 playerbots 静默失效。本脚本已内置正确的 cd。
#
# 前台跑 mangosd 的原因：mangosd 自带交互控制台（建号、GM 指令都在这里），
#   首次启动若开了随机 bot，会比较久地生成/装备 bot，请等完再操作。
#
# 用法：  bash scripts/60-start-server.sh
#   可选环境变量：WOW_ROOT（默认当前目录）
# 停止：  前台 mangosd 用 Ctrl-C；后台 realmd 用 pkill realmd 或见下方提示
# 幂等：  重复运行会先检测端口占用；缺 .conf 时自动从 .dist 补齐（已存在的一
#         律不覆盖，手改内容不会被碰到）
# ==============================================================================
set -euo pipefail

WOW_ROOT="${WOW_ROOT:-$(pwd)}"
BIN="$WOW_ROOT/run/bin"
ETC="$WOW_ROOT/run/etc"
LOG_DIR="$WOW_ROOT/run/log"

for f in "$BIN/mangosd" "$BIN/realmd"; do
  [[ -e "$f" ]] || { echo "[错误] 缺少二进制 $f —— 先跑 scripts/30-build-server.sh"; exit 1; }
done

# 配置文件兜底：缺失的 .conf 自动从对应 .dist 拷贝；已存在的一律不动（默认装法下
# .dist 默认值即可跑通，详见 docs/06 §2 的必检项说明）。
# 四个模块配置：transmog/dualspec/achievements 模板默认 Enable=0，首次从 .dist
# 生成时改为 1；barber 模板已是 1，只复制。已有 .conf 不覆盖。
COPIED=""
for f in mangosd realmd aiplayerbot anticheat transmog dualspec achievements barber; do
  if [[ -e "$ETC/$f.conf" ]]; then
    :
  elif [[ -e "$ETC/$f.conf.dist" ]]; then
    cp "$ETC/$f.conf.dist" "$ETC/$f.conf"
    case "$f" in
      transmog)     sed -i 's/^Transmog\.Enable *= *0/Transmog.Enable = 1/' "$ETC/$f.conf" ;;
      dualspec)     sed -i 's/^Dualspec\.Enable *= *0/Dualspec.Enable = 1/' "$ETC/$f.conf" ;;
      achievements) sed -i 's/^Achievements\.Enable *= *0/Achievements.Enable = 1/' "$ETC/$f.conf" ;;
    esac
    COPIED="${COPIED}${COPIED:+ }$f.conf"
    echo "[OK]  已从 .dist 模板补齐 $f.conf"
  else
    # 模块配置仅在编了 BUILD_MODULES 时才有 .dist；缺核心配置才硬失败
    case "$f" in
      mangosd|realmd|aiplayerbot|anticheat)
        echo "[错误] $ETC 下既无 $f.conf 也无 $f.conf.dist —— 先跑 scripts/30-build-server.sh（make install 会装入 .dist 模板）"
        exit 1
        ;;
      *)
        echo "[警告] 缺少 $f.conf.dist（未编入对应模块？），跳过"
        ;;
    esac
  fi
done
if [[ -n "$COPIED" ]]; then
  echo "[提示] 本次新补齐：$COPIED —— 若装库时改过数据库账号/密码，请核对 mangosd.conf / realmd.conf 的 DatabaseInfo（docs/06 §2）"
fi

port_busy() { ss -ltn "sport = :$1" 2>/dev/null | grep -q LISTEN; }

if port_busy 3724; then
  echo "[提示] 3724 端口已被监听（realmd 可能已在运行），不再重复启动"
else
  mkdir -p "$LOG_DIR"
  cd "$BIN"
  nohup ./realmd -c ../etc/realmd.conf > ../log/realmd.log 2>&1 &
  echo "[OK]  realmd 已后台启动（日志：run/log/realmd.log，停止：pkill realmd）"
  sleep 1
  port_busy 3724 && echo "[OK]  3724 监听确认" || echo "[警告] 3724 尚未监听，请看 run/log/realmd.log"
fi

cat <<'EOF'

==> 启动 mangosd（前台，控制台可用于建号；正常输出应依次看到：

    四个数据库各 2 条连接成功（MySQL 客户端/服务端版本行）
    Realm running as realm ID 1
    Using World DB: Classic DB version 1.12.1 ... （世界内容 + ACID）
    数据文件全部就位时正常加载地图次数
    —— 若缺数据文件，会以 "Correct *.map files not found" 结束退出（这是
      服务器其余全部正确的标志，回到 docs/04-extract.md 补提取数据）

    首次启动若开了随机 bot，部分启动时间用于生成 bot 角色（正常现象）。

    控制台建号：
      account create <用户名> <密码>
      account set gmlevel <用户名> 3      （3=管理员，可自选）
    关服：Ctrl-C 或控制台 .server shutdown 30

EOF
cd "$BIN"
exec ./mangosd -c ../etc/mangosd.conf
