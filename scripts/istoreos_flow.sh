#!/bin/bash
# ==========================================
# iStoreOS-Flow 数据采集脚本
# 作者：https://github.com/Rabbit-Spec
# 版本：1.0.2
# 日期：2026.03.06
# ==========================================

# 此处 IP 会被安装脚本自动替换
ISTOREOS_IP="192.168.1.1" 
SSH_CMD="ssh -o StrictHostKeyChecking=no -i /config/.ssh/id_rsa root@$ISTOREOS_IP"

ACTION=${1:-fetch}

# 智能探测当前活跃的代理服务
detect_proxy() {
    $SSH_CMD '
        if ps -w | grep -v grep | grep -i "openclash" >/dev/null; then echo "openclash";
        elif ps -w | grep -v grep | grep -i "passwall" >/dev/null; then echo "passwall";
        elif ps -w | grep -v grep | grep -i "nikki" >/dev/null; then echo "nikki";
        else echo "none"; fi
    '
}

case "$ACTION" in
    reboot) $SSH_CMD "reboot" ;;
    proxy_on)
        SERVICE=$(detect_proxy)
        [ "$SERVICE" != "none" ] && $SSH_CMD "/etc/init.d/$SERVICE start" ;;
    proxy_off)
        $SSH_CMD "[ -x /etc/init.d/openclash ] && /etc/init.d/openclash stop; \
                  [ -x /etc/init.d/passwall ] && /etc/init.d/passwall stop; \
                  [ -x /etc/init.d/nikki ] && /etc/init.d/nikki stop;" ;;
    proxy_state)
        $SSH_CMD '
            if ps -w | grep -v grep | grep -i "openclash" >/dev/null; then echo "ON_OpenClash";
            elif ps -w | grep -v grep | grep -i "passwall" >/dev/null; then echo "ON_PassWall";
            elif ps -w | grep -v grep | grep -i "nikki" >/dev/null; then echo "ON_Nikki";
            else echo "OFF"; fi
        ' ;;
    fetch)
        $SSH_CMD '
            # 1. 基础系统信息抓取
            sysinfo=$(ubus call system info)
            uptime=$(echo "$sysinfo" | jsonfilter -e "@.uptime")
            mem_total=$(echo "$sysinfo" | jsonfilter -e "@.memory.total")
            mem_free=$(echo "$sysinfo" | jsonfilter -e "@.memory.free")
            load=$(echo "$sysinfo" | jsonfilter -e "@.load[0]")
            
            # 2. 智能模式探测逻辑
            # 尝试获取物理 WAN 信息
            wan_name=$(ubus list network.interface.* | cut -d. -f3 | grep -E "wan|pppoe" | head -n 1)
            [ -z "$wan_name" ] && wan_name="wan"
            wan_status=$(ubus call network.interface.$wan_name status 2>/dev/null)
            
            # 提取接口 IP 和设备名
            ip=$(echo "$wan_status" | jsonfilter -e "@[\"ipv4-address\"][0].address")
            wan_dev=$(echo "$wan_status" | jsonfilter -e "@.l3_device")
            
            # --- 自适应判断核心 ---
            if [ -n "$ip" ] && [ "$ip" != "unknown" ]; then
                # 【主路由模式】：IP 存在且非空，使用接口流量
                mode="main"
            else
                # 【旁路由模式】：IP 缺失，通过外部 API 获取公网 IP，流量锁定 br-lan
                mode="side"
                ip=$(curl -s --connect-timeout 3 http://api.ipify.org || echo "unknown")
                wan_dev="br-lan"
            fi
            
            # 3. 抓取选定接口的流量统计
            rx=0; tx=0
            if [ -n "$wan_dev" ]; then
               dev_status=$(ubus call network.device status "{\"name\":\"$wan_dev\"}" 2>/dev/null)
               rx=$(echo "$dev_status" | jsonfilter -e "@.statistics.rx_bytes" || echo 0)
               tx=$(echo "$dev_status" | jsonfilter -e "@.statistics.tx_bytes" || echo 0)
            fi
            
            # 4. 温度与版本
            temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || cat /sys/class/thermal/thermal_zone1/temp 2>/dev/null || echo 0)
            devices=$(cat /proc/net/arp | grep -c -v IP)
            fw_version=$(grep "DISTRIB_DESCRIPTION" /etc/openwrt_release | cut -d"'"'"'" -f2)

            # 5. 格式化输出 JSON
            printf "{\"uptime\":%d,\"mem_total\":%d,\"mem_free\":%d,\"load\":%d,\"temp\":%.1f,\"devices\":%d,\"ip\":\"%s\",\"wan_rx\":%d,\"wan_tx\":%d,\"fw_ver\":\"%s\"}\n" \
                   "$uptime" "$mem_total" "$mem_free" "$load" "$(($temp_raw/1000))" "$devices" "$ip" "$rx" "$tx" "$fw_version"
        ' > /config/shell/istoreos_flow.json ;;
esac