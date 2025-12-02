#!/bin/bash

# 每日测速服务安装脚本 - 增强版
# 下载并安装 Systemd 服务，每天凌晨3点自动执行测速

set -e  # 遇到错误立即退出

echo "=== 每日测速服务安装脚本 - 增强版 ==="
echo "将安装每日凌晨3点自动测速服务"
echo ""

# 检查是否以root运行
if [ "$EUID" -ne 0 ]; then 
    echo "请使用 sudo 运行此脚本: sudo bash $0"
    exit 1
fi

# 0. 安装依赖（如果需要）
echo "0. 检查系统依赖..."
if command -v speedtest-cli >/dev/null 2>&1; then
    echo "✅ speedtest-cli 已安装"
else
    echo "⚠️  未检测到 speedtest-cli，尝试安装..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y speedtest-cli 2>/dev/null || {
            echo "❌ 无法安装 speedtest-cli，请手动安装:"
            echo "   Ubuntu/Debian: sudo apt-get install speedtest-cli"
            echo "   CentOS/RHEL: sudo yum install speedtest-cli"
            echo "继续安装服务，但测速脚本可能需要依赖..."
        }
    fi
fi

# 1. 创建脚本目录
echo ""
echo "1. 创建脚本目录..."
mkdir -p /opt/daily-scripts /var/log/speedtest
echo "✅ 目录创建完成:"
echo "   /opt/daily-scripts - 脚本目录"
echo "   /var/log/speedtest - 日志目录"

# 2. 下载测速脚本
echo ""
echo "2. 下载测速脚本..."
if curl -fsSL https://raw.githubusercontent.com/534607701/nick/main/replacez5_speedtest.sh -o /opt/daily-scripts/replacez5_speedtest.sh; then
    chmod +x /opt/daily-scripts/replacez5_speedtest.sh
    
    # 备份原始脚本
    cp /opt/daily-scripts/replacez5_speedtest.sh /opt/daily-scripts/replacez5_speedtest.sh.backup
    
    # 添加执行时间戳到日志
    if ! grep -q "echo \"执行时间:" /opt/daily-scripts/replacez5_speedtest.sh; then
        sed -i '1i\#!/bin/bash\n# 每日自动测速脚本\n# 自动添加时间戳\necho "执行时间: $(date "+%Y-%m-%d %H:%M:%S")"' /opt/daily-scripts/replacez5_speedtest.sh
    fi
    
    echo "✅ 测速脚本下载完成"
    echo "   路径: /opt/daily-scripts/replacez5_speedtest.sh"
    echo "   权限: $(ls -la /opt/daily-scripts/replacez5_speedtest.sh | awk '{print $1}')"
    
    # 测试脚本是否可以执行
    if /bin/bash -n /opt/daily-scripts/replacez5_speedtest.sh 2>/dev/null; then
        echo "✅ 脚本语法检查通过"
    else
        echo "⚠️  脚本语法检查失败，但继续安装"
    fi
else
    echo "❌ 下载测速脚本失败，请检查网络连接"
    echo "尝试使用备用方法创建基本脚本..."
    
    # 创建基本测速脚本
    cat > /opt/daily-scripts/replacez5_speedtest.sh << 'BASIC_SCRIPT'
#!/bin/bash
# 基本测速脚本
echo "测速开始: $(date)"
echo "如需完整功能，请手动下载:"
echo "curl -fsSL https://raw.githubusercontent.com/534607701/nick/main/replacez5_speedtest.sh -o /opt/daily-scripts/replacez5_speedtest.sh"
BASIC_SCRIPT
    
    chmod +x /opt/daily-scripts/replacez5_speedtest.sh
    echo "✅ 已创建基本测速脚本"
fi

# 3. 创建 systemd 服务文件（增强版）
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

# 随机延迟 0-300 秒（5分钟），避免多个服务器同时测速
ExecStartPre=/bin/sleep $((RANDOM % 300))

# 执行测速脚本，同时输出到日志文件和 journal
ExecStart=/bin/bash -c "/opt/daily-scripts/replacez5_speedtest.sh 2>&1 | tee -a /var/log/speedtest/speedtest-$(date +\%Y\%m\%d).log"

# 成功或失败都视为完成
SuccessExitStatus=0 1

# 超时设置（2小时）
TimeoutSec=7200

# 资源限制
LimitNOFILE=65536

