#!/bin/bash
# ==========================================
# iStoreOS-Flow 一键部署脚本
# 作者：https://github.com/Rabbit-Spec
# 版本：1.0.1
# 日期：2026.03.05
# ==========================================

export HOSTNAME="ha-istoreos-flow"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

RAW_URL="https://raw.githubusercontent.com/Rabbit-Spec/iStoreOS_Flow/main"

echo -e "${BLUE}======================================================${NC}"
echo -e "          🚀 iStoreOS-Flow 自动化安装程序"
echo -e "${BLUE}======================================================${NC}"

# 1. 自动预检：检查是否在 HA 终端运行
if [ ! -d "/config" ]; then
    echo -e "${RED}❌ 错误: 未检测到 /config 目录，请确保在 HA Terminal 插件中运行。${NC}"
    exit 1
fi

# 2. 获取 IP
read -p "👉 请输入 iStoreOS 的 IP (回车默认 192.168.1.1): " OW_IP
OW_IP=${OW_IP:-192.168.1.1}

# 3. 自动处理 SSH 密钥
mkdir -p ~/.ssh
if [ ! -f ~/.ssh/id_rsa ]; then
    echo -e "${BLUE}[1/4] 正在自动生成 SSH 秘钥...${NC}"
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -q -N ""
fi

# 4. 自动化推送 (增加备用连接选项以提升成功率)
echo -e "${BLUE}[2/4] 正在尝试建立免密连接，请输 root 密码...${NC}"
# 使用 -o 选项进一步屏蔽主机名干扰
cat ~/.ssh/id_rsa.pub | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$OW_IP" "mkdir -p /etc/dropbear && tee -a /etc/dropbear/authorized_keys" || {
    echo -e "${RED}❌ 连接失败，请检查 iStoreOS 是否开启了 SSH 访问。${NC}"
    exit 1
}

# 5. 自动化下载与配置
echo -e "${BLUE}[3/4] 正在拉取组件并注入配置...${NC}"
mkdir -p /config/shell /config/packages /config/www/img
curl -sSL -o /config/shell/istoreos_flow.sh "${RAW_URL}/scripts/istoreos_flow.sh"
curl -sSL -o /config/packages/istoreos_flow.yaml "${RAW_URL}/packages/istoreos_flow.yaml"

# 自动替换脚本内的 IP
sed -i "s/ISTOREOS_IP=\".*\"/ISTOREOS_IP=\"$OW_IP\"/g" /config/shell/istoreos_flow.sh
chmod +x /config/shell/istoreos_flow.sh

# 6. 自动化挂载配置
echo -e "${BLUE}[4/4] 正在检查 HA 挂载状态...${NC}"
if ! grep -q "packages: !include_dir_named packages" /config/configuration.yaml; then
    if grep -q "homeassistant:" /config/configuration.yaml; then
        sed -i '/homeassistant:/a \  packages: !include_dir_named packages' /config/configuration.yaml
    else
        echo -e "homeassistant:\n  packages: !include_dir_named packages\n$(cat /config/configuration.yaml)" > /config/configuration.yaml
    fi
fi

echo -e "${GREEN}======================================================${NC}"
echo -e "           🎉 自动化部署任务已完成！"
echo -e "${GREEN}======================================================${NC}"
echo -e "请在 HA 开发者工具中点击【重新启动】即可点亮仪表盘。"