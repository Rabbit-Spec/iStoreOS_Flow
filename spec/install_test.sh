#!/bin/bash
# ==========================================
# iStoreOS-Flow 一键部署脚本 (全自动防玄学 Bug 版)
# 作者：https://github.com/Rabbit-Spec
# ==========================================

set -e 

# --- 颜色与日志函数 ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'  
RED='\033[0;31m'
NC='\033[0m'         

RAW_URL="https://raw.githubusercontent.com/Rabbit-Spec/iStoreOS_Flow/main"

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo -e "${BLUE}======================================================${NC}"
echo -e "          🚀 iStoreOS-Flow 终极自动化部署"
echo -e "${BLUE}======================================================${NC}"

# 1. 主机名修复
CURRENT_HOSTNAME=$(hostname)
if [[ "$CURRENT_HOSTNAME" == *"_"* ]]; then
    ha host options --hostname "ha-istoreos-flow" > /dev/null 2>&1 || true
    export HOSTNAME="ha-istoreos-flow"
fi

# 2. 获取 IP
INPUT_IP=""
echo -e "${YELLOW}👉 请输入 iStoreOS 的 IP (直接回车默认 192.168.1.1): ${NC}"
read INPUT_IP </dev/tty || true
OW_IP=$(echo "$INPUT_IP" | tr -d '\r\n ')
if [ -z "$OW_IP" ]; then
    OW_IP="192.168.1.1"
fi
success "目标路由 IP 锁定为: $OW_IP"

# 3. 自动生成与推送 SSH 密钥
log "正在配置底层免密通道..."
mkdir -p ~/.ssh
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -q -N ""
fi

warn "即将连接，请根据提示输入 iStoreOS 的 root 密码..."
cat ~/.ssh/id_rsa.pub | ssh -o "StrictHostKeyChecking=no" \
    -o "UserKnownHostsFile=/dev/null" \
    -o "GlobalKnownHostsFile=/dev/null" \
    root@"$OW_IP" "mkdir -p /etc/dropbear && tee -a /etc/dropbear/authorized_keys" || {
    error "免密通道打通失败！请确认 IP 正确且 SSH 已开启。"
    exit 1
}

# 4. 下载核心组件
log "正在拉取在线核心组件..."
mkdir -p /config/shell /config/packages /config/www/img

curl -sSL --connect-timeout 10 --retry 3 -o /config/shell/istoreos_flow.sh "${RAW_URL}/scripts/istoreos_flow.sh"
curl -sSL --connect-timeout 10 --retry 3 -o /config/packages/istoreos_flow.yaml "${RAW_URL}/packages/istoreos_flow.yaml"
curl -sSL --connect-timeout 15 --retry 3 -o /config/www/img/istoreos_flow.jpg "${RAW_URL}/img/istoreos_flow.jpg" 2>/dev/null || true

sed -i "s/ISTOREOS_IP=\".*\"/ISTOREOS_IP=\"$OW_IP\"/g" /config/shell/istoreos_flow.sh
chmod +x /config/shell/istoreos_flow.sh
success "核心组件下载并配置完毕。"

# 5. HACS 检查
if [ ! -d "/config/custom_components/hacs" ]; then
    warn "未检测到 HACS，请确保稍后手动安装。"
fi

# ==========================================
# 核心自动化修复区：解决未知动作 Bug
# ==========================================
CONFIG_FILE="/config/configuration.yaml"
PACKAGE_FILE="/config/packages/istoreos_flow.yaml"

# 6. 从 Package 中安全剥离 shell_command (防止 HA 底层冲突)
log "正在优化指令层级，防止动作未注册 Bug..."
if grep -q "shell_command:" "$PACKAGE_FILE"; then
    # 删除 packages 里的 shell_command 及下面包含 istoreos_flow.sh 的行
    sed -i '/^shell_command:/,/istoreos_flow\.sh/d' "$PACKAGE_FILE" 2>/dev/null || true
fi

# 7. 强制将 shell_command 注入主 configuration.yaml
sed -i -e '$a\' "$CONFIG_FILE" 2>/dev/null || echo "" >> "$CONFIG_FILE"

if ! grep -q "update_istoreos_flow" "$CONFIG_FILE"; then
    if grep -q "^shell_command:" "$CONFIG_FILE"; then
        # 如果系统已有 shell_command 根节点，直接追加两行
        sed -i '/^shell_command:/a \ \ update_istoreos_flow: "bash /config/shell/istoreos_flow.sh fetch"\n  reboot_istoreos_flow: "bash /config/shell/istoreos_flow.sh reboot"' "$CONFIG_FILE"
    else
        # 如果没有，创建根节点并写入
        echo -e "\nshell_command:\n  update_istoreos_flow: \"bash /config/shell/istoreos_flow.sh fetch\"\n  reboot_istoreos_flow: \"bash /config/shell/istoreos_flow.sh reboot\"\n" >> "$CONFIG_FILE"
    fi
    success "系统级 Shell Command 注册成功！"
fi

# 8. Packages 挂载注入
log "正在安全挂载 Packages 目录..."
if ! grep -q "packages:.*!include_dir_named" "$CONFIG_FILE"; then
    if grep -q "^homeassistant:" "$CONFIG_FILE"; then
        sed -i '/^homeassistant:/a \ \ packages: !include_dir_named packages' "$CONFIG_FILE"
    else
        echo -e "\nhomeassistant:\n  packages: !include_dir_named packages\n" >> "$CONFIG_FILE"
    fi
    success "Packages 挂载成功！"
else
    success "Packages 已配置，跳过。"
fi

echo -e "${GREEN}======================================================${NC}"
echo -e "             🎉 ${YELLOW}iStoreOS-Flow 部署成功！${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "${YELLOW}📌 终极一步：${NC}"
echo -e "   请前往 HA 的 ${BLUE}开发者工具 -> YAML 配置 -> 重新启动${NC}"
echo -e "   (彻底重启后，数据面板将直接点亮！)"
echo -e "${GREEN}======================================================${NC}"
