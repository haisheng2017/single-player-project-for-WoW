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
[[ $EUID -eq 0 ]] || { echo "[ERROR] Run this script with sudo (apt write access required)"; exit 1; }

echo "==> apt update ..."
export DEBIAN_FRONTEND=noninteractive

# ---- Docker 容器环境（实测结论，详见 troubleshooting #26） ----
# docker run 交互容器：必须以 --init 启动（pid 1 = tini 收割退出的 mysqld），
#   否则 mysql-server 安装将稳定失败（postinst 对僵尸的 kill -0 判存活恒真，
#   报 Unable to shut down server）——不加 --init 无法使用本脚本。
# docker build 的 RUN 层：实测直接可行（构建执行环境自带进程托管），无需处理。
if [[ -f /.dockerenv ]]; then
  pid1=$(ps -p 1 -o comm= 2>/dev/null || echo unknown)
  echo "[CONTAINER] pid 1 = ${pid1}"
  case "$pid1" in
    tini|docker-init)
      echo "[OK]        --init present; mysql-server can be installed normally" ;;
    *)
      echo "[NOTE]      docker run interactive container with pid 1 = bash/sh"
      echo "            (currently '${pid1}'): mysql-server install cannot"
      echo "            complete without --init (verified by live testing). Exit"
      echo "            and restart the container with 'docker run --init' first."
      echo "            Inside a docker build RUN layer: works as-is, continue." ;;
  esac
fi

apt-get update -y

echo "==> Installing build toolchain and runtime dependencies (Ubuntu 22.04) ..."
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
echo "==> Key tools self-check:"
for cmd in gcc-12 g++-12 clang cmake make git mysql; do
  command -v "$cmd" >/dev/null 2>&1 && echo "[OK]  $cmd  ($("$cmd" --version 2>/dev/null | head -1))" \
                                    || echo "[MISSING] $cmd"
done

echo ""
echo "==> Enabling and starting the MySQL service ..."
systemctl enable --now mysql 2>/dev/null || service mysql start || true
systemctl is-active mysql >/dev/null 2>&1 || service mysql status >/dev/null 2>&1 \
  || { echo "[ERROR] MySQL service failed to start; check: journalctl -u mysql -n 50"; exit 1; }
echo "[OK]  MySQL service is running"
echo ""
echo "Done. Next step: scripts/20-prepare-playerbots.sh (no sudo needed)"
