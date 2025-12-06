#!/bin/bash

set -e  # 遇到错误立即退出

# FRP 客户端自动安装脚本 - 增强稳定版
FRP_VERSION="${1:-0.64.0}"
REMOTE_PORT="${2:-39565}"
PROXY_NAME="${3:-ssh}"

echo "开始安装 FRP 客户端 v$FRP_VERSION - 增强稳定版"

# 配置参数（必须与服务端一致）
SERVER_ADDR="67.215.246.67"  # 服务器IP
SERVER_PORT="7000"
AUTH_TOKEN="qazwsx123.0"      # 必须与服务端token一致

# 停止并清理现有服务
cleanup_existing() {
    echo "检查现有 FRP 服务..."
    
    # 停止监控服务
    if systemctl is-active --quiet frpc-monitor.timer 2>/dev/null; then
        echo "停止 FRP 监控定时器..."
        systemctl stop frpc-monitor.timer
    fi
    
    if systemctl is-active --quiet frpc-monitor.service 2>/dev/null; then
        echo "停止 FRP 监控服务..."
        systemctl stop frpc-monitor.service
    fi
    
    # 停止主服务
    if systemctl is-active --quiet frpc 2>/dev/null; then
        echo "停止运行中的 FRP 客户端服务..."
        systemctl stop frpc
        sleep 2
    fi
    
    if systemctl is-enabled --quiet frpc 2>/dev/null; then
        echo "禁用 FRP 客户端服务..."
        systemctl disable frpc
    fi
    
    # 清理监控定时器
    if systemctl is-enabled --quiet frpc-monitor.timer 2>/dev/null; then
        echo "禁用 FRP 监控定时器..."
        systemctl disable frpc-monitor.timer
    fi
    
    # 清理进程
    if pgrep frpc > /dev/null; then
        echo "发现残留的 frpc 进程，正在清理..."
        pkill -9 frpc
        sleep 1
    fi
    
    echo "现有服务清理完成"
}

