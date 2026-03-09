#!/bin/bash

# ==================================================
# FRPC 多客户端安装脚本 - 自动检测版
# 特性：自动检测 frpc 是否存在，不存在则下载安装
# ==================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 打印函数
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_input() { echo -e "${BLUE}[INPUT]${NC} $1"; }
print_step() { echo -e "${CYAN}[STEP $1]${NC} $2"; }

# 清屏
clear
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     FRPC 多客户端安装脚本 - 自动检测版                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ==================== 交互式输入部分 ====================

# 1. SSH 客户端配置
print_step "1/7" "配置 SSH 穿透客户端 (连接 8.141.12.76)"

print_input "请输入 SSH 穿透的远程端口 (例如 15002):"
while true; do
    read -p "> " SSH_REMOTE_PORT
    if [[ "$SSH_REMOTE_PORT" =~ ^[0-9]+$ ]] && [ "$SSH_REMOTE_PORT" -ge 1 ] && [ "$SSH_REMOTE_PORT" -le 65535 ]; then
        break
    else
        print_error "请输入有效的端口号 (1-65535)"
    fi
done

# 2. 批量端口客户端配置
print_step "2/7" "配置批量端口穿透客户端 (连接 209.146.116.106)"

print_input "请输入批量端口的起始端口 (例如 46200):"
while true; do
    read -p "> " START_PORT
    if [[ "$START_PORT" =~ ^[0-9]+$ ]] && [ "$START_PORT" -ge 1 ] && [ "$START_PORT" -le 65535 ]; then
        break
    else
        print_error "请输入有效的起始端口 (1-65535)"
    fi
done

print_input "请输入批量端口的结束端口 (必须 >= $START_PORT):"
while true; do
    read -p "> " END_PORT
    if [[ "$END_PORT" =~ ^[0-9]+$ ]] && [ "$END_PORT" -ge "$START_PORT" ] && [ "$END_PORT" -le 65535 ]; then
        break
    else
        print_error "请输入有效的结束端口，且必须大于等于 $START_PORT"
    fi
done

PORT_COUNT=$((END_PORT - START_PORT + 1))
print_info "将配置 $PORT_COUNT 个端口映射 (${START_PORT}-${END_PORT})"

# 3. 确认配置
echo ""
print_warn "请确认以下配置信息："
echo "----------------------------------------"
echo "SSH 客户端："
echo "  - 服务器: 8.141.12.76:7000"
echo "  - SSH远程端口: $SSH_REMOTE_PORT"
echo ""
echo "批量端口客户端："
echo "  - 服务器: 209.146.116.106:7000"
echo "  - 端口范围: $START_PORT - $END_PORT (共 $PORT_COUNT 个端口)"
echo "----------------------------------------"
echo ""

print_input "确认无误？(y/n): "
read -p "> " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    print_warn "安装已取消"
    exit 0
fi

# ==================== 固定配置 ====================
FRP_VERSION="0.61.0"
DOWNLOAD_BASE_URL="https://github.com/fatedier/frp/releases/download"
AUTH_TOKEN="qazwsx123.0"
SERVER_PORT="7000"

SSH_SERVER="8.141.12.76"
CDN_SERVER="209.146.116.106"

CONFIG_DIR="/etc/frp"
LOG_DIR="/var/log/frp"
FRPC_PATH="/usr/local/bin/frpc"

# ==================== 检查并安装 frpc ====================
print_step "3/7" "检查 frpc 环境"

# 检查 frpc 是否存在
if [ ! -f "$FRPC_PATH" ]; then
    print_warn "未找到 frpc，开始下载安装..."
    
    # 检测系统架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH_STR="amd64" ;;
        aarch64) ARCH_STR="arm64" ;;
        armv7l) ARCH_STR="arm" ;;
        *) print_error "不支持的架构: $ARCH"; exit 1 ;;
    esac
    
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    DOWNLOAD_FILE="frp_${FRP_VERSION}_${OS}_${ARCH_STR}.tar.gz"
    DOWNLOAD_URL="${DOWNLOAD_BASE_URL}/v${FRP_VERSION}/${DOWNLOAD_FILE}"
    
    print_info "系统架构: ${ARCH_STR}, 操作系统: ${OS}"
    print_info "下载地址: ${DOWNLOAD_URL}"
    
    # 创建临时目录
    cd /tmp
    
    # 下载
    if command -v wget &>/dev/null; then
        wget -q --show-progress "$DOWNLOAD_URL"
    elif command -v curl &>/dev/null; then
        curl -# -L -O "$DOWNLOAD_URL"
    else
        print_error "请安装 wget 或 curl"
        exit 1
    fi
    
    # 解压并安装
    print_info "解压并安装 frpc..."
    tar -xzf "$DOWNLOAD_FILE"
    cd "frp_${FRP_VERSION}_${OS}_${ARCH_STR}"
    sudo cp frpc "$FRPC_PATH"
    sudo chmod +x "$FRPC_PATH"
    
    # 清理临时文件
    cd /tmp
    rm -rf "frp_${FRP_VERSION}_${OS}_${ARCH_STR}" "$DOWNLOAD_FILE"
    
    print_info "frpc 安装完成"
else
    print_info "frpc 已存在: $FRPC_PATH"
    # 显示版本
    $FRPC_PATH --version
fi

# ==================== 清理旧服务 ====================
print_step "4/7" "清理旧的 FRP 服务"

print_info "停止所有旧服务..."
sudo systemctl stop frpc@vastaictssh.service frpc@vastaictcdn.service 2>/dev/null
sudo pkill -f frpc 2>/dev/null
sleep 2

