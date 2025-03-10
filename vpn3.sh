#!/bin/bash

# 一键部署 Xray VPN 脚本
# 全局变量：定义域名，只需修改此处即可
#DOMAIN="addons.mozilla.org"
DOMAIN="dl.google.com"

# 更新系统
sudo apt update -y && sudo apt upgrade -y

# 安装 unzip 和 qrencode (如果不存在)
command -v unzip >/dev/null || sudo apt install unzip -y
command -v qrencode >/dev/null || sudo apt install qrencode -y

# 停止 Xray 服务，防止在修改配置时出错
systemctl stop xray

# 删除旧的 Xray 配置文件，防止因错误配置导致启动失败
CONFIG_FILE="/usr/local/etc/xray/config.json"
if [ -f "$CONFIG_FILE" ]; then
    echo "删除旧的 Xray 配置文件..."
    rm -f "$CONFIG_FILE"
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
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key" | awk '{print $3}')
echo "Private key: $PRIVATE_KEY"
echo "Public key: $PUBLIC_KEY"

# 获取服务器 IP
SERVER_IP=$(curl -s https://api.ipify.org)
echo "Server IP: $SERVER_IP"

# 配置 Xray
CONFIG_FILE="/usr/local/etc/xray/config.json"

# 定义需要屏蔽的域名
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

# 去除最后一个逗号
ROUTE_RULES="${ROUTE_RULES%,}"

# 写入配置文件
cat > $CONFIG_FILE <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "dns": {
    "hosts": {
      "example.com": "1.2.3.4",
      "example.org": "5.6.7.8"
    },
    "servers": [
      "8.8.8.8",
      "8.8.4.4",
      "1.1.1.1",
      "1.0.0.1",
      "223.5.5.5"
    ],
    "client": "8.8.8.8",
    "prefetch": true
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "ip": ["geoip:cn"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "domain": ["geosite:category-ads-all"],
        "outboundTag": "block"
      },
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
          "serverNames": ["$DOMAIN"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [""]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
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

# 启动 Xray 服务
systemctl restart xray && systemctl enable xray

# 检查 Xray 状态
systemctl status xray

# 创建更新 dat 文件的脚本
mkdir -p /usr/local/etc/xray-script
cat > /usr/local/etc/xray-script/update-dat.sh <<EOF
#!/usr/bin/env bash

set -e

XRAY_DIR="/usr/local/share/xray"

GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/raw/release/geoip.dat"
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/raw/release/geosite.dat"

[ -d \$XRAY_DIR ] || mkdir -p \$XRAY_DIR
cd \$XRAY_DIR

curl -L -o geoip.dat.new \$GEOIP_URL
curl -L -o geosite.dat.new \$GEOSITE_URL

rm -f geoip.dat geosite.dat

mv geoip.dat.new geoip.dat
mv geosite.dat.new geosite.dat

systemctl -q is-active xray && systemctl restart xray
EOF

# 赋予更新脚本可执行权限
chmod +x /usr/local/etc/xray-script/update-dat.sh

# 执行一次更新脚本
/usr/local/etc/xray-script/update-dat.sh

# 设置 crontab 每周一 23:00 执行更新
(crontab -l 2>/dev/null; echo "00 23 * * 1 /usr/local/etc/xray-script/update-dat.sh >/dev/null 2>&1") | crontab -

# 启用 BBR 并优化网络性能
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
cat << EOF | sudo tee -a /etc/sysctl.conf
# TCP Fast Open
net.ipv4.tcp_fast_open=3

# TCP 内存优化
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.core.rmem_max=16777216
net.core.wmem_max=16777216

# UDP 加速优化
net.ipv4.udp_rmem_min=4096
net.ipv4.udp_wmem_min=4096
EOF
sysctl -p

# 生成 VPN 配置链接（名称改为“服务器IP+Xtls+Reality”）
VPN_NAME="${SERVER_IP}+Xtls+Reality"
VPN_LINK="vless://$UUID@$SERVER_IP:443?security=reality&encryption=none&pbk=$PUBLIC_KEY&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=$DOMAIN#$VPN_NAME"
echo "VPN Link: $VPN_LINK"

# 安装 qrencode 并生成二维码
qrencode -o - -t ANSIUTF8 "$VPN_LINK"
