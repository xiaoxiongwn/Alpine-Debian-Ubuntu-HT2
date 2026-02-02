#!/usr/bin/env bash
set -e

### ===== 可修改参数 =====
TAG="ShadowQUIC"
WORKDIR="/etc/shadowquic"
BIN="/usr/local/bin/shadowquic"
CONF="$WORKDIR/config.yaml"
PORT_FILE="$WORKDIR/port.txt"
USERNAME_LEN=8
PASSWORD_LEN=16
### =====================

# 必须 root
if [ "$(id -u)" != "0" ]; then
    echo "❌ 请使用 root"
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

# 生成认证用户名密码
USERNAME=$(head -c 32 /dev/urandom | tr -dc A-Za-z0-9 | head -c $USERNAME_LEN)
PASSWORD=$(head -c 32 /dev/urandom | tr -dc A-Za-z0-9 | head -c $PASSWORD_LEN)

# 端口
if [ ! -f "$PORT_FILE" ]; then
    PORT=$(( ( RANDOM % 40000 ) + 20000 ))
    echo "$PORT" > "$PORT_FILE"
else
    PORT=$(cat "$PORT_FILE")
fi

# 公网 IPv4
IP=$(curl -s https://api.ipify.org || curl -s ifconfig.me)
[ -z "$IP" ] && { echo "❌ 获取 IPv4 失败"; exit 1; }

# IPv6 可选
IPV6=$(curl -6 -s https://api64.ipify.org 2>/dev/null || true)

# 下载 shadowquic 最新二进制
echo "▶ 下载 shadowquic..."
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) FILE="shadowquic-x86_64-linux" ;;
  aarch64) FILE="shadowquic-aarch64-linux" ;;
  *) echo "❌ 不支持架构: $ARCH"; exit 1 ;;
esac

curl -L -o "$BIN" "https://github.com/spongebob888/shadowquic/releases/latest/download/$FILE"
chmod +x "$BIN"

# 写入 YAML 配置
echo "▶ 生成配置文件 (YAML)..."
cat > "$CONF" <<EOF
bind-addr: "0.0.0.0:$PORT"
users:
  - username: "$USERNAME"
    password: "$PASSWORD"
# 可选伪装 (如不需要可删掉以下两行)
server-name: ""
jls-upstream:
  addr: ""
  rate-limit: 0
alpn: ["h3"]
congestion-control: bbr
zero-rtt: true
initial-mtu: 1400
min-mtu: 1290
EOF

# 安装为守护服务
if [ "$OS" = "alpine" ]; then
    echo "▶ 配置 OpenRC..."
    cat > /etc/init.d/shadowquic <<'EOF'
#!/sbin/openrc-run
name="shadowquic"
command="/usr/local/bin/shadowquic"
command_args="-c /etc/shadowquic/config.yaml"
command_background=true
pidfile="/run/shadowquic.pid"
supervisor="supervise-daemon"
depend() {
    need net
}
EOF
    chmod +x /etc/init.d/shadowquic
    rc-update add shadowquic default
    rc-service shadowquic restart
else
    echo "▶ 配置 systemd..."
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

# 输出链接（手动格式）
OUT="shadowquic://$USERNAME:$PASSWORD@$IP:$PORT#$TAG"
echo
echo "=============================="
echo "✅ ShadowQUIC 安装完成"
echo "📌 IPv4: $IP"
[ -n "$IPV6" ] && echo "📌 IPv6: $IPV6"
echo "👤 用户名: $USERNAME"
echo "🔑 密码: $PASSWORD"
echo "🎲 端口: $PORT"
echo "📎 链接: $OUT"
echo "=============================="
