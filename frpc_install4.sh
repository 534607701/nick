#!/bin/bash

set -e  # 遇到错误立即退出

# FRP 客户端安装脚本 - 智能管理版
FRP_VERSION="${1:-0.64.0}"
DEFAULT_REMOTE_PORT="${2:-39565}"
DEFAULT_PROXY_NAME="${3:-ssh}"

echo "开始安装 FRP 客户端 v$FRP_VERSION - 智能管理版"

# 配置参数
SERVER_ADDR="67.215.246.67"
SERVER_PORT="7000"
AUTH_TOKEN="qazwsx123.0"

# 停止并清理现有服务
cleanup_existing() {
    echo "检查现有 FRP 服务..."
    
    for service in frpc frpc-monitor.timer frpc-monitor.service; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo "停止 $service..."
            systemctl stop "$service"
        fi
    done
    
    if pgrep frpc > /dev/null; then
        echo "清理残留进程..."
        pkill -9 frpc
        sleep 1
    fi
    
    echo "现有服务清理完成"
}

# 获取SSH配置
get_ssh_config() {
    echo ""
    echo "=== SSH 配置 ==="
    
    # SSH远程端口
    while true; do
        read -p "请输入SSH远程端口号 (默认: ${DEFAULT_REMOTE_PORT}): " SSH_PORT
        SSH_PORT=${SSH_PORT:-$DEFAULT_REMOTE_PORT}
        if [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && [ "$SSH_PORT" -ge 1 ] && [ "$SSH_PORT" -le 65535 ]; then
            break
        else
            echo "错误: 端口号必须是 1-65535 之间的数字"
        fi
    done
    
    # SSH代理名称
    while true; do
        read -p "请输入SSH代理名称 (默认: ssh_$(hostname)): " SSH_NAME
        SSH_NAME=${SSH_NAME:-"ssh_$(hostname)"}
        if [[ "$SSH_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            break
        else
            echo "错误: 代理名称只能包含字母、数字、下划线和连字符"
        fi
    done
    
    SSH_REMOTE_PORT=$SSH_PORT
    SSH_PROXY_NAME=$SSH_NAME
}

# 批量端口管理选项
get_bulk_ports_option() {
    echo ""
    echo "=== 批量端口配置选项 ==="
    echo "1. 禁用批量端口 (推荐)"
    echo "2. 启用批量端口，但使用智能连接管理"
    echo "3. 启用批量端口，包含所有端口"
    echo ""
    
    while true; do
        read -p "请选择 (1/2/3 默认:1): " BULK_OPTION
        BULK_OPTION=${BULK_OPTION:-1}
        
        case $BULK_OPTION in
            1)
                BULK_ENABLED=false
                BULK_MODE="disabled"
                echo "已选择: 禁用批量端口"
                break
                ;;
            2)
                BULK_ENABLED=true
                BULK_MODE="smart"
                echo "已选择: 启用批量端口 (智能模式)"
                break
                ;;
            3)
                BULK_ENABLED=true
                BULK_MODE="full"
                echo "已选择: 启用批量端口 (完整模式)"
                break
                ;;
            *)
                echo "无效选项，请重新选择"
                ;;
        esac
    done
}

# 获取批量端口配置
get_bulk_ports_config() {
    if [ "$BULK_ENABLED" = false ]; then
        return 0
    fi
    
    echo ""
    echo "=== 批量端口配置 ==="
    
    # 起始端口
    while true; do
        read -p "请输入起始端口 (建议: 16386, 默认: 16386): " START_PORT
        START_PORT=${START_PORT:-16386}
        if [[ "$START_PORT" =~ ^[0-9]+$ ]] && [ "$START_PORT" -ge 1024 ] && [ "$START_PORT" -le 65000 ]; then
            break
        else
            echo "错误: 起始端口必须是 1024-65000 之间的数字"
        fi
    done
    
    # 端口数量
    while true; do
        read -p "请输入端口数量 (默认: 200): " PORT_COUNT
        PORT_COUNT=${PORT_COUNT:-200}
        if [[ "$PORT_COUNT" =~ ^[0-9]+$ ]] && [ "$PORT_COUNT" -ge 1 ] && [ "$PORT_COUNT" -le 1000 ]; then
            END_PORT=$((START_PORT + PORT_COUNT - 1))
            if [ "$END_PORT" -le 65535 ]; then
                break
            else
                echo "错误: 结束端口 $END_PORT 超出范围 (最大65535)"
            fi
        else
            echo "错误: 端口数量必须是 1-1000 之间的数字"
        fi
    done
    
    BULK_START_PORT=$START_PORT
    BULK_COUNT=$PORT_COUNT
    BULK_END_PORT=$END_PORT
}

