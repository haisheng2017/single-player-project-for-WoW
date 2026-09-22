#!/usr/bin/env bash
# ==============================================================================
# 20-prepare-playerbots.sh —— 把 playerbots 模块"双保险"挂进 mangos-classic
#
# 背景（务必理解，详见 docs/02-source-layout.md）：
#   1) core 的 CMake 与 classic-db 的 InstallFullDB.sh 都硬编码引用
#      mangos-classic/src/modules/PlayerBots 这一路径 —— 靠软链接来满足；
#   2) 该链接必须是【三层】 ../../.. 相对路径（位于 src/modules/ 内，向上三级
#      才是三仓库父目录）。写成两层会指向 mangos-classic/playerbots（不存在），
#      症状是 InstallFullDB 的 playerbots 环节"静默空转"：显示 SUCCESS 但
#      ai_playerbot_* 一张表都没进库；
#   3) 开 BUILD_PLAYERBOTS 后，CMake FetchContent 的 git 下载路径是
#      先 rm -rf 再 git clone —— 本脚本配套的固定做法是让 30 号构建脚本用
#      -DFETCHCONTENT_SOURCE_DIR_PLAYERBOTS 指向本仓库外的 playerbots 目录，
#      FetchContent 即完全复用本地克隆、不触发下载。指向 core 外目录所需的
#      out-of-tree 二元目录改动【已提交进 fork 主分支】，本脚本只做
#      "在位校验"：不在位时说明当前检出不是 fork 主分支形态，给出诊断而非
#      自动打档。
#
# 用法（在三仓库父目录）：bash scripts/20-prepare-playerbots.sh
#   可用 WOW_ROOT 环境变量指定父目录，如：WOW_ROOT=$HOME/wow bash scripts/20-...
# 幂等：可重复执行
# ==============================================================================
set -euo pipefail

WOW_ROOT="${WOW_ROOT:-$(pwd)}"
CORE="$WOW_ROOT/mangos-classic"
BOTS="$WOW_ROOT/playerbots"

for d in "$CORE" "$BOTS"; do
  [[ -d $d ]] || { echo "[错误] 仓库目录不存在：$d（请在三仓库父目录运行，或设 WOW_ROOT）"; exit 1; }
done

echo "==> 建立三层软链接 src/modules/PlayerBots -> ../../../playerbots"
mkdir -p "$CORE/src/modules"
ln -sfn ../../../playerbots "$CORE/src/modules/PlayerBots"

# 链接正确性自检：必须能顺着链接看到 playerbots 的 SQL
if ls "$CORE"/src/modules/PlayerBots/sql/world/*.sql >/dev/null 2>&1; then
  echo "[OK]  软链接解析正常（已能看到 sql/world/*.sql）"
else
  echo "[错误] 软链接解析失败！请检查 mangos-classic/src/modules/PlayerBots 的链接目标层数"
  ls -la "$CORE/src/modules/"
  exit 1
fi

echo "==> 校验 out-of-tree 支持是否在位（fork 主分支自带，本脚本不打档）"
if grep -q 'add_subdirectory(${playerbots_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR}/modules/PlayerBots)' "$CORE/src/CMakeLists.txt"; then
  echo "[OK]  out-of-tree 二元目录支持已在位（fork 主分支自带）"
elif grep -q 'add_subdirectory(${playerbots_SOURCE_DIR})' "$CORE/src/CMakeLists.txt"; then
  echo "[警告] 当前检出不带 out-of-tree 二元目录支持——fork 主分支已包含该改动。"
  echo "       请确认 mangos-classic 停在 fork 主分支且包含相应提交："
  echo "         cd $CORE && git remote -v && git log --oneline -1"
  echo "       （常见原因：误克隆了上游 cmangos 原仓库，或同步上游时丢失了该行——"
  echo "         参见 docs/troubleshooting.md #4 / #21）"
  exit 1
else
  echo "[警告] src/CMakeLists.txt 既非带支持形态也非补丁前形态——上游可能已重构，请人工检查"
  exit 1
fi

echo ""
echo "完成。下一步：scripts/30-build-server.sh"
