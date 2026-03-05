#!/bin/bash
# ==========================================
# iStoreOS-Flow 一键部署脚本
# 作者：https://github.com/Rabbit-Spec
# 版本：1.0.7
# 日期：2026.03.06
# ==========================================

set -e 

# --- 颜色定义 ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'  
RED='\033[0;31m'
NC='\033[0m'         

# 定义基础 URL
RAW_URL="https://raw.githubusercontent.com/Rabbit-Spec/iStoreOS_Flow/main"

# --- 封装日志函数 ---
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- 脚本逻辑 ---
echo -e "${BLUE}======================================================${NC}"
echo -e "          🚀 欢迎使用 iStoreOS-Flow 部署向导"
echo -e "${BLUE}======================================================${NC}"

# 1. 自动修复 HA 主机名非法字符问题
CURRENT_HOSTNAME=$(hostname)
if [[ "$CURRENT_HOSTNAME" == *"_"* ]]; then
    warn "检测到非法主机名: $CURRENT_HOSTNAME，可能导致 SSH 连接失败。"
    log "正在自动将 HA 系统主机名修正为 'ha-istoreos-flow'..."
    ha host options --hostname "ha-istoreos-flow" > /dev/null 2>&1 || true
    export HOSTNAME="ha-istoreos-flow"
    success "主机名环境已修正。"
fi

# 2. 防管道劫持获取 IP
INPUT_IP=""
echo -e "${YELLOW}👉 步骤 1/5: 请输入 iStoreOS 的 IP (直接回车默认 192.168.1.1): ${NC}"
read INPUT_IP </dev/tty || true
OW_IP=$(echo "$INPUT_IP" | tr -d '\r\n ')
if [ -z "$OW_IP" ]; then
    OW_IP="192.168.1.1"
fi
success "目标路由 IP 锁定为: $OW_IP"

# 3. 自动生成与推送 SSH 密钥
log "正在配置底层免密通道 (持久化路径)..."
# 统一使用 /config/.ssh 目录
mkdir -p /config/.ssh
chmod 700 /config/.ssh

if [ ! -f /config/.ssh/id_rsa ]; then
    log "生成新的 SSH 密钥..."
    ssh-keygen -t rsa -b 2048 -f /config/.ssh/id_rsa -q -N ""
fi

# 核心：必须确保私钥权限为 600，否则 SSH 会报错
chmod 600 /config/.ssh/id_rsa
success "本地密钥就绪。"

warn "即将连接路由器，请根据提示输入 iStoreOS 的 root 密码..."
# 使用新路径下的公钥进行推送
cat /config/.ssh/id_rsa.pub | ssh -o "StrictHostKeyChecking=no" \
    -o "UserKnownHostsFile=/dev/null" \
    root@"$OW_IP" "mkdir -p /etc/dropbear && tee -a /etc/dropbear/authorized_keys" || {
    error "免密连接失败！"
    exit 1
}
success "SSH 免密登录配置完成！"

# 4. 创建目录并下载文件
log "步骤 3/5: 正在拉取在线核心组件..."
mkdir -p /config/shell /config/packages /config/www/img || {
    error "创建目录失败！请检查 Home Assistant 的系统权限。"
    exit 1
}

curl -sSL --connect-timeout 10 --retry 3 -o /config/shell/istoreos_flow.sh "${RAW_URL}/scripts/istoreos_flow.sh" || {
    error "下载 istoreos_flow.sh 失败！"
    exit 1
}

curl -sSL --connect-timeout 10 --retry 3 -o /config/packages/istoreos_flow.yaml "${RAW_URL}/packages/istoreos_flow.yaml" || {
    error "下载 istoreos_flow.yaml 失败！"
    exit 1
}

curl -sSL --connect-timeout 15 --retry 3 -o /config/www/img/istoreos_flow.jpg "${RAW_URL}/img/istoreos_flow.jpg" 2>/dev/null || warn "封面图下载失败，请稍后手动上传。"