# 显示配置摘要
show_config_summary() {
    echo ""
    echo "================ 配置确认 ================="
    echo "服务器地址: $SERVER_ADDR:$SERVER_PORT"
    echo "认证令牌: ${AUTH_TOKEN:0:4}****"
    echo ""
    echo "=== SSH 配置 ==="
    echo "远程端口: $SSH_REMOTE_PORT"
    echo "代理名称: $SSH_PROXY_NAME"
    echo ""
    
    if [ "$BULK_ENABLED" = true ]; then
        echo "=== 批量端口配置 ==="
        echo "模式: $BULK_MODE"
        echo "起始端口: $BULK_START_PORT"
        echo "端口数量: $BULK_COUNT"
        echo "结束端口: $BULK_END_PORT"
        echo ""
        
        if [ "$BULK_MODE" = "smart" ]; then
            echo "⚠️  智能模式说明:"
            echo "   - 仅配置端口映射，但不主动连接"
            echo "   - 当有连接请求时才会建立隧道"
            echo "   - 减少不必要的连接错误日志"
            echo ""
        fi
    else
        echo "=== 批量端口配置: 禁用 ==="
        echo ""
    fi
    
    read -p "确认开始安装？(y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "安装已取消"
        exit 0
    fi
}

# 创建配置文件
create_config_file() {
    echo "创建配置文件..."
    
    # 基础配置
    cat > /etc/frp/frpc.toml << CONFIG
# ===== FRP 客户端配置 - FRP v$FRP_VERSION =====
# 生成时间: $(date)
# 主机名: $(hostname)
# 模式: $BULK_MODE

serverAddr = "$SERVER_ADDR"
serverPort = $SERVER_PORT
auth.token = "$AUTH_TOKEN"

# ===== SSH 主连接 =====
[[proxies]]
name = "$SSH_PROXY_NAME"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = $SSH_REMOTE_PORT
CONFIG
    
    # 批量端口配置
    if [ "$BULK_ENABLED" = true ]; then
        echo "" >> /etc/frp/frpc.toml
        echo "# ===== 批量端口映射 (共 $BULK_COUNT 个) =====" >> /etc/frp/frpc.toml
        echo "# 模式: $BULK_MODE" >> /etc/frp/frpc.toml
        echo "" >> /etc/frp/frpc.toml
        
        for ((i=0; i<BULK_COUNT; i++)); do
            PORT=$((BULK_START_PORT + i))
            
            echo "[[proxies]]" >> /etc/frp/frpc.toml
            echo "name = \"port_${PORT}_tcp\"" >> /etc/frp/frpc.toml
            echo "type = \"tcp\"" >> /etc/frp/frpc.toml
            echo "localIP = \"127.0.0.1\"" >> /etc/frp/frpc.toml
            echo "localPort = $PORT" >> /etc/frp/frpc.toml
            echo "remotePort = $PORT" >> /etc/frp/frpc.toml
            
            if [ "$BULK_MODE" = "smart" ]; then
                # 添加健康检查配置，减少错误日志
                echo "healthCheckType = \"tcp\"" >> /etc/frp/frpc.toml
                echo "healthCheckTimeoutSeconds = 3" >> /etc/frp/frpc.toml
                echo "healthCheckMaxFailed = 1" >> /etc/frp/frpc.toml
                echo "healthCheckIntervalSeconds = 10" >> /etc/frp/frpc.toml
            fi
            
            echo "" >> /etc/frp/frpc.toml
        done
    fi
    
    echo "✅ 配置文件已创建: /etc/frp/frpc.toml"
}

