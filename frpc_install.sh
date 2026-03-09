#!/bin/bash

# ==================================================
# FRPC 多客户端稳定版安装脚本 - 优化版
# 特性：自动清理旧服务、配置验证、健康检查
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
echo "║     FRPC 多客户端稳定版安装脚本 - 优化版 (带自动清理)       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ==================== 交互式输入部分 ====================

# 1. SSH 客户端配置
print_step "1/7" "配置 SSH 穿透客户端 (连接 8.141.12.76)"

print_input "请输入 SSH 穿透的远程端口 (例如 14001):"
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

print_input "请输入批量端口的起始端口 (例如 36000):"
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

INSTALL_BASE="/usr/local/frp"
CONFIG_DIR="/etc/frp"
LOG_DIR="/var/log/frp"
SCRIPT_DIR="/usr/local/bin/frp-scripts"

# ==================== 清理旧服务 ====================
print_step "3/7" "清理旧的 FRP 服务"

print_info "停止所有旧服务..."
systemctl stop frpc@vastaictssh.service frpc@vastaictcdn.service 2>/dev/null
systemctl stop frpc-business-monitor 2>/dev/null
systemctl stop frpc-healthcheck-ssh.timer frpc-healthcheck-cdn.timer 2>/dev/null

print_info "禁用所有旧服务..."
systemctl disable frpc@vastaictssh.service frpc@vastaictcdn.service 2>/dev/null
systemctl disable frpc-healthcheck-ssh.timer frpc-healthcheck-cdn.timer 2>/dev/null

print_info "杀死所有 frpc 进程..."
pkill -f frpc
pkill -f vastaictcdn
sleep 2

print_info "删除旧的配置文件..."
rm -rf /etc/frp/vastaict*.toml 2>/dev/null
rm -rf /etc/systemd/system/frpc*.service 2>/dev/null
rm -rf /etc/systemd/system/frpc*.timer 2>/dev/null
rm -rf /usr/local/bin/frp-* 2>/dev/null
rm -rf /var/log/frp/frpc-*.log 2>/dev/null

print_info "清理完成"

# ==================== 检测系统架构并下载 ====================
print_step "4/7" "检测系统架构并下载 FRP"

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

# 创建必要目录
mkdir -p "$INSTALL_BASE" "$CONFIG_DIR" "$LOG_DIR" "$SCRIPT_DIR"

# 下载 FRP
cd /tmp
if [ ! -f "$DOWNLOAD_FILE" ]; then
    print_info "下载 FRP v${FRP_VERSION}..."
    if command -v wget &>/dev/null; then
        wget -q --show-progress "$DOWNLOAD_URL"
    elif command -v curl &>/dev/null; then
        curl -# -L -O "$DOWNLOAD_URL"
    else
        print_error "请安装 wget 或 curl"
        exit 1
    fi
fi

# 解压并安装
print_info "解压并安装 FRPC..."
tar -xzf "$DOWNLOAD_FILE"
cd "frp_${FRP_VERSION}_${OS}_${ARCH_STR}"
cp frpc "$INSTALL_BASE/"
chmod +x "$INSTALL_BASE/frpc"
ln -sf "$INSTALL_BASE/frpc" /usr/local/bin/frpc

# ==================== 生成配置文件 ====================
print_step "5/7" "生成配置文件（使用稳定版配置）"

# SSH 客户端配置 (移除不支持的 maxPoolCount)
cat > "$CONFIG_DIR/vastaictssh.toml" << EOF
# SSH 穿透配置 - 连接到 ${SSH_SERVER}
serverAddr = "${SSH_SERVER}"
serverPort = ${SERVER_PORT}

auth.method = "token"
auth.token = "${AUTH_TOKEN}"

# 日志配置
log.to = "${LOG_DIR}/frpc-ssh.log"
log.level = "info"
log.maxDays = 7

# 连接池配置（只使用支持的字段）
transport.poolCount = 5
transport.heartbeatInterval = 30
transport.heartbeatTimeout = 90

[[proxies]]
name = "ssh_proxy"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = ${SSH_REMOTE_PORT}

# 代理健康检查
healthCheck.type = "tcp"
healthCheck.timeoutSeconds = 3
healthCheck.maxFailed = 3
healthCheck.intervalSeconds = 10
EOF

# CDN 客户端配置
cat > "$CONFIG_DIR/vastaictcdn.toml" << EOF
# 批量端口穿透配置 - 连接到 ${CDN_SERVER}
serverAddr = "${CDN_SERVER}"
serverPort = ${SERVER_PORT}

auth.method = "token"
auth.token = "${AUTH_TOKEN}"

# 日志配置
log.to = "${LOG_DIR}/frpc-cdn.log"
log.level = "info"
log.maxDays = 7

