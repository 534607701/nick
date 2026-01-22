#!/bin/bash
# /usr/local/bin/fan_smart_control.sh
# 使用您系统的正确转速值

# 首先确保IPMI在手动模式
sudo ipmitool raw 0x30 0x45 0x01 0x02 >/dev/null 2>&1

# 温度阈值（摄氏度）
TEMP_HIGH=80        # >80°C: 50%
TEMP_MEDIUM=60      # >60°C: 31%
TEMP_LOW=45         # >45°C: 16%

# 转速设置 - 使用您的系统的正确值！
FAN_50="0x3C"   # 50% - 您的原始命令
FAN_31="0x28"   # 31% (比0x3C低一些)
FAN_16="0x1E"   # 16% (您之前用的空闲值)
FAN_10="0x14"   # 10% (更低)

# 获取最高GPU温度
get_max_temp() {
    nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | \
    sort -nr | head -1 | tr -d '\r' | xargs
}

# 设置所有风扇
set_all_fans() {
    local speed=$1
    echo "[$(date '+%H:%M:%S')] 设置风扇: $speed"
    
    # 设置所有4个风扇控制器
    sudo ipmitool raw 0x30 0x70 0x66 0x01 0x00 $speed >/dev/null 2>&1
    sudo ipmitool raw 0x30 0x70 0x66 0x01 0x01 $speed >/dev/null 2>&1
    sudo ipmitool raw 0x30 0x70 0x66 0x01 0x02 $speed >/dev/null 2>&1
    sudo ipmitool raw 0x30 0x70 0x66 0x01 0x03 $speed >/dev/null 2>&1
}

# 防止重复运行
LOCK_FILE="/tmp/fan_control.lock"
if [ -f "$LOCK_FILE" ]; then
    OLD_PID=$(cat "$LOCK_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "脚本已在运行 (PID: $OLD_PID)"
        exit 1
    fi
fi
echo $$ > "$LOCK_FILE"
trap "rm -f $LOCK_FILE; exit" INT TERM EXIT

# 主程序
echo "=== 智能风扇控制系统 ==="
echo "使用您的转速值: 50%=0x3C, 31%=0x28, 16%=0x1E, 10%=0x14"
echo "温度阈值: >80°C=50%, >60°C=31%, >45°C=16%, 其他=10%"
echo "========================================"

LAST_SPEED=""
while true; do
    TEMP=$(get_max_temp)
    
    # 根据温度选择转速
    if [ "$TEMP" -ge "$TEMP_HIGH" ]; then
        SPEED="$FAN_50"
        MODE="高负载(50%)"
    elif [ "$TEMP" -ge "$TEMP_MEDIUM" ]; then
        SPEED="$FAN_31"
        MODE="中等(31%)"
    elif [ "$TEMP" -ge "$TEMP_LOW" ]; then
        SPEED="$FAN_16"
        MODE="低负载(16%)"
    else
        SPEED="$FAN_10"
        MODE="空闲(10%)"
    fi
    
    # 只在转速变化时设置
    if [ "$SPEED" != "$LAST_SPEED" ]; then
        echo "[$(date '+%H:%M:%S')] GPU温度: ${TEMP}°C → ${MODE}"
        set_all_fans "$SPEED"
        LAST_SPEED="$SPEED"
    fi
    
    sleep 10
done
