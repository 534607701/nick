#!/bin/bash
# /usr/local/bin/fan_smart_control.sh
# 智能风扇控制系统 - 根据您的温度要求调整

# 首先确保IPMI在手动模式
sudo ipmitool raw 0x30 0x45 0x01 0x02 >/dev/null 2>&1

# 温度阈值（摄氏度）
TEMP_CRITICAL=80      # >80°C: 60%
TEMP_HIGH=70          # >70°C: 50%
TEMP_MEDIUM=60        # >60°C: 40%
TEMP_LOW=45           # >45°C: 30%

# 转速设置 - 基于您提供的映射表
FAN_60="0x46"   # 60% - 8500 RPM
FAN_50="0x3C"   # 50% - 7400 RPM
FAN_40="0x28"   # 40% - 4500 RPM
FAN_30="0x1E"   # 30% - 估计值
FAN_10="0x0A"   # 10% - 估计值

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
echo "温度阈值设置:"
echo "  >80°C: 60% (0x46) - 8500 RPM"
echo "  >70°C: 50% (0x3C) - 7400 RPM"
echo "  >60°C: 40% (0x28) - 4500 RPM"
echo "  >45°C: 30% (0x1E)"
echo "  其他:   10% (0x0A)"
echo "========================================"

LAST_SPEED=""
while true; do
    TEMP=$(get_max_temp)
    
    # 根据温度选择转速
    if [ -n "$TEMP" ] && [ "$TEMP" -ge "$TEMP_CRITICAL" ]; then
        SPEED="$FAN_60"
        MODE="紧急(60%)"
    elif [ -n "$TEMP" ] && [ "$TEMP" -ge "$TEMP_HIGH" ]; then
        SPEED="$FAN_50"
        MODE="高负载(50%)"
    elif [ -n "$TEMP" ] && [ "$TEMP" -ge "$TEMP_MEDIUM" ]; then
        SPEED="$FAN_40"
        MODE="中等(40%)"
    elif [ -n "$TEMP" ] && [ "$TEMP" -ge "$TEMP_LOW" ]; then
        SPEED="$FAN_30"
        MODE="低负载(30%)"
    else
        SPEED="$FAN_10"
        MODE="空闲(10%)"
    fi
    
    # 只在转速变化时设置
    if [ "$SPEED" != "$LAST_SPEED" ]; then
        if [ -n "$TEMP" ]; then
            echo "[$(date '+%H:%M:%S')] GPU温度: ${TEMP}°C → ${MODE}"
        else
            echo "[$(date '+%H:%M:%S')] 无法获取温度 → ${MODE} (默认)"
        fi
        set_all_fans "$SPEED"
        LAST_SPEED="$SPEED"
    fi
    
    sleep 10
done
