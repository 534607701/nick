#!/bin/bash

# ============================================
# FRP智能监控守护进程 - 完整安装脚本
# 功能：自动监控FRP端口错误，发现错误时自动重启
# ============================================

set -e

echo "============================================="
echo "FRP智能监控守护进程安装程序"
echo "版本: 1.0"
echo "功能: 自动监控、错误检测、智能重启"
echo "============================================="

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用 sudo 或以 root 用户运行此脚本"
    exit 1
fi

# 配置参数
MONITOR_NAME="frp-error-monitor"
INSTALL_DIR="/opt/frp-monitor"
CONFIG_DIR="/etc/frp-monitor"
LOG_DIR="/var/log/frp-monitor"
SERVICE_NAME="frp-monitor"

# 1. 创建必要的目录
echo "📁 创建目录结构..."
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR" "$LOG_DIR/backups"

# 2. 创建核心监控脚本
echo "📝 创建核心监控脚本..."

cat > "$INSTALL_DIR/monitor.sh" << 'EOF'
#!/bin/bash

# ===== FRP智能监控核心脚本 =====
# 作者: Auto-Generated
# 功能: 监控FRP端口错误，自动重启服务

# ===== 配置区域 =====
CONFIG_FILE="/etc/frp/frpc.toml"
FRP_SERVICE="frpc"
LOG_FILE="/var/log/frp-monitor/monitor.log"
ERROR_LOG="/var/log/frp-monitor/errors.log"
BACKUP_DIR="/var/log/frp-monitor/backups"
CHECK_INTERVAL=30                     # 检查间隔（秒）
ERROR_THRESHOLD=10                    # 触发重启的错误数量阈值
RESTART_COOLDOWN=300                  # 重启冷却时间（秒）
MAX_LOG_SIZE=10485760                 # 最大日志大小（10MB）
SERVER_ADDR="67.215.246.67"
SERVER_PORT="7000"

# ===== 初始化 =====
mkdir -p "$BACKUP_DIR"
current_pid=$$

# ===== 日志函数 =====
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp [$level] - $message" | tee -a "$LOG_FILE"
    
    # 重要日志同时输出到syslog
    if [[ "$level" =~ ^(ERROR|WARNING|ACTION|CRITICAL)$ ]]; then
        logger -t "frp-monitor" "[$level] $message"
    fi
}

# ===== 清理日志 =====
cleanup_logs() {
    # 清理监控日志
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt "$MAX_LOG_SIZE" ]; then
        log "INFO" "监控日志文件过大，进行轮转"
        mv "$LOG_FILE" "${LOG_FILE}.old"
        gzip "${LOG_FILE}.old" &
    fi
    
    # 清理错误日志
    if [ -f "$ERROR_LOG" ] && [ $(stat -c%s "$ERROR_LOG" 2>/dev/null || echo 0) -gt "$MAX_LOG_SIZE" ]; then
        mv "$ERROR_LOG" "${ERROR_LOG}.old"
        gzip "${ERROR_LOG}.old" &
    fi
    
    # 清理旧备份（保留最近7天）
    find "$BACKUP_DIR" -name "*.backup.*" -type f -mtime +7 -delete 2>/dev/null || true
}

# ===== 备份配置文件 =====
backup_config() {
    local backup_file="${BACKUP_DIR}/frpc.toml.backup.$(date +%s)"
    if cp "$CONFIG_FILE" "$backup_file" 2>/dev/null; then
        log "INFO" "配置文件已备份到: $backup_file"
        return 0
    else
        log "ERROR" "配置文件备份失败"
        return 1
    fi
}

# ===== 检查FRP错误 =====
check_frp_errors() {
    local error_count=0
    
    # 检查最近1分钟内的连接错误
    if journalctl -u "$FRP_SERVICE" --since "1 minute ago" 2>/dev/null | grep -q "connect to local service"; then
        error_count=$(journalctl -u "$FRP_SERVICE" --since "1 minute ago" 2>/dev/null | grep -c "connect to local service.*connection refused")
        
        # 记录错误详情到错误日志
        if [ "$error_count" -gt 0 ]; then
            journalctl -u "$FRP_SERVICE" --since "1 minute ago" 2>/dev/null | grep "connect to local service" | head -5 >> "$ERROR_LOG"
        fi
    fi
    
    # 检查工作连接错误
    local work_errors=$(journalctl -u "$FRP_SERVICE" --since "1 minute ago" 2>/dev/null | grep -c "work connection.*error")
    
    local total_errors=$((error_count + work_errors))
    
    if [ "$total_errors" -gt 0 ]; then
        log "WARNING" "检测到 $total_errors 个错误 (端口: $error_count, 工作连接: $work_errors)"
    fi
    
    echo "$total_errors"
}

