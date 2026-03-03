#!/bin/bash

# Axis AI Deploy Script - FRP代理客户端
# 一键安装 - 内网穿透版 (稳定性优化版)

# 预设配置（可修改）
DOMAIN="38.255.16.238"
SERVER_PORT=7000
AUTH_TOKEN="qazwsx123.0"
WEB_PORT=7500
WEB_USER="admin"
WEB_PASSWORD="admin"
PROXY_PREFIX="proxy"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "═══════════════════════════════════════════════════════════════════════════════════"
echo "║                                                                              ║"
echo "║                 ****隔壁老王**** 一键安装脚本 (稳定性优化版)                  ║"
echo "║                                                                              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 步骤1: 网络连通性测试
log_info "[1/5] 网络连通性测试中..."

# 网络连通性测试
if ping -c 3 -W 3 $DOMAIN > /dev/null 2>&1; then
    log_info "✓ 网络连通性正常"
else
    log_error "✗ 网络连通性异常"
    log_error "无法连接到服务器域名: $DOMAIN"
    log_error "请检查网络或域名解析"
    exit 1
fi

# 步骤2: 获取服务器IP和Token
log_info "[2/5] 获取服务器配置信息..."

# 获取服务器IP
while true; do
    read -p "请输入服务器IP地址: " SERVER_IP
    if [ -n "$SERVER_IP" ]; then
        if [[ $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            break
        else
            log_error "请输入有效的IP地址"
        fi
    else
        log_error "服务器IP不能为空"
    fi
done

# 获取认证Token
while true; do
    read -p "请输入认证Token: " INPUT_TOKEN
    if [ -n "$INPUT_TOKEN" ]; then
        AUTH_TOKEN="$INPUT_TOKEN"
        break
    else
        log_error "Token不能为空"
    fi
done

log_info "服务器地址: $SERVER_IP:$SERVER_PORT"
log_info "认证Token: ${AUTH_TOKEN:0:5}***${AUTH_TOKEN: -3}"

# 步骤3: 下载和安装程序
TARGET_DIR="/var/lib/vastai_kaalia/docker_tmp"
PROGRAM="$TARGET_DIR/vastaictcdn"
CONFIG_DIR="/var/lib/vastai_kaalia"
LOG_DIR="/var/log/vastaictcdn"

log_info "[3/5] 下载安装程序..."

# 创建必要目录
mkdir -p "$TARGET_DIR" "$CONFIG_DIR" "$LOG_DIR"

# 如果服务已在运行，先停止
if systemctl is-active vastaictcdn > /dev/null 2>&1; then
    log_info "停止现有服务..."
    systemctl stop vastaictcdn > /dev/null 2>&1
    sleep 2
fi

# 获取系统架构
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    armv7l) ARCH="arm" ;;
    *) log_error "不支持的架构: $ARCH"; exit 1 ;;
esac

# 获取操作系统类型
OS=$(uname -s | tr '[A-Z]' '[a-z]')

# 下载FRP（带重试机制）
FRP_VERSION="0.65.0"
FILENAME="frp_${FRP_VERSION}_${OS}_${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILENAME}"

log_info "正在下载 FRP v$FRP_VERSION..."
max_retries=3
retry_count=0
download_success=false

while [ $retry_count -lt $max_retries ] && [ "$download_success" = false ]; do
    if command -v wget &> /dev/null; then
        if wget --timeout=30 -q -O "$FILENAME" "$DOWNLOAD_URL"; then
            download_success=true
        fi
    elif command -v curl &> /dev/null; then
        if curl --connect-timeout 30 -s -L -o "$FILENAME" "$DOWNLOAD_URL"; then
            download_success=true
        fi
    else
        log_error "需要wget或curl"
        exit 1
    fi
    
    if [ "$download_success" = false ]; then
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            log_warn "下载失败，${retry_count}/${max_retries} 次重试..."
            sleep 3
        fi
    fi
done

if [ "$download_success" = false ]; then
    log_error "下载失败，请检查网络连接"
    exit 1
fi

log_info "✓ 下载完成"

# 解压并安装
log_info "解压文件中..."
if ! tar -zxf "$FILENAME" > /dev/null 2>&1; then
    log_error "解压失败，文件可能损坏"
    exit 1
fi

EXTRACT_DIR="frp_${FRP_VERSION}_${OS}_${ARCH}"
cp "$EXTRACT_DIR/frpc" "$PROGRAM"
chmod +x "$PROGRAM"

# 清理临时文件
rm -rf "$EXTRACT_DIR" "$FILENAME"

log_info "✓ 安装程序完成"

# 步骤4: 配置端口范围（移除100个端口的限制）
log_info "[4/5] 配置端口范围..."

# 获取起始端口
while true; do
    read -p "请输入起始端口: " START_PORT
    if [[ "$START_PORT" =~ ^[0-9]+$ ]] && [ "$START_PORT" -ge 1 ] && [ "$START_PORT" -le 65535 ]; then
        break
    else
        log_error "请输入有效的端口号 (1-65535)"
    fi
