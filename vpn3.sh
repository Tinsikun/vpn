#!/bin/bash

# 一键部署 Xray Reality VPN 脚本
# 设置域名
DOMAIN="addons.mozilla.org"

# 更新系统
sudo apt update -y && sudo apt upgrade -y
cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# 安装必要的软件
command -v unzip >/dev/null || sudo apt install unzip -y
command -v qrencode >/dev/null || sudo apt install qrencode -y

# 停止 Xray 服务（如果已安装）
systemctl is-active --quiet xray && systemctl stop xray

# 备份旧配置
CONFIG_FILE="/usr/local/etc/xray/config.json"
if [ -f "$CONFIG_FILE" ]; then
    echo "备份旧的 Xray 配置..."
    mv "$CONFIG_FILE" "$CONFIG_FILE.bak"
fi

# 安装 Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"

# 检查 Xray 版本
xray version

# 生成 UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "UUID: $UUID"

# 生成 Reality 密钥对
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key" | cut -d ' ' -f3)
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key" | cut -d ' ' -f3)
echo "Private Key: $PRIVATE_KEY"
echo "Public Key: $PUBLIC_KEY"

# 获取服务器 IP
SERVER_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)
echo "Server IP: $SERVER_IP"

# 定义屏蔽域名
BLOCKED_DOMAINS=("account.listary.com")

# 构建屏蔽规则
ROUTE_RULES=""
for domain in "${BLOCKED_DOMAINS[@]}"; do
    ROUTE_RULES+="
      {
        \"type\": \"field\",
        \"domain\": [\"$domain\"],
        \"outboundTag\": \"block\"
      },"
done
ROUTE_RULES="${ROUTE_RULES%,}"

# 写入 Xray 配置文件
cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "dns": {
    "servers": ["8.8.8.8", "8.8.4.4", "1.1.1.1", "223.5.5.5"],
    "prefetch": true
  },
  "routing": {
    "rules": [
      $ROUTE_RULES
    ]
  },
  "inbounds": [
    {
      "tag": "xray-xtls-reality",
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "$DOMAIN:443",
          "serverNames": [
            "$DOMAIN"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [""]
        }
      },
      "sniffing": {
        "enabled": false
      },
      "workers": 4
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

# 重新启动 Xray
systemctl restart xray
systemctl enable xray

# ---------------------------
# ⚡ 网络优化 (BBR + TCP 调优)
# ---------------------------
echo ">>> 开始优化 BBR 网络加速"
modprobe tcp_bbr
echo "tcp_bbr" | tee -a /etc/modules-load.d/modules.conf
sysctl_config="/etc/sysctl.conf"

cat >> "$sysctl_config" <<EOF

# BBR加速
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_notsent_lowat = 16384
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 87380 67108864
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_no_metrics_save = 1
EOF

sysctl -p
echo ">>> BBR 优化完成！"

# ---------------------------
# 🔗 生成 VLESS Reality 配置链接
# ---------------------------
VLESS_URL="vless://${UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&pbk=${PUBLIC_KEY}&fp=chrome&type=tcp#Xray-Reality"
echo "VLESS Reality 配置链接："
echo "$VLESS_URL"

# 生成二维码
qrencode -o reality.png -s 10 "$VLESS_URL"
echo "二维码已生成：reality.png"

# 完成部署
echo "✅ Xray Reality 安装完成！"
