#!/bin/bash

# 一键部署 Xray VPN 脚本
# 该脚本将自动安装和配置 Xray VPN 服务，生成 VPN 链接和二维码图片。
# 请在 Ubuntu 或 Debian 系统上以 root 用户运行此脚本。
# 依赖：curl、qrencode、systemctl

# 函数：检查命令执行结果
check_command() {
    if [ $? -ne 0 ]; then
        echo "错误：$1 失败，请检查服务器环境后重试。"
        exit 1
    fi
}

echo "开始部署 Xray VPN..."

# 1. 系统更新（自动选择包维护者的配置文件版本）
echo "正在更新系统..."
export DEBIAN_FRONTEND=noninteractive
apt update -y && apt upgrade -y -o Dpkg::Options::="--force-confnew"
check_command "系统更新"

# 2. 安装 Xray
echo "正在安装 Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
check_command "Xray 安装"
xray version

# 3. 生成 UUID 和 Reality 密钥
echo "正在生成 UUID 和密钥..."
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "生成的 UUID: $UUID"

KEY_PAIR=$(xray x25519)
PRIVATE_KEY=$(echo "$KEY_PAIR" | grep "Private key" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEY_PAIR" | grep "Public key" | awk '{print $3}')
echo "生成的私钥: $PRIVATE_KEY"
echo "生成的公钥: $PUBLIC_KEY"

# 4. 配置 Xray
echo "正在配置 Xray..."
CONFIG_FILE="/usr/local/etc/xray/config.json"
cat > $CONFIG_FILE <<EOL
{
    "log": {
        "loglevel": "warning"
    },
    "dns": {
        "servers": [
            "8.8.8.8",
            "8.8.4.4",
            "223.5.5.5"
        ],
        "client": "8.8.8.8",
        "prefetch": true
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
                    "dest": "addons.mozilla.org:443",
                    "serverNames": [
                        "addons.mozilla.org"
                    ],
                    "privateKey": "$PRIVATE_KEY",
                    "shortIds": [
                        ""
                    ]
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
        }
    ]
}
EOL
check_command "Xray 配置"

# 5. 启动 Xray 服务
echo "正在启动 Xray 服务..."
systemctl restart xray && systemctl enable xray
check_command "Xray 服务启动"
systemctl status xray --no-pager

# 6. 设置自动更新 dat 文件
echo "正在设置 dat 文件自动更新..."
mkdir -p /usr/local/etc/xray-script
UPDATE_SCRIPT="/usr/local/etc/xray-script/update-dat.sh"
cat > $UPDATE_SCRIPT <<EOL
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
EOL
chmod +x $UPDATE_SCRIPT
check_command "更新脚本创建"

# 添加每周一 23:00 的 cron 任务
(crontab -l 2>/dev/null; echo "00 23 * * 1 $UPDATE_SCRIPT >/dev/null 2>&1") | crontab -
check_command "Cron 任务设置"

# 7. 启用 BBR 和网络优化
echo "正在启用 BBR 和网络优化..."
echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_rmem=4096 87380 16777216" | tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_wmem=4096 65536 16777216" | tee -a /etc/sysctl.conf
echo "net.ipv4.udp_rmem_min=4096" | tee -a /etc/sysctl.conf
echo "net.ipv4.udp_wmem_min=4096" | tee -a /etc/sysctl.conf
sysctl -p
check_command "网络优化"
echo 3 > /proc/sys/net/ipv4/tcp_fastopen
check_command "TCP Fast Open"

# 8. 获取服务器公网 IP
echo "正在获取服务器公网 IP..."
SERVER_IP=$(curl -s ifconfig.me)
echo "服务器 IP: $SERVER_IP"

# 9. 安装 qrencode（自动处理配置文件更新）
echo "正在安装 qrencode..."
export DEBIAN_FRONTEND=noninteractive
apt install -y qrencode -o Dpkg::Options::="--force-confnew"
check_command "qrencode 安装"

# 10. 生成 VPN 链接
VPN_LINK="vless://$UUID@$SERVER_IP:443?type=tcp&security=reality&flow=xtls-rprx-vision&fp=chrome&sni=addons.mozilla.org&pbk=$PUBLIC_KEY#vpn-xlts-reality"
echo "VPN 链接: $VPN_LINK"

# 11. 生成二维码图片
QR_CODE_FILE="/tmp/vpn_qr.png"
qrencode -o $QR_CODE_FILE "$VPN_LINK"
check_command "二维码生成"
echo "二维码已保存至: $QR_CODE_FILE"

# 在终端显示 ASCII 码二维码
echo "在终端显示 ASCII 码二维码："
qrencode -t ansi "$VPN_LINK"

# 12. 显示部署完成信息
echo "----------------------------------------"
echo "VPN 部署成功！"
echo "请在支持 VLESS 的客户端（如 V2rayNG）中使用以下配置："
echo "服务器 IP: $SERVER_IP"
echo "端口: 443"
echo "UUID: $UUID"
echo "Flow: xtls-rprx-vision"
echo "安全性: reality"
echo "SNI: addons.mozilla.org"
echo "公钥: $PUBLIC_KEY"
echo "VPN 链接: $VPN_LINK"
echo "二维码图片路径: $QR_CODE_FILE"
echo "----------------------------------------"
echo "提示：二维码图片位于 $QR_CODE_FILE，可通过 SCP 或其他工具下载查看。"
