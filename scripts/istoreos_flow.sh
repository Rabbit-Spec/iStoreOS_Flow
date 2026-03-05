#!/bin/bash
# ==========================================
# iStoreOS-Flow 数据采集脚本
# 作者：https://github.com/Rabbit-Spec
# 版本：1.0.0
# 日期：2026.03.05
# ==========================================

ISTOREOS_IP="192.168.1.1" 
SSH_CMD="ssh -o StrictHostKeyChecking=no -i /config/.ssh/id_rsa root@$ISTOREOS_IP"

ACTION=${1:-fetch}

# 智能探测当前活跃的代理服务
detect_proxy() {
    $SSH_CMD '
        if ps -w | grep -v grep | grep -i "openclash" >/dev/null; then echo "openclash";
        elif ps -w | grep -v grep | grep -i "passwall" >/dev/null; then echo "passwall";
        elif ps -w | grep -v grep | grep -i "nikki" >/dev/null; then echo "nikki";
        elif [ -x /etc/init.d/openclash ]; then echo "openclash";
        elif [ -x /etc/init.d/passwall ]; then echo "passwall";
        elif [ -x /etc/init.d/nikki ]; then echo "nikki";
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
            sysinfo=$(ubus call system info)
            uptime=$(echo "$sysinfo" | jsonfilter -e "@.uptime")
            mem_total=$(echo "$sysinfo" | jsonfilter -e "@.memory.total")
            mem_free=$(echo "$sysinfo" | jsonfilter -e "@.memory.free")
            load=$(echo "$sysinfo" | jsonfilter -e "@.load[0]")
            wan_status=$(ubus call network.interface.wan status 2>/dev/null)
            ip=$(echo "$wan_status" | jsonfilter -e "@[\"ipv4-address\"][0].address" || echo "unknown")
            wan_dev=$(echo "$wan_status" | jsonfilter -e "@.l3_device")
            if [ -n "$wan_dev" ]; then
               dev_status=$(ubus call network.device status "{\"name\":\"$wan_dev\"}")
               rx=$(echo "$dev_status" | jsonfilter -e "@.statistics.rx_bytes")
               tx=$(echo "$dev_status" | jsonfilter -e "@.statistics.tx_bytes")
            fi
            temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
            devices=$(cat /proc/net/arp | grep -c -v IP)
            fw_version=$(grep "DISTRIB_DESCRIPTION" /etc/openwrt_release | cut -d"'"'"'" -f2)

            printf "{\"uptime\":%d,\"mem_total\":%d,\"mem_free\":%d,\"load\":%d,\"temp\":%.1f,\"devices\":%d,\"ip\":\"%s\",\"wan_rx\":%d,\"wan_tx\":%d,\"fw_ver\":\"%s\"}\n" \
                   "$uptime" "$mem_total" "$mem_free" "$load" "$(($temp/1000))" "$devices" "$ip" "$rx" "$tx" "$fw_version"
        ' > /config/shell/istoreos_flow.json ;;
esac