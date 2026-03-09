#!/bin/bash

# ==================================================
# FRPC 多客户端稳定版安装脚本 - 互动式配置
# 特性：健康检查、自动重启、日志轮转、防掉线
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
echo "║         FRPC 多客户端稳定版安装脚本 - Axis AI Edition        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ==================== 交互式输入部分 ====================

# 1. SSH 客户端配置
print_step "1/6" "配置 SSH 穿透客户端 (连接 8.141.12.76)"

print_input "请输入 SSH 穿透的远程端口 (例如 15001):"
while true; do
    read -p "> " SSH_REMOTE_PORT
    if [[ "$SSH_REMOTE_PORT" =~ ^[0-9]+$ ]] && [ "$SSH_REMOTE_PORT" -ge 1 ] && [ "$SSH_REMOTE_PORT" -le 65535 ]; then
        break
    else
        print_error "请输入有效的端口号 (1-65535)"
    fi
done

# 2. 批量端口客户端配置
print_step "2/6" "配置批量端口穿透客户端 (连接 209.146.116.106)"

# 输入起始端口
print_input "请输入批量端口的起始端口 (例如 10000):"
while true; do
    read -p "> " START_PORT
    if [[ "$START_PORT" =~ ^[0-9]+$ ]] && [ "$START_PORT" -ge 1 ] && [ "$START_PORT" -le 65535 ]; then
        break
    else
        print_error "请输入有效的起始端口 (1-65535)"
    fi
done

# 输入结束端口
print_input "请输入批量端口的结束端口 (必须 >= $START_PORT):"
while true; do
    read -p "> " END_PORT
    if [[ "$END_PORT" =~ ^[0-9]+$ ]] && [ "$END_PORT" -ge "$START_PORT" ] && [ "$END_PORT" -le 65535 ]; then
        break
    else
        print_error "请输入有效的结束端口，且必须大于等于 $START_PORT"
    fi
done

# 计算端口数量
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

# 服务器配置
SSH_SERVER="8.141.12.76"
CDN_SERVER="209.146.116.106"

# 安装路径
INSTALL_BASE="/usr/local/frp"
CONFIG_DIR="/etc/frp"
LOG_DIR="/var/log/frp"
SCRIPT_DIR="/usr/local/bin/frp-scripts"

# ==================== 开始安装 ====================

print_step "3/6" "检测系统架构并下载 FRP"

# 检测系统架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        ARCH_STR="amd64"
        ;;
    aarch64)
        ARCH_STR="arm64"
        ;;
    armv7l)
        ARCH_STR="arm"
        ;;
    *)
        print_error "不支持的架构: $ARCH"
        exit 1
        ;;
esac

# 检测操作系统
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

print_step "4/6" "生成配置文件"

# 生成 SSH 客户端配置 (vastaictssh.toml)
SSH_CONFIG="$CONFIG_DIR/vastaictssh.toml"
cat > "$SSH_CONFIG" <<EOF
# SSH 穿透配置 - 连接到 ${SSH_SERVER}
serverAddr = "${SSH_SERVER}"
serverPort = ${SERVER_PORT}

auth.method = "token"
auth.token = "${AUTH_TOKEN}"

# 日志配置
log.to = "${LOG_DIR}/frpc-ssh.log"
log.level = "info"
log.maxDays = 7

# 连接池和重试配置（增强稳定性）
transport.poolCount = 5
transport.maxPoolCount = 20
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

# 生成批量端口客户端配置 (vastaictcdn.toml)
CDN_CONFIG="$CONFIG_DIR/vastaictcdn.toml"
cat > "$CDN_CONFIG" <<EOF
# 批量端口穿透配置 - 连接到 ${CDN_SERVER}
serverAddr = "${CDN_SERVER}"
serverPort = ${SERVER_PORT}

auth.method = "token"
auth.token = "${AUTH_TOKEN}"

# 日志配置
log.to = "${LOG_DIR}/frpc-cdn.log"
log.level = "info"
log.maxDays = 7