# 获取远程端口参数
get_remote_port() {
    if [ -n "$REMOTE_PORT" ] && [ "$REMOTE_PORT" != "39565" ]; then
        if [[ "$REMOTE_PORT" =~ ^[0-9]+$ ]] && [ "$REMOTE_PORT" -ge 1 ] && [ "$REMOTE_PORT" -le 65535 ]; then
            echo "使用指定远程端口: $REMOTE_PORT"
            return 0
        else
            echo "错误: 端口号必须是 1-65535 之间的数字"
            exit 1
        fi
    fi
    
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

# 获取代理名称参数
get_proxy_name() {
    if [ -n "$PROXY_NAME" ] && [ "$PROXY_NAME" != "ssh" ]; then
        if [[ "$PROXY_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo "使用指定代理名称: $PROXY_NAME"
            return 0
        else
            echo "错误: 代理名称只能包含字母、数字、下划线和连字符"
            exit 1
        fi
    fi
    
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

# 端口生成函数
generate_ports() {
    echo ""
    echo "=== 端口配置生成器 ==="
    echo "可选步骤: 为批量端口映射生成配置"
    echo ""
    
    read -p "是否要生成批量端口配置？(y/N): " GEN_PORTS
    if [[ ! "$GEN_PORTS" =~ ^[Yy]$ ]]; then
        echo "跳过端口生成"
        return 0
    fi
    
    read -p "请输入起始端口 (默认: 16386): " user_start_port
    read -p "请输入生成端口数量 (默认: 200): " user_count
    
    # 设置默认值（如果用户输入为空）
    START_PORT=${user_start_port:-16386}
    COUNT=${user_count:-200}
    PORT_CONF_FILE="/etc/frp/ports.conf"
    
    # 验证输入是否为数字
    if ! [[ "$START_PORT" =~ ^[0-9]+$ ]]; then
        echo "错误: 起始端口必须是数字!"
        exit 1
    fi
    
    if ! [[ "$COUNT" =~ ^[0-9]+$ ]]; then
        echo "错误: 端口数量必须是数字!"
        exit 1
    fi
    
    # 验证端口范围
    if [ "$START_PORT" -lt 1024 ] || [ "$START_PORT" -gt 65535 ]; then
        echo "错误: 起始端口必须在 1024-65535 范围内!"
        exit 1
    fi
    
    END_PORT=$((START_PORT + COUNT - 1))
    if [ "$COUNT" -lt 1 ] || [ "$END_PORT" -gt 65535 ]; then
        echo "错误: 端口数量无效或超出可用端口范围!"
        echo "起始端口: $START_PORT, 结束端口: $END_PORT, 最大端口: 65535"
        exit 1
    fi
    
    echo ""
    echo "开始生成端口配置..."
    echo "起始端口: $START_PORT"
    echo "结束端口: $END_PORT"
    echo "生成数量: $COUNT"
    echo "输出文件: $PORT_CONF_FILE"
    echo ""
    
    # 询问用户是否继续
    read -p "确认生成配置？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消端口生成"
        return 0
    fi
    
    # 清空或创建输出文件
    echo "# 自动生成的端口配置" > "$PORT_CONF_FILE"
    echo "# 生成时间: $(date)" >> "$PORT_CONF_FILE"
    echo "# 起始端口: $START_PORT, 数量: $COUNT" >> "$PORT_CONF_FILE"
    echo "" >> "$PORT_CONF_FILE"
    
    # 生成配置
    for ((i=0; i<COUNT; i++)); do
        PORT=$((START_PORT + i))
        
        cat >> "$PORT_CONF_FILE" << EOF
[[proxies]]
name = "port_${PORT}_tcp"
type = "tcp"
localIP = "127.0.0.1"
localPort = $PORT
remotePort = $PORT

EOF
        
        # 显示进度
        if (( (i + 1) % 50 == 0 )); then
            echo "已生成 $((i + 1))/$COUNT 个配置"
        fi
    done
    
    echo ""
    echo "✅ 端口配置生成完成!"
    echo "📁 文件: $PORT_CONF_FILE"
    echo "📊 大小: $(du -h "$PORT_CONF_FILE" | cut -f1)"
    echo "📈 行数: $(wc -l < "$PORT_CONF_FILE")"
    
    # 询问是否将端口配置合并到主配置文件
    read -p "是否将端口配置合并到主配置文件？(Y/n): " MERGE_CONFIRM
    MERGE_CONFIRM=${MERGE_CONFIRM:-Y}
    
    if [[ "$MERGE_CONFIRM" =~ ^[Yy]$ ]]; then
        echo "合并端口配置到主配置文件..."
        
        # 备份原配置文件
        cp /etc/frp/frpc.toml /etc/frp/frpc.toml.backup.$(date +%s)
        
        # 合并配置
        {
            echo "# ===== FRP 客户端主配置 ====="
            echo "# 生成时间: $(date)"
            echo "# 主机名: $(hostname)"
            echo ""
            echo "serverAddr = \"$SERVER_ADDR\""
            echo "serverPort = $SERVER_PORT"
            echo "auth.token = \"$AUTH_TOKEN\""
            echo ""
            echo "# ===== 连接优化参数 ====="
            echo "transport.protocol = \"tcp\""
            echo "transport.tcpMux = true"
            echo "transport.tcpMuxKeepaliveInterval = 60"
            echo "transport.heartbeatInterval = 30"
            echo "transport.heartbeatTimeout = 90"
            echo "transport.loginFailExit = false"
            echo "transport.maxPoolCount = 5"
            echo "transport.dialServerTimeout = 10"
            echo "transport.dialServerKeepAlive = 7200"
            echo ""
            echo "# ===== SSH 主连接 ====="
            echo "[[proxies]]"
            echo "name = \"$PROXY_NAME\""
            echo "type = \"tcp\""
            echo "localIP = \"127.0.0.1\""
            echo "localPort = 22"
            echo "remotePort = $REMOTE_PORT"
            echo ""
            echo "# ===== 批量端口映射 (共 $COUNT 个) ====="
            cat "$PORT_CONF_FILE"
        } > /etc/frp/frpc.toml
        
        echo "✅ 端口配置已合并到 /etc/frp/frpc.toml"
    else
        echo "端口配置保存为独立文件: $PORT_CONF_FILE"
        echo "您可以手动将其内容添加到 /etc/frp/frpc.toml 文件中"
    fi
}

# 安装监控脚本
install_monitoring() {
    echo ""
    echo "=== 安装监控系统 ==="
    
    # 创建监控脚本
    cat > /usr/local/bin/frpc-monitor.sh << 'MONITOR_SCRIPT'
#!/bin/bash
# FRP客户端监控脚本 - 增强版
# 自动检测连接状态并在异常时重启服务

SERVER_ADDR="67.215.246.67"
SERVER_PORT="7000"
REMOTE_PORT="${1:-39565}"
LOG_FILE="/var/log/frpc-monitor.log"
MAX_RETRIES=3
RETRY_DELAY=30
PROXY_NAME="ssh_$(hostname)"

# Telegram通知配置（可选）
TG_BOT_TOKEN=""
TG_CHAT_ID=""
TG_ENABLE=false

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp [$level] - $message" | tee -a "$LOG_FILE"
    
    # 同时输出到systemd journal
    logger -t "frpc-monitor" "[$level] $message"
}

check_connection() {
    local check_type="$1"
    
    case "$check_type" in
        "process")
            # 检查frpc进程是否存在
            if ! pgrep -f "frpc.*toml" > /dev/null; then
                log "ERROR" "FRPC进程不存在"
                return 1
            fi
            log "INFO" "FRPC进程运行正常"
            return 0
            ;;
            
        "server")
            # 检查是否能连接服务器
            if ! timeout 8 bash -c "cat < /dev/null > /dev/tcp/$SERVER_ADDR/$SERVER_PORT" 2>/dev/null; then
                log "ERROR" "无法连接到FRP服务器 $SERVER_ADDR:$SERVER_PORT"
                return 1
            fi
            log "INFO" "FRP服务器连接正常"
            return 0
            ;;
            
        "tunnel")
            # 检查隧道状态（通过检查本地端口）
            if ss -ltn | grep -q ":$REMOTE_PORT "; then
                log "INFO" "隧道端口 $REMOTE_PORT 监听正常"
                return 0
            else
                log "WARN" "隧道端口 $REMOTE_PORT 未监听"
                return 1
            fi
            ;;
            
        "service")
            # 检查systemd服务状态
            if systemctl is-active --quiet frpc; then
                log "INFO" "FRPC systemd服务状态: 运行中"
                return 0
            else
                log "ERROR" "FRPC systemd服务状态: 停止"
                return 1
            fi
            ;;
    esac
}

