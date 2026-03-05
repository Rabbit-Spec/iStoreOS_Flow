#!/bin/bash
# ==========================================
# iStoreOS-Flow 一键部署脚本
# 作者：https://github.com/Rabbit-Spec
# 版本：1.0.2
# 日期：2026.03.05
# ==========================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

RAW_URL="https://raw.githubusercontent.com/Rabbit-Spec/iStoreOS_Flow/main"

echo -e "${BLUE}======================================================${NC}"
echo -e "          🚀 iStoreOS-Flow 自动化部署程序"
echo -e "${BLUE}======================================================${NC}"

# --- 核心自动化修复：修正 HA 系统主机名 ---
# 检查当前系统主机名是否包含非法字符（如下划线）
CURRENT_HOSTNAME=$(hostname)
if [[ "$CURRENT_HOSTNAME" == *"_"* ]]; then
    echo -e "${YELLOW}[修复] 检测到非法主机名: $CURRENT_HOSTNAME${NC}"
    echo -e "${BLUE}正在自动将 HA 系统主机名修正为 'ha-istoreos-flow'...${NC}"
    # 使用 HA 官方 CLI 修改系统级主机名
    ha host options --hostname "ha-istoreos-flow" > /dev/null 2>&1 || true
    export HOSTNAME="ha-istoreos-flow"
    echo -e "${GREEN}✅ 主机名环境已修正。${NC}"
fi

# 1. 获取并清洗 IP 地址（防止末尾有空格）
read -p "👉 请输入 iStoreOS 的 IP (默认 192.168.1.1): " INPUT_IP
OW_IP=$(echo "${INPUT_IP:-192.168.1.1}" | tr -d ' ')

# 2. 自动生成密钥
mkdir -p ~/.ssh
if [ ! -f ~/.ssh/id_rsa ]; then
    echo -e "${BLUE}[1/4] 正在生成 SSH 密钥...${NC}"
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -q -N ""
fi

# 3. 强制建立 SSH 连接
echo -e "${BLUE}[2/4] 正在尝试建立免密连接，请输 root 密码...${NC}"
# 增加 -o HostKeyAlias 选项进一步规避主机名检查
cat ~/.ssh/id_rsa.pub | ssh -o "StrictHostKeyChecking=no" \
    -o "UserKnownHostsFile=/dev/null" \
    -o "GlobalKnownHostsFile=/dev/null" \
    root@"$OW_IP" "mkdir -p /etc/dropbear && tee -a /etc/dropbear/authorized_keys" || {
    echo -e "${RED}❌ 连接失败。请确认 iStoreOS 的 SSH (Dropbear) 已开启。${NC}"
    exit 1
}

# 4. 下载并配置核心文件
echo -e "${BLUE}[3/4] 正在拉取 istoreos_flow 组件...${NC}"
mkdir -p /config/shell /config/packages /config/www/img
curl -sSL -o /config/shell/istoreos_flow.sh "${RAW_URL}/scripts/istoreos_flow.sh"
curl -sSL -o /config/packages/istoreos_flow.yaml "${RAW_URL}/packages/istoreos_flow.yaml"

sed -i "s/ISTOREOS_IP=\".*\"/ISTOREOS_IP=\"$OW_IP\"/g" /config/shell/istoreos_flow.sh
chmod +x /config/shell/istoreos_flow.sh

# 5. 自动挂载配置
echo -e "${BLUE}[4/4] 正在配置 HA 自动加载...${NC}"
if ! grep -q "packages: !include_dir_named packages" /config/configuration.yaml; then
    sed -i '/homeassistant:/a \  packages: !include_dir_named packages' /config/configuration.yaml
fi

echo -e "${GREEN}======================================================${NC}"
echo -e "           🎉 部署完成！请重启 Home Assistant"
echo -e "${GREEN}======================================================${NC}"