# ===== 检查FRP服务状态 =====
check_frp_service() {
    # 检查服务是否运行
    if ! systemctl is-active --quiet "$FRP_SERVICE"; then
        log "ERROR" "FRP服务未运行"
        return 1
    fi
    
    # 检查进程是否存在
    if ! pgrep -f "frpc.*toml" > /dev/null; then
        log "ERROR" "FRP进程不存在"
        return 2
    fi
    
    # 检查服务器连接
    if ! timeout 5 nc -z "$SERVER_ADDR" "$SERVER_PORT" 2>/dev/null; then
        log "WARNING" "FRP服务器连接测试失败"
        return 3
    fi
    
    return 0
}

# ===== 重启FRP服务 =====
restart_frp_service() {
    local reason="$1"
    local attempt=1
    local max_attempts=3
    local restart_delay=5
    
    log "ACTION" "开始重启FRP服务 - 原因: $reason"
    
    while [ $attempt -le $max_attempts ]; do
        log "INFO" "重启尝试 $attempt/$max_attempts"
        
        # 备份配置
        backup_config
        
        # 停止服务
        systemctl stop "$FRP_SERVICE"
        sleep 2
        
        # 确保进程停止
        pkill -9 frpc 2>/dev/null || true
        sleep 1
        
        # 启动服务
        systemctl start "$FRP_SERVICE"
        
        # 等待启动完成
        sleep $restart_delay
        
        # 检查是否启动成功
        if systemctl is-active --quiet "$FRP_SERVICE"; then
            log "SUCCESS" "FRP服务重启成功 (第${attempt}次尝试)"
            
            # 验证连接
            sleep 3
            if timeout 5 nc -z "$SERVER_ADDR" "$SERVER_PORT" 2>/dev/null; then
                log "SUCCESS" "FRP连接验证成功"
                return 0
            else
                log "WARNING" "服务已启动但连接验证失败"
            fi
        else
            log "ERROR" "FRP服务启动失败"
        fi
        
        attempt=$((attempt + 1))
        if [ $attempt -le $max_attempts ]; then
            log "INFO" "等待 ${restart_delay}秒后重试..."
            sleep $restart_delay
            restart_delay=$((restart_delay * 2))  # 指数退避
        fi
    done
    
    log "CRITICAL" "FRP服务重启失败，已达到最大重试次数"
    return 1
}

# ===== 健康检查 =====
health_check() {
    # 检查系统资源
    local pid=$(pgrep -f "frpc.*toml")
    if [ -n "$pid" ]; then
        local mem_kb=$(ps -o rss= -p "$pid" 2>/dev/null || echo 0)
        local mem_mb=$((mem_kb / 1024))
        
        if [ "$mem_mb" -gt 200 ]; then
            log "WARNING" "FRP内存使用较高: ${mem_mb}MB"
        fi
    fi
    
    # 检查监控进程自身
    local monitor_pids=$(pgrep -f "monitor.sh" | grep -v "^$current_pid$" | wc -l)
    if [ "$monitor_pids" -gt 2 ]; then
        log "WARNING" "检测到多个监控进程 ($monitor_pids 个)"
    fi
}