check_resources() {
    # 检查系统资源
    local pid=$(pgrep -f "frpc.*toml")
    
    if [ -n "$pid" ]; then
        # 检查内存使用
        local mem_usage=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print $1/1024 "MB"}')
        local cpu_usage=$(ps -o %cpu= -p "$pid" 2>/dev/null)
        
        log "INFO" "FRPC资源使用 - 内存: ${mem_usage:-N/A}, CPU: ${cpu_usage:-N/A}%"
        
        # 如果内存使用超过500MB，记录警告
        if [ -n "$mem_usage" ] && [ "${mem_usage%MB}" -gt 500 ]; then
            log "WARN" "FRPC内存使用较高: $mem_usage"
        fi
    fi
}

restart_service() {
    local reason="$1"
    log "WARN" "尝试重启FRPC服务 - 原因: $reason"
    
    # 发送重启通知
    send_notification "FRPC服务重启" "原因: $reason"
    
    for i in $(seq 1 $MAX_RETRIES); do
        log "INFO" "重启尝试 $i/$MAX_RETRIES"
        
        # 先优雅停止
        systemctl stop frpc
        sleep 3
        
        # 确保进程已停止
        if pgrep -f "frpc.*toml" > /dev/null; then
            log "WARN" "强制终止残留进程"
            pkill -9 frpc
            sleep 2
        fi
        
        # 启动服务
        systemctl start frpc
        sleep 10  # 给服务足够的时间启动
        
        # 检查启动结果
        if systemctl is-active --quiet frpc; then
            log "INFO" "FRPC服务重启成功 (尝试 $i/$MAX_RETRIES)"
            
            # 等待连接建立
            sleep 5
            
            # 验证连接
            if check_connection "server" && check_connection "tunnel"; then
                log "INFO" "FRPC连接验证成功"
                send_notification "FRPC重启成功" "第${i}次尝试成功，连接已恢复"
                return 0
            else
                log "WARN" "FRPC服务已启动但连接未建立"
            fi
        else
            log "ERROR" "FRPC服务启动失败"
            systemctl status frpc --no-pager | tail -20 >> "$LOG_FILE"
        fi
        
        if [ $i -lt $MAX_RETRIES ]; then
            log "INFO" "等待 ${RETRY_DELAY}秒后重试..."
            sleep $RETRY_DELAY
        fi
    done
    
    log "ERROR" "FRPC服务重启失败，已达到最大重试次数"
    send_notification "FRPC重启失败" "已尝试$MAX_RETRIES次均失败，需要手动检查"
    return 1
}