# 自动注入 IP 至脚本
sed -i "s/ISTOREOS_IP=\".*\"/ISTOREOS_IP=\"$OW_IP\"/g" /config/shell/istoreos_flow.sh
success "核心组件下载并配置完毕。"

# 5. 设置权限
log "正在配置脚本执行权限..."
chmod +x /config/shell/istoreos_flow.sh || {
    error "赋予执行权限失败！"
    exit 1
}

# 6. HACS 环境检查
log "步骤 4/5: 正在检查 HACS 环境..."
if [ ! -d "/config/custom_components/hacs" ]; then
    warn "未在 /config/custom_components 中检测到 HACS。"
    warn "请确保稍后手动安装 HACS，否则无法下载所需的前端卡片。"
else
    success "检测到 HACS 已安装。"
fi

# 7. YAML 安全注入配置
log "步骤 5/5: 正在安全注入系统配置..."
CONFIG_FILE="/config/configuration.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
    error "找不到系统核心配置文件: $CONFIG_FILE！"
    exit 1
fi

# 防粘连补丁：确保文件末尾有换行符
sed -i -e '$a\' "$CONFIG_FILE" 2>/dev/null || echo "" >> "$CONFIG_FILE"

if ! grep -q "packages:.*!include_dir_named" "$CONFIG_FILE"; then
    warn "检测到尚未挂载 Packages，正在执行自动注入..."
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak" || warn "无法创建备份，将继续强制注入。"
    
    if grep -q "^homeassistant:" "$CONFIG_FILE"; then
        sed -i '/^homeassistant:/a \ \ packages: !include_dir_named packages' "$CONFIG_FILE" || {
            error "sed 注入失败！"
            exit 1
        }
        success "已成功将 Packages 挂载至现有 homeassistant 节点。"
    else
        echo -e "\nhomeassistant:\n  packages: !include_dir_named packages\n" >> "$CONFIG_FILE" || {
            error "echo 写入失败！"
            exit 1
        }
        success "已自动创建 homeassistant 节点并完成挂载。"
    fi
else
    success "检测到 Packages 已配置，跳过注入步骤。"
fi

# --- 结束提示 ---
echo -e "${GREEN}======================================================${NC}"
echo -e "             🎉 ${YELLOW}iStoreOS-Flow 部署成功！${NC}"
echo -e ""
echo -e "        🧑‍💻  作者: ${BLUE}https://github.com/Rabbit-Spec${NC}"
echo -e "        🏷️  版本: ${BLUE}v1.0.0${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "${YELLOW}📌 后续操作指南：${NC}\n"

echo -e " ${YELLOW}[1]${NC} 检查 HACS 依赖插件"
echo -e "     请确保在 HACS 前端界面搜索并下载了以下插件:"
echo -e "     ├─ ${GREEN}Mushroom${NC}"
echo -e "     ├─ ${GREEN}Mini-Graph-Card${NC}"
echo -e "     └─ ${GREEN}Card-mod${NC}\n"

echo -e " ${YELLOW}[2]${NC} ${RED}彻底重启系统${NC}"
echo -e "     前往 HA 的 ${BLUE}开发者工具 -> YAML 配置 -> 重新启动${NC}\n"

echo -e " ${YELLOW}[3]${NC} 导入高颜值仪表盘"
echo -e "     新建仪表盘 -> 切换至代码编辑器模式 -> 粘贴以下链接中的全部内容:"
echo -e "     └─ ${BLUE}https://raw.githubusercontent.com/Rabbit-Spec/iStoreOS_Flow/main/dashboards/dashboard.yaml${NC}\n"

echo -e " ${YELLOW}💡 技术提示：${NC}"
echo -e "     您的 iStoreOS IP (${OW_IP}) 已被全自动注入脚本，无需任何手动修改！"
echo -e "${GREEN}======================================================${NC}"