# 连接池和重试配置（增强稳定性）
transport.poolCount = 10
transport.maxPoolCount = 50
transport.heartbeatInterval = 20
transport.heartbeatTimeout = 60

# TCP 多路复用，提高性能
transport.protocol = "tcp"
transport.tcpMux = true

# 批量端口映射
EOF

# 添加批量端口配置
for ((port=START_PORT; port<=END_PORT; port++)); do
    # 计算对应的远程端口（可以根据需要调整偏移量，这里使用相同端口）
    REMOTE_PORT=$port
    
    cat >> "$CDN_CONFIG" <<EOF

[[proxies]]
name = "tcp_${port}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${port}
remotePort = ${REMOTE_PORT}

# 代理健康检查
healthCheck.type = "tcp"
healthCheck.timeoutSeconds = 3
healthCheck.maxFailed = 3
healthCheck.intervalSeconds = 10
EOF
done

print_info "配置文件生成完成"

# ==================== 创建健康检查脚本 ====================

print_step "5/6" "创建健康检查和自愈脚本"

# SSH 客户端健康检查脚本
SSH_HEALTH_SCRIPT="$SCRIPT_DIR/check-ssh.sh"
cat > "$SSH_HEALTH_SCRIPT" <<'EOF'
#!/bin/bash
# SSH 客户端健康检查脚本

CONFIG_DIR="/etc/frp"
LOG_DIR="/var/log/frp"
CLIENT_NAME="ssh"
SERVER_ADDR="8.141.12.76"
SERVER_PORT="7000"

# 检查进程是否运行
if ! pgrep -f "frpc.*vastaictssh" > /dev/null; then
    echo "[$(date)] SSH客户端进程不存在，重启中..." >> "$LOG_DIR/frpc-ssh-health.log"
    systemctl restart frpc@vastaictssh
    exit 1
fi

# 尝试连接服务器检查网络
timeout 5 nc -zv $SERVER_ADDR $SERVER_PORT 2>/dev/null
if [ $? -ne 0 ]; then
    echo "[$(date)] SSH客户端无法连接到服务器，重启中..." >> "$LOG_DIR/frpc-ssh-health.log"
    systemctl restart frpc@vastaictssh
    exit 1
fi

# 检查日志中是否有大量错误
if tail -n 50 "$LOG_DIR/frpc-ssh.log" 2>/dev/null | grep -q "error\|EOF\|timeout" ; then
    echo "[$(date)] SSH客户端检测到错误，重启中..." >> "$LOG_DIR/frpc-ssh-health.log"
    systemctl restart frpc@vastaictssh
    exit 1
fi

exit 0
EOF

# CDN 客户端健康检查脚本
CDN_HEALTH_SCRIPT="$SCRIPT_DIR/check-cdn.sh"
cat > "$CDN_HEALTH_SCRIPT" <<'EOF'
#!/bin/bash
# CDN 客户端健康检查脚本

CONFIG_DIR="/etc/frp"
LOG_DIR="/var/log/frp"
CLIENT_NAME="cdn"
SERVER_ADDR="209.146.116.106"
SERVER_PORT="7000"
EXPECTED_PROXIES=$(grep -c "\[\[proxies\]\]" "$CONFIG_DIR/vastaictcdn.toml")

# 检查进程是否运行
if ! pgrep -f "frpc.*vastaictcdn" > /dev/null; then
    echo "[$(date)] CDN客户端进程不存在，重启中..." >> "$LOG_DIR/frpc-cdn-health.log"
    systemctl restart frpc@vastaictcdn
    exit 1
fi

# 尝试连接服务器检查网络
timeout 5 nc -zv $SERVER_ADDR $SERVER_PORT 2>/dev/null
if [ $? -ne 0 ]; then
    echo "[$(date)] CDN客户端无法连接到服务器，重启中..." >> "$LOG_DIR/frpc-cdn-health.log"
    systemctl restart frpc@vastaictcdn
    exit 1
fi

