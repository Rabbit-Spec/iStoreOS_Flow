#!/bin/bash
# ==========================================
# iStoreOS-Flow 数据采集脚本 (精准排查适配版)
# 作者：https://github.com/Rabbit-Spec
# 版本：1.1.2
# 日期：2026.03.06
# ==========================================

# 这里的 IP 会在安装时自动替换，请确保指向正确
ISTOREOS_IP="192.168.1.1" 
SSH_CMD="ssh -o StrictHostKeyChecking=no -i /config/.ssh/id_rsa root@$ISTOREOS_IP"

ACTION=${1:-fetch}

# 1. 增强型探测函数：根据您的 ps 实测结果进行精准匹配
detect_proxy() {
    $SSH_CMD '
        if ps -w | grep -v grep | grep -i "/etc/openclash/clash" >/dev/null; then echo "openclash";
        elif ps -w | grep -v grep | grep -i "passwall" >/dev/null; then echo "passwall";
        elif ps -w | grep -v grep | grep -i "passwall2" >/dev/null; then echo "passwall2";
        elif ps -w | grep -v grep | grep -i "nikki" >/dev/null; then echo "nikki";
        else echo "none"; fi
    '
}

case "$ACTION" in
    reboot) $SSH_CMD "reboot" ;;

    proxy_on)
        # 开启逻辑：默认启动您当前正在使用的 OpenClash
        $SSH_CMD "/etc/init.d/openclash start" ;;

    proxy_off)
        # 彻底清理逻辑：排查神器！一次性彻底关停所有可能冲突的插件
        $SSH_CMD '
            [ -x /etc/init.d/openclash ] && /etc/init.d/openclash stop;
            [ -x /etc/init.d/passwall ] && /etc/init.d/passwall stop;
            [ -x /etc/init.d/passwall2 ] && /etc/init.d/passwall2 stop;
            [ -x /etc/init.d/nikki ] && /etc/init.d/nikki stop;
            # 暴力清理残留进程，确保网络环境彻底回正
            killall -9 clash nikki v2ray-plugin 2>/dev/null || true
        ' ;;

    proxy_state)
        # 状态回显：返回精确的插件名称，方便在 HA 面板排查
        $SSH_CMD '
            if ps -w | grep -v grep | grep -i "/etc/openclash/clash" >/dev/null; then echo "ON_OpenClash";
            elif ps -w | grep -v grep | grep -i "passwall" >/dev/null; then echo "ON_PassWall";
            elif ps -w | grep -v grep | grep -i "passwall2" >/dev/null; then echo "ON_PassWall2";
            elif ps -w | grep -v grep | grep -i "nikki" >/dev/null; then echo "ON_Nikki";
            else echo "OFF"; fi
        ' ;;

    fetch)
        $SSH_CMD '
            # 1. 系统基础信息抓取
            sysinfo=$(ubus call system info)
            uptime=$(echo "$sysinfo" | jsonfilter -e "@.uptime")
            mem_total=$(echo "$sysinfo" | jsonfilter -e "@.memory.total")
            mem_free=$(echo "$sysinfo" | jsonfilter -e "@.memory.free")
            load=$(echo "$sysinfo" | jsonfilter -e "@.load[0]")
            
            # 2. 智能探测与 IP 切换逻辑
            wan_name=$(ubus list network.interface.* | cut -d. -f3 | grep -E "wan|pppoe" | head -n 1)
            [ -z "$wan_name" ] && wan_name="wan"
            wan_status=$(ubus call network.interface.$wan_name status 2>/dev/null)
            wan_ip=$(echo "$wan_status" | jsonfilter -e "@[\"ipv4-address\"][0].address")
            
            if [ -n "$wan_ip" ] && [ "$wan_ip" != "unknown" ]; then
                mode="main"
                display_ip="$wan_ip"
                wan_dev=$(echo "$wan_status" | jsonfilter -e "@.l3_device")
            else
                mode="side"
                # 旁路由模式：获取 LAN 内网 IP，流量锁定 br-lan
                display_ip=$(ubus call network.interface.lan status | jsonfilter -e "@[\"ipv4-address\"][0].address")
                wan_dev="br-lan"
            fi
            
            # 3. 流量、温度与版本
            rx=0; tx=0
            [ -n "$wan_dev" ] && dev_status=$(ubus call network.device status "{\"name\":\"$wan_dev\"}" 2>/dev/null)
            rx=$(echo "$dev_status" | jsonfilter -e "@.statistics.rx_bytes" || echo 0)
            tx=$(echo "$dev_status" | jsonfilter -e "@.statistics.tx_bytes" || echo 0)
            temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || cat /sys/class/thermal/thermal_zone1/temp 2>/dev/null || echo 0)
            devices=$(cat /proc/net/arp | grep -c -v IP)
            fw_version=$(grep "DISTRIB_DESCRIPTION" /etc/openwrt_release | cut -d"'"'"'" -f2)

            # 4. JSON 格式化输出 (确保包含 mode 字段)
            printf "{\"uptime\":%d,\"mode\":\"%s\",\"ip\":\"%s\",\"mem_total\":%d,\"mem_free\":%d,\"load\":%d,\"temp\":%.1f,\"devices\":%d,\"wan_rx\":%lu,\"wan_tx\":%lu,\"fw_ver\":\"%s\"}\n" \
                   "$uptime" "$mode" "$display_ip" "$mem_total" "$mem_free" "$load" "$(($temp_raw/1000))" "$devices" "$rx" "$tx" "$fw_version"
        ' > /config/shell/istoreos_flow.json ;;
esac