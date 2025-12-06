#!/bin/bash

# ============================================
# FRP智能监控守护进程安装脚本
# 配置：5秒检查一次，1个错误就重启，冷却120秒
# ============================================

set -e

echo "============================================="
echo "FRP智能监控守护进程安装程序"
echo "配置: 5秒/1错误/120秒冷却"
echo "============================================="

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用 sudo 或以 root 用户运行此脚本"
    exit 1
fi

# 配置参数
INSTALL_DIR="/opt/frp-monitor"
LOG_DIR="/var/log/frp-monitor"
SERVICE_NAME="frp-monitor"

# 1. 检查依赖
echo "🔍 检查系统依赖..."
if ! command -v bc &> /dev/null; then
    echo "安装 bc 工具..."
    apt-get update && apt-get install -y bc
fi

if ! command -v socat &> /dev/null; then
    echo "安装 socat 工具..."
    apt-get install -y socat
fi

# 2. 创建目录
echo "📁 创建目录结构..."
mkdir -p "$INSTALL_DIR" "$LOG_DIR" "$LOG_DIR/backups"
chmod 755 "$LOG_DIR"

# 3. 创建核心监控脚本（5秒检查，1个错误重启，120秒冷却）
echo "📝 创建核心监控脚本..."

cat > "$INSTALL_DIR/monitor.sh" << 'MONITOR_EOF'
#!/bin/bash
# FRP错误监控核心脚本
# 配置: 5秒检查，1个错误重启，120秒冷却

# 配置
FRP_SERVICE="frpc"
LOG_FILE="/var/log/frp-monitor/monitor.log"
ERROR_LOG="/var/log/frp-monitor/errors.log"
CHECK_INTERVAL=5           # 5秒检查一次
ERROR_THRESHOLD=1          # 1个错误就重启
RESTART_COOLDOWN=120       # 冷却120秒

# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$ERROR_LOG")"

# 日志函数
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - $1" >> "$LOG_FILE"
}

# 检查错误
check_errors() {
    local errors=0
    # 检查最近30秒的连接错误（因为5秒检查一次，检查30秒内的错误更合理）
    if command -v journalctl &> /dev/null; then
        errors=$(journalctl -u "$FRP_SERVICE" --since "30 seconds ago" 2>/dev/null | grep -c "connect to local service.*connection refused")
    fi
    echo $errors
}

# 重启FRP服务
restart_frp() {
    log "检测到错误，重启FRP服务..."
    
    # 备份配置
    local backup_file="/var/log/frp-monitor/backups/frpc.toml.backup.$(date +%s)"
    cp /etc/frp/frpc.toml "$backup_file" 2>/dev/null && log "配置文件已备份: $backup_file"
    
    # 停止服务
    systemctl stop "$FRP_SERVICE" 2>/dev/null
    sleep 2
    
    # 确保进程停止
    pkill -9 frpc 2>/dev/null || true
    sleep 1
    
    # 启动服务
    systemctl start "$FRP_SERVICE"
    sleep 5
    
    # 检查结果
    if systemctl is-active --quiet "$FRP_SERVICE"; then
        log "FRP服务重启成功"
        return 0
    else
        log "FRP服务重启失败"
        return 1
    fi
}

# 主循环
log "监控守护进程启动 PID: $$"
LAST_RESTART=0

while true; do
    # 检查服务状态
    if ! systemctl is-active --quiet "$FRP_SERVICE"; then
        log "FRP服务未运行，尝试启动..."
        systemctl start "$FRP_SERVICE"
        sleep 5
    fi
    
    # 检查错误
    ERROR_COUNT=$(check_errors)
    CURRENT_TIME=$(date +%s)
    
    if [ "$ERROR_COUNT" -ge "$ERROR_THRESHOLD" ]; then
        log "发现 $ERROR_COUNT 个错误（阈值: $ERROR_THRESHOLD）"
        
        # 检查冷却时间
        if [ $((CURRENT_TIME - LAST_RESTART)) -ge "$RESTART_COOLDOWN" ]; then
            restart_frp
            LAST_RESTART=$CURRENT_TIME
        else
            local cooldown_left=$((RESTART_COOLDOWN - (CURRENT_TIME - LAST_RESTART)))
            log "冷却时间内，还需等待 ${cooldown_left}秒"
        fi
    elif [ "$ERROR_COUNT" -gt 0 ]; then
        log "有 $ERROR_COUNT 个错误，但未达到阈值（实际已达到阈值1，这里应该是逻辑检查）"
    fi
    
    # 清理旧日志（保持日志文件不超过1000行）
    if [ -f "$LOG_FILE" ] && [ $(wc -l < "$LOG_FILE") -gt 1000 ]; then
        tail -500 "$LOG_FILE" > "${LOG_FILE}.tmp"
        mv "${LOG_FILE}.tmp" "$LOG_FILE"
        log "已清理旧日志"
    fi
    
    sleep "$CHECK_INTERVAL"