# 检查日志中是否有大量错误
if tail -n 50 "$LOG_DIR/frpc-cdn.log" 2>/dev/null | grep -q "error\|EOF\|timeout\|connection refused" ; then
    echo "[$(date)] CDN客户端检测到错误，重启中..." >> "$LOG_DIR/frpc-cdn-health.log"
    systemctl restart frpc@vastaictcdn
    exit 1
fi

# 检查代理数量是否正常（可选，需要更复杂的逻辑）
# 这里简单检查日志中是否有代理注册失败
if tail -n 100 "$LOG_DIR/frpc-cdn.log" 2>/dev/null | grep -q "proxy.*failed" ; then
    echo "[$(date)] CDN客户端代理注册失败，重启中..." >> "$LOG_DIR/frpc-cdn-health.log"
    systemctl restart frpc@vastaictcdn
    exit 1
fi

exit 0
EOF

chmod +x "$SSH_HEALTH_SCRIPT" "$CDN_HEALTH_SCRIPT"

# ==================== 创建 Systemd 服务 ====================

print_step "6/6" "创建 Systemd 服务和定时器"

# 创建服务模板
SERVICE_TEMPLATE="/etc/systemd/system/frpc@.service"
cat > "$SERVICE_TEMPLATE" <<EOF
[Unit]
Description=FRPC Client for %I
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/tmp
Environment="GODEBUG=madvdontneed=1"
ExecStartPre=/bin/sleep 2
ExecStart=/usr/local/bin/frpc -c /etc/frp/%i.toml
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10
StartLimitBurst=5
StartLimitIntervalSec=60

# 优化文件描述符限制
LimitNOFILE=65536
LimitNPROC=65536

# 日志处理
StandardOutput=append:/var/log/frp/frpc-%i.log
StandardError=append:/var/log/frp/frpc-%i.error.log

[Install]
WantedBy=multi-user.target
EOF

# SSH 客户端健康检查服务
cat > "/etc/systemd/system/frpc-healthcheck-ssh.service" <<EOF
[Unit]
Description=FRPC SSH Health Check Service
After=frpc@vastaictssh.service

[Service]
Type=oneshot
ExecStart=$SSH_HEALTH_SCRIPT
User=root

[Install]
WantedBy=multi-user.target
EOF

# CDN 客户端健康检查服务
cat > "/etc/systemd/system/frpc-healthcheck-cdn.service" <<EOF
[Unit]
Description=FRPC CDN Health Check Service
After=frpc@vastaictcdn.service

[Service]
Type=oneshot
ExecStart=$CDN_HEALTH_SCRIPT
User=root

[Install]
WantedBy=multi-user.target
EOF

# SSH 客户端健康检查定时器
cat > "/etc/systemd/system/frpc-healthcheck-ssh.timer" <<EOF
[Unit]
Description=FRPC SSH Health Check Timer
Requires=frpc@vastaictssh.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=3min
RandomizedDelaySec=10

[Install]
WantedBy=timers.target
EOF

# CDN 客户端健康检查定时器
cat > "/etc/systemd/system/frpc-healthcheck-cdn.timer" <<EOF
[Unit]
Description=FRPC CDN Health Check Timer
Requires=frpc@vastaictcdn.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=3min
RandomizedDelaySec=10

[Install]
WantedBy=timers.target
EOF

# 日志轮转配置
cat > "/etc/logrotate.d/frpc" <<EOF
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

print_info "重新加载 Systemd 配置..."
systemctl daemon-reload

print_info "启用并启动 SSH 客户端服务..."
systemctl enable frpc@vastaictssh.service
systemctl restart frpc@vastaictssh.service

print_info "启用并启动 CDN 客户端服务..."
systemctl enable frpc@vastaictcdn.service
systemctl restart frpc@vastaictcdn.service

print_info "启用健康检查定时器..."
systemctl enable frpc-healthcheck-ssh.timer
systemctl enable frpc-healthcheck-cdn.timer
systemctl start frpc-healthcheck-ssh.timer
systemctl start frpc-healthcheck-cdn.timer

