#!/bin/bash
# ==========================================
# iStoreOS-Flow 自动化部署脚本 (防输入劫持版)
# ==========================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

RAW_URL="https://raw.githubusercontent.com/Rabbit-Spec/iStoreOS_Flow/main"

echo -e "${BLUE}======================================================${NC}"
echo -e "          🚀 iStoreOS-Flow 自动化安装程序"
echo -e "${BLUE}======================================================${NC}"

# --- 1. 修复主机名非法字符问题 ---
CURRENT_HOSTNAME=$(hostname)
if [[ "$CURRENT_HOSTNAME" == *"_"* ]]; then
    ha host options --hostname "ha-istoreos-flow" > /dev/null 2>&1 || true
    export HOSTNAME="ha-istoreos-flow"
fi

# --- 2. 核心修复：防 curl 管道劫持键盘输入 ---
INPUT_IP=""
# 强制从当前终端 (/dev/tty) 读取输入，无视管道流
read -p "👉 请输入 iStoreOS 的 IP (直接回车默认 192.168.1.1): " INPUT_IP </dev/tty || true

# 彻底清洗输入数据，剔除空格和隐藏的换行符
OW_IP=$(echo "$INPUT_IP" | tr -d '\r\n ')

# 兜底默认值
if [ -z "$OW_IP" ]; then
    OW_IP="192.168.1.1"
fi
echo -e "${GREEN}👉 即将连接的目标路由 IP 为: $OW_IP ${NC}"

# --- 3. 自动生成密钥 ---
mkdir -p ~/.ssh
if [ ! -f ~/.ssh/id_rsa ]; then
    echo -e "${BLUE}[1/4] 正在生成 SSH 密钥...${NC}"
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -q -N ""
fi

# --- 4. 强制建立 SSH 连接 ---
echo -e "${BLUE}[2/4] 正在打通免密通道，请输 $OW_IP 的 root 密码...${NC}"
cat ~/.ssh/id_rsa.pub | ssh -o "StrictHostKeyChecking=no" \
    -o "UserKnownHostsFile=/dev/null" \
    -o "GlobalKnownHostsFile=/dev/null" \
    root@"$OW_IP" "mkdir -p /etc/dropbear && tee -a /etc/dropbear/authorized_keys" || {
    echo -e "${RED}❌ 连接失败。请确认 IP 正确且 iStoreOS 的 SSH (Dropbear) 已开启。${NC}"
    exit 1
}

# --- 5. 下载并配置核心文件 ---
echo -e "${BLUE}[3/4] 正在拉取 istoreos_flow 组件...${NC}"
mkdir -p /config/shell /config/packages /config/www/img
curl -sSL -o /config/shell/istoreos_flow.sh "${RAW_URL}/scripts/istoreos_flow.sh"
curl -sSL -o /config/packages/istoreos_flow.yaml "${RAW_URL}/packages/istoreos_flow.yaml"

# 替换真实的 IP
sed -i "s/ISTOREOS_IP=\".*\"/ISTOREOS_IP=\"$OW_IP\"/g" /config/shell/istoreos_flow.sh
chmod +x /config/shell/istoreos_flow.sh

# --- 6. 自动挂载配置 ---
echo -e "${BLUE}[4/4] 正在配置 HA 自动加载...${NC}"
if ! grep -q "packages: !include_dir_named packages" /config/configuration.yaml; then
    sed -i '/homeassistant:/a \  packages: !include_dir_named packages' /config/configuration.yaml
fi

echo -e "${GREEN}======================================================${NC}"
echo -e "           🎉 部署完成！请重启 Home Assistant"
echo -e "${GREEN}======================================================${NC}"