# 连接池配置（只使用支持的字段）
transport.poolCount = 10
transport.heartbeatInterval = 20
transport.heartbeatTimeout = 60
transport.tcpMux = true
transport.protocol = "tcp"

# 批量端口映射
EOF

# 添加批量端口配置
for ((port=START_PORT; port<=END_PORT; port++)); do
    cat >> "$CONFIG_DIR/vastaictcdn.toml" << EOF

[[proxies]]
name = "tcp_${port}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${port}
remotePort = ${port}

# 代理健康检查
healthCheck.type = "tcp"
healthCheck.timeoutSeconds = 3
healthCheck.maxFailed = 3
healthCheck.intervalSeconds = 10
EOF
done

# 验证配置文件
print_info "验证配置文件..."
/usr/local/bin/frpc -c "$CONFIG_DIR/vastaictssh.toml" -v || {
    print_error "SSH 配置文件验证失败"
    exit 1
}
/usr/local/bin/frpc -c "$CONFIG_DIR/vastaictcdn.toml" -v || {
    print_error "CDN 配置文件验证失败"
    exit 1
}
print_info "配置文件验证通过"

# ==================== 创建 Systemd 服务 ====================
print_step "6/7" "创建 Systemd 服务"

# 服务模板（使用稳定版配置）
cat > "/etc/systemd/system/frpc@.service" << 'EOF'
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

# 健康检查脚本
cat > "$SCRIPT_DIR/check-ssh.sh" << 'EOF'
#!/bin/bash
LOG_DIR="/var/log/frp"
if ! pgrep -f "frpc.*vastaictssh" > /dev/null; then
    echo "[$(date)] SSH客户端进程不存在，重启中..." >> "$LOG_DIR/frpc-ssh-health.log"
    systemctl restart frpc@vastaictssh
    exit 1
fi
exit 0
EOF

cat > "$SCRIPT_DIR/check-cdn.sh" << 'EOF'
#!/bin/bash
LOG_DIR="/var/log/frp"
if ! pgrep -f "frpc.*vastaictcdn" > /dev/null; then
    echo "[$(date)] CDN客户端进程不存在，重启中..." >> "$LOG_DIR/frpc-cdn-health.log"
    systemctl restart frpc@vastaictcdn
    exit 1
fi
exit 0
EOF

chmod +x "$SCRIPT_DIR"/*.sh

# 健康检查定时器
cat > "/etc/systemd/system/frpc-healthcheck-ssh.service" << EOF
[Unit]
Description=FRPC SSH Health Check
After=frpc@vastaictssh.service

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/check-ssh.sh
User=root
EOF

cat > "/etc/systemd/system/frpc-healthcheck-cdn.service" << EOF
[Unit]
Description=FRPC CDN Health Check
After=frpc@vastaictcdn.service

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/check-cdn.sh
User=root
EOF

cat > "/etc/systemd/system/frpc-healthcheck-ssh.timer" << EOF
[Unit]
Description=FRPC SSH Health Check Timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=3min

[Install]
WantedBy=timers.target
EOF

cat > "/etc/systemd/system/frpc-healthcheck-cdn.timer" << EOF
[Unit]
Description=FRPC CDN Health Check Timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=3min

[Install]
WantedBy=timers.target
EOF

# 日志轮转
cat > "/etc/logrotate.d/frpc" << EOF
/var/log/frp/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    sharedscripts
    postrotate
        systemctl kill -s HUP frpc@vastaictssh.service 2>/dev/null || true
        systemctl kill -s HUP frpc@vastaictcdn.service 2>/dev/null || true
    endscript
}
EOF

# ==================== 启动服务 ====================
print_step "7/7" "启动服务"

# 重新加载 systemd
systemctl daemon-reload

# 启动服务
print_info "启动 SSH 客户端服务..."
systemctl enable frpc@vastaictssh.service
systemctl start frpc@vastaictssh.service

print_info "启动 CDN 客户端服务..."
systemctl enable frpc@vastaictcdn.service
systemctl start frpc@vastaictcdn.service

print_info "启动健康检查定时器..."
systemctl enable frpc-healthcheck-ssh.timer frpc-healthcheck-cdn.timer
systemctl start frpc-healthcheck-ssh.timer frpc-healthcheck-cdn.timer

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
check_service "frpc-healthcheck-ssh.timer" "SSH 健康检查"
check_service "frpc-healthcheck-cdn.timer" "CDN 健康检查"

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
tail -5 "$LOG_DIR/frpc-ssh.log" 2>/dev/null || echo "SSH 日志暂无输出"
echo "----------------------------------------"
tail -5 "$LOG_DIR/frpc-cdn.log" 2>/dev/null || echo "CDN 日志暂无输出"
echo "----------------------------------------"

# 可选：删除安装脚本
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