done

# 获取结束端口
while true; do
    read -p "请输入结束端口: " END_PORT
    if [[ "$END_PORT" =~ ^[0-9]+$ ]] && [ "$END_PORT" -ge "$START_PORT" ] && [ "$END_PORT" -le 65535 ]; then
        break
    else
        log_error "结束端口必须大于等于起始端口且小于等于65535"
    fi
done

PORT_COUNT=$((END_PORT - START_PORT + 1))
log_info "端口配置摘要:"
log_info "  - 端口范围: $START_PORT - $END_PORT"
log_info "  - 总端口数: $PORT_COUNT 个端口"

read -p "确认配置? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    log_warn "安装已取消"
    exit 0
fi

# 生成配置文件（优化版）
CONFIG_FILE="$TARGET_DIR/vastaictcdn.toml"

cat > $CONFIG_FILE << EOF
# FRP 客户端配置文件 - 稳定性优化版
# 生成时间: $(date)

# 基础配置
serverAddr = "$SERVER_IP"
serverPort = $SERVER_PORT

auth.method = "token"
auth.token = "$AUTH_TOKEN"

# 日志配置（关键：日志轮转，避免磁盘满）
log.to = "/var/log/vastaictcdn/frpc.log"
log.level = "info"
log.maxDays = 3

# 连接稳定性优化
transport.protocol = "tcp"
transport.tcpMux = true
transport.tcpMuxKeepaliveInterval = 30
transport.maxPoolCount = 10
transport.connectTimeout = 10
transport.udpPacketSize = 1500

# 健康检查配置
healthCheck.timeout = 10
healthCheck.maxFailed = 3
healthCheck.interval = 60

# 保持连接
transport.heartbeatInterval = 30
transport.heartbeatTimeout = 90

# Web服务器配置（客户端仪表板）
webServer.addr = "127.0.0.1"
webServer.port = 7400
webServer.user = "admin"
webServer.password = "admin"

{{- range \$i, \$v := parseNumberRangePair "$START_PORT-$END_PORT" "$START_PORT-$END_PORT" }}
[[proxies]]
name = "$PROXY_PREFIX-{{ \$v.First }}"
type = "tcp"
localIP = "127.0.0.1"
localPort = {{ \$v.First }}
remotePort = {{ \$v.Second }}
# 代理稳定性优化
transport.useEncryption = true
transport.useCompression = true
# 健康检查
healthCheck.type = "tcp"
healthCheck.timeout = 5
healthCheck.interval = 60
{{- end }}
EOF

# 保存配置信息
echo "$START_PORT-$END_PORT" > "$CONFIG_DIR/host_port_range"
echo "$SERVER_IP" > "$CONFIG_DIR/host_ipaddr"
echo "$((END_PORT + 1))" > "$CONFIG_DIR/check_port"

log_info "✓ 配置文件生成完成"

# 步骤5: 配置和启动服务
log_info "[5/5] 配置和启动服务..."

# 创建增强版健康检查脚本
HEALTH_SCRIPT="$TARGET_DIR/vastaish"
cat > $HEALTH_SCRIPT << 'HEALTHEOF'
#!/bin/bash

# 健康检查脚本 - 稳定性增强版
CONFIG_DIR="/var/lib/vastai_kaalia"
LOG_FILE="/var/log/vastaictcdn/health.log"
PROGRAM="/var/lib/vastai_kaalia/docker_tmp/vastaictcdn"

# 日志函数
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 检查服务进程
check_process() {
    if ! pgrep -f "vastaictcdn" > /dev/null; then
        log_msg "服务进程不存在，重启服务"
        systemctl restart vastaictcdn
        return 1
    fi
    return 0
}

# 检查连接状态（通过SS或netstat）
check_connections() {
    if command -v ss &> /dev/null; then
        CONN_COUNT=$(ss -tn | grep -c "$SERVER_IP:$SERVER_PORT" 2>/dev/null || echo 0)
    elif command -v netstat &> /dev/null; then
        CONN_COUNT=$(netstat -tn | grep -c "$SERVER_IP:$SERVER_PORT" 2>/dev/null || echo 0)
    else
        CONN_COUNT=0
    fi
    
    if [ "$CONN_COUNT" -eq 0 ]; then
        log_msg "警告: 无活动连接"
    fi
}

# 检查日志文件大小（防止日志过大）
check_log_size() {
    LOG_FILE="/var/log/vastaictcdn/frpc.log"
    if [ -f "$LOG_FILE" ]; then
        SIZE=$(du -m "$LOG_FILE" | cut -f1)
        if [ "$SIZE" -gt 100 ]; then
            log_msg "日志文件过大(${SIZE}MB)，轮转日志"
            mv "$LOG_FILE" "${LOG_FILE}.old"
            systemctl restart vastaictcdn
        fi
    fi
}