# 日志配置
StandardOutput=journal
StandardError=journal
SyslogIdentifier=daily-speedtest

# 工作目录
WorkingDirectory=/opt/daily-scripts

[Install]
WantedBy=multi-user.target
EOF

echo "✅ 服务文件创建完成: /etc/systemd/system/daily-speedtest.service"

# 4. 创建 systemd 定时器文件（增强版）
echo ""
echo "4. 创建 Systemd 定时器文件..."
cat > /etc/systemd/system/daily-speedtest.timer << 'EOF'
[Unit]
Description=Run SpeedTest daily at 3 AM with random delay
Requires=daily-speedtest.service

[Timer]
# 每天凌晨3点执行，随机延迟0-30分钟
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=1800
Persistent=true

# 如果错过执行时间（如服务器关机），开机后立即执行
OnBootSec=1min
OnUnitActiveSec=1d

[Install]
WantedBy=timers.target
EOF

echo "✅ 定时器文件创建完成: /etc/systemd/system/daily-speedtest.timer"

# 5. 创建日志轮转配置
echo ""
echo "5. 创建日志轮转配置..."
cat > /etc/logrotate.d/speedtest << 'EOF'
/var/log/speedtest/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
EOF

echo "✅ 日志轮转配置创建完成: /etc/logrotate.d/speedtest"

# 6. 重新加载 systemd 配置
echo ""
echo "6. 重新加载 Systemd 配置..."
systemctl daemon-reload
echo "✅ Systemd 配置已重新加载"

# 7. 启用并启动定时器
echo ""
echo "7. 启用定时器服务..."
systemctl enable daily-speedtest.timer
systemctl start daily-speedtest.timer
echo "✅ 定时器服务已启用并启动"

# 8. 立即测试一次（可选）
echo ""
read -p "是否立即测试一次测速脚本？(y/N): " TEST_NOW
if [[ "$TEST_NOW" =~ ^[Yy]$ ]]; then
    echo "正在测试测速脚本..."
    if timeout 60 /bin/bash /opt/daily-scripts/replacez5_speedtest.sh 2>&1 | head -20; then
        echo "✅ 测速脚本测试成功"
    else
        echo "⚠️  测速脚本测试可能有问题，请检查"
    fi
fi

# 9. 显示安装状态
echo ""
echo "========================================"
echo "安装完成！"
echo "========================================"
echo ""
echo "📁 脚本位置: /opt/daily-scripts/replacez5_speedtest.sh"
echo "📁 备份位置: /opt/daily-scripts/replacez5_speedtest.sh.backup"
echo "📁 日志目录: /var/log/speedtest/"
echo "⏰ 定时设置: 每天凌晨 3:00 自动执行（随机延迟0-30分钟）"
echo ""
echo "📊 服务状态检查:"
systemctl status daily-speedtest.timer --no-pager -l | head -20
echo ""
echo "🕐 下次执行时间:"
systemctl list-timers daily-speedtest.timer --no-pager | grep daily-speedtest || echo "正在获取定时器信息..."
echo ""
echo "📝 查看日志文件:"
echo "   ls -la /var/log/speedtest/"
echo ""
echo "🔧 管理命令:"
echo "   手动执行测试: sudo bash /opt/daily-scripts/replacez5_speedtest.sh"
echo "   查看今日日志: sudo journalctl -u daily-speedtest.service --since today"
echo "   查看所有日志: sudo journalctl -u daily-speedtest.service"
echo "   查看文件日志: tail -f /var/log/speedtest/speedtest-$(date +%Y%m%d).log"
echo "   禁用定时器:   sudo systemctl disable daily-speedtest.timer"
echo "   停止定时器:   sudo systemctl stop daily-speedtest.timer"
echo "   重新启用:     sudo systemctl enable --now daily-speedtest.timer"
echo "   检查定时器:   systemctl list-timers --all"
echo ""
echo "🔄 更新脚本:"
echo "   curl -fsSL https://raw.githubusercontent.com/534607701/nick/main/replacez5_speedtest.sh -o /opt/daily-scripts/replacez5_speedtest.sh"
echo "   chmod +x /opt/daily-scripts/replacez5_speedtest.sh"
echo "   systemctl restart daily-speedtest.service"
echo ""
echo "✨ 安装完成！测速服务将在每天凌晨3点自动运行。"
