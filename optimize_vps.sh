```bash
   #!/bin/bash

   # 一键优化 Google Cloud VPS 网络，适用于 XTLS-RPRX-Vision VPN
   # 修复版：避免 JSON 解析错误，优化 DNS 和网络配置
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
   systemctl disable systemd-resolved
   systemctl stop systemd-resolved
   rm -f /etc/resolv.conf
   cat << EOF > /etc/resolv.conf
   nameserver 8.8.8.8
   nameserver 8.8.4.4
   nameserver 1.1.1.1
   nameserver 1.0.0.1
   EOF
   chmod 644 /etc/resolv.conf

   # 4. 提示手动优化 Xray 配置
   echo "Xray 配置文件优化提示："
   echo "请手动编辑 /usr/local/etc/xray/config.json，确保以下设置："
   echo "- 确认 'flow' 设置为 'xtls-rprx-vision'（在 inbound 的 settings 中）。"
   echo "- 添加 TLS 分片：'fragment': {'enabled': true, 'range': '100-300'}（在 tlsSettings 中）。"
   echo "- 启用 TCP Fast Open：'sockopt': {'tfo': true, 'tcpFastOpenQueueLen': 4096}（在 streamSettings 中）。"
   echo "示例（在 inbound 中添加或修改）："
   cat << EXAMPLE
   {
     "inbounds": [{
       "settings": {
         "flow": "xtls-rprx-vision"
       },
       "streamSettings": {
         "tlsSettings": {
           "fragment": {
             "enabled": true,
             "range": "100-300"
           }
         },
         "sockopt": {
           "tfo": true,
           "tcpFastOpenQueueLen": 4096
         }
       }
     }]
   }
   EXAMPLE
   echo "请按需编辑配置文件后保存。"

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
   echo "如需恢复原始配置，可使用备份文件：/etc/sysctl.conf.bak 和 /usr/local/etc/xray/config.json.bak"
   ```

2. **保存并赋予执行权限**：
   ```bash
   chmod +x optimize_vps_fixed.sh
   ```

3. **运行修复后的脚本**：
   ```bash
   ./optimize_vps_fixed.sh
   ```

4. **手动优化 Xray 配置文件**：
   - 脚本会提示你编辑 `/usr/local/etc/xray/config.json`。运行以下命令：
     ```bash
     nano /usr/local/etc/xray/config.json
     ```
   - 根据提示，确保 `inbounds` 部分包含以下设置（具体字段位置取决于你的配置，建议备份后修改）：
     ```json
     {
       "inbounds": [{
         "settings": {
           "flow": "xtls-rprx-vision"
         },
         "streamSettings": {
           "tlsSettings": {
             "fragment": {
               "enabled": true,
               "range": "100-300"
             }
           },
           "sockopt": {
             "tfo": true,
             "tcpFastOpenQueueLen": 4096
           }
         }
       }]
     }
     ```
   - 保存并退出（Ctrl+O，Enter，Ctrl+X）。

5. **重启 Xray 服务**：
   ```bash
   sudo systemctl restart xray
   ```

6. **验证服务状态**：
   ```bash
   sudo systemctl status xray
   ```
   确认显示 `Active: active (running)`。

#### 步骤 4：测试优化效果
1. **连接 VPN**：
   - 在你的客户端设备上使用 VPN 客户端（支持 XTLS-RPRX-Vision 的客户端，如 V2RayNG、Nekobox 或 Qv2ray）连接到 VPS。
2. **测试访问**：
   - 访问 x.com，检查页面加载速度。
   - 打开 YouTube，播放高清视频，观察缓冲和流畅度。
3. **检查网络性能**：
   - 在 VPS 上安装 `iftop` 查看带宽使用：
     ```bash
     sudo apt-get install iftop
     iftop -i eth0
     ```
   - 确认 YouTube 视频流占用合理带宽（5-20 Mbps 视分辨率而定）。

#### 步骤 5：处理潜在问题
- **如果 Xray 仍无法启动**：
  - 检查配置文件语法：
    ```bash
    /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
    ```
    如果报错，修正 `config.json` 中的语法问题。
  - 提供你的 `config.json`（去除敏感信息如 UUID 和域名）给我，我可以帮你调试。

- **如果 DNS 配置仍被覆盖**：
  - 确认 `systemd-resolved` 已禁用：
    ```bash
    systemctl is-active systemd-resolved
    ```
    应返回 `inactive`。
  - 如果仍被覆盖，检查是否有其他服务（如云初始化脚本）修改 DNS。

- **如果速度未提升**：
  - 确认 VPS 区域是否靠近你的位置（你的 VPS 名为 `jp-vpn`，可能是 `asia-northeast1`）。运行以下命令检查：
    ```bash
    gcloud compute instances describe jp-vpn --format='get(zone)'
    ```
    如果延迟较高，考虑迁移到其他区域（如 `asia-east1`）。
  - 检查客户端与 VPS 的网络延迟：
    ```bash
    ping <your-vps-external-ip>
    ```

---

### 总结
修复后的脚本已解决 `chattr` 和 `jq` 导致的问题，并提示手动优化 Xray 配置。请按以下步骤操作：
1. 恢复 Xray 配置文件并重启服务。
2. 禁用 `systemd-resolved` 并手动设置 DNS。
3. 运行修复后的脚本（`optimize_vps_fixed.sh`）。
4. 手动编辑 `config.json` 添加优化设置。
5. 测试 x.com 和 YouTube 的访问速度。

如果运行脚本或编辑配置文件时遇到进一步问题，请提供以下信息：
- `/usr/local/etc/xray/config.json` 的内容（去除敏感信息）。
- 运行修复脚本后的完整输出。
- Xray 服务日志（`journalctl -u xray -b`）。
我将为你提供更精确的解决方案。