# ===== 主监控循环 =====
main_monitor() {
    local last_restart_time=0
    
    log "START" "FRP智能监控守护进程启动 PID: $$"
    log "INFO" "监控配置: 检查间隔=${CHECK_INTERVAL}秒, 错误阈值=${ERROR_THRESHOLD}"
    log "INFO" "FRP服务: $FRP_SERVICE"
    log "INFO" "配置文件: $CONFIG_FILE"
    
    # 初始检查
    if [ ! -f "$CONFIG_FILE" ]; then
        log "CRITICAL" "FRP配置文件不存在: $CONFIG_FILE"
        exit 1
    fi
    
    # 主循环
    while true; do
        local current_time=$(date +%s)
        
        # 清理日志
        cleanup_logs
        
        # 健康检查
        health_check
        
        # 检查FRP服务状态
        check_frp_service
        local service_status=$?
        
        case $service_status in
            0)
                # 服务正常，检查错误
                local error_count=$(check_frp_errors)
                
                if [ "$error_count" -ge "$ERROR_THRESHOLD" ]; then
                    log "WARNING" "错误数量达到阈值: $error_count/$ERROR_THRESHOLD"
                    
                    # 检查是否在冷却期内
                    if [ $((current_time - last_restart_time)) -gt "$RESTART_COOLDOWN" ]; then
                        restart_frp_service "错误数量达到阈值 ($error_count)"
                        last_restart_time=$current_time
                    else
                        local cooldown_left=$((RESTART_COOLDOWN - (current_time - last_restart_time)))
                        log "INFO" "在冷却期内，还需等待 ${cooldown_left}秒"
                    fi
                elif [ "$error_count" -gt 0 ]; then
                    log "INFO" "有 $error_count 个错误，但未达到阈值"
                fi
                ;;
            1|2)
                # 服务未运行或进程不存在，立即重启
                restart_frp_service "服务状态异常 ($service_status)"
                last_restart_time=$current_time
                ;;
            3)
                # 连接问题，观察一段时间
                log "WARNING" "服务器连接问题，持续监控中..."
                ;;
        esac
        
        # 等待下一次检查
        sleep "$CHECK_INTERVAL"
    done
}

# ===== 信号处理 =====
trap 'log "STOP" "收到停止信号，退出监控"; exit 0' TERM INT

# ===== 主函数 =====
main() {
    # 检查是否已有实例在运行
    local existing_pids=$(pgrep -f "monitor.sh" | grep -v "^$$$")
    if [ -n "$existing_pids" ]; then
        echo "检测到已有监控进程在运行 (PID: $existing_pids)"
        echo "是否要停止现有进程并启动新的？(y/N)"
        read -r answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            kill $existing_pids 2>/dev/null
            sleep 2
        else
            echo "退出安装"
            exit 0
        fi
    fi
    
    # 启动监控
    main_monitor
}

# 运行主函数
main "$@"
EOF

chmod +x "$INSTALL_DIR/monitor.sh"
echo "✅ 核心监控脚本创建完成"

# 3. 创建管理工具
echo "🔧 创建管理工具..."

cat > "$INSTALL_DIR/manager.sh" << 'EOF'
#!/bin/bash

# ===== FRP监控管理工具 =====
# 提供便捷的命令行管理接口

MONITOR_SERVICE="frp-monitor"
MONITOR_SCRIPT="$INSTALL_DIR/monitor.sh"
LOG_FILE="/var/log/frp-monitor/monitor.log"
ERROR_LOG="/var/log/frp-monitor/errors.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 显示颜色文本
color_echo() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# 显示标题
show_header() {
    echo ""
    color_echo "$BLUE" "========================================"
    color_echo "$BLUE" "    FRP智能监控管理工具"
    color_echo "$BLUE" "========================================"
    echo ""
}