send_notification() {
    local subject="$1"
    local message="$2"
    
    if [ "$TG_ENABLE" = true ] && [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
        local full_message="[FRPC监控] $subject%0A$message%0A主机: $(hostname)%0A时间: $(date '+%Y-%m-%d %H:%M:%S')"
        
        curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TG_CHAT_ID}" \
            -d "text=${full_message}" \
            -d "parse_mode=HTML" \
            --max-time 10 >/dev/null 2>&1 &
    fi
    
    # 也可以发送到本地syslog
    logger -t "frpc-alert" "$subject - $message"
}

cleanup_logs() {
    # 清理过大的日志文件
    local max_size_mb=50
    local log_size=$(du -m "$LOG_FILE" 2>/dev/null | cut -f1)
    
    if [ -n "$log_size" ] && [ "$log_size" -gt "$max_size_mb" ]; then
        log "INFO" "日志文件过大(${log_size}MB)，进行轮转"
        mv "$LOG_FILE" "${LOG_FILE}.old"
        touch "$LOG_FILE"
        gzip "${LOG_FILE}.old" &
    fi
}

main() {
    log "INFO" "=== FRPC健康检查开始 ==="
    
    # 清理日志
    cleanup_logs
    
    # 检查进程状态
    if ! check_connection "process"; then
        restart_service "进程不存在"
        exit 0
    fi
    
    # 检查服务状态
    if ! check_connection "service"; then
        restart_service "systemd服务停止"
        exit 0
    fi
    
    # 检查服务器连接
    if ! check_connection "server"; then
        restart_service "服务器连接失败"
        exit 0
    fi
    
    # 检查隧道状态
    if ! check_connection "tunnel"; then
        restart_service "隧道连接异常"
        exit 0
    fi
    
    # 检查资源使用
    check_resources
    
    log "INFO" "=== FRPC健康检查完成 - 所有检查正常 ==="
}

# 运行主函数
main "$@"
MONITOR_SCRIPT
    
    chmod +x /usr/local/bin/frpc-monitor.sh
    
    # 创建监控服务文件
    cat > /etc/systemd/system/frpc-monitor.service << 'MONITOR_SERVICE'
[Unit]
Description=FRPC健康检查服务
After=frpc.service
Requires=frpc.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/frpc-monitor.sh
User=root

# 资源限制
LimitNOFILE=4096
LimitNPROC=256

# 安全配置
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadOnlyPaths=/

# 超时设置
TimeoutStartSec=120
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
MONITOR_SERVICE
    
    # 创建监控定时器
    cat > /etc/systemd/system/frpc-monitor.timer << 'MONITOR_TIMER'
[Unit]
Description=FRPC监控定时器 - 每5分钟检查一次
Requires=frpc.service

[Timer]
OnCalendar=*:0/5
Persistent=true
RandomizedDelaySec=60
AccuracySec=1min

