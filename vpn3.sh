#!/bin/bash

# 一键部署 Xray VPN 脚本
# 全局变量：定义域名，只需修改此处即可
DOMAIN="addons.mozilla.org"

# 记录开始时间
start_time=$(date +%s)
echo "===== Xray VPN 一键部署脚本开始执行 ====="
echo "部署时间: $(date)"

# 更新系统
echo "正在更新系统..."
sudo apt update -y && sudo apt upgrade -y
cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# 安装必要工具
echo "正在安装必要工具..."
for pkg in unzip qrencode curl jq; do
    if ! command -v $pkg &>/dev/null; then
        echo "正在安装 $pkg..."
        sudo apt install $pkg -y
    fi
done

# 停止 Xray 服务，防止在修改配置时出错
if systemctl is-active --quiet xray; then
    echo "停止 Xray 服务..."
    systemctl stop xray
fi

# 备份旧的 Xray 配置文件
CONFIG_FILE="/usr/local/etc/xray/config.json"
if [ -f "$CONFIG_FILE" ]; then
    echo "备份旧的 Xray 配置文件..."
    mv "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
fi

# 安装或更新 Xray
echo "安装/更新 Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# 检查 Xray 版本
echo "Xray 版本信息:"
xray version

# 生成 UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "UUID: $UUID"

# 生成 Reality 密钥对
echo "生成 Reality 密钥对..."
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key" | awk '{print $3}')
echo "Private key: $PRIVATE_KEY"
echo "Public key: $PUBLIC_KEY"

# 获取服务器 IP
SERVER_IP=$(curl -s https://api.ipify.org)
echo "服务器 IP: $SERVER_IP"

# 确保配置目录存在
mkdir -p /usr/local/etc/xray

# 配置 Xray
echo "生成 Xray 配置文件..."
CONFIG_FILE="/usr/local/etc/xray/config.json"

# 定义需要屏蔽的域名
BLOCKED_DOMAINS=("account.listary.com")

# 构建屏蔽规则
ROUTE_RULES=""
for domain in "${BLOCKED_DOMAINS[@]}"; do
    if [ -n "$ROUTE_RULES" ]; then
        ROUTE_RULES+=","
    fi
    ROUTE_RULES+="
      {
        \"type\": \"field\",
        \"domain\": [\"$domain\"],
        \"outboundTag\": \"block\"
      }"
done

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
    "clientIp": "8.8.8.8",
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
      }$([ -n "$ROUTE_RULES" ] && echo ",$ROUTE_RULES")
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

# 验证 JSON 格式
if command -v jq &>/dev/null; then
    if jq . "$CONFIG_FILE" > /dev/null; then
        echo "配置文件 JSON 格式验证通过"
    else
        echo "警告: 配置文件 JSON 格式有误，请检查"
        exit 1
    fi
fi

# 确保配置文件权限正确
chmod 644 "$CONFIG_FILE"
chown root:root "$CONFIG_FILE"

# 启动 Xray 服务
echo "启动 Xray 服务..."
systemctl restart xray && systemctl enable xray

# 检查 Xray 状态
echo "Xray 服务状态:"
systemctl status xray --no-pager

# 创建更新 dat 文件的脚本
echo "创建 dat 文件更新脚本..."
mkdir -p /usr/local/etc/xray-script
cat > /usr/local/etc/xray-script/update-dat.sh <<EOF
#!/usr/bin/env bash

set -e

XRAY_DIR="/usr/local/share/xray"
echo "\$(date) - 开始更新 Xray dat 文件..."

GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/raw/release/geoip.dat"
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/raw/release/geosite.dat"

[ -d \$XRAY_DIR ] || mkdir -p \$XRAY_DIR
cd \$XRAY_DIR

echo "下载 geoip.dat..."
curl -L -o geoip.dat.new \$GEOIP_URL

echo "下载 geosite.dat..."
curl -L -o geosite.dat.new \$GEOSITE_URL

rm -f geoip.dat geosite.dat

mv geoip.dat.new geoip.dat
mv geosite.dat.new geosite.dat

if systemctl -q is-active xray; then
    echo "重启 Xray 服务..."
    systemctl restart xray
    echo "Xray 服务已重启"
else
    echo "Xray 服务未运行，跳过重启"
fi

echo "\$(date) - Xray dat 文件更新完成"
EOF

# 赋予更新脚本可执行权限
chmod +x /usr/local/etc/xray-script/update-dat.sh

# 执行一次更新脚本
echo "执行 dat 文件更新..."
/usr/local/etc/xray-script/update-dat.sh

# 设置 crontab 每周一 23:00 执行更新
echo "设置自动更新..."
(crontab -l 2>/dev/null | grep -v "update-dat.sh"; echo "00 23 * * 1 /usr/local/etc/xray-script/update-dat.sh >/var/log/xray-update.log 2>&1") | crontab -

# 启用 BBR 并优化网络性能
echo "优化系统网络性能..."
{
    echo "# 启用 BBR"
    echo "net.core.default_qdisc=fq"
    echo "net.ipv4.tcp_congestion_control=bbr"
    echo "# TCP Fast Open"
    echo "net.ipv4.tcp_fast_open=3"
    echo "# TCP 内存优化"
    echo "net.ipv4.tcp_rmem=4096 87380 16777216"
    echo "net.ipv4.tcp_wmem=4096 65536 16777216"
    echo "net.core.rmem_max=16777216"
    echo "net.core.wmem_max=16777216"
    echo "# UDP 加速优化"
    echo "net.ipv4.udp_rmem_min=4096"
    echo "net.ipv4.udp_wmem_min=4096"
} > /etc/sysctl.d/99-xray-bbr.conf

sysctl -p /etc/sysctl.d/99-xray-bbr.conf

# 生成 VPN 配置链接
VPN_NAME="${SERVER_IP}+Xtls+Reality"
VPN_LINK="vless://$UUID@$SERVER_IP:443?security=reality&encryption=none&pbk=$PUBLIC_KEY&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=$DOMAIN#$VPN_NAME"
echo -e "\n==== VPN 配置信息 ===="
echo "VPN 链接: $VPN_LINK"

# 确保 qrencode 已安装并生成二维码
if command -v qrencode &>/dev/null; then
    echo -e "\n==== VPN 二维码 ===="
    qrencode -o - -t ANSIUTF8 "$VPN_LINK"
fi

# 保存配置信息到文件
CONFIG_INFO="/root/xray_config_info.txt"
{
    echo "===== Xray VPN 配置信息 ====="
    echo "安装时间: $(date)"
    echo "服务器 IP: $SERVER_IP"
    echo "域名: $DOMAIN"
    echo "UUID: $UUID"
    echo "Private Key: $PRIVATE_KEY"
    echo "Public Key: $PUBLIC_KEY"
    echo "VPN 链接: $VPN_LINK"
    echo "============================="
} > "$CONFIG_INFO"

chmod 600 "$CONFIG_INFO"

# 计算执行时间
end_time=$(date +%s)
duration=$((end_time - start_time))
echo -e "\n===== Xray VPN 部署完成 ====="
echo "总共用时: $((duration / 60)) 分 $((duration % 60)) 秒"
echo "配置信息已保存到: $CONFIG_INFO"
echo "============================="