# 显示状态
show_status() {
    show_header
    
    # 监控服务状态
    color_echo "$BLUE" "📊 监控服务状态:"
    if systemctl is-active --quiet "$MONITOR_SERVICE"; then
        color_echo "$GREEN" "  状态: 运行中 ✓"
        local pid=$(systemctl show -p MainPID "$MONITOR_SERVICE" | cut -d= -f2)
        local uptime=$(ps -o etime= -p "$pid" 2>/dev/null | xargs || echo "未知")
        echo "  进程PID: $pid"
        echo "  运行时间: $uptime"
    else
        color_echo "$RED" "  状态: 已停止 ✗"
    fi
    
    # FRP服务状态
    color_echo "$BLUE" "📊 FRP主服务状态:"
    if systemctl is-active --quiet frpc; then
        color_echo "$GREEN" "  状态: 运行中 ✓"
    else
        color_echo "$RED" "  状态: 已停止 ✗"
    fi
    
    echo ""
    
    # 日志文件信息
    color_echo "$BLUE" "📁 日志文件信息:"
    if [ -f "$LOG_FILE" ]; then
        echo "  监控日志: $LOG_FILE"
        echo "  文件大小: $(du -h "$LOG_FILE" | cut -f1)"
        echo "  最后修改: $(stat -c "%y" "$LOG_FILE" | cut -c1-19)"
        echo "  总行数: $(wc -l < "$LOG_FILE")"
    else
        color_echo "$YELLOW" "  监控日志: 不存在"
    fi
    
    if [ -f "$ERROR_LOG" ]; then
        echo "  错误日志: $ERROR_LOG"
        echo "  错误数量: $(grep -c "connect to local service" "$ERROR_LOG" 2>/dev/null || echo 0)"
    fi
    
    echo ""
    
    # 最近错误统计
    color_echo "$BLUE" "📈 最近错误统计 (最近10分钟):"
    local recent_errors=$(journalctl -u frpc --since "10 minutes ago" 2>/dev/null | grep -c "connect to local service")
    echo "  端口连接错误: $recent_errors"
    
    local recent_work_errors=$(journalctl -u frpc --since "10 minutes ago" 2>/dev/null | grep -c "work connection.*error")
    echo "  工作连接错误: $recent_work_errors"
    
    echo ""
    
    # 最近重启记录
    color_echo "$BLUE" "🔄 最近重启记录:"
    if [ -f "$LOG_FILE" ]; then
        local restart_count=$(grep -c "开始重启FRP服务" "$LOG_FILE" 2>/dev/null || echo 0)
        echo "  总重启次数: $restart_count"
        
        if [ "$restart_count" -gt 0 ]; then
            echo "  最近5次重启:"
            grep "开始重启FRP服务" "$LOG_FILE" 2>/dev/null | tail -5 | while read line; do
                echo "  $(echo "$line" | cut -c1-60)..."
            done
        fi
    fi
    
    echo ""
}

# 查看日志
show_logs() {
    show_header
    
    echo "选择要查看的日志:"
    echo "1. 实时监控日志"
    echo "2. 最近监控日志 (100行)"
    echo "3. 错误日志"
    echo "4. FRP服务日志"
    echo ""
    
    read -p "请选择 (1-4): " log_choice
    
    case $log_choice in
        1)
            color_echo "$GREEN" "开始实时监控日志 (Ctrl+C 退出)..."
            tail -f "$LOG_FILE"
            ;;
        2)
            color_echo "$GREEN" "最近监控日志:"
            tail -100 "$LOG_FILE"
            ;;
        3)
            if [ -f "$ERROR_LOG" ]; then
                color_echo "$GREEN" "错误日志:"
                tail -50 "$ERROR_LOG"
            else
                color_echo "$YELLOW" "错误日志文件不存在"
            fi
            ;;
        4)
            color_echo "$GREEN" "FRP服务日志:"
            journalctl -u frpc -n 50 --no-pager
            ;;
        *)
            color_echo "$RED" "无效选择"
            ;;
    esac
}

# 重启监控
restart_monitor() {
    show_header
    color_echo "$YELLOW" "重启监控服务..."
    
    systemctl restart "$MONITOR_SERVICE"
    sleep 2
    
    if systemctl is-active --quiet "$MONITOR_SERVICE"; then
        color_echo "$GREEN" "✅ 监控服务重启成功"
    else
        color_echo "$RED" "❌ 监控服务重启失败"
    fi
    
    show_status
}

# 停止监控
stop_monitor() {
    show_header
    color_echo "$YELLOW" "停止监控服务..."
    
    systemctl stop "$MONITOR_SERVICE"
    sleep 1
    
    if ! systemctl is-active --quiet "$MONITOR_SERVICE"; then
        color_echo "$GREEN" "✅ 监控服务已停止"
    else
        color_echo "$RED" "❌ 监控服务停止失败"
    fi
}

# 启动监控
start_monitor() {
    show_header
    color_echo "$YELLOW" "启动监控服务..."
    
    systemctl start "$MONITOR_SERVICE"
    sleep 2
    
    if systemctl is-active --quiet "$MONITOR_SERVICE"; then
        color_echo "$GREEN" "✅ 监控服务启动成功"
    else
        color_echo "$RED" "❌ 监控服务启动失败"
    fi
}

# 重启FRP服务
restart_frp() {
    show_header
    color_echo "$YELLOW" "重启FRP服务..."
    
    systemctl restart frpc
    sleep 3
    
    if systemctl is-active --quiet frpc; then
        color_echo "$GREEN" "✅ FRP服务重启成功"
    else
        color_echo "$RED" "❌ FRP服务重启失败"
    fi
}