done
MONITOR_EOF

chmod +x "$INSTALL_DIR/monitor.sh"
echo "✅ 核心监控脚本创建完成"
echo "   配置: 每${CHECK_INTERVAL}秒检查，${ERROR_THRESHOLD}个错误重启，冷却${RESTART_COOLDOWN}秒"

# 4. 创建管理工具
echo "🔧 创建管理工具..."

cat > "$INSTALL_DIR/manager.sh" << 'MANAGER_EOF'
#!/bin/bash
# FRP监控管理工具

MONITOR_SERVICE="frp-monitor"
LOG_FILE="/var/log/frp-monitor/monitor.log"

show_status() {
    echo "========================================"
    echo "    FRP智能监控状态"
    echo "========================================"
    echo ""
    
    # 监控服务状态
    echo "📊 监控服务状态:"
    if systemctl is-active --quiet "$MONITOR_SERVICE"; then
        echo "   ✅ 运行中"
        local pid=$(systemctl show -p MainPID "$MONITOR_SERVICE" | cut -d= -f2)
        echo "   🔧 进程PID: $pid"
        if [ -n "$pid" ]; then
            local uptime=$(ps -o etime= -p "$pid" 2>/dev/null | xargs || echo "未知")
            echo "   ⏱️  运行时间: $uptime"
        fi
    else
        echo "   ❌ 已停止"
    fi
    
    echo ""
    
    # FRP服务状态
    echo "📊 FRP主服务状态:"
    if systemctl is-active --quiet frpc; then
        echo "   ✅ 运行中"
    else
        echo "   ❌ 已停止"
    fi
    
    echo ""
    
    # 日志信息
    echo "📁 日志信息:"
    if [ -f "$LOG_FILE" ]; then
        echo "   📄 日志文件: $LOG_FILE"
        echo "   📏 文件大小: $(du -h "$LOG_FILE" | cut -f1)"
        echo "   📝 日志行数: $(wc -l < "$LOG_FILE")"
        echo "   🕐 最后修改: $(stat -c "%y" "$LOG_FILE" | cut -c1-19)"
        
        echo ""
        echo "   📈 最近日志:"
        tail -5 "$LOG_FILE" | while read line; do
            echo "     $line"
        done
    else
        echo "   📄 日志文件: 不存在"
    fi
    
    echo ""
    
    # 错误统计
    echo "📈 最近错误统计:"
    local recent_errors=0
    if command -v journalctl &> /dev/null; then
        recent_errors=$(journalctl -u frpc --since "1 minute ago" 2>/dev/null | grep -c "connect to local service.*connection refused")
    fi
    echo "   最近1分钟错误数: $recent_errors"
    
    echo ""
    
    # 监控配置
    echo "⚙️  监控配置:"
    echo "   检查间隔: 5秒"
    echo "   错误阈值: 1个错误"
    echo "   冷却时间: 120秒"
    echo "   检查窗口: 最近30秒"
}

case "${1:-status}" in
    status)
        show_status
        ;;
    logs)
        if [ -f "$LOG_FILE" ]; then
            if [ "$2" = "-f" ]; then
                tail -f "$LOG_FILE"
            else
                tail -50 "$LOG_FILE"
            fi
        else
            echo "日志文件不存在: $LOG_FILE"
        fi
        ;;
    restart)
        echo "重启监控服务..."
        systemctl restart "$MONITOR_SERVICE"
        sleep 2
        show_status
        ;;
    start)
        echo "启动监控服务..."
        systemctl start "$MONITOR_SERVICE"
        sleep 2
        show_status
        ;;
    stop)
        echo "停止监控服务..."
        systemctl stop "$MONITOR_SERVICE"
        echo "监控服务已停止"
        ;;
    frp-restart)
        echo "重启FRP服务..."
        systemctl restart frpc
        sleep 3
        show_status
        ;;
    config)
        echo "当前监控配置:"
        grep -E "^(CHECK_INTERVAL|ERROR_THRESHOLD|RESTART_COOLDOWN)" /opt/frp-monitor/monitor.sh | head -3
        ;;
    *)
        echo "用法: $0 {status|logs|restart|start|stop|frp-restart|config}"
        echo ""
        echo "命令:"
        echo "  status       查看状态"
        echo "  logs [-f]    查看日志(-f实时)"
        echo "  restart      重启监控"
        echo "  start        启动监控"
        echo "  stop         停止监控"
        echo "  frp-restart  重启FRP服务"
        echo "  config       查看监控配置"
        ;;
