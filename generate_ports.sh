#!/bin/bash

# 端口生成脚本
# 用法: ./generate_ports.sh [起始端口] [数量]

# 获取用户输入
echo "=== FRPC 端口配置生成器 ==="
read -p "请输入起始端口 (默认: 16386): " user_start_port
read -p "请输入生成端口数量 (默认: 200): " user_count

# 设置默认值（如果用户输入为空）
START_PORT=${user_start_port:-16386}
COUNT=${user_count:-200}
OUTPUT_FILE="ports.conf"

# 验证输入是否为数字
if ! [[ "$START_PORT" =~ ^[0-9]+$ ]]; then
    echo "错误: 起始端口必须是数字!"
    exit 1
fi

if ! [[ "$COUNT" =~ ^[0-9]+$ ]]; then
    echo "错误: 端口数量必须是数字!"
    exit 1
fi

# 验证端口范围
if [ "$START_PORT" -lt 1024 ] || [ "$START_PORT" -gt 65535 ]; then
    echo "错误: 起始端口必须在 1024-65535 范围内!"
    exit 1
fi

if [ "$COUNT" -lt 1 ] || [ "$((START_PORT + COUNT))" -gt 65535 ]; then
    echo "错误: 端口数量无效或超出可用端口范围!"
    exit 1
fi

echo ""
echo "开始生成端口配置..."
echo "起始端口: $START_PORT"
echo "生成数量: $COUNT"
echo "输出文件: $OUTPUT_FILE"
echo "结束端口: $((START_PORT + COUNT - 1))"
echo ""

# 清空或创建输出文件
echo "# 自动生成的端口配置" > $OUTPUT_FILE
echo "# 生成时间: $(date)" >> $OUTPUT_FILE
echo "# 起始端口: $START_PORT, 数量: $COUNT" >> $OUTPUT_FILE
echo "" >> $OUTPUT_FILE

# 生成配置
for ((i=0; i<COUNT; i++)); do
    PORT=$((START_PORT + i))
    
    cat >> $OUTPUT_FILE << EOF
[[proxies]]
name = "port_${PORT}_tcp"
type = "tcp"
localIP = "127.0.0.1"
localPort = $PORT
remotePort = $PORT

EOF
    
    # 显示进度
    if (( (i + 1) % 10 == 0 )); then
        echo "已生成 $((i + 1))/$COUNT 个配置"
    fi
done

echo ""
echo "配置生成完成!"
echo "文件: $OUTPUT_FILE"
echo "大小: $(du -h $OUTPUT_FILE | cut -f1)"
echo "行数: $(wc -l < $OUTPUT_FILE)"