# 在系统启动后5分钟开始
OnBootSec=5min

[Install]
WantedBy=timers.target
MONITOR_TIMER
    
    # 启用并启动监控定时器
    systemctl daemon-reload
    systemctl enable frpc-monitor.timer
    systemctl start frpc-monitor.timer
    
    echo "✅ 监控系统安装完成"
    echo "   - 监控脚本: /usr/local/bin/frpc-monitor.sh"
    echo "   - 日志文件: /var/log/frpc-monitor.log"
    echo "   - 检查频率: 每5分钟一次"
    echo "   - 随机延迟: 60秒（避免所有客户端同时检查）"
}

# 配置日志轮转
setup_logrotate() {
    echo ""
    echo "=== 配置日志轮转 ==="
    
    cat > /etc/logrotate.d/frpc << 'LOGROTATE'
# FRP客户端日志轮转
/var/log/frpc*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    sharedscripts
    postrotate
        # 重新打开日志文件句柄
        systemctl kill -s HUP frpc 2>/dev/null || true
    endscript
}

# FRP监控日志轮转
/var/log/frpc-monitor.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
LOGROTATE
    
    echo "✅ 日志轮转配置完成"
    echo "   - FRP日志: 每天轮转，保留7天"
    echo "   - 监控日志: 每周轮转，保留4周"
}

# 优化系统配置
optimize_system() {
    echo ""
    echo "=== 优化系统配置 ==="
    
    # 增加文件描述符限制
    if ! grep -q "frpc limits" /etc/security/limits.conf; then
        cat >> /etc/security/limits.conf << LIMITS
# FRP客户端文件描述符限制
* soft nofile 65536
* hard nofile 65536
root soft nofile 65536
root hard nofile 65536
LIMITS
        echo "✅ 文件描述符限制已增加"
    fi
    
    # 优化TCP参数（可选）
    if [ -f /etc/sysctl.d/99-frpc-optimize.conf ]; then
        echo "TCP优化配置已存在，跳过"
    else
        cat > /etc/sysctl.d/99-frpc-optimize.conf << SYSCTL
# FRP客户端TCP优化
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
SYSCTL
        sysctl -p /etc/sysctl.d/99-frpc-optimize.conf 2>/dev/null || true
        echo "✅ TCP优化配置已添加"
    fi
    
    echo "系统优化完成"
}

# 安装增强版FRP服务
install_enhanced_frpc_service() {
    echo ""
    echo "=== 安装增强版FRP服务 ==="
    
    FRP_ARCH=$(detect_architecture)
    INSTALL_DIR="/opt/frp/frp_${FRP_VERSION}_linux_${FRP_ARCH}"
    
    cat > /etc/systemd/system/frpc.service << ENHANCED_SERVICE
[Unit]
Description=Frp Client Service - Enhanced Stability v2.0
After=network.target nss-lookup.target
Wants=network.target
Before=frpc-monitor.service

[Service]
Type=simple
User=root

# ===== 增强稳定性配置 =====
Restart=always
RestartSec=10
StartLimitInterval=0
StartLimitBurst=0

# 优雅停止配置
TimeoutStopSec=30
KillMode=mixed
KillSignal=SIGTERM
SendSIGKILL=yes
SendSIGKILL=after=30s

# 执行命令
ExecStart=$INSTALL_DIR/frpc -c /etc/frp/frpc.toml
ExecReload=/bin/kill -HUP \$MAINPID

# 预启动检查
ExecStartPre=/bin/sleep 3
ExecStartPre=/bin/bash -c 'for i in {1..5}; do ping -c 1 -W 2 $SERVER_ADDR >/dev/null 2>&1 && break || sleep 2; done'

# 启动后验证
ExecStartPost=/bin/sleep 5
ExecStartPost=/bin/bash -c 'systemctl is-active --quiet frpc && echo "FRPC启动成功" || echo "FRPC启动失败"'

# 资源限制
LimitNOFILE=65536
LimitNPROC=512
LimitCORE=infinity

# 环境变量
Environment="GODEBUG=netdns=go"
Environment="FRP_LOG_LEVEL=info"
Environment="FRP_LOG_MAX_DAYS=3"

# 安全配置
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/etc/frp /var/log
ReadOnlyPaths=/
InaccessiblePaths=/boot /lost+found

# 日志配置
StandardOutput=journal
StandardError=journal
SyslogIdentifier=frpc
LogLevelMax=debug

# 工作目录
WorkingDirectory=/etc/frp

[Install]
WantedBy=multi-user.target
Also=frpc-monitor.timer
ENHANCED_SERVICE
    
    systemctl daemon-reload
    echo "✅ 增强版FRP服务配置完成"
}

