#!/usr/bin/env bash
# ==============================================================================
# 50-extract-client-data.sh —— 从 1.12.x 客户端提取服务器所需的四个数据目录
#
# 产出：dbc / maps / vmaps / mmaps（自动拷贝到 run/bin/，随服务器使用）
# 前提：
#   - 已运行 30-build-server.sh 且构建机的 CPU 架构为 x86_64/amd64
#     （arm64 上提取器被 core 的 CMake 强制关闭；arm 机器请到任一台 x86_64
#      Linux 机器上跑本脚本，产物为跨平台数据文件，拷回即可用）
#   - 拿到一份 1.12.1 / 1.12.2 / 1.12.3 客户端的 Data/ 目录（构建号
#     5875 / 6005 / 6141 任一皆可；中英文客户端均可）
#
# 提取的 mmaps（bot 寻路数据）生成非常耗时（数十分钟到数小时，取决于 CPU）；
# 提取器会逐项询问，选不完全跳过。四目录中只有 mmaps 是"可选"的——
# 缺 mmaps 服务器仍能启动，仅 bot 寻路智能下降，可后补。
#
# 用法：  bash scripts/50-extract-client-data.sh /path/to/WoW112client
#   客户端目录即包含 Data/（注意大写 D）的那一层
# 幂等：  可重复执行（产物覆盖）
# ==============================================================================
set -euo pipefail

WOW_ROOT="${WOW_ROOT:-$(pwd)}"
CLIENT_DIR="${1:-}"

[[ -n "$CLIENT_DIR" ]] || { echo "用法：bash scripts/50-extract-client-data.sh /path/to/WoW112client"; exit 1; }
[[ -d "$CLIENT_DIR/Data" ]] || { echo "[错误] $CLIENT_DIR 下没有 Data/ 目录——Linux 大小写敏感，必须是先大写 D 的 Data"; exit 1; }

TOOLS_DIR="$WOW_ROOT/run/bin/tools"
[[ -d "$TOOLS_DIR" ]] || { echo "[错误] $TOOLS_DIR 不存在——请先运行 30-build-server.sh（x86_64 机器且开启提取器构建）"; exit 1; }

echo "==> 拷贝提取工具到客户端目录"
cp "$TOOLS_DIR"/* "$CLIENT_DIR"/
chmod +x "$CLIENT_DIR"/*.sh 2>/dev/null || true

echo "==> 运行 CMaNGOS 官方交互式提取脚本（按提示作答；mmaps 可按需跳过/包含）"
cd "$CLIENT_DIR"
bash ./ExtractResources.sh

echo ""
echo "==> 收集产物到服务器数据目录"
MISSING=()
for d in dbc maps vmaps mmaps; do
  if [[ -d "$CLIENT_DIR/$d" ]]; then
    mkdir -p "$WOW_ROOT/run/bin/$d"
    cp -R "$CLIENT_DIR/$d/." "$WOW_ROOT/run/bin/$d/"
    echo "[OK]  $d -> run/bin/$d"
  else
    MISSING+=("$d")
  fi
done

if ((${#MISSING[@]})); then
  echo "[提示] 未产出目录：${MISSING[*]}"
  [[ " ${MISSING[*]} " == *" mmaps "* && ${#MISSING[@]} -eq 1 ]] \
    && echo "      （只有 mmaps 缺失——服务器仍可启动，bot 寻路质量下降，可稍后补提）" \
    || { echo "[错误] 关键目录缺失，请根据上方提取日志排查后重跑"; exit 1; }
fi

echo ""
echo "完成。下一步：scripts/60-start-server.sh"
