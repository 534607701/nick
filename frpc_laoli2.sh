#!/bin/bash

set -e  # 遇到错误立即退出

# FRP 客户端自动安装脚本 - 增强稳定版 (兼容 0.64.0)
FRP_VERSION="${1:-0.64.0}"
DEFAULT_REMOTE_PORT="${2:-39565}"
DEFAULT_PROXY_NAME="${3:-ssh}"

echo "开始安装 FRP 客户端 v$FRP_VERSION - 增强稳定版"

# 配置参数（必须与服务端一致）
SERVER_ADDR="45.77.214.165"  # 服务器IP
SERVER_PORT="7000"
AUTH_TOKEN="qazwsx123.0"      # 必须与服务端token一致

# 设置执行权限
set_permissions() {
    echo "设置执行权限..."
    chmod +x /usr/local/bin/frpc-monitor.sh 2>/dev/null || true
    chmod +x /opt/frp/frp_*/frpc 2>/dev/null || true
    chmod 755 /etc/frp /opt/frp 2>/dev/null || true
}

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

# 获取SSH远程端口参数
get_ssh_port() {
    if [ -n "$DEFAULT_REMOTE_PORT" ] && [ "$DEFAULT_REMOTE_PORT" != "39565" ]; then
        SSH_REMOTE_PORT=$DEFAULT_REMOTE_PORT
        echo "使用指定SSH远程端口: $SSH_REMOTE_PORT"
        return 0
    fi
    
    while true; do
        read -p "请输入SSH远程端口号 (默认: 39565): " INPUT_PORT
        INPUT_PORT=${INPUT_PORT:-39565}
        if [[ "$INPUT_PORT" =~ ^[0-9]+$ ]] && [ "$INPUT_PORT" -ge 1 ] && [ "$INPUT_PORT" -le 65535 ]; then
            SSH_REMOTE_PORT=$INPUT_PORT
            break
        else
            echo "错误: 端口号必须是 1-65535 之间的数字"
        fi
    done
}