print_info "删除旧的配置文件..."
sudo rm -rf $CONFIG_DIR/vastaict*.toml 2>/dev/null
sudo rm -rf /etc/systemd/system/frpc*.service 2>/dev/null
sudo rm -rf /etc/systemd/system/frpc*.timer 2>/dev/null

# ==================== 创建配置目录 ====================
print_step "5/7" "创建配置目录"

sudo mkdir -p $CONFIG_DIR $LOG_DIR
print_info "目录创建完成"

# ==================== 生成配置文件 ====================
print_step "6/7" "生成配置文件"

# SSH 客户端配置
print_info "创建 SSH 配置文件..."
sudo tee $CONFIG_DIR/vastaictssh.toml > /dev/null << EOF
serverAddr = "${SSH_SERVER}"
serverPort = ${SERVER_PORT}
auth.method = "token"
auth.token = "${AUTH_TOKEN}"
log.to = "${LOG_DIR}/frpc-ssh.log"
log.level = "info"

[[proxies]]
name = "ssh_proxy"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = ${SSH_REMOTE_PORT}
EOF

# CDN 客户端配置（基础部分）
print_info "创建 CDN 配置文件..."
sudo tee $CONFIG_DIR/vastaictcdn.toml > /dev/null << EOF
serverAddr = "${CDN_SERVER}"
serverPort = ${SERVER_PORT}
auth.method = "token"
auth.token = "${AUTH_TOKEN}"
log.to = "${LOG_DIR}/frpc-cdn.log"
log.level = "info"
transport.tcpMux = true
EOF

# 添加批量端口
print_info "添加 $PORT_COUNT 个端口映射..."
for port in $(seq $START_PORT $END_PORT); do
    sudo tee -a $CONFIG_DIR/vastaictcdn.toml > /dev/null << EOF

[[proxies]]
name = "tcp_${port}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${port}
remotePort = ${port}
EOF
done

# 验证配置文件
print_info "验证配置文件..."
$FRPC_PATH -c $CONFIG_DIR/vastaictssh.toml -v
if [ $? -ne 0 ]; then
    print_error "SSH 配置文件验证失败"
    exit 1
fi

$FRPC_PATH -c $CONFIG_DIR/vastaictcdn.toml -v
if [ $? -ne 0 ]; then
    print_error "CDN 配置文件验证失败"
    exit 1
fi
print_info "配置文件验证通过"

# ==================== 创建 Systemd 服务 ====================
print_info "创建 systemd 服务文件..."

sudo tee /etc/systemd/system/frpc@.service > /dev/null << 'EOF'
[Unit]
Description=FRPC Client for %I
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/frpc -c /etc/frp/%i.toml
Restart=always
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# ==================== 启动服务 ====================
print_step "7/7" "启动服务"

sudo systemctl daemon-reload
sudo systemctl enable frpc@vastaictssh.service frpc@vastaictcdn.service
sudo systemctl start frpc@vastaictssh.service frpc@vastaictcdn.service

# 等待服务启动
sleep 3

# ==================== 检查服务状态 ====================
echo ""
print_info "服务状态检查"
echo "----------------------------------------"

check_service() {
    if systemctl is-active --quiet "$1"; then
        echo -e "  ${GREEN}✓${NC} $2: 运行中"
        return 0
    else
        echo -e "  ${RED}✗${NC} $2: 未运行"
        return 1
    fi
}

check_service "frpc@vastaictssh.service" "SSH 客户端"
check_service "frpc@vastaictcdn.service" "CDN 客户端"

echo "----------------------------------------"

# 显示配置信息
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   安装完成！                                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "配置文件位置："
echo "  SSH 客户端: ${GREEN}$CONFIG_DIR/vastaictssh.toml${NC}"
echo "  CDN 客户端: ${GREEN}$CONFIG_DIR/vastaictcdn.toml${NC}"
echo ""
echo "日志文件位置："
echo "  SSH 日志: ${YELLOW}$LOG_DIR/frpc-ssh.log${NC}"
echo "  CDN 日志: ${YELLOW}$LOG_DIR/frpc-cdn.log${NC}"
echo ""
echo "管理命令："
echo "  ${CYAN}systemctl status frpc@vastaictssh${NC}"
echo "  ${CYAN}systemctl status frpc@vastaictcdn${NC}"
echo "  ${CYAN}tail -f $LOG_DIR/frpc-ssh.log${NC}"
echo "  ${CYAN}tail -f $LOG_DIR/frpc-cdn.log${NC}"
echo ""
echo "配置的端口映射："
echo "  SSH 远程端口: ${GREEN}$SSH_REMOTE_PORT${NC}"
echo "  批量端口范围: ${GREEN}$START_PORT - $END_PORT${NC} (共 $PORT_COUNT 个端口)"
echo ""

# 查看初始日志
print_info "查看初始日志输出："
echo "----------------------------------------"
sudo tail -5 "$LOG_DIR/frpc-ssh.log" 2>/dev/null || echo "SSH 日志暂无输出"
echo "----------------------------------------"
sudo tail -5 "$LOG_DIR/frpc-cdn.log" 2>/dev/null || echo "CDN 日志暂无输出"
echo "----------------------------------------"

# ==================== 可选：删除安装脚本 ====================
SCRIPT_PATH="$(realpath "$0" 2>/dev/null)"
if [ -f "$SCRIPT_PATH" ] && [ "$SCRIPT_PATH" != "/bin/bash" ] && [ "$SCRIPT_PATH" != "/usr/bin/bash" ]; then
    echo ""
    print_input "是否删除安装脚本自身？(y/n): "
    read -p "> " DELETE_SCRIPT
    if [[ "$DELETE_SCRIPT" =~ ^[Yy]$ ]]; then
        rm -f "$SCRIPT_PATH" 2>/dev/null
        print_info "安装脚本已删除"
    fi
fi

print_info "脚本执行完毕！"
