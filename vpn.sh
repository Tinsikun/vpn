#!/bin/bash

# --------------------- 脚本配置区 ---------------------
# 可自定义配置以下变量，以满足不同需求

XRAY_VERSION="latest"      # Xray 版本，可选 "latest" 或指定版本号，例如 "v1.8.5"
REALITY_DEST="addons.mozilla.org:443" # Reality 目标地址，推荐使用常用域名和端口
REALITY_SNI="addons.mozilla.org"   # Reality SNI，需与 REALITY_DEST 的域名一致
DNS_SERVERS=("8.8.8.8" "8.8.4.4" "223.5.5.5" "1.1.1.1" "1.0.0.1") # DNS 服务器列表，可自定义
ADDITIONAL_BLOCKED_DOMAINS=("account.listary.com" "example.com" "another-example.org") # 额外封锁的域名列表，可以添加更多域名
BLOCK_AD_DOMAINS="geosite:category-ads-all" # 广告域名 GeoSite 规则，可自定义
DIRECT_CN_IP=true           # 国内 IP 是否直连 (true: 直连, false: 阻止)
ENABLE_BBR=true             # 是否启用 BBR 优化 (true: 启用, false: 禁用)

# --------------------- 代码执行区 (以下内容非必要不建议修改) ---------------------

# 检查是否以 root 权限运行
if [[ "$EUID" -ne 0 ]]; then
  echo "错误：请使用 sudo 或 root 权限运行此脚本。"
  exit 1
fi

# 设置变量 (部分变量已在配置区定义)
XRAY_CONFIG="/usr/local/etc/xray/config.json"
UPDATE_SCRIPT="/usr/local/etc/xray-script/update-dat.sh"
DNS_SERVERS_STRING=$(IFS=","; echo -s "${DNS_SERVERS[*]}") # 将 DNS 服务器数组转换为字符串
ADDITIONAL_BLOCKED_DOMAINS_STRING=$(IFS=","; echo -s "${ADDITIONAL_BLOCKED_DOMAINS[*]}") # 新增：将 ADDITIONAL_BLOCKED_DOMAINS 数组转换为字符串
BLOCK_AD_DOMAINS_STRING="${BLOCK_AD_DOMAINS}" # 确保 BLOCK_AD_DOMAINS 变量为字符串

# 函数：错误处理
error_exit() {
  echo -e "\n脚本执行出错，错误信息：$1"
  exit 1
}

# 函数：检查命令是否安装
check_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo -e "错误：命令 '$1' 未安装，请先安装。"
    exit 1
  fi
}

# 更新系统
apt update -y || error_exit "apt update 失败"
apt upgrade -y || error_exit "apt upgrade 失败"

# 安装 unzip (如果不存在)
check_command unzip || apt install unzip -y || error_exit "unzip 安装失败"

# 安装 Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"

# 检查 Xray 版本
xray version

# 生成 UUID 和 Reality 密钥对
UUID=$(cat /proc/sys/kernel/random/uuid) || error_exit "UUID 生成失败"
KEYS=$(xray x25519) || error_exit "Reality 密钥对生成失败"
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key" | awk '{print $3}')

# 获取服务器 IP
SERVER_IP=$(curl -s https://api.ipify.org) || error_exit "获取服务器 IP 失败"

# 配置 Xray
cat > "$XRAY_CONFIG" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "dns": {
    "hosts": {},
    "servers": [ $DNS_SERVERS_STRING ],
    "client": "1.1.1.1",
    "prefetch": true
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"type": "field", "protocol": ["bittorrent"], "outboundTag": "block"},
      {"type": "field", "ip": ["geoip:private"], "outboundTag": "block"},
      {
        "type": "field",
        "ip": ["geoip:cn"],
        "outboundTag": "$(if ${DIRECT_CN_IP}; then echo "direct"; else echo "block"; fi)"
      },
      {
        "type": "field",
        "domain": [ $BLOCK_AD_DOMAINS_STRING, "$BLOCK_AD_DOMAINS_STRING" ], # 修改后的 domain 规则，同时使用自定义域名列表和广告域名规则
        "outboundTag": "block"
      }
    ]
  },
  "inbounds": [{
    "tag": "xray-xtls-reality",
    "listen": "0.0.0.0",
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "$UUID", "flow": "xtls-rprx-vision"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "dest": "$REALITY_DEST",
        "serverNames": ["$REALITY_SNI"],
        "privateKey": "$PRIVATE_KEY",
        "shortIds": [""]
      }
    },
    "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]},
    "workers": 4
  }],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "block"}
  ]
}
EOF

# 启动 Xray 服务
systemctl restart xray && systemctl enable xray || error_exit "Xray 服务启动失败"

# 检查 Xray 状态
systemctl status xray

# 创建更新 dat 文件的脚本 (与新原代码一致)
mkdir -p /usr/local/etc/xray-script
cat > "$UPDATE_SCRIPT" <<EOF
#!/usr/bin/env bash
set -e
XRAY_DIR="/usr/local/share/xray"
GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/raw/release/geoip.dat"
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/raw/release/geosite.dat"
[ -d "\$XRAY_DIR" ] || mkdir -p "\$XRAY_DIR"
cd "\$XRAY_DIR"
curl -L -o geoip.dat.new "\$GEOIP_URL"
curl -L -o geosite.dat.new "\$GEOSITE_URL"
rm -f geoip.dat geosite.dat
mv geoip.dat.new geoip.dat
mv geosite.dat.new geosite.dat
sudo systemctl -q is-active xray && sudo systemctl restart xray
EOF

# 赋予更新脚本可执行权限 (与新原代码一致)
chmod +x "$UPDATE_SCRIPT" || error_exit "更新脚本授权失败"

# 执行一次更新脚本 (与新原代码一致)
"$UPDATE_SCRIPT" || error_exit "更新脚本执行失败"

# 设置 crontab 每周一 23:00 执行更新 (与新原代码一致)
(crontab -l 2>/dev/null; echo "00 23 * * 1 sudo $UPDATE_SCRIPT >/dev/null 2>&1") | crontab - || error_exit "Crontab 设置失败"

# 优化网络参数 (可配置是否启用 BBR)
if [ "$ENABLE_BBR" = true ]; then
  echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf || error_exit "网络参数优化失败"
  echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf || error_exit "网络参数优化失败"
  cat << EOF | sudo tee -a /etc/sysctl.conf || error_exit "网络参数优化失败"
net.ipv4.tcp_fast_open=3
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.udp_rmem_min=4096
net.ipv4.udp_wmem_min=4096
EOF
  sysctl -p || error_exit "网络参数应用失败"
  echo "BBR 已启用，网络参数已优化。"
else
  echo "BBR 未启用，网络参数优化已跳过。"
fi


# 生成 VPN 配置链接
VPN_LINK="vless://$UUID@$SERVER_IP:443?security=reality&encryption=none&pbk=$PUBLIC_KEY&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=$REALITY_SNI#Xray-Reality"
echo "VPN Link: $VPN_LINK"

# 安装 qrencode 并生成二维码
apt install qrencode -y || error_exit "qrencode 安装失败"
qrencode -o - -t ANSIUTF8 "$VPN_LINK"

echo -e "\n🎉 VPN 创建完成！🎉"
echo -e "\n🚀 VPN 配置链接 (请复制到您的客户端):"
echo "$VPN_LINK"
echo -e "\n🖼️  VPN 配置二维码 (请使用客户端扫描):"
echo -e "\n✅  VPS 搭建完成！享受快速、稳定、高效的VPN服务吧！"