# 获取SSH代理名称参数
get_ssh_name() {
    if [ -n "$DEFAULT_PROXY_NAME" ] && [ "$DEFAULT_PROXY_NAME" != "ssh" ]; then
        SSH_PROXY_NAME=$DEFAULT_PROXY_NAME
        echo "使用指定SSH代理名称: $SSH_PROXY_NAME"
        return 0
    fi
    
    while true; do
        read -p "请输入SSH代理名称 (默认: ssh_$(hostname)): " INPUT_NAME
        INPUT_NAME=${INPUT_NAME:-"ssh_$(hostname)"}
        if [[ "$INPUT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            SSH_PROXY_NAME=$INPUT_NAME
            break
        else
            echo "错误: 代理名称只能包含字母、数字、下划线和连字符"
        fi
    done
}

# 获取批量端口配置
get_bulk_ports_config() {
    echo ""
    echo "=== 批量端口配置设置 ==="
    
    read -p "是否配置批量端口映射？(Y/n): " CONFIG_BULK
    CONFIG_BULK=${CONFIG_BULK:-Y}
    
    if [[ ! "$CONFIG_BULK" =~ ^[Yy]$ ]]; then
        echo "跳过批量端口配置"
        BULK_ENABLED=false
        return 0
    fi
    
    BULK_ENABLED=true
    
    # 获取起始端口
    while true; do
        read -p "请输入批量端口起始端口号 (建议: 16386): " BULK_START_PORT
        BULK_START_PORT=${BULK_START_PORT:-16386}
        if [[ "$BULK_START_PORT" =~ ^[0-9]+$ ]] && [ "$BULK_START_PORT" -ge 1024 ] && [ "$BULK_START_PORT" -le 65535 ]; then
            break
        else
            echo "错误: 起始端口必须是 1024-65535 之间的数字"
        fi
    done
    
    # 获取端口数量
    while true; do
        read -p "请输入批量端口数量 (建议: 200): " BULK_COUNT
        BULK_COUNT=${BULK_COUNT:-200}
        if [[ "$BULK_COUNT" =~ ^[0-9]+$ ]] && [ "$BULK_COUNT" -ge 1 ] && [ "$BULK_COUNT" -le 1000 ]; then
            BULK_END_PORT=$((BULK_START_PORT + BULK_COUNT - 1))
            if [ "$BULK_END_PORT" -le 65535 ]; then
                break
            else
                echo "错误: 结束端口 $BULK_END_PORT 超出范围 (最大65535)"
            fi
        else
            echo "错误: 端口数量必须是 1-1000 之间的数字"
        fi
    done
    
    echo ""
    echo "批量端口配置确认:"
    echo "起始端口: $BULK_START_PORT"
    echo "端口数量: $BULK_COUNT"
    echo "结束端口: $BULK_END_PORT"
    echo ""
}

# 显示配置摘要
show_config_summary() {
    echo ""
    echo "================ 配置确认 ================="
    echo "服务器地址: $SERVER_ADDR"
    echo "服务器端口: $SERVER_PORT"
    echo "认证令牌: ${AUTH_TOKEN:0:4}****"
    echo ""
    echo "=== SSH 配置 ==="
    echo "SSH远程端口: $SSH_REMOTE_PORT"
    echo "SSH代理名称: $SSH_PROXY_NAME"
    echo ""
    
    if [ "$BULK_ENABLED" = true ]; then
        echo "=== 批量端口配置 ==="
        echo "起始端口: $BULK_START_PORT"
        echo "端口数量: $BULK_COUNT"
        echo "结束端口: $BULK_END_PORT"
        echo ""
    else
        echo "=== 批量端口配置: 禁用 ==="
        echo ""
    fi
    
    echo "总代理数量: $((1 + ${BULK_COUNT:-0}))"
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

# 生成并合并端口配置
generate_and_merge_ports() {
    echo ""
    echo "=== 生成配置文件 ==="
    
    PORT_CONF_FILE="/etc/frp/ports.conf"
    
    # 创建主配置文件（包含SSH配置）
    {
        echo "# ===== FRP 客户端配置 - FRP v$FRP_VERSION ====="
        echo "# 生成时间: $(date)"
        echo "# 主机名: $(hostname)"
        echo ""
        echo "serverAddr = \"$SERVER_ADDR\""
        echo "serverPort = $SERVER_PORT"
        echo "auth.token = \"$AUTH_TOKEN\""
        echo ""
        echo "# ===== SSH 主连接 ====="
        echo "[[proxies]]"
        echo "name = \"$SSH_PROXY_NAME\""
        echo "type = \"tcp\""
        echo "localIP = \"127.0.0.1\""
        echo "localPort = 22"
        echo "remotePort = $SSH_REMOTE_PORT"
        echo ""
    } > /etc/frp/frpc.toml
    
    if [ "$BULK_ENABLED" = true ]; then
        echo "开始生成批量端口配置..."
        
        # 生成端口配置文件
        {
            echo "# 批量端口配置"
            echo "# 生成时间: $(date)"
            echo "# 起始端口: $BULK_START_PORT, 数量: $BULK_COUNT"
            echo "# 注意: 这些端口需要本地有服务监听才能正常工作"
            echo ""
        } > "$PORT_CONF_FILE"
        
        # 在主配置文件中添加批量端口配置标题
        {
            echo "# ===== 批量端口映射 (共 $BULK_COUNT 个) ====="
            echo "# 注意: 这些端口需要本地有服务监听才能正常工作"
            echo ""
        } >> /etc/frp/frpc.toml
        
        # 生成并追加端口配置
        for ((i=0; i<BULK_COUNT; i++)); do
            PORT=$((BULK_START_PORT + i))
            
            # 写入端口配置文件
            echo "# 端口: $PORT" >> "$PORT_CONF_FILE"
            echo "[[proxies]]" >> "$PORT_CONF_FILE"
            echo "name = \"port_${PORT}_tcp\"" >> "$PORT_CONF_FILE"
            echo "type = \"tcp\"" >> "$PORT_CONF_FILE"
            echo "localIP = \"127.0.0.1\"" >> "$PORT_CONF_FILE"
            echo "localPort = $PORT" >> "$PORT_CONF_FILE"
            echo "remotePort = $PORT" >> "$PORT_CONF_FILE"
            echo "" >> "$PORT_CONF_FILE"
            
            # 写入主配置文件
            echo "[[proxies]]" >> /etc/frp/frpc.toml
            echo "name = \"port_${PORT}_tcp\"" >> /etc/frp/frpc.toml
            echo "type = \"tcp\"" >> /etc/frp/frpc.toml
            echo "localIP = \"127.0.0.1\"" >> /etc/frp/frpc.toml
            echo "localPort = $PORT" >> /etc/frp/frpc.toml
            echo "remotePort = $PORT" >> /etc/frp/frpc.toml
            echo "" >> /etc/frp/frpc.toml
            
            # 显示进度
            if [ "$BULK_COUNT" -gt 50 ] && (( (i + 1) % 50 == 0 )); then
                echo "已生成 $((i + 1))/$BULK_COUNT 个端口配置"
            fi
        done
        
        echo ""
        echo "✅ 批量端口配置生成完成!"
        echo "📁 主配置文件: /etc/frp/frpc.toml"
        echo "📁 端口配置文件: $PORT_CONF_FILE"
        echo "📊 总代理数量: $((1 + BULK_COUNT)) (SSH + 批量端口)"
        echo "📈 端口范围: $BULK_START_PORT - $BULK_END_PORT"
        echo ""
        echo "⚠️  注意: 批量端口需要本地有服务监听才能正常工作"
    else
        echo "仅配置SSH连接，不包含批量端口"
        echo "📁 主配置文件: /etc/frp/frpc.toml"
        echo "📊 总代理数量: 1 (仅SSH)"
    fi
}

# 安装监控脚本
install_monitoring() {
    echo ""
    echo "=== 安装监控系统 ==="
    
    # 创建监控脚本目录
    mkdir -p /usr/local/bin
    
    # 创建监控脚本
    cat > /usr/local/bin/frpc-monitor.sh << 'MONITOR_SCRIPT'
#!/bin/bash
# FRP客户端监控脚本 - 增强稳定版

SERVER_ADDR="45.77.214.165"
SERVER_PORT="7000"
SSH_REMOTE_PORT="39565"
LOG_FILE="/var/log/frpc-monitor.log"
MAX_RETRIES=3
RETRY_DELAY=30

# 从配置文件读取SSH端口
if [ -f "/etc/frp/frpc.toml" ]; then
    SSH_REMOTE_PORT=$(grep -A 2 "name = \"ssh_" /etc/frp/frpc.toml | grep "remotePort" | grep -o '[0-9]\+' | head -1)
    SSH_REMOTE_PORT=${SSH_REMOTE_PORT:-39565}
fi

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp [$level] - $message" | tee -a "$LOG_FILE"
}

check_frpc() {
    # 检查进程
    if ! pgrep -f "frpc.*toml" > /dev/null; then
        log "ERROR" "FRPC进程不存在"
        return 1
    fi
    
    # 检查服务状态
    if ! systemctl is-active --quiet frpc; then
        log "ERROR" "FRPC服务未运行"
        return 1
    fi
    
    # 检查连接
    if ! timeout 10 nc -z "$SERVER_ADDR" "$SERVER_PORT" 2>/dev/null; then
        log "WARNING" "无法连接到FRP服务器"
        return 2
    fi
    
    log "INFO" "FRPC状态正常"
    return 0
}

restart_frpc() {
    local reason="$1"
    log "WARNING" "尝试重启FRPC服务 - 原因: $reason"
    
    for i in $(seq 1 $MAX_RETRIES); do
        log "INFO" "重启尝试 $i/$MAX_RETRIES"
        
        # 停止服务
        systemctl stop frpc
        sleep 3
        
        # 确保进程停止
        if pgrep -f "frpc.*toml" > /dev/null; then
            pkill -9 frpc
            sleep 2
        fi
        
        # 启动服务
        systemctl start frpc
        sleep 8
        
        # 检查启动结果
        if systemctl is-active --quiet frpc; then
            log "INFO" "FRPC服务重启成功 (尝试 $i/$MAX_RETRIES)"
            
            # 等待连接建立
            sleep 3
            
            # 验证连接
            if timeout 5 nc -z "$SERVER_ADDR" "$SERVER_PORT" 2>/dev/null; then
                log "INFO" "FRPC连接验证成功"
                return 0
            else
                log "WARNING" "FRPC服务已启动但连接未建立"
            fi
        else
            log "ERROR" "FRPC服务启动失败"
        fi
        
        if [ $i -lt $MAX_RETRIES ]; then
            log "INFO" "等待 ${RETRY_DELAY}秒后重试..."
            sleep $RETRY_DELAY
        fi
    done
    
    log "ERROR" "FRPC服务重启失败，已达到最大重试次数"
    return 1
}

main() {
    log "INFO" "=== FRPC健康检查开始 ==="
    
    # 检查FRPC状态
    check_result=$(check_frpc)
    case $? in
        0)
            # 状态正常，无需操作
            ;;
        1)
            # 进程或服务异常，重启
            restart_frpc "进程/服务异常"
            ;;
        2)
            # 连接问题，但进程正常
            log "WARNING" "服务器连接问题，但进程正常"
            # 等待一段时间再检查
            sleep 5
            if ! timeout 5 nc -z "$SERVER_ADDR" "$SERVER_PORT" 2>/dev/null; then
                restart_frpc "持续连接失败"
            fi
            ;;
    esac
    
    # 清理过大的日志
    if [ -f "$LOG_FILE" ] && [ $(wc -l < "$LOG_FILE") -gt 1000 ]; then
        tail -500 "$LOG_FILE" > "${LOG_FILE}.tmp"
        mv "${LOG_FILE}.tmp" "$LOG_FILE"
        log "INFO" "已清理监控日志"
    fi
    
    log "INFO" "=== FRPC健康检查完成 ==="
}

