#!/bin/bash

set -e  # 遇到错误立即退出

# FRP 客户端自动安装脚本 - 增强稳定版
FRP_VERSION="${1:-0.64.0}"
REMOTE_PORT="${2:-}"
PROXY_NAME="${3:-}"

echo "开始安装 FRP 客户端 v$FRP_VERSION (增强稳定版)"

# 配置参数（必须与服务端一致）
SERVER_ADDR="67.215.246.67"  # 服务器IP
SERVER_PORT="7000"
AUTH_TOKEN="qazwsx123.0"      # 必须与服务端token一致

# 停止并清理现有服务
cleanup_existing() {
    echo "检查现有 FRP 服务..."
    if systemctl is-active --quiet frpc 2>/dev/null; then
        echo "停止运行中的 FRP 客户端服务..."
        systemctl stop frpc
        sleep 2
    fi
    
    if systemctl is-enabled --quiet frpc 2>/dev/null; then
        echo "禁用 FRP 客户端服务..."
        systemctl disable frpc
    fi
    
    if pgrep frpc > /dev/null; then
        echo "发现残留的 frpc 进程，正在清理..."
        pkill -9 frpc
        sleep 1
    fi
    
    # 清理旧的监控任务
    if crontab -l 2>/dev/null | grep -q "frpc_monitor"; then
        echo "清理旧的监控任务..."
        crontab -l | grep -v "frpc_monitor" | crontab -
    fi
}

# 获取远程端口参数 - 修改为独立函数
get_remote_port() {
    # 如果通过参数提供了端口，则直接使用
    if [ -n "$REMOTE_PORT" ]; then
        if [[ "$REMOTE_PORT" =~ ^[0-9]+$ ]] && [ "$REMOTE_PORT" -ge 1 ] && [ "$REMOTE_PORT" -le 65535 ]; then
            echo "使用指定远程端口: $REMOTE_PORT"
            return 0
        else
            echo "错误: 端口号必须是 1-65535 之间的数字"
            exit 1
        fi
    fi
    
    # 如果没有提供参数，则提示用户输入
    while true; do
        read -p "请输入远程端口号 (默认: 39565): " INPUT_PORT
        INPUT_PORT=${INPUT_PORT:-39565}
        if [[ "$INPUT_PORT" =~ ^[0-9]+$ ]] && [ "$INPUT_PORT" -ge 1 ] && [ "$INPUT_PORT" -le 65535 ]; then
            REMOTE_PORT=$INPUT_PORT
            break
        else
            echo "错误: 端口号必须是 1-65535 之间的数字"
        fi
    done
}

# 获取代理名称参数 - 修改为独立函数
get_proxy_name() {
    # 如果通过参数提供了代理名称，则直接使用
    if [ -n "$PROXY_NAME" ]; then
        if [[ "$PROXY_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo "使用指定代理名称: $PROXY_NAME"
            return 0
        else
            echo "错误: 代理名称只能包含字母、数字、下划线和连字符"
            exit 1
        fi
    fi
    
    # 如果没有提供参数，则提示用户输入
    while true; do
        read -p "请输入代理名称 (默认: ssh_$(hostname)): " INPUT_NAME
        INPUT_NAME=${INPUT_NAME:-"ssh_$(hostname)"}
        if [[ "$INPUT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            PROXY_NAME=$INPUT_NAME
            break
        else
            echo "错误: 代理名称只能包含字母、数字、下划线和连字符"
        fi
    done
}

# 显示配置摘要
show_config_summary() {
    echo ""
    echo "配置确认:"
    echo "服务器地址: $SERVER_ADDR"
    echo "服务器端口: $SERVER_PORT"
    echo "认证令牌: ${AUTH_TOKEN:0:4}****"
    echo "远程端口: $REMOTE_PORT"
    echo "代理名称: $PROXY_NAME"
    echo ""
    
    read -p "确认开始安装？(y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "安装已取消"
        exit 0
    fi
}

# 检查架构
detect_architecture() {
    local ARCH=$(uname -m)
    case $ARCH in
        "x86_64") echo "amd64" ;;
        "aarch64") echo "arm64" ;;
        "armv7l") echo "arm" ;;
        "armv6l") echo "arm" ;;
        *) echo "不支持的架构: $ARCH"; exit 1 ;;
    esac
}

# 检查是否以 root 权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "请使用 sudo 或以 root 用户运行此脚本"
        exit 1
    fi
}

