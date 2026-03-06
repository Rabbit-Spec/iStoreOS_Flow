#!/bin/bash
# ==========================================
# iStoreOS-Flow 一键部署脚本
# 作者：https://github.com/Rabbit-Spec
# 版本：1.2.4
# 日期：2026.03.06
# ==========================================

set -e 

# --- 颜色定义 ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'  
RED='\033[0;31m'
NC='\033[0m'         

# 定义基础 URL 及防缓存变量
RAW_URL="https://raw.githubusercontent.com/Rabbit-Spec/iStoreOS_Flow/main"
T=$(date +%s)

# --- 封装日志函数 ---
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- 脚本逻辑 ---
echo -e "${BLUE}======================================================${NC}"
echo -e "          🚀 欢迎使用 iStoreOS-Flow 部署向导"
echo -e "                🏷️  版本: v1.2.4"
echo -e "${BLUE}======================================================${NC}"

# 1. 自动修复 HA 主机名
log "正在检测系统环境稳定性..."
CURRENT_HOSTNAME=$(hostname)
if [[ "$CURRENT_HOSTNAME" == *"_"* ]]; then
    warn "检测到非法主机名: $CURRENT_HOSTNAME，可能导致 SSH 连接失败。"
    log "正在自动执行系统调用修复主机名为 'ha-istoreos-flow'..."
    ha host options --hostname "ha-istoreos-flow" > /dev/null 2>&1 || true
    export HOSTNAME="ha-istoreos-flow"
    success "系统主机名环境修正完成。"
else
    success "系统主机名环境正常，无需修复。"
fi

# 2. IP 获取
INPUT_IP=""
echo -e "${YELLOW}👉 步骤 1/5: 请输入 iStoreOS 的 IP (直接回车默认 192.168.1.1): ${NC}"
read INPUT_IP </tty || read INPUT_IP </dev/tty || true
OW_IP=$(echo "$INPUT_IP" | tr -d '\r\n ')
if [ -z "$OW_IP" ]; then
    OW_IP="192.168.1.1"
fi
success "目标路由 IP 已锁定为: $OW_IP"

# 3. SSH 密钥配置
log "步骤 2/5: 开始配置底层加密免密通道..."
mkdir -p /config/.ssh
chmod 700 /config/.ssh
log "已确保持久化目录 /config/.ssh 权限正确。"

if [ ! -f /config/.ssh/id_rsa ]; then
    log "正在调用 OpenSSH 生成 2048 位 RSA 密钥对..."
    ssh-keygen -t rsa -b 2048 -f /config/.ssh/id_rsa -q -N ""
    success "新密钥对生成成功。"
else
    success "检测到本地已有密钥对，跳过重复生成步骤。"
fi
chmod 600 /config/.ssh/id_rsa

log "正在执行预检：测试与 $OW_IP 的免密连通性..."
if ssh -o "BatchMode=yes" -o "ConnectTimeout=3" -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -i /config/.ssh/id_rsa root@"$OW_IP" "exit" >/dev/null 2>&1; then
    success "检测到双机已建立免密授权，跳过密钥推送流程。"
else
    warn "未检测到授权，即将尝试将公钥推送至路由设备..."
    warn "请在下方提示处输入 iStoreOS 的 root 密码并回车:"
    cat /config/.ssh/id_rsa.pub | ssh -o "StrictHostKeyChecking=no" \
        -o "UserKnownHostsFile=/dev/null" \
        root@"$OW_IP" "mkdir -p /etc/dropbear && awk '!a[\$0]++' /etc/dropbear/authorized_keys > /tmp/ak.tmp 2>/dev/null; mv /tmp/ak.tmp /etc/dropbear/authorized_keys 2>/dev/null; tee -a /etc/dropbear/authorized_keys" || {
        error "无法通过 SSH 建立授权！请检查密码是否正确。步骤中断。"
        exit 1
    }
    success "SSH 公钥已成功写入路由器的授权清单。"
fi