# 运行主函数
main "$@"
MONITOR_SCRIPT
    
    # 设置执行权限
    chmod +x /usr/local/bin/frpc-monitor.sh
    
    # 创建监控服务文件
    cat > /etc/systemd/system/frpc-monitor.service << 'MONITOR_SERVICE'
[Unit]
Description=FRPC健康检查服务
After=frpc.service
Requires=frpc.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/frpc-monitor.sh
User=root

# 资源限制
LimitNOFILE=4096

# 安全配置
NoNewPrivileges=true
PrivateTmp=true

# 超时设置
TimeoutStartSec=120

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
RandomizedDelaySec=30

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
}

# 安装FRP服务
install_frpc_service() {
    echo ""
    echo "=== 安装FRP系统服务 ==="
    
    FRP_ARCH=$(detect_architecture)
    INSTALL_DIR="/opt/frp/frp_${FRP_VERSION}_linux_${FRP_ARCH}"
    
    # 确保安装目录存在
    mkdir -p "$INSTALL_DIR"
    
    cat > /etc/systemd/system/frpc.service << FRPC_SERVICE
[Unit]
Description=Frp Client Service v$FRP_VERSION
After=network.target
Wants=network.target

[Service]
Type=simple
User=root

# 重启策略
Restart=always
RestartSec=10
StartLimitInterval=0
StartLimitBurst=0

# 执行命令
ExecStart=$INSTALL_DIR/frpc -c /etc/frp/frpc.toml
ExecReload=/bin/kill -HUP \$MAINPID

# 资源限制
LimitNOFILE=65536

# 安全配置
NoNewPrivileges=true
PrivateTmp=true

# 工作目录
WorkingDirectory=/etc/frp

[Install]
WantedBy=multi-user.target
FRPC_SERVICE
    
    systemctl daemon-reload
    echo "✅ FRP服务配置完成"
}

