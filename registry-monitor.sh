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

# 缓存主机名解析
declare -A HOSTNAME_CACHE

get_hostname() {
    local ip=$1
    # 检查缓存
    if [ -n "${HOSTNAME_CACHE[$ip]}" ]; then
        echo "${HOSTNAME_CACHE[$ip]}"
        return
    fi
    
    # 解析主机名
    local hostname
    if command -v host &>/dev/null; then
        hostname=$(host "$ip" 2>/dev/null | grep -o "domain name pointer.*" | cut -d' ' -f4 | sed 's/\.$//' | head -1)
    fi
    
    if [ -z "$hostname" ] || [ "$hostname" = "NXDOMAIN" ]; then
        hostname=""
    fi
    
    # 存入缓存
    HOSTNAME_CACHE[$ip]="$hostname"
    echo "$hostname"
}

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
                hostname=$(get_hostname "$ip")
                if [ -n "$hostname" ]; then
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
    
    # 获取最近5分钟的日志
    RECENT_LOGS=$(docker logs --since 5m docker-registry 2>&1)
    ACTIVITY_COUNT=0
    
    if [ -z "$RECENT_LOGS" ]; then
        echo "  无最近拉取活动"
    else
        # 解析JSON格式的日志（response completed）
        echo "$RECENT_LOGS" | grep "response completed" | grep -v "_catalog" | tail -10 | while read line; do
            # 提取时间
            time_str=$(echo "$line" | grep -o 'time="[^"]*"' | cut -d'"' -f2 | cut -c12-19)
            [ -z "$time_str" ] && time_str=$(date '+%H:%M:%S')
            
            # 提取客户端IP
            client_ip=$(echo "$line" | grep -o 'http.request.remoteaddr="[^"]*"' | cut -d'"' -f2 | cut -d: -f1)
            [ -z "$client_ip" ] && client_ip=$(echo "$line" | grep -o 'http.request.client="[^"]*"' | cut -d'"' -f2 | cut -d: -f1)
            
            # 提取镜像名称（从URI）
            uri=$(echo "$line" | grep -o 'http.request.uri="[^"]*"' | cut -d'"' -f2)
            image=""
            if [[ "$uri" == /v2/*/manifests/* ]]; then
                # 提取 /v2/library/alpine/manifests/latest -> library/alpine
                image=$(echo "$uri" | sed 's|^/v2/||;s|/manifests/.*||')
            fi
            
            # 提取HTTP方法
            method=$(echo "$line" | grep -o 'http.request.method="[^"]*"' | cut -d'"' -f2)
            
            if [ -n "$client_ip" ] && [ -n "$image" ] && [ "$method" = "GET" ]; then
                ACTIVITY_COUNT=$((ACTIVITY_COUNT + 1))
                hostname=$(get_hostname "$client_ip")
                if [ -n "$hostname" ]; then
                    echo -e "  ${BLUE}$time_str${NC} - ${CYAN}$hostname${NC} (${YELLOW}$client_ip${NC}) 拉取: ${GREEN}$image${NC}"
                else
                    echo -e "  ${BLUE}$time_str${NC} - ${YELLOW}$client_ip${NC} 拉取: ${GREEN}$image${NC}"
                fi
            fi
        done
        
        # 解析Apache格式的日志
        echo "$RECENT_LOGS" | grep 'GET /v2/.*/manifests/' | grep -v "_catalog" | tail -5 | while read line; do
            # 提取时间 [31/Dec/2025:04:08:01
            time_str=$(echo "$line" | grep -o '\[.*\]' | tr -d '[]' | cut -d: -f2-4 | sed 's/:/ /g' | awk '{print $1":"$2":"$3}')
            [ -z "$time_str" ] && time_str=$(date '+%H:%M:%S')
            
            # 提取客户端IP（第一个字段）
            client_ip=$(echo "$line" | awk '{print $1}')
            
            # 提取URI
            uri=$(echo "$line" | grep -o 'GET /v2/[^ ]*' | sed 's/GET //')
            image=""
            if [[ "$uri" == /v2/*/manifests/* ]]; then
                image=$(echo "$uri" | sed 's|^/v2/||;s|/manifests/.*||')
            fi
            
            if [ -n "$client_ip" ] && [ -n "$image" ] && [ "$client_ip" != "-" ]; then
                ACTIVITY_COUNT=$((ACTIVITY_COUNT + 1))
                hostname=$(get_hostname "$client_ip")
                if [ -n "$hostname" ]; then
                    echo -e "  ${BLUE}$time_str${NC} - ${CYAN}$hostname${NC} (${YELLOW}$client_ip${NC}) 拉取: ${GREEN}$image${NC}"
                else
                    echo -e "  ${BLUE}$time_str${NC} - ${YELLOW}$client_ip${NC} 拉取: ${GREEN}$image${NC}"
                fi
            fi
        done
        
        if [ $ACTIVITY_COUNT -eq 0 ]; then
            echo "  无最近拉取活动"
        fi
    fi
    
    # 3. 显示热门镜像统计
    echo ""
    echo "🔥 热门镜像统计 (今日):"
    echo "----------------------"
    
    # 获取今日日志
    TODAY_LOGS=$(docker logs --since 24h docker-registry 2>&1)
    
    if [ -n "$TODAY_LOGS" ]; then
        echo "$TODAY_LOGS" | \
            grep -E '(response completed.*GET.*/manifests/|GET /v2/.*/manifests/)' | \
            grep -v "_catalog" | \
            sed 's/.*http.request.uri="//;s/".*//;s|.*GET /v2/|/v2/|' | \
            grep '/v2/' | \
            sed 's|^/v2/||;s|/manifests/.*||' | \
            sort | uniq -c | sort -rn | head -5 | \
            while read count img; do
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
            start_seconds=$(date -d "$start_time" +%s 2>/dev/null || date +%s -d '1 hour ago')
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
    else
        echo -e "日志级别: ${RED}容器未运行${NC}"
    fi
    
    # 6. 显示最后2条完整日志（用于调试）
    echo ""
    echo "📝 最近完整日志:"
    echo "---------------"
    docker logs --tail 2 docker-registry 2>&1 | while read line; do
        short_line=$(echo "$line" | cut -c1-100)
        echo "  $short_line"
    done
    
    # 7. 等待3秒刷新
    echo ""
    echo "=========================================="
    echo -e "${BLUE}监控自动刷新中... (按 Ctrl+C 退出)${NC}"
    sleep 3
done


chmod +x /root/registry-monitor.sh
