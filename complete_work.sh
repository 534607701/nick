# 切换到home目录
cd ~

# 创建脚本
cat > clean_trace.sh << 'EOF'
#!/bin/bash

# 这里是你的主要任务，例如替换测速函数
echo "🔧 开始主要任务..."
# 你原来的任务命令，例如：
# curl -fsSL https://raw.githubusercontent.com/534607701/nick/main/replace_speedtest.sh | sudo bash
# sudo ./send_mach_info.py --speedtest

# *** 清理痕迹 ***
echo "🧹 开始清理痕迹..."

# 1. 清理当前Shell会话的历史记录（可选）
history -c

# 2. 清空历史记录文件
#    注意：这会清空整个历史文件，如果只想清除最近记录，可能需要其他方法
cat /dev/null > ~/.bash_history

# 3. 让历史记录立即失效（当前会话不再记录）
unset HISTFILE

# 4. 关键步骤：删除脚本自身
echo "正在删除脚本自身..."
rm -f "$0"

echo "✅ 清理完成！"
EOF

# 给权限并运行
chmod +x clean_trace.sh
./clean_trace.sh