# 显示安装总结
show_installation_summary() {
    echo ""
    echo "================================================"
    echo "✅ FRP客户端安装完成！"
    echo "================================================"
    echo ""
    echo "=== 核心配置 ==="
    echo "服务器地址: $SERVER_ADDR:$SERVER_PORT"
    echo "认证令牌: ${AUTH_TOKEN:0:4}****"
    echo ""
    echo "=== SSH 配置 ==="
    echo "SSH远程端口: $SSH_REMOTE_PORT"
    echo "SSH代理名称: $SSH_PROXY_NAME"
    echo ""
    
    if [ "$BULK_ENABLED" = true ]; then
        echo "=== 批量端口配置 ==="
        echo "起始端口: $BULK_START_PORT"
        echo "端口数量: $BULK_COUNT"
        echo "结束端口: $BULK_END_PORT"
        echo "总代理数量: $((1 + BULK_COUNT))"
        echo ""
    else
        echo "=== 批量端口配置: 禁用 ==="
        echo "总代理数量: 1"
        echo ""
    fi
    
    echo "=== 服务状态 ==="
    systemctl status frpc --no-pager | grep -A 2 "Active:" || echo "服务状态检查失败"
    echo ""
    
    echo "=== 文件位置 ==="
    echo "主配置文件: /etc/frp/frpc.toml"
    if [ "$BULK_ENABLED" = true ]; then
        echo "端口配置文件: /etc/frp/ports.conf"
    fi
    echo "安装目录: /opt/frp/frp_${FRP_VERSION}_linux_${FRP_ARCH}"
    echo "监控脚本: /usr/local/bin/frpc-monitor.sh"
    echo ""
    
    echo "=== 测试连接 ==="
    echo "SSH连接命令:"
    echo "  ssh username@$SERVER_ADDR -p $SSH_REMOTE_PORT"
    echo ""
    echo "端口测试:"
    echo "  nc -zv $SERVER_ADDR $SSH_REMOTE_PORT"
    echo ""
    
    if [ "$BULK_ENABLED" = true ]; then
        echo "=== 批量端口测试 ==="
        echo "测试第一个批量端口:"
        echo "  nc -zv $SERVER_ADDR $BULK_START_PORT"
        echo ""
    fi
    
    echo "=== 常用命令 ==="
    echo "查看状态: systemctl status frpc"
    echo "查看日志: journalctl -u frpc -f"
    echo "重启服务: systemctl restart frpc"
    echo "停止服务: systemctl stop frpc"
    echo "手动监控: /usr/local/bin/frpc-monitor.sh"
    echo ""
    
    echo "=== 监控系统 ==="
    echo "监控每5分钟自动运行一次"
    echo "查看监控日志: tail -f /var/log/frpc-monitor.log"
    echo ""
    
    if [ "$BULK_ENABLED" = true ]; then
        echo "⚠️  批量端口注意事项:"
        echo "1. 批量端口需要本地有服务监听才能正常工作"
        echo "2. 如不需要某些端口，可编辑 /etc/frp/frpc.toml 注释掉相关配置"
        echo "3. 端口范围: $BULK_START_PORT - $BULK_END_PORT"
        echo ""
    fi
    
    echo "================================================"
}