# 显示安装总结
show_installation_summary() {
    echo ""
    echo "================================================"
    echo "✅ FRP客户端增强版安装完成！"
    echo "================================================"
    echo ""
    echo "=== 核心配置 ==="
    echo "服务器地址: $SERVER_ADDR:$SERVER_PORT"
    echo "远程端口: $REMOTE_PORT"
    echo "代理名称: $PROXY_NAME"
    echo "认证令牌: ${AUTH_TOKEN:0:4}****"
    echo ""
    
    echo "=== 稳定性特性 ==="
    echo "1. 主服务自动重启 (Restart=always)"
    echo "2. 智能监控系统 (每5分钟检查)"
    echo "3. 多层健康检查 (进程/服务/连接/隧道)"
    echo "4. 智能重试机制 (最多3次，30秒间隔)"
    echo "5. 资源使用监控 (内存/CPU)"
    echo "6. 日志轮转管理 (自动清理)"
    echo ""
    
    echo "=== 监控系统 ==="
    echo "• 监控脚本: /usr/local/bin/frpc-monitor.sh"
    echo "• 监控日志: /var/log/frpc-monitor.log"
    echo "• 检查频率: 每5分钟自动运行"
    echo "• 检查内容: 进程状态、服务状态、服务器连接、隧道状态"
    echo ""
    
    echo "=== 文件位置 ==="
    echo "主配置文件: /etc/frp/frpc.toml"
    echo "端口配置文件: /etc/frp/ports.conf"
    echo "安装目录: /opt/frp/frp_${FRP_VERSION}_linux_${FRP_ARCH}"
    echo "监控配置: /etc/systemd/system/frpc-monitor.*"
    echo ""
    
    if [ -f "/etc/frp/ports.conf" ]; then
        PORT_COUNT=$(grep -c "^\[\[proxies\]\]" /etc/frp/ports.conf)
        echo "=== 端口统计 ==="
        echo "批量端口数量: $PORT_COUNT"
        echo "起始端口: $START_PORT"
        echo "结束端口: $END_PORT"
        echo ""
    fi
    
    echo "=== 常用命令 ==="
    echo "查看主服务状态: systemctl status frpc"
    echo "查看监控状态: systemctl status frpc-monitor.timer"
    echo "查看实时日志: journalctl -u frpc -f"
    echo "查看监控日志: tail -f /var/log/frpc-monitor.log"
    echo "手动运行监控: /usr/local/bin/frpc-monitor.sh"
    echo "重启服务: systemctl restart frpc"
    echo "停止所有: systemctl stop frpc frpc-monitor.timer"
    echo ""
    
    echo "=== 连接测试 ==="
    echo "SSH连接命令:"
    echo "  ssh username@$SERVER_ADDR -p $REMOTE_PORT"
    echo "  ssh -o Port=$REMOTE_PORT username@$SERVER_ADDR"
    echo ""
    echo "端口测试:"
    echo "  nc -zv $SERVER_ADDR $REMOTE_PORT"
    echo ""
    
    echo "=== 故障排除 ==="
    echo "1. 查看详细日志: journalctl -u frpc --since '1 hour ago' -l"
    echo "2. 检查连接状态: ss -tlnp | grep frpc"
    echo "3. 手动测试连接: timeout 5 nc -z $SERVER_ADDR $SERVER_PORT"
    echo "4. 检查监控日志: cat /var/log/frpc-monitor.log | tail -20"
    echo ""
    
    echo "监控系统将在5分钟后开始自动运行"
    echo "如需立即测试监控，运行: /usr/local/bin/frpc-monitor.sh"
    echo "================================================"
}

