#!/bin/bash

# 一键优化 Google Cloud VPS 网络，适用于 XTLS-RPRX-Vision VPN
# 最终版：含 DNS 扩展、BBR 调优、重启 VPS
# 适用于 Ubuntu 22.04+

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 权限运行此脚本：sudo bash $0"
  exit 1
fi

echo "开始优化系统网络参数..."

# 备份配置文件
echo "备份现有配置..."
[ -f /etc/sysctl.conf ] && cp /etc/sysctl.conf /etc/sysctl.conf.bak
[ -f /usr/local/etc/xray/config.json ] && cp /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.bak

# 启用 BBR
echo "启用 Google BBR 拥塞控制..."
modprobe tcp_bbr
echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
sysctl -w net.core.default_qdisc=fq
sysctl -w net.ipv4.tcp_congestion_control=bbr

# 写入网络优化参数
echo "写入 TCP 网络优化参数..."
cat << EOF >> /etc/sysctl.d/99-xray-optimization.conf
# IP 转发
net.ipv4.ip_forward=1

# TCP 缓冲区
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_adv_win_scale=2

# 连接优化
net.ipv4.tcp_max_syn_backlog=8192
net.core.somaxconn=32768
net.ipv4.tcp_syncookies=1
net.core.netdev_max_backlog=5000
net.ipv4.tcp_tw_reuse=1

# 超时及 keepalive
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=5

# MTU 优化
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_no_metrics_save=1
EOF

# 应用设置
sysctl --system

# 配置 DNS
echo "配置 DNS：Google + Cloudflare + AliDNS + OpenDNS..."
systemctl disable systemd-resolved >/dev/null 2>&1
systemctl stop systemd-resolved >/dev/null 2>&1
rm -f /etc/resolv.conf
cat << EOF > /etc/resolv.conf
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
nameserver 1.0.0.1
nameserver 223.5.5.5
nameserver 208.67.222.222
nameserver 208.67.220.220
EOF
chmod 644 /etc/resolv.conf

# 输出优化建议
echo ""
echo "✅ 网络优化已完成！"
echo "➡️ 建议检查 /usr/local/etc/xray/config.json 中："
echo "   - inbound.flow: 应为 'xtls-rprx-vision'"
echo "   - tlsSettings.fragment: {'enabled': true, 'range': '100-300'}"
echo "   - sockopt.tfo: 启用 TCP Fast Open"
echo ""
echo "🚀 系统将在 10 秒后自动重启以应用所有设置..."
sleep 10
reboot
