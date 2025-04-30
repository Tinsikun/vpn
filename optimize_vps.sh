#!/bin/bash

# 一键优化 Google Cloud VPS 网络，适用于 XTLS-RPRX-Vision VPN
# 目标：提升访问 x.com 和 YouTube 的速度和稳定性
# 适用于 Ubuntu 22.04 LTS

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 权限运行此脚本：sudo bash $0"
  exit 1
fi

# 备份现有配置文件
echo "备份现有配置文件..."
[ -f /etc/sysctl.conf ] && cp /etc/sysctl.conf /etc/sysctl.conf.bak
[ -f /usr/local/etc/xray/config.json ] && cp /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.bak

# 1. 启用 Google BBR 拥塞控制算法
echo "启用 Google BBR..."
modprobe tcp_bbr
echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
sysctl -w net.core.default_qdisc=fq
sysctl -w net.ipv4.tcp_congestion_control=bbr

# 2. 优化 TCP 和网络参数
echo "优化 TCP 和网络参数..."
cat << EOF >> /etc/sysctl.conf
# 启用 IP 转发
net.ipv4.ip_forward=1

# 优化 TCP 窗口和缓冲区
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_adv_win_scale=2

# 优化连接队列和重用
net.ipv4.tcp_max_syn_backlog=8192
net.core.somaxconn=32768
net.ipv4.tcp_syncookies=1
net.core.netdev_max_backlog=5000
net.ipv4.tcp_tw_reuse=1

# 减少超时和优化 keepalive
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=5

# MTU 和 MSS 优化（适合 YouTube 流媒体）
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_no_metrics_save=1
EOF

# 应用 sysctl 设置
sysctl -p

# 3. 配置快速 DNS
echo "配置 Google 和 Cloudflare DNS..."
cat << EOF > /etc/resolv.conf
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF

# 防止 resolv.conf 被覆盖
chattr +i /etc/resolv.conf

# 4. 优化 Xray 配置文件
echo "优化 Xray 配置文件..."
XRAY_CONFIG="/usr/local/etc/xray/config.json"
if [ -f "$XRAY_CONFIG" ]; then
  # 备份原始配置
  cp "$XRAY_CONFIG" "$XRAY_CONFIG.bak"
  
  # 假设使用 XTLS-RPRX-Vision，优化流控和连接设置
  jq '.inbounds[0].settings.flow = "xtls-rprx-vision" | 
      .inbounds[0].settings.tlsSettings.fragment.enabled = true | 
      .inbounds[0].settings.tlsSettings.fragment.range = "100-300" | 
      .inbounds[0].streamSettings.sockopt.tfo = true | 
      .inbounds[0].streamSettings.sockopt.tcpFastOpenQueueLen = 4096' "$XRAY_CONFIG" > /tmp/xray_config_tmp.json
  mv /tmp/xray_config_tmp.json "$XRAY_CONFIG"
else
  echo "未找到 Xray 配置文件 ($XRAY_CONFIG)，请手动优化。"
fi

# 5. 重启 Xray 服务
echo "重启 Xray 服务..."
systemctl restart xray
systemctl enable xray

# 6. 检查优化结果
echo "检查优化结果..."
echo "BBR 状态："
sysctl net.ipv4.tcp_congestion_control
echo "IP 转发状态："
sysctl net.ipv4.ip_forward
echo "DNS 配置："
cat /etc/resolv.conf
echo "Xray 服务状态："
systemctl status xray --no-pager

echo "优化完成！请测试访问 x.com 和 YouTube 的速度。"
echo "如需恢复原始配置，可使用备份文件：/etc/sysctl.conf.bak 和 $XRAY_CONFIG.bak"
