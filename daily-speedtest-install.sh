#!/bin/bash

# 每日测速服务安装脚本
# 下载并安装 Systemd 服务，每天凌晨3点自动执行测速

set -e  # 遇到错误立即退出

echo "=== 每日测速服务安装脚本 ==="
echo "将安装每日凌晨3点自动测速服务"
echo ""

# 检查是否以root运行
if [ "$EUID" -ne 0 ]; then 
    echo "请使用 sudo 运行此脚本: sudo bash $0"
    exit 1
fi

# 1. 创建脚本目录
echo "1. 创建脚本目录..."
mkdir -p /opt/daily-scripts
echo "✅ 目录创建完成: /opt/daily-scripts"

# 2. 下载测速脚本
echo ""
echo "2. 下载测速脚本..."
if curl -fsSL https://raw.githubusercontent.com/534607701/nick/main/replacez5_speedtest.sh -o /opt/daily-scripts/replacez5_speedtest.sh; then
    chmod +x /opt/daily-scripts/replacez5_speedtest.sh
    echo "✅ 测速脚本下载完成"
    echo "   路径: /opt/daily-scripts/replacez5_speedtest.sh"
    echo "   权限: $(ls -la /opt/daily-scripts/replacez5_speedtest.sh | awk '{print $1}')"
else
    echo "❌ 下载测速脚本失败，请检查网络连接"
    exit 1
fi

# 3. 创建 systemd 服务文件
echo ""
echo "3. 创建 Systemd 服务文件..."
cat > /etc/systemd/system/daily-speedtest.service << 'EOF'
[Unit]
Description=Daily SpeedTest Service
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=/bin/bash /opt/daily-scripts/replacez5_speedtest.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "✅ 服务文件创建完成: /etc/systemd/system/daily-speedtest.service"

# 4. 创建 systemd 定时器文件
echo ""
echo "4. 创建 Systemd 定时器文件..."
cat > /etc/systemd/system/daily-speedtest.timer << 'EOF'
[Unit]
Description=Run SpeedTest daily at 3 AM
Requires=daily-speedtest.service

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

echo "✅ 定时器文件创建完成: /etc/systemd/system/daily-speedtest.timer"

# 5. 重新加载 systemd 配置
echo ""
echo "5. 重新加载 Systemd 配置..."
systemctl daemon-reload
echo "✅ Systemd 配置已重新加载"

# 6. 启用并启动定时器
echo ""
echo "6. 启用定时器服务..."
systemctl enable daily-speedtest.timer
systemctl start daily-speedtest.timer
echo "✅ 定时器服务已启用并启动"

# 7. 显示安装状态
echo ""
echo "7. 检查服务状态..."
echo ""
echo "========================================"
echo "安装完成！"
echo "========================================"
echo ""
echo "📁 脚本位置: /opt/daily-scripts/replacez5_speedtest.sh"
echo "⏰ 定时设置: 每天凌晨 3:00 自动执行"
echo ""
echo "📊 服务状态检查:"
echo "   定时器状态: systemctl status daily-speedtest.timer"
echo "   服务状态:   systemctl status daily-speedtest.service"
echo "   下次执行时间: systemctl list-timers daily-speedtest.timer"
echo ""
echo "🔧 管理命令:"
echo "   手动执行测试: sudo bash /opt/daily-scripts/replacez5_speedtest.sh"
echo "   查看日志:     journalctl -u daily-speedtest.service"
echo "   禁用定时器:   sudo systemctl disable daily-speedtest.timer"
echo "   停止定时器:   sudo systemctl stop daily-speedtest.timer"
echo "   重新启用:     sudo systemctl enable --now daily-speedtest.timer"
echo ""
echo "📝 查看定时器详情:"
systemctl list-timers daily-speedtest.timer 2>/dev/null || echo "定时器详情将在几秒后可用"
echo ""
echo "✨ 安装完成！测速服务将在每天凌晨3点自动运行。"