# 4. 下载文件
# 💡 这里增加了明确的步骤日志，确保你知道脚本运行到了哪里
log "步骤 3/5: 开始拉取 iStoreOS-Flow 核心组件..."

log "正在初始化本地目录结构..."
mkdir -p /config/shell /config/packages /config/www/img
success "目录结构准备就绪。"

# 详细文件下载日志 (增加 v=$T 防缓存)
log "正在下载数据采集脚本 (istoreos_flow.sh)..."
curl -sSL --connect-timeout 15 --retry 3 -o /config/shell/istoreos_flow.sh "${RAW_URL}/scripts/istoreos_flow.sh?v=$T" || {
    error "下载 istoreos_flow.sh 失败！请检查网络。"
    exit 1
}
success "istoreos_flow.sh 下载成功。"

log "正在下载传感器定义文件 (istoreos_flow.yaml)..."
curl -sSL --connect-timeout 15 --retry 3 -o /config/packages/istoreos_flow.yaml "${RAW_URL}/packages/istoreos_flow.yaml?v=$T" || {
    error "下载 istoreos_flow.yaml 失败！"
    exit 1
}
success "istoreos_flow.yaml 下载成功。"

log "正在下载仪表盘背景图 (istoreos_flow.jpg)..."
curl -sSL --connect-timeout 20 --retry 5 -o /config/www/img/istoreos_flow.jpg "${RAW_URL}/img/istoreos_flow.jpg?v=$T" || {
    error "背景图下载失败！"
    exit 1
}
success "istoreos_flow.jpg 下载成功。"

log "正在执行 IP 地址动态注入..."
sed -i "s/ISTOREOS_IP=\".*\"/ISTOREOS_IP=\"$OW_IP\"/g" /config/shell/istoreos_flow.sh
success "已将目标 IP $OW_IP 硬编码至本地采集脚本。"

# 5. 权限配置
log "正在配置脚本内核可执行位 (chmod +x)..."
chmod +x /config/shell/istoreos_flow.sh
success "采集脚本执行权限配置完毕。"

# 6. HACS 检查
log "步骤 4/5: 环境依赖项深度扫描..."
if [ ! -d "/config/custom_components/hacs" ]; then
    warn "警告：未检测到 HACS 组件，请务必手动安装以确保前端卡片正常工作。"
else
    success "检测到 HACS 环境已就绪。"
fi

# 7. YAML 注入
log "步骤 5/5: 正在将 iStoreOS-Flow 模块挂载至系统核心..."
CONFIG_FILE="/config/configuration.yaml"

# 防粘连处理
sed -i -e '$a\' "$CONFIG_FILE" 2>/dev/null || echo "" >> "$CONFIG_FILE"
log "已完成 configuration.yaml 尾部空白符修正。"

if ! grep -q "packages:.*!include_dir_named" "$CONFIG_FILE"; then
    log "检测到 Packages 尚未启用，准备执行安全备份..."
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak" && success "已创建备份副本: ${CONFIG_FILE}.bak"
    
    log "正在分析 YAML 树状结构并注入挂载指令..."
    if grep -q "^homeassistant:" "$CONFIG_FILE"; then
        sed -i '/^homeassistant:/a \ \ packages: !include_dir_named packages' "$CONFIG_FILE"
        success "已成功将 Packages 挂载至 homeassistant 节点下。"
    else
        echo -e "\nhomeassistant:\n  packages: !include_dir_named packages\n" >> "$CONFIG_FILE"
        success "已自动补全 homeassistant 根节点并完成挂载。"
    fi
else
    success "系统 Packages 挂载点已存在，跳过注入逻辑。"
fi

# --- 结束提示 ---
echo -e "${GREEN}======================================================${NC}"
echo -e "             🎉 ${YELLOW}iStoreOS-Flow 部署成功！${NC}"
echo -e ""
echo -e "        🧑‍💻  作者: ${BLUE}https://github.com/Rabbit-Spec${NC}"
echo -e "        🏷️  版本: ${BLUE}v1.2.4${NC}"
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