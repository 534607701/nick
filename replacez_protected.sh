#!/bin/bash

# 配置
AUTH_FILE="/tmp/speedtest_auth.codes"
TOKEN_FILE="/tmp/speedtest_current.token"
TOKEN_TTL=300  # 5分钟有效期

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 显示横幅
echo -e "${BLUE}"
echo "╔══════════════════════════════════════╗"
echo "║          隧道测速系统 v2.0           ║"
echo "║    需要验证码方可进行测速操作        ║"
echo "╚══════════════════════════════════════╝"
echo -e "${NC}"

# 检查认证文件是否存在
if [ ! -f "$AUTH_FILE" ]; then
    echo -e "${RED}❌ 系统未初始化，请联系管理员获取验证码${NC}"
    exit 1
fi

# 检查当前token
if [ -f "$TOKEN_FILE" ]; then
    token_time=$(stat -c %Y "$TOKEN_FILE" 2>/dev/null || echo 0)
    current_time=$(date +%s)
    time_diff=$((current_time - token_time))
    
    if [ $time_diff -gt $TOKEN_TTL ]; then
        echo -e "${YELLOW}⚠️ 验证码已过期，请重新获取${NC}"
        rm -f "$TOKEN_FILE"
    else
        current_token=$(cat "$TOKEN_FILE")
        echo -e "${GREEN}✅ 验证通过！开始执行测速系统。。。${NC}"
        echo ""
        # 删除已使用的token
        rm -f "$TOKEN_FILE"
        # 执行实际脚本
        exec /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/534607701/nick/main/replacez_speedtest.sh)"
        exit 0
    fi
fi

# 修复：检查是否在终端中运行，如果不是则提示下载执行
if [ ! -t 0 ]; then
    echo -e "${YELLOW}⚠️ 检测到非交互式执行${NC}"
    echo -e "${BLUE}📥 请使用以下命令下载后执行：${NC}"
    echo "curl -fsSL https://raw.githubusercontent.com/534607701/nick/main/replacez_protected_bin -o speedtest_protected && chmod +x speedtest_protected && ./speedtest_protected"
    exit 1
fi

# 验证码输入
echo -e "${YELLOW}🔐 请输入一次性验证码:${NC}"
read -s -p "验证码: " input_code
echo ""

# 验证验证码
if grep -q "^$input_code$" "$AUTH_FILE"; then
    echo -e "${GREEN}✅ 验证码正确！生成访问令牌。。。${NC}"
    
    # 生成新的随机token
    new_token=$(openssl rand -hex 16 2>/dev/null || date +%s%N | md5sum | head -c 32)
    echo "$new_token" > "$TOKEN_FILE"
    
    # 删除已使用的验证码
    grep -v "^$input_code$" "$AUTH_FILE" > "$AUTH_FILE.tmp" && mv "$AUTH_FILE.tmp" "$AUTH_FILE"
    
    echo -e "${GREEN}🎯 令牌已生成，5分钟内有效${NC}"
    echo -e "${BLUE}🔄 重新执行命令以继续。。。${NC}"
else
    echo -e "${RED}❌ 验证码错误或已使用${NC}"
    echo -e "${YELLOW}💡 请向管理员获取新的验证码${NC}"
    exit 1
fi
