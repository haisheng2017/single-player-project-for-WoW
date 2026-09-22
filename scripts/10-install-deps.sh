#!/usr/bin/env bash
# ==============================================================================
# 10-install-deps.sh —— Ubuntu 22.04 全部系统依赖一键安装
#
# 依赖清单对齐 CMaNGOS 官方 wiki（Ubuntu 22.04）与官方 CI（.github/workflows/ubuntu.yml）
# 用法：  sudo bash 10-install-deps.sh
# 幂等：  可重复执行
# ==============================================================================
set -euo pipefail

# 出处：清单一字不差对应官方 wiki 与 CI，包用途逐条说明见 docs/01-environment.md
[[ $EUID -eq 0 ]] || { echo "[错误] 请用 sudo 运行本脚本（需要 apt 写权限）"; exit 1; }

echo "==> apt update ..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

echo "==> 安装编译链与运行依赖（Ubuntu 22.04）..."
# 为什么要 gcc-12/clang：Ubuntu 22.04 默认 gcc/g++ 11 存在编译器内部缺陷，
# 官方 wiki 明确提示 GCC 11.2/11.3 编不过 TileAssembler.cpp；CI 的双矩阵即 gcc-12 与 clang。
apt-get install -y \
  build-essential gcc-12 g++-12 clang \
  automake autoconf make patch libtool binutils grep \
  cmake libboost-all-dev \
  libssl-dev zlib1g-dev libbz2-dev \
  libmysqlclient-dev mysql-client \
  mysql-server \
  git ca-certificates gzip

echo ""
echo "==> 关键工具自检："
for cmd in gcc-12 g++-12 clang cmake make git mysql; do
  command -v "$cmd" >/dev/null 2>&1 && echo "[OK]  $cmd  ($("$cmd" --version 2>/dev/null | head -1))" \
                                    || echo "[缺失] $cmd"
done

echo ""
echo "==> 启动并使 MySQL 服务开机可用 ..."
systemctl enable --now mysql 2>/dev/null || service mysql start || true
systemctl is-active mysql >/dev/null 2>&1 || service mysql status >/dev/null 2>&1 \
  || { echo "[错误] MySQL 服务未能启动，请排查：journalctl -u mysql -n 50"; exit 1; }
echo "[OK]  MySQL 服务运行中"
echo ""
echo "完成。下一步：scripts/20-prepare-playerbots.sh（无需 sudo）"
