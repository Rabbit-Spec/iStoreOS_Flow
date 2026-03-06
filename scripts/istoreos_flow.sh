#!/bin/bash
# ==========================================
# iStoreOS-Flow 数据采集脚本
# 作者：https://github.com/Rabbit-Spec
# 版本：1.3.7
# 日期：2026.03.06
# 说明：此脚本运行在 Home Assistant 内部，通过 SSH 远程登录到 iStoreOS 获取系统数据。
# ==========================================

# 1. 定义路由器 IP 和免密登录的 SSH 命令
ISTOREOS_IP="192.168.1.1" 
SSH_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /config/.ssh/id_rsa root@$ISTOREOS_IP"

# 2. 接收外部参数，默认动作为 fetch (获取数据)
ACTION=${1:-fetch}

case "$ACTION" in
    # 动作：重启路由器
    reboot) $SSH_CMD "reboot" ;;

    # 动作：检查科学上网插件的运行状态
    proxy_state)
        $SSH_CMD '
            # 依次检查各主流代理插件的进程是否存在
            if ps -w | grep -v grep | grep -i "/etc/openclash/clash" >/dev/null; then echo "ON_OpenClash";
            elif ps -w | grep -v grep | grep -i "passwall" >/dev/null; then echo "ON_PassWall";
            elif ps -w | grep -v grep | grep -i "passwall2" >/dev/null; then echo "ON_PassWall2";
            elif ps -w | grep -v grep | grep -i "nikki" >/dev/null; then echo "ON_Nikki";
            else echo "OFF"; fi
        ' ;;

    # 动作：获取所有系统数据并打包成 JSON
    fetch)
        $SSH_CMD '
            # ---------------------------
            # 第一部分：获取基础系统信息
            # ---------------------------
            sysinfo=$(ubus call system info)
            uptime=$(echo "$sysinfo" | jsonfilter -e "@.uptime")        # 运行时间
            mem_total=$(echo "$sysinfo" | jsonfilter -e "@.memory.total") # 总内存
            mem_free=$(echo "$sysinfo" | jsonfilter -e "@.memory.free")   # 空闲内存
            load=$(echo "$sysinfo" | jsonfilter -e "@.load[0]")           # CPU 负载
            
            # ---------------------------
            # 第二部分：判断路由模式与获取 IP
            # ---------------------------
            # 自动寻找包含 wan 或 pppoe 的接口作为公网接口
            wan_name=$(ubus list network.interface.* | cut -d. -f3 | grep -E "wan|pppoe" | head -n 1)
            [ -z "$wan_name" ] && wan_name="wan"
            wan_status=$(ubus call network.interface.$wan_name status 2>/dev/null)
            wan_ip=$(echo "$wan_status" | jsonfilter -e "@[\"ipv4-address\"][0].address" 2>/dev/null)
            
            # 如果能获取到公网 IP，说明是主路由；否则判断为旁路由，并取内网 IP
            if [ -n "$wan_ip" ] && [ "$wan_ip" != "unknown" ]; then
                mode="main"
                display_ip="$wan_ip"
                wan_dev=$(echo "$wan_status" | jsonfilter -e "@.l3_device")
            else
                mode="side"
                display_ip=$(ubus call network.interface.lan status | jsonfilter -e "@[\"ipv4-address\"][0].address" 2>/dev/null)
                wan_dev="br-lan"
            fi
            
            # ---------------------------
            # 第三部分：获取网络流量、温度和设备数
            # ---------------------------
            rx=0; tx=0
            [ -n "$wan_dev" ] && dev_status=$(ubus call network.device status "{\"name\":\"$wan_dev\"}" 2>/dev/null)
            rx=$(echo "$dev_status" | jsonfilter -e "@.statistics.rx_bytes" || echo 0) # 总下载字节
            tx=$(echo "$dev_status" | jsonfilter -e "@.statistics.tx_bytes" || echo 0) # 总上传字节
            # 读取 CPU 温度 (适配不同硬件的路径)
            temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || cat /sys/class/thermal/thermal_zone1/temp 2>/dev/null || echo 0)
            # 通过 ARP 表统计当前局域网内的设备数量
            devices=$(cat /proc/net/arp | grep -c -v IP)
            fw_version=$(grep "DISTRIB_DESCRIPTION" /etc/openwrt_release | cut -d"'"'"'" -f2)

            # ---------------------------
            # 第四部分：扫描所有磁盘的容量信息
            # ---------------------------
            disks_json="["
            first_disk=1
            disk_total=0
            disk_free=0
            # 遍历根目录和挂载在 /mnt 下的所有物理硬盘
            for mnt in / $(ls -d /mnt/* 2>/dev/null); do
                [ ! -d "$mnt" ] && continue
                # 排除系统内部使用的虚拟挂载点
                case "$mnt" in /mnt/cfg*|/mnt/log*) continue ;; esac
                
                # 获取空间信息并分割出 总空间 和 剩余空间 (KB)
                df_info=$(df -k "$mnt" | tail -n 1 | tr -s " ")
                d_total=$(echo "$df_info" | cut -d " " -f 2)
                d_free=$(echo "$df_info" | cut -d " " -f 4)
                d_name=$(basename "$mnt")
                
                # 如果是根目录，则命名为 System，并单独保存为系统盘的变量
                [ "$d_name" == "/" ] && { d_name="System"; disk_total=$d_total; disk_free=$d_free; }
                
                # 拼接成 JSON 数组格式
                [ $first_disk -eq 0 ] && disks_json="$disks_json,"
                disks_json="$disks_json{\"name\":\"$d_name\",\"total\":$d_total,\"free\":$d_free}"
                first_disk=0
            done
            disks_json="$disks_json]"

            # ---------------------------
            # 第五部分：扫描物理网口的状态和速率
            # ---------------------------
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

            # ---------------------------
            # 第六部分：测试外网连通性 (Ping)
            # ---------------------------
            # 向阿里云 DNS 发送 1 个数据包，超时设为 1 秒，并提取毫秒数
            ping_ms=$(ping -c 1 -W 1 223.5.5.5 | grep "time=" | sed "s/.*time=\([0-9.]*\).*/\1/")
            [ -z "$ping_ms" ] && ping_ms=0

            # ---------------------------
            # 最终输出：将所有收集到的数据按 JSON 格式打印，并存入文件
            # ---------------------------
            printf "{\"uptime\":%d,\"mode\":\"%s\",\"ip\":\"%s\",\"mem_total\":%lu,\"mem_free\":%lu,\"load\":%d,\"temp\":%.1f,\"devices\":%d,\"wan_rx\":%lu,\"wan_tx\":%lu,\"fw_ver\":\"%s\",\"ports\":%s,\"disk_total\":%lu,\"disk_free\":%lu,\"disks\":%s,\"ping\":%.1f}\n" \
                   "$uptime" "$mode" "$display_ip" "$mem_total" "$mem_free" "$load" "$(($temp_raw/1000))" "$devices" "$rx" "$tx" "$fw_version" "$ports_json" "${disk_total:-0}" "${disk_free:-0}" "$disks_json" "${ping_ms:-0}"
        ' > /config/shell/istoreos_flow.json ;;
esac