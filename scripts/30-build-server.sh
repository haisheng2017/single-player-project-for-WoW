#!/usr/bin/env bash
# ==============================================================================
# 30-build-server.sh —— 编译服务端（mangosd + realmd + playerbots + ahbot + 模块 + 提取工具）
#
# 关键点（详见 docs/03-build.md / docs/09-modules.md）：
#   a) 编译器必须 gcc-12 或 clang（22.04 默认 gcc-11 有编译器 bug）；
#   b) -DFETCHCONTENT_SOURCE_DIR_PLAYERBOTS 必须带上（复用本地 playerbots
#      克隆，避免 CMake FetchContent 先 rm -rf 再从 GitHub 重克隆）；
#   c) x86_64（amd64）机器上 BUILD_EXTRACTORS=ON 可用；机器名以 arm 开头时
#      （如 macOS arm64）会被 CMake 强制跳过（core 顶层 CMakeLists.txt 的 ARM
#      检查只匹配 ^arm——Ubuntu aarch64 不命中，需实际核对），届时请到任意
#      x86 Linux 机器上单独提取（见 docs/04-extract.md）。
#   d) AHBot（拍卖行机器人）默认随 playerbots 模块版编入，本脚本显式传
#      -DBUILD_AHBOT=OFF。注意方向：core 的 BUILD_AHBOT=ON 是"启用 2021
#      内置老拍卖 bot"，且会同时把模块版 AhBot 编出编译（#ifndef BUILD_AHBOT
#      门控）——不推荐；两版读同一个 run/etc/ahbot.conf，模块模板首节已把
#      内置版键 AuctionHouseBot.Seller/Buyer.Enabled 置 0（详见 docs/03）。
#      模块版的运行配置 run/etc/ahbot.conf 没有上游 install 规则——本脚本
#      在 make install 后自动从模块模板 playerbots/ahbot/ahbot.conf.dist.in
#      拷贝生成（模板无 @ 替换符，直拷即用；已存在时不覆盖）。
#   e) 五个功能模块默认编入（-DBUILD_MODULES=ON 与各 BUILD_MODULE_*；四个
#      外观/天赋 + immersive 进度共享）。源码须已由 20 号脚本挂到 src/modules/
#      {modules,transmog,dualspec,achievements,barber,immersive}；本地缺失时
#      CMake 才会 FetchContent 拉取。make install 会装入对应 .conf.dist；
#      运行时 Enable 由 60 号首次补齐（immersive 另首开两个共享开关）。
#
# 用法：在父目录  bash scripts/30-build-server.sh
#   可用 WOW_ROOT=... 指定父目录；BUILD_CC/BUILD_CXX 可覆盖默认编译器；
#   BUILD_AHBOT=ON 可显式切换为 core 内置老版拍卖 bot（默认 OFF=模块版，见 d 条）
# 幂等：可重复执行（增量编译）
# ==============================================================================
set -euo pipefail

WOW_ROOT="${WOW_ROOT:-$(pwd)}"
CORE="$WOW_ROOT/mangos-classic"
BOTS="$WOW_ROOT/playerbots"
BUILD_DIR="$WOW_ROOT/build"
INSTALL_DIR="$WOW_ROOT/run"

for d in "$CORE" "$BOTS"; do
  [[ -d $d ]] || { echo "[ERROR] Repository directory not found: $d"; exit 1; }
done

# 已挂载检查（20 号脚本是否跑过）
if ! ls "$CORE"/src/modules/PlayerBots/sql >/dev/null 2>&1; then
  echo "[ERROR] src/modules/PlayerBots symlink missing or unresolvable; run scripts/20-prepare-playerbots.sh first"
  exit 1
fi
for folder in modules transmog dualspec achievements barber; do
  if [[ ! -f "$CORE/src/modules/$folder/CMakeLists.txt" ]]; then
    echo "[ERROR] src/modules/$folder missing or unresolvable; run scripts/20-prepare-playerbots.sh first"
    exit 1
  fi
done

# 编译器选择：默认 gcc-12，可选 clang
CC_BIN="${BUILD_CC:-gcc-12}"
CXX_BIN="${BUILD_CXX:-g++-12}"
if ! command -v "$CXX_BIN" >/dev/null 2>&1; then
  echo "[NOTE] ${CXX_BIN} not found, falling back to clang/clang++"
  CC_BIN="clang"; CXX_BIN="clang++"
  command -v "$CXX_BIN" >/dev/null 2>&1 || { echo "[ERROR] Neither gcc-12 nor clang is available; run 10-install-deps.sh first"; exit 1; }
fi
echo "==> Using compiler: $CXX_BIN"

# AHBot：模块版随 playerbots 默认编入；BUILD_AHBOT 选"内置老版"（默认 OFF，
# 机理见头注 d 条）
AHBOT="${BUILD_AHBOT:-OFF}"

echo "==> cmake configure (FetchContent override parameters in place)"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
CC="$CC_BIN" CXX="$CXX_BIN" cmake "$CORE" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DPCH=1 -DDEBUG=0 \
  -DBUILD_PLAYERBOTS=ON \
  -DBUILD_AHBOT="$AHBOT" \
  -DFETCHCONTENT_SOURCE_DIR_PLAYERBOTS="$BOTS" \
  -DBUILD_EXTRACTORS=ON \
  -DBUILD_MODULES=ON \
  -DBUILD_MODULE_TRANSMOG=ON \
  -DBUILD_MODULE_DUALSPEC=ON \
  -DBUILD_MODULE_ACHIEVEMENTS=ON \
  -DBUILD_MODULE_BARBER=ON \
  -DBUILD_MODULE_IMMERSIVE=ON

echo "==> Building (nproc jobs; first run ~10-30 min, PCH on)"
make -j"$(nproc)"

echo "==> Installing to $INSTALL_DIR"
make install

# ahbot.conf（模块版）：模块没有该文件的 install 规则——从模板拷贝生成
# （无 @ 替换符，直拷即用；已存在不覆盖，尊重手工改动）。
# 仅当内置老版未被选中（BUILD_AHBOT=ON 会把模块版编出编译）时需要。
if [[ "$AHBOT" != "ON" && ! -e "$INSTALL_DIR/etc/ahbot.conf" && -f "$BOTS/ahbot/ahbot.conf.dist.in" ]]; then
  cp "$BOTS/ahbot/ahbot.conf.dist.in" "$INSTALL_DIR/etc/ahbot.conf"
  echo "[OK]  Created run/etc/ahbot.conf (no upstream install rule; copied from module template)"
fi

echo ""
echo "==> Artifact self-check:"
for f in run/bin/mangosd run/bin/realmd \
         run/etc/mangosd.conf.dist run/etc/realmd.conf.dist \
         run/etc/anticheat.conf.dist run/etc/aiplayerbot.conf.dist \
         run/etc/transmog.conf.dist run/etc/dualspec.conf.dist \
         run/etc/achievements.conf.dist run/etc/barber.conf.dist \
         run/etc/immersive.conf.dist; do
  [[ -e "$WOW_ROOT/$f" ]] && echo "[OK]  $f" || echo "[MISSING] $f"
done
if [[ "$AHBOT" != "ON" ]]; then
  [[ -e "$WOW_ROOT/run/etc/ahbot.conf" ]] && echo "[OK]  run/etc/ahbot.conf" || echo "[MISSING] run/etc/ahbot.conf"
fi
echo ""
echo "Done. Next step: docs/05-database.md + scripts/40-prepare-database.sh"
echo "       After InstallFullDB: scripts/45-install-module-sql.sh (docs/09-modules.md)"
