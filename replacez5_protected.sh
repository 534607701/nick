#!/bin/bash

# 配置
TOKEN_FILE="/tmp/speedtest_current.token"
TOKEN_TTL=300
AUTH_SERVER="159.13.62.19"  # 你的VPS IP
AUTH_PORT="8080"

echo "=========================================="
echo "          隧道测速系统 v3.0"
echo "    需要验证码方可进行测速操作"
echo "=========================================="

# 检查当前token
if [ -f "$TOKEN_FILE" ]; then
    token_time=$(stat -c %Y "$TOKEN_FILE" 2>/dev/null || stat -f %m "$TOKEN_FILE" 2>/dev/null || echo 0)
    current_time=$(date +%s)
    time_diff=$((current_time - token_time))
    
    if [ $time_diff -gt $TOKEN_TTL ]; then
        echo "提示: 会话已过期，请重新验证"
        rm -f "$TOKEN_FILE"
    else
        current_token=$(cat "$TOKEN_FILE")
        echo "成功: 验证通过！开始执行测速系统。。。"
        echo ""
        # 删除已使用的token
        rm -f "$TOKEN_FILE"
        # 执行实际脚本
        exec /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/534607701/nick/main/replacez5_speedtest.sh)"
        exit 0
    fi
fi

# 验证码输入
echo "提示: 请输入一次性验证码:"
read -s -p "验证码: " input_code
echo ""

# 验证输入是否为空
if [ -z "$input_code" ]; then
    echo "错误: 验证码不能为空"
    exit 1
fi

# 连接到VPS服务器验证验证码
echo "正在验证..."
response_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "http://$AUTH_SERVER:$AUTH_PORT/verify?code=$input_code")

# 调试信息（可选）
echo "调试: 服务器响应码: $response_code"

if [ "$response_code" = "200" ]; then
    echo "成功: 验证码正确！生成访问令牌。。。"
    
    # 生成新的随机token
    if command -v openssl >/dev/null 2>&1; then
        new_token=$(openssl rand -hex 16 2>/dev/null)
    else
        new_token=$(date +%s%N | md5sum | head -c 32)
    fi
    
    echo "$new_token" > "$TOKEN_FILE"
    
    echo "成功: 令牌已生成，5分钟内有效"
    echo "提示: 重新执行命令以继续。。。"
else
    echo "错误: 验证失败 (响应码: $response_code)"
    echo "可能的原因:"
    echo "  - 验证码错误或已使用"
    echo "  - 验证服务未运行"
    echo "  - 网络连接问题"
    echo "提示: 请检查网络连接或联系管理员"
    exit 1
fi
