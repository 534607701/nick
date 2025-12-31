#!/bin/bash
echo "=========================================="
echo "   Registry 实时监控面板"
echo "=========================================="
echo "启动时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Registry地址: 192.168.0.23:5000"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

while true; do
    clear
    echo "=========================================="
    echo "   Registry 实时监控面板"
    echo "=========================================="
    echo "当前时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # 1. 显示当前连接数
    echo "🔗 客户端连接统计:"
    echo "----------------"
    CONNECTIONS=$(ss -tunp 2>/dev/null | grep :5000 | grep -v LISTEN | wc -l)
    echo -e "活跃连接数: ${GREEN}$CONNECTIONS${NC}"
    if [ $CONNECTIONS -gt 0 ]; then
        ss -tunp 2>/dev/null | grep :5000 | grep -v LISTEN | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | \
            while read count ip; do
                hostname=$(host "$ip" 2>/dev/null | grep -o "domain name pointer.*" | cut -d' ' -f4 | sed 's/\.$//' | head -1)
                if [ -n "$hostname" ] && [ "$hostname" != "NXDOMAIN" ]; then
                    echo -e "  ${CYAN}$hostname${NC} ($ip): ${GREEN}$count${NC} 个连接"
                else
                    echo -e "  ${YELLOW}$ip${NC}: ${GREEN}$count${NC} 个连接"
                fi
            done
    fi
    echo ""
    
    # 2. 显示最近5分钟的拉取日志
    echo "📥 最近拉取活动 (最近5分钟):"
    echo "----------------------------"
    
    # 创建临时文件存储解析结果
    TEMP_FILE=$(mktemp)
    
    # 获取并处理最近5分钟日志
    docker logs --since 5m docker-registry 2>&1 | \
        grep -E '(response completed.*/manifests/|GET /v2/.*/manifests/)' | \
        grep -v "_catalog" | \
        tail -20 > "$TEMP_FILE"
    
    if [ ! -s "$TEMP_FILE" ]; then
        echo "  无最近拉取活动"
    else
        # 处理JSON格式日志
        grep 'response completed' "$TEMP_FILE" | while read line; do
            # 提取时间
            time_str=$(echo "$line" | grep -o 'time="[^"]*"' | cut -d'"' -f2 | cut -c12-19)
            [ -z "$time_str" ] && time_str=$(date '+%H:%M:%S')
            
            # 提取客户端IP - 多种尝试
            client_ip=""
            # 尝试 remoteaddr
            if echo "$line" | grep -q 'remoteaddr='; then
                client_ip=$(echo "$line" | sed 's/.*remoteaddr=//;s/".*//' | cut -d: -f1)
            fi
            # 尝试 client
            if [ -z "$client_ip" ] && echo "$line" | grep -q 'http.request.client='; then
                client_ip=$(echo "$line" | sed 's/.*http.request.client="//;s/".*//' | cut -d: -f1)
            fi
            
            # 提取URI和镜像
            uri=$(echo "$line" | sed 's/.*http.request.uri="//;s/".*//')
            image=""
            if [[ "$uri" =~ ^/v2/.*/manifests/ ]]; then
                image=$(echo "$uri" | sed 's|^/v2/||;s|/manifests/.*||')
            fi
            
            # 提取HTTP方法
            method=$(echo "$line" | sed 's/.*http.request.method="//;s/".*//')
            
            if [ -n "$client_ip" ] && [ -n "$image" ] && [ "$method" = "GET" ]; then
                hostname=$(host "$client_ip" 2>/dev/null | grep -o "domain name pointer.*" | cut -d' ' -f4 | sed 's/\.$//' | head -1)
                if [ -n "$hostname" ] && [ "$hostname" != "NXDOMAIN" ]; then
                    echo -e "  ${BLUE}$time_str${NC} - ${CYAN}$hostname${NC} (${YELLOW}$client_ip${NC}) 拉取: ${GREEN}$image${NC}"
                else
                    echo -e "  ${BLUE}$time_str${NC} - ${YELLOW}$client_ip${NC} 拉取: ${GREEN}$image${NC}"
                fi
            fi
        done
        
        # 处理Apache格式日志
        grep 'GET /v2/.*/manifests/' "$TEMP_FILE" | grep -v 'response completed' | while read line; do
            # 提取时间
            time_str=$(echo "$line" | grep -o '\[[^]]*\]' | tr -d '[]' | cut -d: -f2-4 | sed 's/:/ /g' | awk '{print $1":"$2":"$3}')
            [ -z "$time_str" ] && time_str=$(date '+%H:%M:%S')
            
            # 提取客户端IP
            client_ip=$(echo "$line" | awk '{print $1}')
            
            # 提取URI和镜像
            uri=$(echo "$line" | sed 's/.*"GET //;s/ HTTP.*//')
            image=""
            if [[ "$uri" =~ ^/v2/.*/manifests/ ]]; then
                image=$(echo "$uri" | sed 's|^/v2/||;s|/manifests/.*||')
            fi
            
            if [ -n "$client_ip" ] && [ -n "$image" ] && [ "$client_ip" != "-" ]; then
                hostname=$(host "$client_ip" 2>/dev/null | grep -o "domain name pointer.*" | cut -d' ' -f4 | sed 's/\.$//' | head -1)
                if [ -n "$hostname" ] && [ "$hostname" != "NXDOMAIN" ]; then
                    echo -e "  ${BLUE}$time_str${NC} - ${CYAN}$hostname${NC} (${YELLOW}$client_ip${NC}) 拉取: ${GREEN}$image${NC}"
                else
                    echo -e "  ${BLUE}$time_str${NC} - ${YELLOW}$client_ip${NC} 拉取: ${GREEN}$image${NC}"
                fi
            fi
        done
    fi
    
    rm -f "$TEMP_FILE"
    
    # 3. 显示热门镜像统计
    echo ""
    echo "🔥 热门镜像统计 (今日):"
    echo "----------------------"
    
    # 使用直接的方法统计
    TODAY_STATS=$(docker logs --since 24h docker-registry 2>&1 | \
        grep -E 'GET /v2/.*/manifests/' | \
        sed 's|.*GET /v2/||;s|/manifests/.*||' | \
        sort | uniq -c | sort -rn | head -5)
    
    if [ -n "$TODAY_STATS" ]; then
        echo "$TODAY_STATS" | while read count img; do
            echo -e "  ${YELLOW}$img${NC}: ${GREEN}$count${NC} 次"
        done
    else
        echo "  无统计信息"
    fi
    
    # 4. 显示Registry状态
    echo ""
    echo "📊 Registry状态:"
    echo "---------------"
    if docker ps | grep -q docker-registry; then
        echo -e "容器状态: ${GREEN}running${NC}"
        
        # 计算运行时长
        start_time=$(docker inspect -f '{{.State.StartedAt}}' docker-registry 2>/dev/null)
        if [ -n "$start_time" ]; then
            start_seconds=$(date -d "$start_time" +%s 2>/dev/null || date +%s)
            now_seconds=$(date +%s)
            diff_seconds=$((now_seconds - start_seconds))
            
            hours=$((diff_seconds / 3600))
            minutes=$(( (diff_seconds % 3600) / 60 ))
            seconds=$((diff_seconds % 60))
            
            echo -e "运行时长: ${BLUE}$(printf "%02d:%02d:%02d" $hours $minutes $seconds)${NC}"
        fi
    else
        echo -e "容器状态: ${RED}stopped${NC}"
    fi
    
    # 存储使用情况
    if [ -d "/mnt/nvme/registry-data" ]; then
        storage_usage=$(du -sh /mnt/nvme/registry-data 2>/dev/null | cut -f1)
        echo -e "存储使用: ${YELLOW}$storage_usage${NC}"
    else
        echo -e "存储使用: ${RED}路径不存在${NC}"
    fi
    
    # 5. 显示Registry配置
    echo ""
    echo "⚙️  Registry配置:"
    echo "----------------"
    if docker ps | grep -q docker-registry; then
        log_level=$(docker exec docker-registry sh -c 'cat /etc/docker/registry/config.yml 2>/dev/null | grep -i "level:" | head -1 | cut -d: -f2 | tr -d " "' 2>/dev/null || echo "info")
        echo -e "日志级别: ${BLUE}${log_level}${NC}"
        
        # 显示日志格式
        echo -e "日志格式: ${YELLOW}mixed(JSON+Apache)${NC}"
    else
        echo -e "日志级别: ${RED}容器未运行${NC}"
    fi
    
    # 6. 显示调试信息
    echo ""
    echo "🔍 调试信息:"
    echo "----------"
    echo -e "日志样本数量: ${CYAN}$(docker logs --since 1m docker-registry 2>&1 | wc -l)${NC} 行"
    
    # 检查是否有拉取日志
    PULL_COUNT=$(docker logs --since 1m docker-registry 2>&1 | grep -c '/manifests/')
    echo -e "拉取请求数量: ${GREEN}$PULL_COUNT${NC} 个"
    
    if [ $PULL_COUNT -gt 0 ]; then
        echo -e "示例日志:"
        docker logs --since 1m docker-registry 2>&1 | grep '/manifests/' | head -1 | cut -c1-80 | sed 's/^/  /'
    fi
    
    # 7. 等待3秒刷新
    echo ""
    echo "=========================================="
    echo -e "${BLUE}监控自动刷新中... (按 Ctrl+C 退出)${NC}"
    sleep 3
done

chmod +x /root/registry-monitor.sh