# 配置网络优化参数
configure_network_tuning() {
    echo "配置网络优化参数..."
    
    # 备份现有配置
    cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null || true
    
    # 添加网络优化参数
    cat >> /etc/sysctl.conf << SYSCTL

# FRP 网络优化 (添加于 $(date))
net.core.somaxconn = 65536
net.core.netdev_max_backlog = 65536
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 10
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.ip_local_port_range = 1024 65000
SYSCTL
    
    # 应用配置
    sysctl -p >/dev/null 2>&1 || {
        echo "⚠️  sysctl配置应用失败，继续安装..."
    }
    
    # 增加文件描述符限制
    cat > /etc/security/limits.d/frp-limits.conf << LIMITS
* soft nofile 65536
* hard nofile 65536
root soft nofile 65536
root hard nofile 65536
LIMITS
    
    echo "✅ 网络优化配置完成"
}

# 创建监控脚本
create_monitor_script() {
    echo "创建监控脚本..."
    
    mkdir -p /var/log/frp
    
    cat > /usr/local/bin/frpc_monitor.sh << 'MONITOR'
#!/bin/bash
set -e

FRPC_PID=$(pgrep -f "frpc.*frpc.toml")
LOG_FILE="/var/log/frp/frpc_monitor.log"
MAX_RETRIES=3
RETRY_COUNT=0
SERVER_ADDR="67.215.246.67"
SERVER_PORT="7000"

# 创建日志目录
mkdir -p /var/log/frp

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检查进程是否存在
if [ -z "$FRPC_PID" ]; then
    log "❌ FRPC 进程不存在，尝试重启..."
    systemctl restart frpc
    sleep 5
    
    # 检查重启结果
    if systemctl is-active --quiet frpc; then
        log "✅ FRPC 重启成功"
        exit 0
    else
        log "❌ FRPC 重启失败"
        exit 1
    fi
fi

# 检查连接状态
check_connection() {
    local timeout=10
    
    # 方法1: 使用nc
    if command -v nc >/dev/null 2>&1; then
        if timeout $timeout nc -z -w 5 "$SERVER_ADDR" "$SERVER_PORT" 2>/dev/null; then
            return 0
        fi
    fi
    
    # 方法2: 使用telnet
    if command -v telnet >/dev/null 2>&1; then
        if echo -e "\x1dclose" | timeout $timeout telnet "$SERVER_ADDR" "$SERVER_PORT" 2>&1 | grep -q "Connected"; then
            return 0
        fi
    fi
    
    # 方法3: 使用bash内置的TCP连接
    if timeout $timeout bash -c "cat < /dev/null > /dev/tcp/${SERVER_ADDR}/${SERVER_PORT}" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# 检查连接
if ! check_connection; then
    log "⚠️  FRPC 连接检查失败，重启服务..."
    
    # 记录失败前的状态
    log "重启前状态 - PID: $FRPC_PID"
    
    # 尝试优雅停止
    systemctl stop frpc
    sleep 5
    
    # 确保进程已停止
    if pgrep frpc >/dev/null; then
        pkill -9 frpc
        sleep 2
    fi
    
    # 重启服务
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        RETRY_COUNT=$((RETRY_COUNT + 1))
        log "第 $RETRY_COUNT 次重启尝试..."
        
        if systemctl start frpc; then
            sleep 3
            if systemctl is-active --quiet frpc; then
                log "✅ FRPC 重启成功"
                
                # 验证连接
                if check_connection; then
                    log "✅ 连接验证成功"
                    exit 0
                else
                    log "⚠️  服务已启动但连接验证失败"
                fi
            fi
        fi
        
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            log "等待 10 秒后重试..."
            sleep 10
        fi
    done
    
    log "❌ FRPC 重启失败，达到最大重试次数"
    echo "=== 最后 20 行日志 ===" >> "$LOG_FILE"
    journalctl -u frpc -n 20 --no-pager 2>/dev/null | tee -a "$LOG_FILE"
    exit 1
fi

# 检查内存使用
MEMORY_LIMIT=256000  # 256MB in KB
if [ -f "/proc/$FRPC_PID/status" ]; then
    MEM_USAGE=$(grep VmRSS "/proc/$FRPC_PID/status" | awk '{print $2}' 2>/dev/null || echo "0")
    if [ -n "$MEM_USAGE" ] && [ "$MEM_USAGE" != "0" ] && [ "$MEM_USAGE" -gt "$MEMORY_LIMIT" ]; then
        log "⚠️  FRPC 内存使用过高 (${MEM_USAGE}KB)，重启服务..."
        systemctl restart frpc
        sleep 3
        
        if systemctl is-active --quiet frpc; then
            log "✅ 内存优化重启成功"
        else
            log "❌ 内存优化重启失败"
        fi
    fi
fi

# 记录正常运行状态
if [ $(( $(date +%s) % 300 )) -eq 0 ]; then  # 每5分钟记录一次
    log "✅ FRPC 运行正常 - PID: $FRPC_PID"
fi
MONITOR

    chmod +x /usr/local/bin/frpc_monitor.sh
    
    # 添加到crontab
    echo "添加监控到crontab..."
    (crontab -l 2>/dev/null | grep -v "frpc_monitor"; echo "*/2 * * * * /usr/local/bin/frpc_monitor.sh >/dev/null 2>&1") | crontab -
    
    # 创建日志轮转配置
    cat > /etc/logrotate.d/frp << LOGROTATE
/var/log/frp/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
LOGROTATE
    
    echo "✅ 监控脚本安装完成"
}

# 主安装函数
main() {
    check_root
    
    # 清理现有服务
    cleanup_existing
    
    # 独立获取远程端口
    get_remote_port
    
    # 独立获取代理名称
    get_proxy_name
    
    # 显示配置摘要
    show_config_summary
    
    FRP_ARCH=$(detect_architecture)
    echo "检测到系统架构: $FRP_ARCH"
    
    # 配置网络优化
    configure_network_tuning
    
    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # 下载 FRP
    echo "下载 FRP v$FRP_VERSION..."
    if ! wget -q "https://github.com/fatedier/frp/releases/download/v$FRP_VERSION/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz" -O frp.tar.gz; then
        echo "❌ FRP 下载失败，请检查网络连接和版本号"
        exit 1
    fi
    
    # 解压
    echo "解压文件..."
    tar -xzf frp.tar.gz
    cd "frp_${FRP_VERSION}_linux_${FRP_ARCH}"
    
    # 创建安装目录
    local INSTALL_DIR="/opt/frp/frp_${FRP_VERSION}_linux_${FRP_ARCH}"
    mkdir -p "$INSTALL_DIR" /etc/frp /var/log/frp
    
    # 安装二进制文件
    echo "安装 FRP 到 $INSTALL_DIR..."
    cp frpc "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/frpc"
    
    # 创建链接到PATH
    ln -sf "$INSTALL_DIR/frpc" /usr/local/bin/frpc 2>/dev/null || true
    
    # 测试二进制文件
    echo "测试 FRP 客户端..."
    if ! "$INSTALL_DIR/frpc" --version >/dev/null 2>&1; then
        echo "❌ FRP 客户端二进制文件测试失败"
        exit 1
    fi
    echo "✅ FRP 客户端二进制文件测试成功"
    
    # 创建增强的 TOML 格式配置文件
    echo "创建增强的 TOML 格式配置文件..."
    cat > /etc/frp/frpc.toml << CONFIG
serverAddr = "$SERVER_ADDR"
serverPort = $SERVER_PORT
auth.token = "$AUTH_TOKEN"

# === 增强稳定性配置 ===
# 心跳检测
transport.heartbeatInterval = 30
transport.heartbeatTimeout = 90

# TCP 保活
transport.tcpKeepalive = 7200

# 连接超时
transport.connectServerTimeout = 15
transport.dialServerTimeout = 15

# 连接池
transport.poolCount = 5

# 自动重连
transport.protocol = "tcp"
transport.tcpMux = true
transport.tcpMuxKeepaliveInterval = 60

# 日志配置
log.level = "info"
log.maxDays = 3
log.disablePrintColor = true

# === 代理配置 ===
[[proxies]]
name = "$PROXY_NAME"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = $REMOTE_PORT

# 健康检查
healthCheck.type = "tcp"
healthCheck.timeoutSeconds = 5
healthCheck.maxFailed = 3
healthCheck.intervalSeconds = 30
CONFIG

    echo "✅ 配置文件已创建"
    echo "服务器: $SERVER_ADDR:$SERVER_PORT"
    echo "远程端口: $REMOTE_PORT"
    echo "代理名称: $PROXY_NAME"
    echo "认证令牌: ${AUTH_TOKEN:0:4}****"
    echo "稳定性配置: 心跳30s/超时90s/TCP保活2h"
    
    # 创建增强的服务文件
    echo "创建系统服务..."
    cat > /etc/systemd/system/frpc.service << SERVICE
[Unit]
Description=Frp Client Service (Enhanced Stable Version)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=500
StartLimitBurst=5

[Service]
Type=simple
User=root
Restart=always
RestartSec=10s
StartLimitInterval=0
ExecStartPre=/bin/sleep 3
ExecStart=$INSTALL_DIR/frpc -c /etc/frp/frpc.toml
ExecReload=/bin/kill -HUP \$MAINPID

# 资源限制
LimitNOFILE=65536
LimitNPROC=65536
OOMScoreAdjust=-100

# 环境变量
Environment="GODEBUG=netdns=go"
Environment="GODEBUG=asyncpreemptoff=1"

# 日志配置
StandardOutput=journal
StandardError=journal
SyslogIdentifier=frpc

# 安全配置
NoNewPrivileges=true
ProtectSystem=strict
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SERVICE
    
    # 重新加载 systemd 并启动服务
    echo "启动 FRP 服务..."
    systemctl daemon-reload
    systemctl enable frpc
    
    # 创建监控脚本
    create_monitor_script
    
    # 首次启动
    echo "首次启动服务..."
    if systemctl start frpc; then
        echo "✅ FRP 客户端服务启动成功"
    else
        echo "❌ FRP 客户端服务启动失败"
        echo "=== 错误日志 ==="
        journalctl -u frpc -n 20 --no-pager
        exit 1
    fi
    
    # 等待服务状态稳定
    echo "等待服务启动..."
    for i in {1..10}; do
        if systemctl is-active --quiet frpc; then
            break
        fi
        echo -n "."
        sleep 1
    done
    echo ""
    
    # 检查服务状态
    echo "检查服务状态..."
    if systemctl is-active --quiet frpc; then
        echo "✅ FRP 客户端正在运行"
        
        # 检查进程
        FRPC_PID=$(pgrep frpc)
        echo "进程PID: $FRPC_PID"
        
        # 检查连接
        echo "检查连接状态..."
        sleep 2
        
        echo ""
        echo "=== 连接信息 ==="
        echo "您可以通过以下方式连接 SSH:"
        echo "ssh username@$SERVER_ADDR -p $REMOTE_PORT"
        echo ""
        echo "或者使用完整命令:"
        echo "ssh -o Port=$REMOTE_PORT -o ConnectTimeout=30 username@$SERVER_ADDR"
    else
        echo "❌ FRP 客户端启动失败"
        echo ""
        echo "=== 错误日志 ==="
        journalctl -u frpc --since "1 minute ago" --no-pager -l
        exit 1
    fi
    
    # 清理临时目录
    rm -rf "$TEMP_DIR"
    
    echo ""
    echo "=== 安装完成 ==="
    echo "服务端: $SERVER_ADDR:$SERVER_PORT"
    echo "远程端口: $REMOTE_PORT"
    echo "代理名称: $PROXY_NAME"
    echo "认证令牌: ${AUTH_TOKEN:0:4}****"
    echo ""
    echo "=== 稳定性特性 ==="
    echo "• 心跳检测: 30秒间隔，90秒超时"
    echo "• TCP保活: 2小时"
    echo "• 自动重连: 无限重试，10秒间隔"
    echo "• 连接池: 5个连接"
    echo "• 健康检查: TCP检查，30秒间隔"
    echo "• 监控脚本: 每2分钟检查一次"
    echo ""
    echo "=== 常用命令 ==="
    echo "查看状态: systemctl status frpc"
    echo "查看日志: journalctl -u frpc -f"
    echo "实时监控: tail -f /var/log/frp/frpc_monitor.log"
    echo "停止服务: systemctl stop frpc"
    echo "重启服务: systemctl restart frpc"
    echo "测试连接: timeout 5 telnet $SERVER_ADDR $REMOTE_PORT"
    echo ""
    echo "=== 配置文件位置 ==="
    echo "配置文件: /etc/frp/frpc.toml"
    echo "安装目录: $INSTALL_DIR"
    echo "监控脚本: /usr/local/bin/frpc_monitor.sh"
    echo "监控日志: /var/log/frp/frpc_monitor.log"
    echo ""
    echo "监控任务已添加，系统将每2分钟自动检查FRP连接状态"
    echo "如果连接断开，系统会自动尝试重启服务"
}

# 运行主函数
main "$@"
