cat > manage_service.sh << 'EOF'
#!/bin/bash

case "$1" in
    status)
        echo "🌐 网络优化服务状态"
        echo "========================"
        
        if sudo systemctl is-active speedtest-service.timer >/dev/null 2>&1; then
            echo "✅ 服务状态: 运行中"
        else
            echo "❌ 服务状态: 未运行"
        fi
        
        if [ -f "/var/lib/vastai_kaalia/speedtest_counter" ]; then
            COUNT=$(cat /var/lib/vastai_kaalia/speedtest_counter)
            echo "📊 优化进度: $COUNT/27 次"
        else
            echo "📊 优化进度: 未开始"
        fi
        ;;
    stop)
        sudo systemctl stop speedtest-service.timer
        sudo systemctl disable speedtest-service.timer
        echo "✅ 服务已停止"
        ;;
    start)
        sudo systemctl enable speedtest-service.timer
        sudo systemctl start speedtest-service.timer
        echo "✅ 服务已启动"
        ;;
    reset)
        echo "0" | sudo tee /var/lib/vastai_kaalia/speedtest_counter
        echo "✅ 进度已重置"
        ;;
    *)
        echo "使用方法: $0 {status|start|stop|reset}"
        ;;
esac
EOF

chmod +x manage_service.sh

echo "✅ 管理脚本已创建: manage_service.sh"
