#!/usr/bin/env sh
set -e

### ===== 参数 =====
WORKDIR="/etc/shadowquic"
BIN="/usr/local/bin/shadowquic"
CONF="$WORKDIR/config.yaml"
PORT_FILE="$WORKDIR/port.txt"
TAG="ShadowQUIC-Google"
### =================

# root 检查
[ "$(id -u)" -ne 0 ] && echo "请使用 root 运行" && exit 1

# Alpine 检查
command -v apk >/dev/null 2>&1 || {
  echo "❌ 仅支持 Alpine Linux"
  exit 1
}

echo "▶ Alpine ShadowQUIC 安装开始"

# 依赖
apk add --no-cache curl ca-certificates bash

mkdir -p "$WORKDIR"

# 随机用户
USERNAME=$(head -c 32 /dev/urandom | tr -dc A-Za-z0-9 | head -c 8)
PASSWORD=$(head -c 32 /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

# 端口
if [ ! -f "$PORT_FILE" ]; then
  PORT=$((20000 + RANDOM % 30000))
  echo "$PORT" > "$PORT_FILE"
else
  PORT=$(cat "$PORT_FILE")
fi

# IP
IPV4=$(curl -s https://api.ipify.org || true)
IPV6=$(curl -6 -s https://api64.ipify.org || true)

[ -z "$IPV4" ] && echo "❌ IPv4 获取失败" && exit 1

# 下载 shadowquic
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) FILE="shadowquic-x86_64-linux" ;;
  aarch64) FILE="shadowquic-aarch64-linux" ;;
  *) echo "❌ 不支持架构 $ARCH" && exit 1 ;;
esac

echo "▶ 下载 shadowquic"
curl -L -o "$BIN" \
  "https://github.com/spongebob888/shadowquic/releases/latest/download/$FILE"
chmod +x "$BIN"

# ===== 配置文件（Google 伪装 + 100Mbps）=====
cat > "$CONF" <<EOF
bind-addr: "0.0.0.0:$PORT"

users:
  - username: "$USERNAME"
    password: "$PASSWORD"

server-name: "www.google.com"

jls-upstream:
  addr: "www.google.com:443"
  rate-limit: 100000000

alpn: ["h3"]
congestion-control: bbr
zero-rtt: true
initial-mtu: 1400
min-mtu: 1290
EOF

# ===== OpenRC 服务（关键修正点）=====
cat > /etc/init.d/shadowquic <<'EOF'
#!/sbin/openrc-run

name="shadowquic"
description="ShadowQUIC Server"

command="/usr/local/bin/shadowquic"
command_args="-c /etc/shadowquic/config.yaml"

supervisor="supervise-daemon"

depend() {
    need net
}
EOF

chmod +x /etc/init.d/shadowquic
rc-update add shadowquic default

# 启动
rc-service shadowquic restart

# 输出
echo
echo "=============================="
echo "✅ ShadowQUIC 已在 Alpine 启动"
echo "📌 IPv4: $IPV4"
[ -n "$IPV6" ] && echo "📌 IPv6: $IPV6"
echo "👤 用户名: $USERNAME"
echo "🔐 密码: $PASSWORD"
echo "🎯 端口: $PORT"
echo "🚦 限速: 100 Mbps"
echo "🔗 链接:"
echo "shadowquic://$USERNAME:$PASSWORD@$IPV4:$PORT#$TAG"
[ -n "$IPV6" ] && \
echo "shadowquic://$USERNAME:$PASSWORD@[$IPV6]:$PORT#${TAG}-IPv6"
echo "=============================="
