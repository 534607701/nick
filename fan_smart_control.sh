#!/bin/bash
# /usr/local/bin/fan_smart_control.sh
# 智能风扇控制系统 - 自动适配超微服务器

# ==================== 配置区域 ====================
# 温度阈值（摄氏度）
TEMP_CRITICAL=80      # >80°C: 60%
TEMP_HIGH=70          # >70°C: 50%
TEMP_MEDIUM=60        # >60°C: 40%
TEMP_LOW=45           # >45°C: 30%

# 转速设置（十六进制，0x00-0x64 对应 0-100%）
FAN_60="0x46"   # 60%
FAN_50="0x3C"   # 50%
FAN_40="0x28"   # 40%
FAN_30="0x1E"   # 30%
FAN_10="0x0A"   # 10%
# =================================================

# 检测可用的手动模式命令
detect_manual_mode_cmd() {
    # 测试命令1: X10/X11 常用格式
    if sudo ipmitool raw 0x30 0x45 0x01 0x01 2>/dev/null | grep -q "^[0-9]"; then
        echo "0x30 0x45 0x01 0x01"
        return 0
    fi
    
    # 测试命令2: X11/X12 另一种格式
    if sudo ipmitool raw 0x30 0x30 0x01 0x01 2>/dev/null | grep -q "^[0-9]"; then
        echo "0x30 0x30 0x01 0x01"
        return 0
    fi
    
    # 测试命令3: X9 系列格式
    if sudo ipmitool raw 0x30 0x91 0x5A 0x03 0x00 0xFF 2>/dev/null | grep -q "^[0-9]"; then
        echo "0x30 0x91 0x5A 0x03 0x00 0xFF"
        return 0
    fi
    
    # 没有找到手动模式命令，返回空
    echo ""
    return 1
}

# 检测可用的风扇控制命令格式
detect_fan_control_cmd() {
    # 测试命令格式1: 标准格式 (Zone 0-3)
    if sudo ipmitool raw 0x30 0x70 0x66 0x01 0x00 0x0A 2>/dev/null; then
        echo "standard"
        return 0
    fi
    
    # 测试命令格式2: X11/X12 格式
    if sudo ipmitool raw 0x30 0x91 0x5A 0x03 0x00 0x0A 2>/dev/null; then
        echo "x11"
        return 0
    fi
    
    echo "unknown"
    return 1
}

# 设置风扇为手动模式（自动适配）
set_manual_mode() {
    local cmd=$(detect_manual_mode_cmd)
    
    if [ -z "$cmd" ]; then
        echo "[$(date '+%H:%M:%S')] ⚠ 未检测到手动模式命令，跳过（直接设置转速可能仍有效）"
        return 1
    fi
    
    echo "[$(date '+%H:%M:%S')] 设置手动模式: $cmd"
    sudo ipmitool raw $cmd >/dev/null 2>&1
    sleep 1
    return 0
}

# 获取最高GPU温度
get_max_temp() {
    nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | \
    sort -nr | head -1 | tr -d '\r' | xargs
}

# 设置所有风扇（自动适配）
set_all_fans() {
    local speed=$1
    local format=$(detect_fan_control_cmd)
    
    echo "[$(date '+%H:%M:%S')] 设置风扇转速: $speed"
    
    case "$format" in
        standard)
            # 标准格式：4个分区
            sudo ipmitool raw 0x30 0x70 0x66 0x01 0x00 $speed >/dev/null 2>&1
            sudo ipmitool raw 0x30 0x70 0x66 0x01 0x01 $speed >/dev/null 2>&1
            sudo ipmitool raw 0x30 0x70 0x66 0x01 0x02 $speed >/dev/null 2>&1
            sudo ipmitool raw 0x30 0x70 0x66 0x01 0x03 $speed >/dev/null 2>&1
            ;;
        x11)
            # X11/X12 格式
            sudo ipmitool raw 0x30 0x91 0x5A 0x03 0x00 $speed >/dev/null 2>&1
            sudo ipmitool raw 0x30 0x91 0x5A 0x03 0x01 $speed >/dev/null 2>&1
            ;;
        *)
            # 未知格式，尝试标准格式
            echo "[$(date '+%H:%M:%S')] ⚠ 未知格式，尝试标准格式"
            sudo ipmitool raw 0x30 0x70 0x66 0x01 0x00 $speed >/dev/null 2>&1
            sudo ipmitool raw 0x30 0x70 0x66 0x01 0x01 $speed >/dev/null 2>&1
            sudo ipmitool raw 0x30 0x70 0x66 0x01 0x02 $speed >/dev/null 2>&1
            sudo ipmitool raw 0x30 0x70 0x66 0x01 0x03 $speed >/dev/null 2>&1
            ;;
    esac
}

# 获取当前风扇控制模式
get_fan_mode() {
    sudo ipmitool raw 0x30 0x45 0x00 2>/dev/null | tr -d ' ' | tr -d '\n'
}

# 检查是否需要切换手动模式（可选，不强制）
try_manual_mode() {
    local current_mode=$(get_fan_mode)
    
    # 如果已经是手动模式或命令不支持，直接返回
    if [ "$current_mode" = "01" ] || [ "$current_mode" = "1" ]; then
        return 0
    fi
    
    # 尝试设置手动模式（不阻塞主流程）
    set_manual_mode
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

# ==================== 主程序 ====================
echo "=== 智能风扇控制系统 ==="
echo "温度阈值设置:"
echo "  >80°C: 60% (0x46)"
echo "  >70°C: 50% (0x3C)"
echo "  >60°C: 40% (0x28)"
echo "  >45°C: 30% (0x1E)"
echo "  其他:   10% (0x0A)"
echo "========================================"

# 检测系统信息
echo "[$(date '+%H:%M:%S')] 检测硬件信息..."
BOARD=$(sudo dmidecode -s baseboard-product-name 2>/dev/null | head -1)
echo "[$(date '+%H:%M:%S')] 主板型号: ${BOARD:-未知}"

# 检测并显示风扇控制格式
FAN_FORMAT=$(detect_fan_control_cmd)
echo "[$(date '+%H:%M:%S')] 风扇控制格式: $FAN_FORMAT"

# 尝试设置手动模式（不强制，不影响主流程）
try_manual_mode

# 主循环
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
            echo "[$(date '+%H:%M:%S')] ⚠ 无法获取温度 → ${MODE} (默认)"
        fi
        set_all_fans "$SPEED"
        LAST_SPEED="$SPEED"
    fi
    
    sleep 10
done