esac
MANAGER_EOF

chmod +x "$INSTALL_DIR/manager.sh"
ln -sf "$INSTALL_DIR/manager.sh" /usr/local/bin/frp-monitor
echo "✅ 管理工具创建完成"

# 5. 创建系统服务文件
echo "🔄 创建系统服务文件..."

cat > /etc/systemd/system/frp-monitor.service << 'SERVICE_EOF'
[Unit]
Description=FRP Error Monitor Service
Description=Monitor FRP errors and auto-restart (5s/1error/120s)
After=frpc.service network.target
Wants=frpc.service

[Service]
Type=simple
User=root
Restart=always
RestartSec=10
StartLimitInterval=0
StartLimitBurst=0

WorkingDirectory=/opt/frp-monitor
ExecStart=/opt/frp-monitor/monitor.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=frp-monitor

# 资源限制
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# 6. 创建日志轮转
echo "📄 配置日志轮转..."
cat > /etc/logrotate.d/frp-monitor << 'LOGROTATE_EOF'
/var/log/frp-monitor/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
LOGROTATE_EOF

# 7. 启用并启动服务
echo "🚀 启动监控服务..."

systemctl daemon-reload
systemctl enable frp-monitor

echo "启动监控守护进程..."
if systemctl start frp-monitor; then
    echo "✅ 监控服务启动命令已发送"
else
    echo "⚠️  监控服务启动返回非零状态"
    journalctl -u frp-monitor --no-pager -n 10
fi

# 等待并检查
sleep 5

echo ""
echo "============================================="
echo "安装结果验证"
echo "============================================="

# 检查服务状态
if systemctl is-active --quiet frp-monitor; then
    echo "✅ 监控服务: 运行中"
    
    # 获取PID和运行时间
    MONITOR_PID=$(systemctl show -p MainPID frp-monitor | cut -d= -f2)
    if [ "$MONITOR_PID" != "0" ]; then
        echo "   🔧 进程PID: $MONITOR_PID"
        UPTIME=$(ps -o etime= -p "$MONITOR_PID" 2>/dev/null | xargs || echo "未知")
        echo "   ⏱️  运行时间: $UPTIME"
    fi
else
    echo "❌ 监控服务: 未运行"
    echo "   查看错误信息:"
    journalctl -u frp-monitor --no-pager -n 10
fi

echo ""
if systemctl is-active --quiet frpc; then
    echo "✅ FRP服务: 运行中"
else
    echo "❌ FRP服务: 未运行"
fi

echo ""
echo "📁 文件检查:"
ls -la /opt/frp-monitor/
echo "   管理命令: frp-monitor"
echo "   配置文件: /etc/systemd/system/frp-monitor.service"

echo ""
echo "============================================="
echo "使用说明"
echo "============================================="
echo ""
echo "📌 基本命令:"
echo "  查看状态:  sudo frp-monitor status"
echo "  查看日志:  sudo frp-monitor logs"
echo "  实时日志:  sudo frp-monitor logs -f"
echo "  重启监控:  sudo frp-monitor restart"
echo "  重启FRP:   sudo frp-monitor frp-restart"
echo "  查看配置:  sudo frp-monitor config"
echo ""
echo "📌 服务管理:"
echo "  启动: sudo systemctl start frp-monitor"
echo "  停止: sudo systemctl stop frp-monitor"
echo "  状态: sudo systemctl status frp-monitor"
echo ""
echo "📌 监控配置:"
echo "  检查间隔: 5秒"
echo "  错误阈值: 1个错误"
echo "  冷却时间: 120秒"
echo "  检查窗口: 最近30秒"
echo ""
echo "📌 日志位置:"
echo "  监控日志: /var/log/frp-monitor/monitor.log"
echo "  错误日志: /var/log/frp-monitor/errors.log"
echo "  配置备份: /var/log/frp-monitor/backups/"
echo ""
echo "============================================="
echo "✨ 监控守护进程安装完成！"
echo "✨ 当FRP出现端口连接错误时，会自动重启服务。"
echo "✨ 配置: 5秒检查一次，1个错误就重启，冷却120秒"
echo "============================================="

# 8. 显示初始状态
echo ""
echo "正在获取初始状态..."
/usr/local/bin/frp-monitor status | head -40