# 主安装函数
main() {
    check_root
    
    echo "================================================"
    echo "FRP客户端增强版安装程序"
    echo "版本: $FRP_VERSION"
    echo "包含: 主服务 + 智能监控 + 日志管理"
    echo "================================================"
    
    # 清理现有服务
    cleanup_existing
    
    # 获取配置参数
    get_remote_port
    get_proxy_name
    show_config_summary
    
    FRP_ARCH=$(detect_architecture)
    echo "检测到系统架构: $FRP_ARCH"
    
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
    mkdir -p "$INSTALL_DIR" /etc/frp /var/log
    
    # 安装二进制文件
    echo "安装 FRP 到 $INSTALL_DIR..."
    cp frpc "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/frpc"
    
    # 测试二进制文件
    echo "测试 FRP 客户端..."
    if ! "$INSTALL_DIR/frpc" --version >/dev/null 2>&1; then
        echo "❌ FRP 客户端二进制文件测试失败"
        exit 1
    fi
    echo "✅ FRP 客户端二进制文件测试成功"
    
    # 创建优化版TOML配置文件
    echo "创建优化版配置文件..."
    cat > /etc/frp/frpc.toml << CONFIG
# ===== FRP 客户端主配置 =====
# 生成时间: $(date)
# 主机名: $(hostname)

serverAddr = "$SERVER_ADDR"
serverPort = $SERVER_PORT
auth.token = "$AUTH_TOKEN"

# ===== 连接优化参数 =====
transport.protocol = "tcp"
transport.tcpMux = true
transport.tcpMuxKeepaliveInterval = 60
transport.heartbeatInterval = 30
transport.heartbeatTimeout = 90
transport.loginFailExit = false
transport.maxPoolCount = 5
transport.dialServerTimeout = 10
transport.dialServerKeepAlive = 7200
transport.poolCount = 1

# ===== SSH 主连接 =====
[[proxies]]
name = "$PROXY_NAME"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = $REMOTE_PORT
CONFIG

    echo "✅ 优化版配置文件已创建"
    
    # 安装增强版服务
    install_enhanced_frpc_service
    
    # 启动服务
    echo "启动 FRP 服务..."
    systemctl daemon-reload
    systemctl enable frpc
    
    if systemctl start frpc; then
        echo "✅ FRP 客户端服务启动成功"
    else
        echo "❌ FRP 客户端服务启动失败"
        journalctl -u frpc -n 20 --no-pager
        exit 1
    fi
    
    # 等待服务启动
    echo "等待服务初始化..."
    sleep 5
    
    # 检查服务状态
    echo "验证服务状态..."
    if systemctl is-active --quiet frpc; then
        echo "✅ FRP 客户端正在运行"
        
        # 测试连接
        echo "测试服务器连接..."
        if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$SERVER_ADDR/$SERVER_PORT" 2>/dev/null; then
            echo "✅ 服务器连接正常"
        else
            echo "⚠️  服务器连接测试失败，但服务正在运行"
        fi
    else
        echo "❌ FRP 客户端启动失败"
        journalctl -u frpc --since "1 minute ago" --no-pager -l
        exit 1
    fi
    
    # 可选：生成端口配置
    generate_ports
    
    # 安装监控系统
    install_monitoring
    
    # 配置日志轮转
    setup_logrotate
    
    # 优化系统配置
    optimize_system
    
    # 清理临时目录
    rm -rf "$TEMP_DIR"
    
    # 显示安装总结
    show_installation_summary
    
    # 最终状态检查
    echo ""
    echo "=== 最终状态检查 ==="
    systemctl status frpc --no-pager | head -10
    echo ""
    systemctl status frpc-monitor.timer --no-pager | head -5
    echo ""
    echo "安装完成！系统将在5分钟后开始自动监控。"
}

# 运行主函数
main "$@"
