#!/usr/bin/env bash
# ==============================================================================
# 20-prepare-playerbots.sh —— 把 playerbots 与四个外观/天赋模块挂进 mangos-classic
#
# 背景（务必理解，详见 docs/02-source-layout.md / docs/09-modules.md）：
#   1) core 的 CMake 与 classic-db 的 InstallFullDB.sh 都硬编码引用
#      mangos-classic/src/modules/PlayerBots 这一路径 —— 靠软链接来满足；
#   2) 该链接必须是【三层】 ../../.. 相对路径（位于 src/modules/ 内，向上三级
#      才是父目录）。写成两层会指向 mangos-classic/playerbots（不存在），
#      症状是 InstallFullDB 的 playerbots 环节"静默空转"：显示 SUCCESS 但
#      ai_playerbot_* 一张表都没进库；
#   3) 开 BUILD_PLAYERBOTS 后，CMake FetchContent 的 git 下载路径是
#      先 rm -rf 再 git clone —— 本脚本配套的固定做法是让 30 号构建脚本用
#      -DFETCHCONTENT_SOURCE_DIR_PLAYERBOTS 指向本仓库外的 playerbots 目录，
#      FetchContent 即完全复用本地克隆、不触发下载。指向 core 外目录所需的
#      out-of-tree 二元目录改动【已提交进 fork 主分支】，本脚本只做
#      "在位校验"：不在位时说明当前检出不是 fork 主分支形态，给出诊断而非
#      自动打档。
#   4) 开 BUILD_MODULES 后，四个功能模块 + cmangos-modules 框架同样要求
#      src/modules/<folder>/CMakeLists.txt 已在位。本脚本只做用户侧软链接，
#      不替你克隆、不从 ../cmangos-* 自动发现。缺目录则报错退出。
#
# 用法（在父目录）：bash scripts/20-prepare-playerbots.sh
#   可用 WOW_ROOT 环境变量指定父目录，如：WOW_ROOT=$HOME/wow bash scripts/20-...
# 幂等：可重复执行
# ==============================================================================
set -euo pipefail

WOW_ROOT="${WOW_ROOT:-$(pwd)}"
CORE="$WOW_ROOT/mangos-classic"
BOTS="$WOW_ROOT/playerbots"

for d in "$CORE" "$BOTS"; do
  [[ -d $d ]] || { echo "[ERROR] Repository directory not found: ${d} (run from the three-repo parent directory, or set WOW_ROOT)"; exit 1; }
done

echo "==> Creating 3-level symlink src/modules/PlayerBots -> ../../../playerbots"
mkdir -p "$CORE/src/modules"
ln -sfn ../../../playerbots "$CORE/src/modules/PlayerBots"

# 链接正确性自检：必须能顺着链接看到 playerbots 的 SQL
if ls "$CORE"/src/modules/PlayerBots/sql/world/*.sql >/dev/null 2>&1; then
  echo "[OK]  Symlink resolves correctly (sql/world/*.sql visible)"
else
  echo "[ERROR] Symlink resolution failed! Check the link depth of mangos-classic/src/modules/PlayerBots"
  ls -la "$CORE/src/modules/"
  exit 1
fi

echo "==> Verifying out-of-tree support is in place (carried by fork master; this script does not patch)"
if grep -q 'add_subdirectory(${playerbots_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR}/modules/PlayerBots)' "$CORE/src/CMakeLists.txt"; then
  echo "[OK]  Out-of-tree binary-directory support is in place (carried by fork master)"
elif grep -q 'add_subdirectory(${playerbots_SOURCE_DIR})' "$CORE/src/CMakeLists.txt"; then
  echo "[WARN] This checkout lacks out-of-tree binary-directory support - the fork"
  echo "       master branch already carries the change. Verify that mangos-classic"
  echo "       sits on fork master with the relevant commit:"
  echo "         cd $CORE && git remote -v && git log --oneline -1"
  echo "       (Common causes: cloned the upstream cmangos repo by mistake, or lost"
  echo "        the line while syncing upstream - see docs/troubleshooting.md #4 / #21)"
  exit 1
else
  echo "[WARN] src/CMakeLists.txt matches neither the supported nor the pre-patch form - upstream may have restructured; manual inspection needed"
  exit 1
fi

# 四个外观/天赋模块 + 框架：与 PlayerBots 同样的三层相对软链接
# 左侧 = src/modules 下的目录名，右侧 = 父目录下的仓库名
echo "==> Creating 3-level symlinks for modules (framework + four features)"
while read -r folder repo; do
  [[ -z "$folder" ]] && continue
  src="$WOW_ROOT/$repo"
  if [[ ! -d "$src" ]]; then
    echo "[ERROR] Module repository not found: $src"
    echo "        Clone it next to mangos-classic (see docs/09-modules.md), then re-run this script."
    exit 1
  fi
  if [[ ! -f "$src/CMakeLists.txt" ]]; then
    echo "[ERROR] $src has no CMakeLists.txt - wrong checkout or incomplete clone"
    exit 1
  fi
  ln -sfn "../../../$repo" "$CORE/src/modules/$folder"
  if [[ -f "$CORE/src/modules/$folder/CMakeLists.txt" ]]; then
    echo "[OK]  src/modules/$folder -> ../../../$repo"
  else
    echo "[ERROR] Symlink for $folder does not resolve to CMakeLists.txt"
    ls -la "$CORE/src/modules/"
    exit 1
  fi
done <<'EOF'
modules cmangos-modules
transmog cmangos-transmog
dualspec cmangos-dualspec
achievements cmangos-achievements
barber cmangos-barber
EOF

echo ""
echo "Done. Next step: scripts/30-build-server.sh"
