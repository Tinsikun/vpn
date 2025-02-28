#!/bin/bash

# --------------------- 脚本配置区 ---------------------
XRAY_VERSION="latest"
REALITY_DEST="addons.mozilla.org:443"
REALITY_SNI="addons.mozilla.org"
DNS_SERVERS=("8.8.8.8" "8.8.4.4" "223.5.5.5" "1.1.1.1" "1.0.0.1")
ADDITIONAL_BLOCKED_DOMAINS=("account.listary.com" "example.com" "another-example.org")
BLOCK_AD_DOMAINS="geosite:category-ads-all"
DIRECT_CN_IP=true
ENABLE_BBR=true

# --------------------- 代码执行区 ---------------------
[ "$EUID" -ne 0 ] && { echo "请使用 sudo 或 root 权限运行" >&2; exit 1; }

XRAY_CONFIG="/usr/local/etc/xray/config.json"
UPDATE_SCRIPT="/usr/local/etc/xray-script/update-dat.sh"
QR_CODE_FILE="/tmp/xray_qr.png"
TEMP_LOG="/tmp/xray_install.log"

# 函数：错误处理
error_exit() {
    echo "错误：$1" >&2
    [ -f "$TEMP_LOG" ] && { echo "安装日志：" >&2; cat "$TEMP_LOG" >&2; }
    exit 1
}

# 检查必要命令并安装
for cmd in curl unzip systemctl awk qrencode jq; do
    command -v "$cmd" >/dev/null 2>&1 || { apt-get install -y -qq "$cmd" || error_exit "$cmd 未安装"; }
done

# 静默更新系统
apt-get update -qq && apt-get upgrade -y -qq || error_exit "系统更新失败"

# 安装 Xray
INSTALL_SCRIPT=$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh) || error_exit "下载 Xray 安装脚本失败"
echo "$INSTALL_SCRIPT" | bash -s -- -q >"$TEMP_LOG" 2>&1 || error_exit "Xray 安装失败"
[ -x /usr/local/bin/xray ] || error_exit "Xray 可执行文件未找到"

# 生成配置
UUID=$(cat /proc/sys/kernel/random/uuid) || error_exit "UUID 生成失败"
KEYS=$(xray x25519) || error_exit "Reality 密钥生成失败"
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key" | awk '{print $3}')
SERVER_IP=$(curl -s https://api.ipify.org) || error_exit "获取 IP 失败"

# 生成 JSON 配置
cat > "$XRAY_CONFIG" <<EOF || error_exit "配置生成失败"
{
  "log": {"loglevel": "warning"},
  "dns": {
    "servers": $(printf '%s\n' "${DNS_SERVERS[@]}" | jq -R . | jq -s .),
    "client": "1.1.1.1",
    "prefetch": true
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"type": "field", "protocol": ["bittorrent"], "outboundTag": "block"},
      {"type": "field", "ip": ["geoip:private"], "outboundTag": "block"},
      {"type": "field", "ip": ["geoip:cn"], "outboundTag": "$([ "$DIRECT_CN_IP" = true ] && echo "direct" || echo "block")"},
      {"type": "field", "domain": ["$BLOCK_AD_DOMAINS"], "outboundTag": "block"}
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
    "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}
  }],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "block"}
  ]
}
EOF

# 管理 Xray 服务
systemctl restart xray >/dev/null 2>&1 && systemctl enable xray >/dev/null 2>&1 || error_exit "Xray 服务启动失败"

# 创建更新脚本
mkdir -p /usr/local/etc/xray-script
cat > "$UPDATE_SCRIPT" <<EOF || error_exit "更新脚本创建失败"
#!/bin/bash
set -e
XRAY_DIR="/usr/local/share/xray"
GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/raw/release/geoip.dat"
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/raw/release/geosite.dat"
[ -d "\$XRAY_DIR" ] || mkdir -p "\$XRAY_DIR"
cd "\$XRAY_DIR"
curl -fsSL -o geoip.dat.new "\$GEOIP_URL" && mv geoip.dat.new geoip.dat
curl -fsSL -o geosite.dat.new "\$GEOSITE_URL" && mv geosite.dat.new geosite.dat
systemctl -q is-active xray && systemctl restart xray >/dev/null 2>&1
EOF

chmod +x "$UPDATE_SCRIPT" && "$UPDATE_SCRIPT" || error_exit "更新脚本执行失败"
(crontab -l 2>/dev/null; echo "00 23 * * 1 $UPDATE_SCRIPT >/dev/null 2>&1") | crontab - || error_exit "Crontab 设置失败"

# BBR 优化
if [ "$ENABLE_BBR" = true ]; then
    cat << EOF | tee -a /etc/sysctl.conf || error_exit "BBR 配置失败"
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fast_open=3
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.udp_rmem_min=4096
net.ipv4.udp_wmem_min=4096
EOF
    sysctl -p >/dev/null 2>&1 || error_exit "BBR 应用失败"
fi

# 生成 VPN 链接和二维码
VPN_LINK="vless://$UUID@$SERVER_IP:443?security=reality&encryption=none&flow=xtls-rprx-vision#My-VPN"
qrencode -o "$QR_CODE_FILE" "$VPN_LINK" || error_exit "二维码生成失败"

# 输出结果并清理临时文件
echo "VPN 配置链接：$VPN_LINK"
echo "二维码已保存至：$QR_CODE_FILE"
[ -f "$TEMP_LOG" ] && rm -f "$TEMP_LOG"