# 安装增强版监控
install_enhanced_monitor() {
    echo "安装监控系统..."
    
    cat > /usr/local/bin/frpc-monitor.sh << 'MONITOR_SCRIPT'
#!/bin/bash
# FRP客户端智能监控脚本

LOG_FILE="/var/log/frpc-monitor.log"
CONFIG_FILE="/etc/frp/frpc.toml"
BACKUP_DIR="/etc/frp/backups"
MAX_LOG_LINES=1000

# 创建备份目录
mkdir -p "$BACKUP_DIR"

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp [$level] - $message" | tee -a "$LOG_FILE"
}

check_service() {
    # 检查服务状态
    if ! systemctl is-active --quiet frpc; then
        log "ERROR" "FRPC服务未运行"
        return 1
    fi
    
    # 检查进程
    if ! pgrep -f "frpc.*toml" > /dev/null; then
        log "ERROR" "FRPC进程不存在"
        return 1
    fi
    
    return 0
}

check_errors() {
    # 检查最近的错误日志
    local error_count=$(journalctl -u frpc --since "5 minutes ago" 2>/dev/null | grep -c "error\|failed\|Error")
    local warn_count=$(journalctl -u frpc --since "5 minutes ago" 2>/dev/null | grep -c "warn\|Warn")
    
    if [ "$error_count" -gt 10 ]; then
        log "WARNING" "检测到大量错误日志 ($error_count 条)"
        
        # 备份当前配置
        local backup_file="${BACKUP_DIR}/frpc.toml.backup.$(date +%s)"
        cp "$CONFIG_FILE" "$backup_file"
        log "INFO" "配置文件已备份到: $backup_file"
        
        # 如果错误主要是端口连接错误，建议简化配置
        local port_errors=$(journalctl -u frpc --since "5 minutes ago" 2>/dev/null | grep -c "connect to local service")
        if [ "$port_errors" -gt 5 ]; then
            log "WARNING" "检测到大量端口连接错误，建议简化配置"
            
            # 提供简化配置选项
            if [ -f "$CONFIG_FILE" ] && [ $(grep -c "\[\[proxies\]\]" "$CONFIG_FILE") -gt 10 ]; then
                log "INFO" "当前配置有多个代理，可能包含不必要的批量端口"
            fi
        fi
        
        return 1
    fi
    
    return 0
}

cleanup_logs() {
    # 清理监控日志
    if [ -f "$LOG_FILE" ] && [ $(wc -l < "$LOG_FILE") -gt $MAX_LOG_LINES ]; then
        tail -500 "$LOG_FILE" > "${LOG_FILE}.tmp"
        mv "${LOG_FILE}.tmp" "$LOG_FILE"
        log "INFO" "已清理监控日志"
    fi
    
    # 清理旧备份文件（保留最近10个）
    find "$BACKUP_DIR" -name "*.backup.*" -type f | sort -r | tail -n +11 | xargs rm -f 2>/dev/null || true
}

restart_if_needed() {
    if ! check_service || ! check_errors; then
        log "WARNING" "检测到问题，尝试重启服务..."
        
        systemctl restart frpc
        sleep 5
        
        if systemctl is-active --quiet frpc; then
            log "INFO" "服务重启成功"
            return 0
        else
            log "ERROR" "服务重启失败"
            return 1
        fi
    fi
    
    log "INFO" "服务状态正常"
    return 0
}

main() {
    log "INFO" "=== FRPC智能监控开始 ==="
    
    # 检查服务状态
    restart_if_needed
    
    # 清理日志
    cleanup_logs
    
    # 记录资源使用情况
    local pid=$(pgrep -f "frpc.*toml")
    if [ -n "$pid" ]; then
        local mem=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{printf "%.1fMB", $1/1024}')
        local cpu=$(ps -o %cpu= -p "$pid" 2>/dev/null | awk '{printf "%.1f%%", $1}')
        log "INFO" "资源使用 - PID: $pid, 内存: $mem, CPU: $cpu"
    fi
    
    log "INFO" "=== FRPC智能监控完成 ==="
}