# 主检查逻辑
log_msg "执行健康检查"

# 1. 检查进程
if ! check_process; then
    log_msg "服务已重启"
    exit 0
fi

# 2. 检查连接
check_connections

# 3. 检查日志大小
check_log_size

# 4. 端口占用检查
SERVER_IP=$(cat $CONFIG_DIR/host_ipaddr 2>/dev/null || echo "")
LOCAL_PORT=$(cat $CONFIG_DIR/check_port 2>/dev/null || echo "8000")

if [ -n "$SERVER_IP" ]; then
    TARGET_URL="http://${SERVER_IP}:${LOCAL_PORT}"
    
    # 启动临时HTTP服务用于测试
    if ! lsof -i:$LOCAL_PORT | grep -q python3; then
        nohup python3 -m http.server $LOCAL_PORT > /dev/null 2>&1 &
        sleep 2
    fi
    
    # 测试连接
    if curl -s --max-time 10 "$TARGET_URL" > /dev/null; then
        log_msg "连接测试正常"
    else
        log_msg "连接测试失败，尝试重启服务"
        systemctl restart vastaictcdn
    fi
    
    # 清理临时服务
    fuser -k ${LOCAL_PORT}/tcp 2>/dev/null
fi

log_msg "健康检查完成"
exit 0
HEALTHEOF

chmod +x $HEALTH_SCRIPT

# 创建优化版systemd服务
cat > /etc/systemd/system/vastaictcdn.service << SERVICEEOF
[Unit]
Description=Axis AI CDN Service (Stable)
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$TARGET_DIR
Environment="HOME=/root"
ExecStart=$PROGRAM -c $CONFIG_FILE
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10
StartLimitBurst=5
StartLimitIntervalSec=60

# 文件描述符限制
LimitNOFILE=1048576
LimitNPROC=512

# 日志处理
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vastaictcdn

# 超时设置
TimeoutStartSec=30
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
SERVICEEOF

# 创建健康检查服务（定时执行）
cat > /etc/systemd/system/vastaictcdn-health.service << HEALTHSERVICEEOF
[Unit]
Description=Axis AI CDN Health Check
After=network.target

[Service]
Type=oneshot
ExecStart=$HEALTH_SCRIPT
User=root
Group=root
StandardOutput=journal
StandardError=journal
HEALTHSERVICEEOF

# 创建定时器（更频繁的健康检查）
cat > /etc/systemd/system/vastaictcdn-health.timer << TIMEREOF
[Unit]
Description=Axis AI CDN Health Check Timer
Requires=vastaictcdn.service

[Timer]
OnBootSec=1min
OnUnitActiveSec=3min
RandomizedDelaySec=10

[Install]
WantedBy=timers.target
TIMEREOF

# 创建日志轮转配置
cat > /etc/logrotate.d/vastaictcdn << LOGROTATEEOF
/var/log/vastaictcdn/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    sharedscripts
    postrotate
        systemctl kill -s HUP vastaictcdn.service || true
    endscript
}
LOGROTATEEOF

# 启用并启动服务
systemctl daemon-reload
systemctl enable vastaictcdn.service > /dev/null 2>&1
systemctl enable vastaictcdn-health.timer > /dev/null 2>&1
systemctl start vastaictcdn.service
systemctl start vastaictcdn-health.timer

log_info "✓ 服务配置完成"

# 验证服务状态
log_info "正在验证服务状态..."
sleep 5

# 检查服务状态
if systemctl is-active vastaictcdn > /dev/null 2>&1; then
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════════"
    echo "║                                                                              ║"
    echo "║                    ✓ 安装成功！服务运行正常                                ║"
    echo "║                                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo " 服务摘要:"
    echo "  - 端口范围: $START_PORT - $END_PORT ($PORT_COUNT 个端口)"
    echo "  - 服务状态: $(systemctl is-active vastaictcdn)"
    echo "  - 日志位置: $LOG_DIR/frpc.log"
    echo "  - 健康检查: 每3分钟执行一次"
    echo ""
    
    # 显示一些有用的命令
    echo " 常用命令:"
    echo "  - 查看状态: systemctl status vastaictcdn"
    echo "  - 查看日志: journalctl -u vastaictcdn -f"
    echo "  - 重启服务: systemctl restart vastaictcdn"
    echo "  - 查看端口: ss -tuln | grep -E ':$START_PORT-'"
    echo ""
else
    log_error "服务启动失败，查看日志: journalctl -u vastaictcdn -n 50"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo "感谢使用 ****隔壁老王**** 一键安装脚本 (稳定性优化版)！"
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo ""

# 删除脚本自身
SCRIPT_PATH="$(realpath "$0" 2>/dev/null)"
if [ -f "$SCRIPT_PATH" ] && [ "$SCRIPT_PATH" != "/bin/bash" ] && [ "$SCRIPT_PATH" != "/usr/bin/bash" ]; then
    rm -f "$SCRIPT_PATH" 2>/dev/null
fi