# 清理日志
clean_logs() {
    show_header
    color_echo "$YELLOW" "清理日志文件..."
    
    echo "选择清理方式:"
    echo "1. 清空监控日志"
    echo "2. 清空错误日志"
    echo "3. 清理所有日志"
    echo ""
    
    read -p "请选择 (1-3): " clean_choice
    
    case $clean_choice in
        1)
            if [ -f "$LOG_FILE" ]; then
                > "$LOG_FILE"
                color_echo "$GREEN" "✅ 监控日志已清空"
            fi
            ;;
        2)
            if [ -f "$ERROR_LOG" ]; then
                > "$ERROR_LOG"
                color_echo "$GREEN" "✅ 错误日志已清空"
            fi
            ;;
        3)
            [ -f "$LOG_FILE" ] && > "$LOG_FILE"
            [ -f "$ERROR_LOG" ] && > "$ERROR_LOG"
            color_echo "$GREEN" "✅ 所有日志已清空"
            ;;
        *)
            color_echo "$RED" "无效选择"
            ;;
    esac
}

# 查看配置
show_config() {
    show_header
    color_echo "$BLUE" "📋 监控配置信息:"
    
    echo "  配置文件: /etc/systemd/system/frp-monitor.service"
    echo "  监控脚本: $MONITOR_SCRIPT"
    echo "  日志目录: /var/log/frp-monitor/"
    echo "  检查间隔: 30秒"
    echo "  错误阈值: 10个错误"
    echo "  重启冷却: 300秒"
    echo ""
    
    color_echo "$BLUE" "📋 FRP配置信息:"
    if [ -f "/etc/frp/frpc.toml" ]; then
        echo "  配置文件: /etc/frp/frpc.toml"
        local proxy_count=$(grep -c "^\[\[proxies\]\]" /etc/frp/frpc.toml 2>/dev/null || echo 0)
        echo "  代理数量: $proxy_count"
        
        local ssh_config=$(grep -A 2 'name = "ssh_' /etc/frp/frpc.toml 2>/dev/null | head -3)
        if [ -n "$ssh_config" ]; then
            echo "  SSH配置:"
            echo "$ssh_config" | while read line; do
                echo "    $line"
            done
        fi
    else
        color_echo "$RED" "  FRP配置文件不存在"
    fi
    
    echo ""
}

# 显示帮助
show_help() {
    show_header
    color_echo "$GREEN" "使用方法:"
    echo "  $0 [command]"
    echo ""
    color_echo "$GREEN" "可用命令:"
    echo "  status      查看监控和FRP状态"
    echo "  logs        查看日志"
    echo "  restart     重启监控服务"
    echo "  start       启动监控服务"
    echo "  stop        停止监控服务"
    echo "  frp-restart 重启FRP服务"
    echo "  clean       清理日志"
    echo "  config      查看配置"
    echo "  help        显示帮助"
    echo ""
    color_echo "$GREEN" "示例:"
    echo "  $0 status          # 查看状态"
    echo "  $0 logs            # 查看日志"
    echo "  $0 restart         # 重启监控"
    echo ""
}

# 主函数
main() {
    local command="${1:-status}"
    
    case "$command" in
        status)
            show_status
            ;;
        logs)
            show_logs
            ;;
        restart)
            restart_monitor
            ;;
        start)
            start_monitor
            ;;
        stop)
            stop_monitor
            ;;
        frp-restart)
            restart_frp
            ;;
        clean)
            clean_logs
            ;;
        config)
            show_config
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            color_echo "$RED" "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
EOF

chmod +x "$INSTALL_DIR/manager.sh"

# 创建符号链接到/usr/local/bin
ln -sf "$INSTALL_DIR/manager.sh" /usr/local/bin/frp-monitor
echo "✅ 管理工具创建完成 (使用: frp-monitor [command])"

# 4. 创建系统服务文件
echo "🔄 创建系统服务..."

cat > /etc/systemd/system/frp-monitor.service << EOF
[Unit]
Description=FRP Error Monitor Daemon
Description=监控FRP端口错误，自动重启服务
After=frpc.service network.target
Requires=frpc.service
Wants=network-online.target

[Service]
Type=simple
User=root
Restart=always
RestartSec=10
StartLimitInterval=0
StartLimitBurst=0

WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/monitor.sh
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
KillSignal=SIGTERM
TimeoutStopSec=30

# 资源限制
LimitNOFILE=65536
LimitNPROC=4096
LimitCORE=infinity

# 环境变量
Environment="CHECK_INTERVAL=30"
Environment="ERROR_THRESHOLD=10"
Environment="RESTART_COOLDOWN=300"

# 安全配置
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/etc/frp /var/log/frp-monitor
ReadOnlyPaths=/

# 日志配置
StandardOutput=journal
StandardError=journal
SyslogIdentifier=frp-monitor

[Install]
WantedBy=multi-user.target
EOF

# 5. 创建日志轮转配置
echo "📄 配置日志轮转..."

cat > /etc/logrotate.d/frp-monitor << EOF
/var/log/frp-monitor/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    sharedscripts
    postrotate
        systemctl reload frp-monitor >/dev/null 2>&1 || true
    endscript
}
EOF

# 6. 启用并启动服务
echo "🚀 启用并启动监控服务..."

systemctl daemon-reload
systemctl enable frp-monitor

echo "启动监控服务..."
systemctl start frp-monitor

# 7. 等待服务启动
sleep 5

# 8. 创建快捷命令
cat > /usr/local/bin/frp-status << 'EOF'
#!/bin/bash
/usr/local/bin/frp-monitor status
EOF

chmod +x /usr/local/bin/frp-status

# 9. 验证安装
echo ""
echo "============================================="
echo "✅ FRP智能监控守护进程安装完成！"
echo "============================================="
echo ""

echo "📊 安装验证:"
echo "1. 监控服务状态:"
if systemctl is-active --quiet frp-monitor; then
    echo "   ✅ 监控服务: 运行中"
    local monitor_pid=$(systemctl show -p MainPID frp-monitor | cut -d= -f2)
    echo "   🔧 进程PID: $monitor_pid"
else
    echo "   ❌ 监控服务: 未运行"
fi

echo ""
echo "2. FRP服务状态:"
if systemctl is-active --quiet frpc; then
    echo "   ✅ FRP服务: 运行中"
else
    echo "   ❌ FRP服务: 未运行"
fi

echo ""
echo "3. 文件检查:"
ls -la "$INSTALL_DIR/" | grep -E "\.sh$"
echo "   管理工具: /usr/local/bin/frp-monitor"
echo "   状态查询: /usr/local/bin/frp-status"

echo ""
echo "============================================="
echo "🎯 使用说明:"
echo "============================================="
echo ""
echo "📌 管理命令:"
echo "  查看状态:   sudo frp-monitor status"
echo "  查看日志:   sudo frp-monitor logs"
echo "  重启监控:   sudo frp-monitor restart"
echo "  重启FRP:    sudo frp-monitor frp-restart"
echo "  停止监控:   sudo frp-monitor stop"
echo "  启动监控:   sudo frp-monitor start"
echo "  清理日志:   sudo frp-monitor clean"
echo "  查看配置:   sudo frp-monitor config"
echo ""
echo "📌 快捷命令:"
echo "  快速状态:   sudo frp-status"
echo ""
echo "📌 监控特性:"
echo "  • 每30秒检查一次FRP错误"
echo "  • 发现10个以上端口错误时自动重启"
echo "  • 重启冷却时间5分钟"
echo "  • 自动备份配置文件"
echo "  • 详细的日志记录"
echo "  • 智能重启策略（最多重试3次）"
echo ""
echo "📌 日志位置:"
echo "  监控日志:   /var/log/frp-monitor/monitor.log"
echo "  错误日志:   /var/log/frp-monitor/errors.log"
echo "  配置备份:   /var/log/frp-monitor/backups/"
echo ""
echo "📌 服务管理:"
echo "  启动: sudo systemctl start frp-monitor"
echo "  停止: sudo systemctl stop frp-monitor"
echo "  重启: sudo systemctl restart frp-monitor"
echo "  状态: sudo systemctl status frp-monitor"
echo ""
echo "============================================="
echo "✨ 安装完成！监控守护进程已在后台运行。"
echo "✨ 当FRP出现端口连接错误时，系统会自动重启服务。"
echo "============================================="

# 10. 显示初始状态
echo ""
echo "正在获取初始状态..."
/usr/local/bin/frp-monitor status | head -30