# 主安装函数
main() {
    check_root
    
    echo "================================================"
    echo "FRP客户端安装程序 v0.64.0"
    echo "包含: 主服务 + SSH配置 + 批量端口(可选) + 智能监控"
    echo "================================================"
    
    # 清理现有服务
    cleanup_existing
    
    # 获取SSH配置参数
    get_ssh_port
    get_ssh_name
    
    # 获取批量端口配置
    get_bulk_ports_config
    
    # 显示配置摘要
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
    
    # 设置执行权限
    chmod +x "$INSTALL_DIR/frpc"
    
    # 测试二进制文件
    echo "测试 FRP 客户端..."
    if ! "$INSTALL_DIR/frpc" --version >/dev/null 2>&1; then
        echo "❌ FRP 客户端二进制文件测试失败"
        exit 1
    fi
    echo "✅ FRP 客户端二进制文件测试成功"
    
    # 生成并合并端口配置
    generate_and_merge_ports
    
    # 设置配置文件权限
    chmod 644 /etc/frp/frpc.toml /etc/frp/ports.conf 2>/dev/null || true
    
    # 安装服务
    install_frpc_service
    
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
    
    # 等待并检查服务状态
    echo "等待服务初始化..."
    sleep 5
    
    if systemctl is-active --quiet frpc; then
        echo "✅ FRP 客户端正在运行"
        
        # 简单连接测试
        echo "测试服务器连接..."
        if timeout 5 nc -z "$SERVER_ADDR" "$SERVER_PORT" 2>/dev/null; then
            echo "✅ 服务器连接正常"
        else
            echo "⚠️  服务器连接测试失败，但服务正在运行"
        fi
    else
        echo "❌ FRP 客户端启动失败"
        journalctl -u frpc --since "1 minute ago" --no-pager -l
        exit 1
    fi
    
    # 安装监控系统
    install_monitoring
    
    # 配置日志轮转
    setup_logrotate
    
    # 清理临时目录
    rm -rf "$TEMP_DIR"
    
    # 设置所有文件权限
    set_permissions
    
    # 显示安装总结
    show_installation_summary
    
    # 最终建议
    echo ""
    echo "=== 安装后建议 ==="
    echo "1. 测试SSH连接: ssh username@$SERVER_ADDR -p $SSH_REMOTE_PORT"
    if [ "$BULK_ENABLED" = true ]; then
        echo "2. 确保本地服务监听批量端口范围: $BULK_START_PORT-$BULK_END_PORT"
        echo "3. 如不需要批量端口，可编辑配置文件后重启服务"
    fi
    echo "4. 监控系统已启用，会自动维护服务状态"
    echo ""
    echo "安装完成！"
}

# 运行主函数
main "$@"
