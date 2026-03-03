#!/bin/bash

# Axis AI Deploy Script - FRP代理客户端
# 一键安装 - 内网穿透版 (完全修复版)

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
echo "║                 ****隔壁老王**** 一键安装脚本 (完全修复版)                    ║"
echo "║                                                                              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查Python3（用于生成配置）
check_python() {
    if ! command -v python3 &> /dev/null; then
        log_warn "未检测到python3，尝试安装..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y python3
        elif command -v yum &> /dev/null; then
            yum install -y python3
        else
            log_error "无法安装python3，请手动安装"
            exit 1
        fi
    fi
    log_info "✓ python3 已安装"
}

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

# 检查Python
check_python

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
FRP_VERSION="0.61.0"  # 使用更稳定的版本
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

# 步骤4: 配置端口范围
log_info "[4/5] 配置端口范围..."

# 获取起始端口
while true; do
    read -p "请输入起始端口: " START_PORT
    if [[ "$START_PORT" =~ ^[0-9]+$ ]] && [ "$START_PORT" -ge 1024 ] && [ "$START_PORT" -le 65535 ]; then
        break
    else
        log_error "请输入有效的端口号 (1024-65535)"
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

# 使用Python生成正确的配置文件（展开所有端口）
log_info "生成配置文件..."

# 创建Python生成脚本
PYTHON_GEN_SCRIPT="/tmp/generate_frpc_config.py"
cat > $PYTHON_GEN_SCRIPT << 'PYEOF'
#!/usr/bin/env python3
import sys

def generate_config(server_ip, token, start_port, end_port):
    config = f'''# FRP 客户端配置文件 - 自动生成
# 生成时间: $(date)

# 基础配置
serverAddr = "{server_ip}"
serverPort = 7000

auth.method = "token"
auth.token = "{token}"

# 日志配置
log.to = "/var/log/vastaictcdn/frpc.log"
log.level = "info"
log.maxDays = 3

# 连接稳定性优化
transport.protocol = "tcp"
transport.tcpMux = true
transport.tcpMuxKeepaliveInterval = 30
transport.maxPoolCount = 10
transport.connectTimeout = 10

# Web服务器配置（本地监控）
webServer.addr = "127.0.0.1"
webServer.port = 7400
webServer.user = "admin"
webServer.password = "admin"

'''

    # 为每个端口生成代理配置
    for port in range(int(start_port), int(end_port) + 1):
        config += f'''[[proxies]]
name = "proxy-{port}"
type = "tcp"
localIP = "127.0.0.1"
localPort = {port}
remotePort = {port}
transport.useEncryption = true
transport.useCompression = true

'''
    return config

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("Usage: generate_frpc_config.py <server_ip> <token> <start_port> <end_port>")
        sys.exit(1)
    
    server_ip = sys.argv[1]
    token = sys.argv[2]
    start_port = sys.argv[3]
    end_port = sys.argv[4]
    
    print(generate_config(server_ip, token, start_port, end_port))
PYEOF

# 执行Python脚本生成配置文件
CONFIG_FILE="$TARGET_DIR/vastaictcdn.toml"
python3 $PYTHON_GEN_SCRIPT "$SERVER_IP" "$AUTH_TOKEN" "$START_PORT" "$END_PORT" > $CONFIG_FILE

# 检查配置文件是否生成成功
if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
    log_error "配置文件生成失败"
    exit 1
fi

# 显示配置文件预览
log_info "配置文件预览（前10行）:"
head -10 $CONFIG_FILE

# 保存配置信息
echo "$START_PORT-$END_PORT" > "$CONFIG_DIR/host_port_range"
echo "$SERVER_IP" > "$CONFIG_DIR/host_ipaddr"
echo "$((END_PORT + 1))" > "$CONFIG_DIR/check_port"

log_info "✓ 配置文件生成完成（已展开 $PORT_COUNT 个端口）"

# 步骤5: 配置和启动服务
log_info "[5/5] 配置和启动服务..."

# 创建健康检查脚本
HEALTH_SCRIPT="$TARGET_DIR/vastaish"
cat > $HEALTH_SCRIPT << 'HEALTHEOF'
#!/bin/bash

# 健康检查脚本
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

