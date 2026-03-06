#!/bin/bash
# ==========================================
# iStoreOS-Flow 数据采集脚本 (精准排查适配版)
# 作者：https://github.com/Rabbit-Spec
# 版本：1.2.9
# 日期：2026.03.06
# ==========================================


ISTOREOS_IP="192.168.1.1" 
SSH_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /config/.ssh/id_rsa root@$ISTOREOS_IP"

ACTION=${1:-fetch}

case "$ACTION" in
    reboot) $SSH_CMD "reboot" ;;

    proxy_state)
        $SSH_CMD '
            if ps -w | grep -v grep | grep -i "/etc/openclash/clash" >/dev/null; then echo "ON_OpenClash";
            elif ps -w | grep -v grep | grep -i "passwall" >/dev/null; then echo "ON_PassWall";
            elif ps -w | grep -v grep | grep -i "passwall2" >/dev/null; then echo "ON_PassWall2";
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
            
            wan_name=$(ubus list network.interface.* | cut -d. -f3 | grep -E "wan|pppoe" | head -n 1)
            [ -z "$wan_name" ] && wan_name="wan"
            wan_status=$(ubus call network.interface.$wan_name status 2>/dev/null)
            wan_ip=$(echo "$wan_status" | jsonfilter -e "@[\"ipv4-address\"][0].address" 2>/dev/null)
            
            if [ -n "$wan_ip" ] && [ "$wan_ip" != "unknown" ]; then
                mode="main"
                display_ip="$wan_ip"
                wan_dev=$(echo "$wan_status" | jsonfilter -e "@.l3_device")
            else
                mode="side"
                display_ip=$(ubus call network.interface.lan status | jsonfilter -e "@[\"ipv4-address\"][0].address" 2>/dev/null)
                wan_dev="br-lan"
            fi
            
            rx=0; tx=0
            [ -n "$wan_dev" ] && dev_status=$(ubus call network.device status "{\"name\":\"$wan_dev\"}" 2>/dev/null)
            rx=$(echo "$dev_status" | jsonfilter -e "@.statistics.rx_bytes" || echo 0)
            tx=$(echo "$dev_status" | jsonfilter -e "@.statistics.tx_bytes" || echo 0)
            temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || cat /sys/class/thermal/thermal_zone1/temp 2>/dev/null || echo 0)
            devices=$(cat /proc/net/arp | grep -c -v IP)
            fw_version=$(grep "DISTRIB_DESCRIPTION" /etc/openwrt_release | cut -d"'"'"'" -f2)

            ports_json="["
            first_port=1
            for iface in $(ls /sys/class/net/ | grep -E "^(eth|en|lan|wan|igb|br-)"); do
                operstate=$(cat /sys/class/net/$iface/operstate 2>/dev/null || echo "down")
                if [ "$operstate" = "up" ]; then
                    speed=$(cat /sys/class/net/$iface/speed 2>/dev/null || echo "0")
                    [ "$speed" = "-1" ] && speed=0
                else
                    speed=0
                fi
                
                [ $first_port -eq 0 ] && ports_json="$ports_json,"
                ports_json="$ports_json{\"name\":\"$iface\",\"state\":\"$operstate\",\"speed\":$speed}"
                first_port=0
            done
            ports_json="$ports_json]"

            printf "{\"uptime\":%d,\"mode\":\"%s\",\"ip\":\"%s\",\"mem_total\":%lu,\"mem_free\":%lu,\"load\":%d,\"temp\":%.1f,\"devices\":%d,\"wan_rx\":%lu,\"wan_tx\":%lu,\"fw_ver\":\"%s\",\"ports\":%s}\n" \
                   "$uptime" "$mode" "$display_ip" "$mem_total" "$mem_free" "$load" "$(($temp_raw/1000))" "$devices" "$rx" "$tx" "$fw_version" "$ports_json"
        ' > /config/shell/istoreos_flow.json ;;
esac