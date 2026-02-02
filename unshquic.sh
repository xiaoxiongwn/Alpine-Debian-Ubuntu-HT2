#!/usr/bin/env bash
set -e

# ===== 与安装脚本保持一致 =====
WORKDIR="/etc/shadowquic"
BIN="/usr/local/bin/shadowquic"
OPENRC_SERVICE="/etc/init.d/shadowquic"
SYSTEMD_SERVICE="/etc/systemd/system/shadowquic.service"
PIDFILE="/run/shadowquic.pid"
# =================================

# 必须 root
if [ "$(id -u)" != "0" ]; then
    echo "❌ 请使用 root 运行"
    exit 1
fi

# 判断系统
if command -v apk >/dev/null 2>&1; then
    OS="alpine"
elif command -v apt >/dev/null 2>&1; then
    OS="debian"
else
    echo "❌ 不支持的系统（仅 Alpine / Debian / Ubuntu）"
    exit 1
fi

echo "▶ 当前系统: $OS"
echo "▶ 开始卸载 ShadowQUIC（spongebob888 版本）..."

# ===== 停止并移除服务 =====
if [ "$OS" = "alpine" ]; then
    if [ -f "$OPENRC_SERVICE" ]; then
        echo "▶ 停止 OpenRC 服务..."
        rc-service shadowquic stop || true
        rc-update del shadowquic default || true
        rm -f "$OPENRC_SERVICE"
    else
        echo "ℹ 未发现 OpenRC 服务文件"
    fi
else
    if [ -f "$SYSTEMD_SERVICE" ]; then
        echo "▶ 停止 systemd 服务..."
        systemctl stop shadowquic || true
        systemctl disable shadowquic || true
        rm -f "$SYSTEMD_SERVICE"
        systemctl daemon-reload
    else
        echo "ℹ 未发现 systemd 服务文件"
    fi
fi

# ===== 清理文件 =====
echo "▶ 删除配置目录..."
rm -rf "$WORKDIR"

echo "▶ 删除可执行文件..."
rm -f "$BIN"

echo "▶ 清理 PID 文件..."
rm -f "$PIDFILE"

echo
echo "=============================="
echo "✅ ShadowQUIC 已完全卸载"
echo "🖥 系统: $OS"
echo "🧹 已清理内容："
echo "   - ShadowQUIC 服务（OpenRC / systemd）"
echo "   - 配置目录：$WORKDIR"
echo "   - 二进制文件：$BIN"
echo "=============================="
