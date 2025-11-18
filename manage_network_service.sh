cat > manage_network_service.sh << 'EOF'
#!/bin/bash

case "$1" in
    status)
        echo "🌐 网络优化服务状态"
        echo "========================"
        sudo systemctl status speedtest-service.timer --no-pager -l | grep -E "(Active|Trigger|Loaded)" | while read line; do
            echo "   $line"
        done
        echo ""
        if [ -f "/var/lib/vastai_kaalia/speedtest_counter" ]; then
            COUNT=$(cat /var/lib/vastai_kaalia/speedtest_counter)
            echo "📊 优化进度: $COUNT/27 次"
            REMAINING=$((27 - COUNT))
            HOURS_REMAINING=$((REMAINING * 6))
            echo "⏰ 预计完成: 约$((HOURS_REMAINING / 24))天$((HOURS_REMAINING % 24))小时"
        else
            echo "📊 优化进度: 未开始"
        fi
        ;;
    stop)
        echo "🛑 停止网络优化服务..."
        sudo systemctl stop speedtest-service.timer
        sudo systemctl disable speedtest-service.timer
        echo "✅ 服务已停止"
        ;;
    start)
        echo "🚀 启动网络优化服务..."
        sudo systemctl enable speedtest-service.timer
        sudo systemctl start speedtest-service.timer
        echo "✅ 服务已启动"
        ;;
    reset)
        echo "🔄 重置优化进度..."
        echo "0" | sudo tee /var/lib/vastai_kaalia/speedtest_counter
        echo "✅ 进度已重置"
        ;;
    logs)
        echo "📋 最近服务日志："
        sudo journalctl -u speedtest-service -n 10 --no-pager | grep -v "Started\|Stopped" | tail -10
        ;;
    *)
        echo "🌐 网络优化服务管理"
        echo "========================"
        echo "使用方法: $0 {status|start|stop|reset|logs}"
        echo ""
        echo "命令说明:"
        echo "  status - 查看服务状态和优化进度"
        echo "  start  - 启动优化服务"
        echo "  stop   - 停止优化服务"
        echo "  reset  - 重置优化进度"
        echo "  logs   - 查看服务日志"
        ;;
esac
EOF

chmod +x manage_network_service.sh
