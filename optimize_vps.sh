#!/bin/bash
set -e

# 一键优化 Google Cloud VPS 网络，适用于 XTLS-RPRX-Vision VPN
# 支持 Ubuntu 22.04 LTS，含 BBR、DNS 优化、自动重启功能

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 权限运行此脚本：sudo bash $0"
  exit 1
fi

# 2. 备份配置文件
echo "备份现有配置文件..."
[ -f /etc/sysctl.conf ] && cp /etc/sysctl.conf /etc/sysctl.conf.bak
[ -f /usr/local/etc/xray/config.json ] && cp /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.bak

# 3. 启用 Google BBR
echo "启用 Google BBR 拥塞控制..."
modprobe tcp_bbr
grep -qxF "tcp_bbr" /etc/modules-load.d/modules.conf || echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
sysctl -w net.core.default_qdisc=fq
sysctl -w net.ipv4.tcp_congestion_control=bbr

# 4. 写入优化参数
echo "写入 TCP 网络优化参数..."
cat << EOF > /etc/sysctl.d/99-xray-optimization.conf
net.ipv4.ip_forward=1

net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_adv_win_scale=2

net.ipv4.tcp_max_syn_backlog=8192
net.core.somaxconn=32768
net.ipv4.tcp_syncookies=1
net.core.netdev_max_backlog=5000
net.ipv4.tcp_tw_reuse=1

net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=5

net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_no_metrics_save=1
EOF

sysctl --system

# 5. 配置 DNS（Google + Cloudflare + AliDNS + OpenDNS）
read -p "是否禁用 systemd-resolved 并重设 DNS？[y/N]: " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
  echo "配置 DNS..."
  systemctl disable systemd-resolved
  systemctl stop systemd-resolved
  rm -f /etc/resolv.conf
  cat << EOF > /etc/resolv.conf
nameserver 8.8.8.8         # Google
nameserver 8.8.4.4         # Google
nameserver 1.1.1.1         # Cloudflare
nameserver 1.0.0.1         # Cloudflare
nameserver 223.5.5.5       # AliDNS
nameserver 208.67.222.222  # OpenDNS
nameserver 208.67.220.220  # OpenDNS
EOF
  chmod 644 /etc/resolv.conf
else
  echo "已跳过 DNS 修改。"
fi

# 6. 提示 Xray 配置建议
echo
echo "✅ 网络参数优化完成！请检查并手动优化 Xray 配置："
echo "文件路径：/usr/local/etc/xray/config.json"
echo "- inbound -> settings -> flow: 设为 xtls-rprx-vision"
echo "- tlsSettings -> fragment: {\"enabled\": true, \"range\": \"100-300\"}"
echo "- sockopt -> tfo: true"

# 7. 自动重启 VPS
read -p "是否现在重启 VPS 应用设置？[y/N]: " reboot_confirm
if [[ "$reboot_confirm" =~ ^[Yy]$ ]]; then
  echo "系统将在 3 秒后重启..."
  sleep 3
  reboot
else
  echo "请稍后手动重启以应用所有优化。"
fi
