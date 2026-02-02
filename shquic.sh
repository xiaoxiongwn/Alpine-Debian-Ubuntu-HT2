#!/usr/bin/env bash
set -e

### ===== 可修改参数 =====
TAG="ShadowQUIC-Google"
WORKDIR="/etc/shadowquic"
BIN="/usr/local/bin/shadowquic"
CONF="$WORKDIR/config.yaml"
PORT_FILE="$WORKDIR/port.txt"
USERNAME_LEN=8
PASSWORD_LEN=16
### =====================

# 必须 root
if [ "$(id -u)" != "0" ]; then
    echo "❌ 请使用 root 运行"
    exit 1
fi

# 系统判断
if command -v apk >/dev/null 2>&1; then
    OS="alpine"
elif command -v apt >/dev/null 2>&1; then
    OS="debian"
else
    echo "❌ 仅支持 Alpine / Debian / Ubuntu"
    exit 1
fi

echo "▶ 系统: $OS"

# 安装依赖
if [ "$OS" = "alpine" ]; then
    apk add --no-cache curl ca-certificates bash
else
    apt update
    apt install -y curl ca-certificates bash
fi

mkdir -p "$WORKDIR"

USERNAME=$(head -c 32 /dev/urandom | tr -dc A-Za-z0-9 | head -c $USERNAME_LEN)
PASSWORD=$(head -c 32 /dev/urandom | tr -dc A-Za-z0-9 | head -c $PASSWORD_LEN)

# 端口
if [ ! -f "$PORT_FILE" ]; then
    PORT=$(( ( RANDOM % 40000 ) + 20000 ))
    echo "$PORT" > "$PORT_FILE"
else
    PORT=$(cat "$PORT_FILE")
fi

# IPv4
IP=$(curl -s https://api.ipify.org || curl -s ifconfig.me)
[ -z "$IP" ] && { echo "❌ 获取 IPv4 失败"; exit 1; }

# IPv6（可选）
IPV6=$(curl -6 -s https://api64.ipify.org 2>/dev/null || true)

# 下载 shadowquic
echo "▶ 下载 shadowquic..."
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) FILE="shadowquic-linux-amd64" ;;
  aarch64) FILE="shadowquic-linux-arm64" ;;
  *) echo "❌ 不支持架构: $ARCH"; exit 1 ;;
esac

curl -L -o "$BIN" "https://github.com/spongebob888/shadowquic/releases/latest/download/$FILE"
chmod +x "$BIN"

# ===== YAML 配置（Google 伪装 + 100Mbps 限速）=====
cat > "$CONF" <<EOF
bind-addr: "0.0.0.0:$PORT"

users:
  - username: "$USERNAME"
    password: "$PASSWORD"

# Google 伪装
server-name: "www.google.com"

jls-upstream:
  addr: "www.google.com:443"
  rate-limit: 100000000   # 100 Mbps

alpn: ["h3"]
congestion-control: bbr
zero-rtt: true
initial-mtu: 1400
min-mtu: 1290
EOF

# ===== 服务 =====
if [ "$OS" = "alpine" ]; then
    cat > /etc/init.d/shadowquic <<'EOF'
#!/sbin/openrc-run
name="shadowquic"
command="/usr/local/bin/shadowquic"
command_args="-c /etc/shadowquic/config.yaml"
command_background=true
pidfile="/run/shadowquic.pid"
supervisor="supervise-daemon"
depend() { need net; }
EOF
    chmod +x /etc/init.d/shadowquic
    rc-update add shadowquic default
    rc-service shadowquic restart
else
    cat > /etc/systemd/system/shadowquic.service <<EOF
[Unit]
Description=ShadowQUIC Server
After=network.target

[Service]
ExecStart=$BIN -c $CONF
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable shadowquic
    systemctl restart shadowquic
fi

# 输出
LINK_V4="shadowquic://$USERNAME:$PASSWORD@$IP:$PORT#$TAG"
[ -n "$IPV6" ] && LINK_V6="shadowquic://$USERNAME:$PASSWORD@[$IPV6]:$PORT#${TAG}-IPv6"

echo
echo "=============================="
echo "✅ ShadowQUIC 已部署（Google 伪装）"
echo "📌 IPv4: $IP"
[ -n "$IPV6" ] && echo "📌 IPv6: $IPV6"
echo "👤 用户名: $USERNAME"
echo "🔐 密码: $PASSWORD"
echo "🎲 端口: $PORT"
echo "🚦 限速: 100 Mbps"
echo "📎 链接："
echo "$LINK_V4"
[ -n "$IPV6" ] && echo "$LINK_V6"
echo "=============================="
