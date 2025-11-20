#!/bin/bash

# 配置
TOKEN_FILE="/tmp/speedtest_current.token"
TOKEN_TTL=300
AUTH_SERVER="159.13.62.19"  # 你的VPS IP
SPEEDTEST_SCRIPT_URL="https://raw.githubusercontent.com/534607701/nick/main/replacez5_speedtest.sh"

# 颜色定义
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# 进度条函数
progress_bar() {
    local duration=${1:-10}
    local bar_length=50
    local sleep_interval=$(echo "scale=3; $duration / $bar_length" | bc)
    local progress=0
    
    printf "${CYAN}🚀 进度 [${NC}"
    
    for ((i=0; i<bar_length; i++)); do
        printf "${GREEN}█${NC}"
        sleep $sleep_interval
    done
    
    printf "${CYAN}] 100%%${NC}\n"
}

# 彩色输出函数
color_echo() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

clear
echo "=========================================="
color_echo $PURPLE "          隧道测速系统 v3.0"
color_echo $CYAN "    需要验证码方可进行测速操作"
echo "=========================================="
echo ""

# 检查当前token
if [ -f "$TOKEN_FILE" ]; then
    token_time=$(stat -c %Y "$TOKEN_FILE" 2>/dev/null || stat -f %m "$TOKEN_FILE" 2>/dev/null || echo 0)
    current_time=$(date +%s)
    time_diff=$((current_time - token_time))
    
    if [ $time_diff -gt $TOKEN_TTL ]; then
        color_echo $YELLOW "⚠️  提示: 会话已过期，请重新验证"
        rm -f "$TOKEN_FILE"
    else
        current_token=$(cat "$TOKEN_FILE")
        color_echo $GREEN "✅ 成功: 验证通过！开始执行测速系统。。。"
        echo ""
        
        # 删除已使用的token
        rm -f "$TOKEN_FILE"
        
        # 显示进度条
        color_echo $BLUE "📥 正在下载测速脚本..."
        progress_bar 3
        
        # 下载并执行脚本
        temp_script=$(mktemp)
        if curl -fsSL "$SPEEDTEST_SCRIPT_URL" -o "$temp_script"; then
            color_echo $GREEN "✅ 测速脚本下载成功"
            color_echo $BLUE "🔧 开始执行测速优化..."
            progress_bar 5
            
            chmod +x "$temp_script"
            # 使用sudo执行，因为测速脚本需要修改系统文件
            sudo bash "$temp_script"
            rm -f "$temp_script"
            
            color_echo $GREEN "🎉 测速优化完成！"
        else
            color_echo $RED "❌ 错误: 无法下载测速脚本"
            rm -f "$temp_script"
            exit 1
        fi
        exit 0
    fi
fi

# 验证码输入
color_echo $YELLOW "🔐 提示: 请输入一次性验证码:"
read -s -p "$(echo -e ${CYAN}'验证码: '${NC})" input_code
echo ""

# 验证过程
color_echo $BLUE "🔍 正在验证验证码..."
progress_bar 2

# 连接到你的VPS服务器验证验证码
response_code=$(curl -fs -o /dev/null -w "%{http_code}" "http://$AUTH_SERVER:8080/verify?code=$input_code" 2>/dev/null || echo "000")

if [ "$response_code" = "200" ]; then
    color_echo $GREEN "✅ 验证码正确！"
    color_echo $BLUE "🔑 生成访问令牌..."
    progress_bar 2
    
    # 生成新的随机token
    new_token=$(openssl rand -hex 16 2>/dev/null || date +%s%N | md5sum | head -c 32)
    echo "$new_token" > "$TOKEN_FILE"
    
    color_echo $GREEN "✅ 令牌已生成，5分钟内有效"
    color_echo $YELLOW "💡 提示: 重新执行命令以继续。。。"
else
    color_echo $RED "❌ 错误: 验证码错误或已使用"
    color_echo $YELLOW "📞 提示: 请向管理员获取新的验证码"
    exit 1
fi
