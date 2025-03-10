#!/bin/bash

# 更新系统并安装必要工具
apt update
apt upgrade -y
apt install -y curl wget unzip net-tools

# 开启BBR
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

# 验证BBR是否开启
sysctl net.ipv4.tcp_congestion_control
lsmod | grep bbr

# 下载并安装Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# 生成随机UUID
UUID=$(xray uuid)
echo "您的UUID是: $UUID"

# 生成随机端口
PORT=$(shuf -i 10000-65535 -n 1)
echo "您的端口是: $PORT"

# 生成随机X25519私钥和公钥
x25519_keys=$(xray x25519)
private_key=$(echo "$x25519_keys" | grep "Private" | awk -F: '{print $2}' | tr -d ' ')
public_key=$(echo "$x25519_keys" | grep "Public" | awk -F: '{print $2}' | tr -d ' ')
echo "您的私钥是: $private_key"
echo "您的公钥是: $public_key"

# 获取服务器IP
SERVER_IP=$(curl -s4 ip.sb)
echo "您的服务器IP是: $SERVER_IP"

# 配置Xray
cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $PORT,
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
          "show": false,
          "dest": "www.microsoft.com:443",
          "xver": 0,
          "serverNames": [
            "microsoft.com",
            "www.microsoft.com"
          ],
          "privateKey": "$private_key",
          "minClientVer": "",
          "maxClientVer": "",
          "maxTimeDiff": 0,
          "shortIds": [
            "",
            "6ba85179e30d"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

# 重启Xray服务
systemctl restart xray
systemctl status xray

# 检查Xray是否运行
if systemctl is-active --quiet xray; then
    echo "Xray已成功安装并运行！"
else
    echo "Xray安装失败，请检查日志"
fi

# 生成客户端配置信息
echo "======================================================="
echo "VLESS 客户端配置信息："
echo "地址: $SERVER_IP"
echo "端口: $PORT"
echo "UUID: $UUID"
echo "流控: xtls-rprx-vision"
echo "传输协议: tcp"
echo "安全: reality"
echo "SNI: www.microsoft.com"
echo "公钥: $public_key"
echo "指纹: chrome"
echo "======================================================="