# ==================== 等待服务启动 ====================

sleep 5

# ==================== 检查服务状态 ====================

echo ""
print_info "服务状态检查"
echo "----------------------------------------"

# 检查 SSH 客户端
if systemctl is-active --quiet frpc@vastaictssh.service; then
    echo -e "SSH 客户端: ${GREEN}运行中${NC}"
else
    echo -e "SSH 客户端: ${RED}未运行${NC}"
fi

# 检查 CDN 客户端
if systemctl is-active --quiet frpc@vastaictcdn.service; then
    echo -e "CDN 客户端: ${GREEN}运行中${NC}"
else
    echo -e "CDN 客户端: ${RED}未运行${NC}"
fi

# 检查健康检查定时器
if systemctl is-active --quiet frpc-healthcheck-ssh.timer; then
    echo -e "SSH 健康检查: ${GREEN}运行中${NC}"
else
    echo -e "SSH 健康检查: ${RED}未运行${NC}"
fi

if systemctl is-active --quiet frpc-healthcheck-cdn.timer; then
    echo -e "CDN 健康检查: ${GREEN}运行中${NC}"
else
    echo -e "CDN 健康检查: ${RED}未运行${NC}"
fi

echo "----------------------------------------"

# ==================== 显示配置信息 ====================

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   安装完成！                                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "配置文件位置："
echo "  SSH 客户端: ${GREEN}$SSH_CONFIG${NC}"
echo "  CDN 客户端: ${GREEN}$CDN_CONFIG${NC}"
echo ""
echo "日志文件位置："
echo "  SSH 日志: ${YELLOW}$LOG_DIR/frpc-ssh.log${NC}"
echo "  CDN 日志: ${YELLOW}$LOG_DIR/frpc-cdn.log${NC}"
echo "  健康检查日志: ${YELLOW}$LOG_DIR/frpc-*-health.log${NC}"
echo ""
echo "管理命令："
echo "  ${CYAN}systemctl status frpc@vastaictssh${NC}     # 查看 SSH 客户端状态"
echo "  ${CYAN}systemctl status frpc@vastaictcdn${NC}     # 查看 CDN 客户端状态"
echo "  ${CYAN}systemctl status frpc-healthcheck-ssh.timer${NC}  # 查看 SSH 健康检查状态"
echo "  ${CYAN}systemctl status frpc-healthcheck-cdn.timer${NC}  # 查看 CDN 健康检查状态"
echo "  ${CYAN}journalctl -u frpc@vastaictssh -f${NC}     # 实时查看 SSH 客户端日志"
echo "  ${CYAN}journalctl -u frpc@vastaictcdn -f${NC}     # 实时查看 CDN 客户端日志"
echo ""
echo "配置的端口映射："
echo "  SSH 远程端口: ${GREEN}$SSH_REMOTE_PORT${NC}"
echo "  批量端口范围: ${GREEN}$START_PORT - $END_PORT${NC} (共 $PORT_COUNT 个端口)"
echo ""
echo "如需修改配置，请编辑对应的 .toml 文件后执行："
echo "  ${CYAN}systemctl restart frpc@vastaictssh${NC} 或 ${CYAN}systemctl restart frpc@vastaictcdn${NC}"
echo ""

# ==================== 可选：自我删除 ====================

SCRIPT_PATH="$(realpath "$0" 2>/dev/null)"
if [ -f "$SCRIPT_PATH" ] && [ "$SCRIPT_PATH" != "/bin/bash" ] && [ "$SCRIPT_PATH" != "/usr/bin/bash" ]; then
    print_warn "是否删除安装脚本自身？(y/n)"
    read -p "> " DELETE_SCRIPT
    if [[ "$DELETE_SCRIPT" =~ ^[Yy]$ ]]; then
        rm -f "$SCRIPT_PATH" 2>/dev/null
        print_info "安装脚本已删除"
    fi
fi

echo ""
print_info "脚本执行完毕！"