# 运行主函数
main "$@"
MONITOR_SCRIPT
    
    chmod +x /usr/local/bin/frpc-monitor.sh
    
    # 创建监控定时器
    cat > /etc/systemd/system/frpc-monitor.timer << 'TIMER'
[Unit]
Description=FRPC智能监控定时器
Requires=frpc.service

[Timer]
OnCalendar=*:0/5
Persistent=true
RandomizedDelaySec=60

[Install]
WantedBy=timers.target
TIMER
    
    cat > /etc/systemd/system/frpc-monitor.service << 'SERVICE'
[Unit]
Description=FRPC智能监控服务
After=frpc.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/frpc-monitor.sh
User=root

[Install]
WantedBy=multi-user.target
SERVICE
    
    systemctl daemon-reload
    systemctl enable frpc-monitor.timer
    systemctl start frpc-monitor.timer
    
    echo "✅ 智能监控系统安装完成"
}

# 主安装函数
main() {
    echo "================================================"
    echo "FRP客户端智能安装程序"
    echo "================================================"
    
    # 清理现有服务
    cleanup_existing
    
    # 获取配置
    get_ssh_config
    get_bulk_ports_option
    if [ "$BULK_ENABLED" = true ]; then
        get_bulk_ports_config
    fi
    show_config_summary
    
    # 检测架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) FRP_ARCH="amd64" ;;
        aarch64) FRP_ARCH="arm64" ;;
        armv7l) FRP_ARCH="arm" ;;
        *) echo "不支持的架构: $ARCH"; exit 1 ;;
    esac
    
    echo "检测到架构: $FRP_ARCH"
    
    # 下载安装FRP
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    echo "下载 FRP v$FRP_VERSION..."
    wget -q "https://github.com/fatedier/frp/releases/download/v$FRP_VERSION/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz" -O frp.tar.gz
    tar -xzf frp.tar.gz
    cd "frp_${FRP_VERSION}_linux_${FRP_ARCH}"
    
    INSTALL_DIR="/opt/frp/frp_${FRP_VERSION}_linux_${FRP_ARCH}"
    mkdir -p "$INSTALL_DIR" /etc/frp
    
    cp frpc "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/frpc"
    
    # 创建配置
    create_config_file
    
    # 安装服务
    cat > /etc/systemd/system/frpc.service << SERVICE
[Unit]
Description=Frp Client Service
After=network.target

[Service]
Type=simple
User=root
Restart=always
RestartSec=10
StartLimitInterval=0

ExecStart=$INSTALL_DIR/frpc -c /etc/frp/frpc.toml
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICE
    
    systemctl daemon-reload
    systemctl enable frpc
    
    echo "启动服务..."
    systemctl start frpc
    sleep 3
    
    if systemctl is-active --quiet frpc; then
        echo "✅ FRP服务启动成功"
    else
        echo "❌ FRP服务启动失败"
        journalctl -u frpc -n 20 --no-pager
        exit 1
    fi
    
    # 安装监控
    install_enhanced_monitor
    
    # 清理
    rm -rf "$TEMP_DIR"
    
    # 显示总结
    echo ""
    echo "================================================"
    echo "✅ 安装完成！"
    echo "================================================"
    echo ""
    echo "SSH连接:"
    echo "  ssh username@$SERVER_ADDR -p $SSH_REMOTE_PORT"
    echo ""
    echo "服务状态:"
    systemctl status frpc --no-pager | grep -A 2 "Active:"
    echo ""
    echo "配置文件: /etc/frp/frpc.toml"
    echo "安装目录: $INSTALL_DIR"
    echo ""
    
    if [ "$BULK_ENABLED" = true ]; then
        echo "批量端口已配置:"
        echo "  模式: $BULK_MODE"
        echo "  范围: $BULK_START_PORT-$BULK_END_PORT"
        echo ""
        if [ "$BULK_MODE" = "smart" ]; then
            echo "⚠️  智能模式: 减少错误日志，按需连接"
        fi
    fi
    
    echo "监控系统: 每5分钟检查一次"
    echo "查看日志: journalctl -u frpc -f"
    echo "================================================"
}

main "$@"
