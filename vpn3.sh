#!/bin/bash

# 一键部署 Xray VPN 脚本
# 设置全局变量：定义域名
DOMAIN="addons.mozilla.org"

# 更新系统
sudo apt update -y && sudo apt upgrade -y
cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# 安装 unzip 和 qrencode (如果不存在)
command -v unzip >/dev/null || sudo apt install unzip -y
command -v qrencode >/dev/null || sudo apt install qrencode -y

# 停止 Xray 服务（仅在 Xray 运行时停止）
systemctl is-active --quiet xray && systemctl stop xray

# 备份并删除旧的 Xray 配置文件
CONFIG_FILE="/usr/local/etc/xray/config.json"
if [ -f "$CONFIG_FILE" ]; then
    echo "备份旧配置..."
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    rm -f "$CONFIG_FILE"
fi

# 下载并安装 Xray
curl -L -o install-release.sh https://github.com/XTLS/Xray-install/raw/main/install-release.sh && bash install-release.sh

# 检查 Xray 版本
xray version

# 生成 UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "UUID: $UUID"

# 生成 Reality 密钥对
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key" | cut -d ' ' -f3)
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key" | cut -d ' ' -f3)
echo "Private key: $PRIVATE_KEY"
echo "Public key: $PUBLIC_KEY"

# 获取服务器 IP，使用多个 API 以防失败
SERVER_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)
echo "Server IP: $SERVER_IP"

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

# 配置 Xray
CONFIG_FILE="/usr/local/etc/xray/config.json"
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
    "prefetch": true
  },
  "routing": {
    "rules": [
      $ROUTE_RULES
    ]
  }
}
EOF

# 启动 Xray 服务
systemctl start xray && systemctl enable xray

echo "Xray 部署完成！"
echo "UUID: $UUID"
echo "Reality Private Key: $PRIVATE_KEY"
echo "Reality Public Key: $PUBLIC_KEY"
echo "Server IP: $SERVER_IP"
