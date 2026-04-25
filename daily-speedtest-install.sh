#!/bin/bash

# 每日测速服务安装脚本 - 修复版
# 下载并安装 Systemd 服务，每天凌晨3点自动执行测速

set -e  # 遇到错误立即退出

echo "=== 每日测速服务安装脚本 - 修复版 ==="
echo "将安装每日凌晨3点自动测速服务"
echo ""

# 检查是否以root运行
if [ "$EUID" -ne 0 ]; then 
    echo "请使用 sudo 运行此脚本: sudo bash $0"
    exit 1
fi

# 0. 安装依赖
echo "0. 检查系统依赖..."
if command -v speedtest-cli >/dev/null 2>&1; then
    echo "✅ speedtest-cli 已安装"
else
    echo "正在安装 speedtest-cli..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y speedtest-cli
    elif command -v yum >/dev/null 2>&1; then
        yum install -y speedtest-cli
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y speedtest-cli
    else
        echo "⚠️  无法自动安装 speedtest-cli，请手动安装后继续"
        read -p "是否继续安装服务？(y/N): " CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

# 1. 创建脚本目录
echo ""
echo "1. 创建脚本目录..."
mkdir -p /opt/daily-scripts /var/log/speedtest
echo "✅ 目录创建完成"

# 2. 下载测速脚本
echo ""
echo "2. 下载测速脚本..."
if curl -fsSL https://raw.githubusercontent.com/534607701/nick/main/replacez52_speedtest.sh -o /opt/daily-scripts/replacez52_speedtest.sh; then
    chmod +x /opt/daily-scripts/replacez52_speedtest.sh
    echo "✅ 测速脚本下载完成"
else
    echo "❌ 下载测速脚本失败，创建基本脚本..."
    cat > /opt/daily-scripts/replacez52_speedtest.sh << 'BASIC_SCRIPT'
#!/bin/bash
echo "=== 网络测速开始: $(date '+%Y-%m-%d %H:%M:%S') ==="
echo "正在检查网络连接..."
if ping -c 2 8.8.8.8 >/dev/null 2>&1; then
    echo "网络连接正常"
    echo "正在执行测速..."
    
    # 尝试使用 speedtest-cli
    if command -v speedtest-cli >/dev/null 2>&1; then
        echo "使用 speedtest-cli 进行测速..."
        speedtest-cli --simple
    else
        echo "speedtest-cli 未安装，使用其他方法测试..."
        # 简单的下载速度测试
        echo "测试下载速度..."
        timeout 10 curl -o /dev/null -w "下载速度: %{speed_download} bytes/s\n" https://speed.hetzner.de/100MB.bin 2>/dev/null || \
        echo "无法完成测速，请检查网络"
    fi
else
    echo "网络连接失败，无法进行测速"
fi
echo "=== 测速结束: $(date '+%Y-%m-%d %H:%M:%S') ==="
BASIC_SCRIPT
    chmod +x /opt/daily-scripts/replacez52_speedtest.sh
    echo "✅ 已创建基本测速脚本"
fi

# 3. 创建 systemd 服务文件（修复版）
echo ""
echo "3. 创建 Systemd 服务文件..."
cat > /etc/systemd/system/daily-speedtest.service << 'EOF'
[Unit]
Description=Daily SpeedTest Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root

# 随机延迟 0-300 秒
ExecStartPre=/bin/bash -c "sleep $((RANDOM %% 300))"

# 执行测速脚本
ExecStart=/bin/bash /opt/daily-scripts/replacez52_speedtest.sh

# 标准输出重定向到文件
StandardOutput=append:/var/log/speedtest/speedtest.log
StandardError=append:/var/log/speedtest/speedtest-error.log
SyslogIdentifier=daily-speedtest

# 超时设置（30分钟）
TimeoutSec=1800

# 工作目录
WorkingDirectory=/opt/daily-scripts

# 成功或失败都视为完成
SuccessExitStatus=0 1

[Install]
WantedBy=multi-user.target
EOF

echo "✅ 服务文件创建完成"

# 4. 创建 systemd 定时器文件（修复版）
echo ""
echo "4. 创建 Systemd 定时器文件..."
cat > /etc/systemd/system/daily-speedtest.timer << 'EOF'
[Unit]
Description=Run SpeedTest daily at 3 AM
Requires=daily-speedtest.service

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
RandomizedDelaySec=600

[Install]
WantedBy=timers.target
EOF

echo "✅ 定时器文件创建完成"

# 5. 创建日志轮转配置
echo ""
echo "5. 创建日志轮转配置..."
cat > /etc/logrotate.d/speedtest << 'EOF'
/var/log/speedtest/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
    size 10M
}
EOF

echo "✅ 日志轮转配置创建完成"

# 6. 设置日志文件权限
echo ""
echo "6. 设置日志文件权限..."
touch /var/log/speedtest/speedtest.log
touch /var/log/speedtest/speedtest-error.log
chmod 640 /var/log/speedtest/*.log
chown root:root /var/log/speedtest/*.log
echo "✅ 日志文件权限设置完成"

# 7. 重新加载 systemd 配置
echo ""
echo "7. 重新加载 Systemd 配置..."
systemctl daemon-reload
echo "✅ Systemd 配置已重新加载"

# 8. 启用并启动定时器
echo ""
echo "8. 启用定时器服务..."
systemctl enable daily-speedtest.timer
systemctl start daily-speedtest.timer
echo "✅ 定时器服务已启用并启动"

# 9. 测试服务配置
echo ""
echo "9. 验证服务配置..."
if systemctl is-enabled daily-speedtest.timer >/dev/null 2>&1; then
    echo "✅ 定时器已启用"
else
    echo "❌ 定时器启用失败"
fi

# 10. 显示安装状态
echo ""
echo "========================================"
echo "安装完成！"
echo "========================================"
echo ""
echo "📁 脚本位置: /opt/daily-scripts/replacez52_speedtest.sh"
echo "📁 日志文件: /var/log/speedtest/speedtest.log"
echo "⏰ 执行时间: 每天凌晨 3:00（随机延迟0-10分钟）"
echo ""
echo "📊 服务状态:"
systemctl status daily-speedtest.timer --no-pager | head -10
echo ""
echo "🕐 定时器列表:"
systemctl list-timers --no-pager | grep -A1 -B1 daily-speedtest || echo "正在获取定时器信息..."
echo ""
echo "🔧 管理命令:"
echo "   手动测试: sudo bash /opt/daily-scripts/replacez52_speedtest.sh"
echo "   查看日志: sudo tail -f /var/log/speedtest/speedtest.log"
echo "   服务日志: sudo journalctl -u daily-speedtest.service"
echo "   定时器状态: sudo systemctl status daily-speedtest.timer"
echo "   禁用定时器: sudo systemctl disable daily-speedtest.timer"
echo "   启用定时器: sudo systemctl enable daily-speedtest.timer"
echo ""
echo "✨ 安装完成！测速服务将在每天凌晨3点自动运行。"

# 11. 立即测试（可选）
echo ""
read -p "是否立即测试测速脚本？(y/N): " TEST_NOW
if [[ "$TEST_NOW" =~ ^[Yy]$ ]]; then
    echo "正在执行测速测试..."
    echo "=== 测试开始 ==="
    timeout 30 /bin/bash /opt/daily-scripts/replacez5_speedtest.sh
    echo "=== 测试结束 ==="
    echo "查看测试结果: tail -20 /var/log/speedtest/speedtest.log"
fi