# 检查连接状态
check_connections() {
    SERVER_IP=$(cat $CONFIG_DIR/host_ipaddr 2>/dev/null || echo "")
    if [ -n "$SERVER_IP" ] && command -v ss &> /dev/null; then
        CONN_COUNT=$(ss -tn | grep -c "$SERVER_IP:7000" 2>/dev/null || echo 0)
        if [ "$CONN_COUNT" -eq 0 ]; then
            log_msg "警告: 无活动连接到服务器"
        fi
    fi
}

# 检查日志大小
check_log_size() {
    FRPC_LOG="/var/log/vastaictcdn/frpc.log"
    if [ -f "$FRPC_LOG" ]; then
        SIZE=$(du -m "$FRPC_LOG" 2>/dev/null | cut -f1)
        if [ -n "$SIZE" ] && [ "$SIZE" -gt 100 ]; then
            log_msg "日志文件过大(${SIZE}MB)，轮转日志"
            mv "$FRPC_LOG" "${FRPC_LOG}.old"
            systemctl restart vastaictcdn
        fi
    fi
}

# 执行检查
log_msg "执行健康检查"
check_process
check_connections
check_log_size
log_msg "健康检查完成"
exit 0
HEALTHEOF

chmod +x $HEALTH_SCRIPT

# 创建systemd服务
cat > /etc/systemd/system/vastaictcdn.service << SERVICEEOF
[Unit]
Description=Axis AI CDN Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$TARGET_DIR
ExecStart=$PROGRAM -c $CONFIG_FILE
Restart=always
RestartSec=10
StartLimitBurst=5
StartLimitInterval=60

# 文件描述符限制
LimitNOFILE=1048576

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

# 创建健康检查服务
cat > /etc/systemd/system/vastaictcdn-health.service << HEALTHSERVICEEOF
[Unit]
Description=Axis AI CDN Health Check
After=network.target

[Service]
Type=oneshot
ExecStart=$HEALTH_SCRIPT
User=root
Group=root
HEALTHSERVICEEOF

# 创建定时器
cat > /etc/systemd/system/vastaictcdn-health.timer << TIMEREOF
[Unit]
Description=Axis AI CDN Health Check Timer
Requires=vastaictcdn.service

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
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
    # 额外验证：检查是否有错误日志
    ERROR_COUNT=$(journalctl -u vastaictcdn -n 20 --no-pager | grep -c "error\|ERROR\|fail\|FAIL" 2>/dev/null || echo 0)
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════════"
    echo "║                                                                              ║"
    echo "║                    ✓ 安装成功！服务运行正常                                ║"
    echo "║                                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo " 服务摘要:"
    echo "  - 服务器地址: $SERVER_IP:$SERVER_PORT"
    echo "  - 端口范围: $START_PORT - $END_PORT ($PORT_COUNT 个端口)"
    echo "  - 服务状态: $(systemctl is-active vastaictcdn)"
    echo "  - 配置文件: $CONFIG_FILE"
    echo "  - 日志位置: $LOG_DIR/frpc.log"
    echo "  - 健康检查: 每5分钟执行一次"
    echo ""
    echo " 常用命令:"
    echo "  - 查看状态: systemctl status vastaictcdn"
    echo "  - 查看实时日志: journalctl -u vastaictcdn -f"
    echo "  - 重启服务: systemctl restart vastaictcdn"
    echo "  - 测试连接: nc -zv $SERVER_IP $START_PORT"
    echo ""
    
    # 显示前10个端口的配置作为示例
    echo " 已配置端口示例（前10个）:"
    for port in $(seq $START_PORT $((START_PORT + 9 < END_PORT ? START_PORT + 9 : END_PORT))); do
        echo "    - $port -> $SERVER_IP:$port"
    done
    if [ $PORT_COUNT -gt 10 ]; then
        echo "    ... 以及 $((PORT_COUNT - 10)) 个更多端口"
    fi
    echo ""
else
    log_error "服务启动失败，查看日志:"
    journalctl -u vastaictcdn -n 50 --no-pager
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo "感谢使用 ****隔壁老王**** 一键安装脚本 (完全修复版)！"
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo ""

# 删除脚本自身
SCRIPT_PATH="$(realpath "$0" 2>/dev/null)"
if [ -f "$SCRIPT_PATH" ] && [ "$SCRIPT_PATH" != "/bin/bash" ] && [ "$SCRIPT_PATH" != "/usr/bin/bash" ]; then
    rm -f "$SCRIPT_PATH" 2>/dev/null
fi
