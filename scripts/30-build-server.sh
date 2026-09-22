#!/usr/bin/env bash
# ==============================================================================
# 30-build-server.sh —— 编译服务端（mangosd + realmd + playerbots + 提取工具）
#
# 三个关键点（详见 docs/03-build.md）：
#   a) 编译器必须 gcc-12 或 clang（22.04 默认 gcc-11 有编译器 bug）；
#   b) -DFETCHCONTENT_SOURCE_DIR_PLAYERBOTS 必须带上（复用三仓库布局里的本地
#      playerbots 克隆，避免 CMake FetchContent 先 rm -rf 再从 GitHub 重克隆）；
#   c) x86_64（amd64）机器上 BUILD_EXTRACTORS=ON 可用；arm64 上会被 CMake
#      自动强制 OFF（core 顶层 CMakeLists.txt 的 ARM 检查），届时请到任意
#      x86 Linux 机器上单独提取（见 docs/04-extract.md）。
#
# 用法：在三仓库父目录  bash scripts/30-build-server.sh
#   可用 WOW_ROOT=... 指定父目录；BUILD_CC/BUILD_CXX 可覆盖默认编译器
# 幂等：可重复执行（增量编译）
# ==============================================================================
set -euo pipefail

WOW_ROOT="${WOW_ROOT:-$(pwd)}"
CORE="$WOW_ROOT/mangos-classic"
BOTS="$WOW_ROOT/playerbots"
BUILD_DIR="$WOW_ROOT/build"
INSTALL_DIR="$WOW_ROOT/run"

for d in "$CORE" "$BOTS"; do
  [[ -d $d ]] || { echo "[错误] 仓库目录不存在：$d"; exit 1; }
done

# 已挂载检查（20 号脚本是否跑过）
if ! ls "$CORE"/src/modules/PlayerBots/sql >/dev/null 2>&1; then
  echo "[错误] src/modules/PlayerBots 软链接缺失或解析失败，请先运行 scripts/20-prepare-playerbots.sh"
  exit 1
fi

# 编译器选择：默认 gcc-12，可选 clang
CC_BIN="${BUILD_CC:-gcc-12}"
CXX_BIN="${BUILD_CXX:-g++-12}"
if ! command -v "$CXX_BIN" >/dev/null 2>&1; then
  echo "[提示] 未找到 $CXX_BIN，回退到 clang/clang++"
  CC_BIN="clang"; CXX_BIN="clang++"
  command -v "$CXX_BIN" >/dev/null 2>&1 || { echo "[错误] gcc-12 与 clang 均不可用，请先运行 10-install-deps.sh"; exit 1; }
fi
echo "==> 使用编译器：$CXX_BIN"

echo "==> cmake 配置（FetchContent 双保险参数齐备）"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
CC="$CC_BIN" CXX="$CXX_BIN" cmake "$CORE" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DPCH=1 -DDEBUG=0 \
  -DBUILD_PLAYERBOTS=ON \
  -DFETCHCONTENT_SOURCE_DIR_PLAYERBOTS="$BOTS" \
  -DBUILD_EXTRACTORS=ON

echo "==> 编译（nproc 并行，首次约 10-30 分钟，开启 PCH）"
make -j"$(nproc)"

echo "==> 安装到 $INSTALL_DIR"
make install

echo ""
echo "==> 产物自检："
for f in run/bin/mangosd run/bin/realmd \
         run/etc/mangosd.conf.dist run/etc/realmd.conf.dist \
         run/etc/anticheat.conf.dist run/etc/aiplayerbot.conf.dist; do
  [[ -e "$WOW_ROOT/$f" ]] && echo "[OK]  $f" || echo "[缺失] $f"
done
echo ""
echo "完成。下一步：docs/05-database.md + scripts/40-prepare-database.sh"
