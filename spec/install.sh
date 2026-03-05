#!/bin/bash
# ==========================================
# iStoreOS-Flow 一键部署脚本
# 作者：https://github.com/Rabbit-Spec
# 版本：1.0.0
# 日期：2026.03.05
# ==========================================

set -e
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# 指向你的新仓库地址
RAW_URL="https://raw.githubusercontent.com/Rabbit-Spec/iStoreOS_Flow/main"

echo -e "${BLUE}======================================================${NC}"
echo -e "          🚀 欢迎使用 iStoreOS-Flow 部署向导"
echo -e "${BLUE}======================================================${NC}"

# 1. 获取 IP
read -p "👉 请输入您的 iStoreOS 路由器 IP: " OW_IP
if [ -z "$OW_IP" ]; then echo -e "${RED}错误: IP 不能为空${NC}"; exit 1; fi

# 2. SSH 免密设置
mkdir -p ~/.ssh
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -q -N ""
fi
echo -e "${BLUE}正在推送密钥，请根据提示输入 iStoreOS 的 root 密码...${NC}"
cat ~/.ssh/id_rsa.pub | ssh -o StrictHostKeyChecking=no root@"$OW_IP" "mkdir -p /etc/dropbear && tee -a /etc/dropbear/authorized_keys"

# 3. 下载文件
echo -e "${BLUE}正在下载 iStoreOS 专属组件...${NC}"
mkdir -p /config/shell /config/packages /config/www/img
curl -sSL -o /config/shell/istoreos_flow.sh "${RAW_URL}/scripts/istoreos_flow.sh"
curl -sSL -o /config/packages/istoreos_flow.yaml "${RAW_URL}/packages/istoreos_flow.yaml"
curl -sSL -o /config/www/img/istoreos_flow.jpg "${RAW_URL}/img/openwrt_flow.jpg"

# 4. 自动配置
sed -i "s/ISTOREOS_IP=\".*\"/ISTOREOS_IP=\"$OW_IP\"/g" /config/shell/istoreos_flow.sh
chmod +x /config/shell/istoreos_flow.sh

# 5. 挂载 Packages
if ! grep -q "packages: !include_dir_named packages" /config/configuration.yaml; then
    echo -e "${BLUE}正在 configuration.yaml 中注入 packages 配置...${NC}"
    if grep -q "homeassistant:" /config/configuration.yaml; then
        sed -i '/homeassistant:/a \  packages: !include_dir_named packages' /config/configuration.yaml
    else
        echo -e "homeassistant:\n  packages: !include_dir_named packages\n$(cat /config/configuration.yaml)" > /config/configuration.yaml
    fi
fi

echo -e "${GREEN}======================================================${NC}"
echo -e "           🎉 iStoreOS-Flow 部署成功！"
echo -e "${GREEN}======================================================${NC}"