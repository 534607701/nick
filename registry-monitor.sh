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
    
    # 2. 显示最近5分钟的活动
    echo "📥 最近活动 (最近5分钟):"
    echo "-----------------------"
    
    RECENT_LOGS=$(docker logs --since 5m docker-registry 2>&1)
    
    if [ -z "$RECENT_LOGS" ]; then
        echo "  无活动"
    else
        ACTIVITY_COUNT=0
        
        # 显示所有活动
        echo "$RECENT_LOGS" | tail -10 | while read line; do
            # 解析时间戳
            time_str=""
            if echo "$line" | grep -q 'time="'; then
                # JSON格式时间
                time_str=$(echo "$line" | grep -o 'time="[^"]*"' | cut -d'"' -f2 | cut -c12-19)
            elif echo "$line" | grep -q '\[.*\]'; then
                # Apache格式时间
                time_str=$(echo "$line" | grep -o '\[[^]]*\]' | tr -d '[]' | cut -d: -f2-4 | sed 's/:/ /g' | awk '{print $1":"$2":"$3}')
            fi
            [ -z "$time_str" ] && time_str=$(date '+%H:%M:%S')
            
            # 提取客户端IP
            client_ip=""
            if echo "$line" | grep -q 'remoteaddr='; then
                client_ip=$(echo "$line" | sed 's/.*remoteaddr="//;s/".*//' | cut -d: -f1)
            elif echo "$line" | grep -q '^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+'; then
                client_ip=$(echo "$line" | awk '{print $1}')
            fi
            
            # 提取请求类型
            request_type=""
            if echo "$line" | grep -q '/_catalog'; then
                request_type="查询镜像列表"
            elif echo "$line" | grep -q 'GET / '; then
                request_type="访问首页"
            elif echo "$line" | grep -q '/manifests/'; then
                request_type="拉取镜像"
                # 提取镜像名称
                image=$(echo "$line" | sed 's|.*/v2/||;s|/manifests/.*||')
                request_type="$request_type ($image)"
            fi
            
            if [ -n "$client_ip" ] && [ -n "$request_type" ]; then
                ACTIVITY_COUNT=$((ACTIVITY_COUNT + 1))
                hostname=$(host "$client_ip" 2>/dev/null | grep -o "domain name pointer.*" | cut -d' ' -f4 | sed 's/\.$//' | head -1)
                if [ -n "$hostname" ] && [ "$hostname" != "NXDOMAIN" ]; then
                    echo -e "  ${BLUE}$time_str${NC} - ${CYAN}$hostname${NC} (${YELLOW}$client_ip${NC}) ${GREEN}$request_type${NC}"
                else
                    echo -e "  ${BLUE}$time_str${NC} - ${YELLOW}$client_ip${NC} ${GREEN}$request_type${NC}"
                fi
            fi
        done
        
        if [ $ACTIVITY_COUNT -eq 0 ]; then
            echo "  无客户端活动"
        fi
    fi
    
    # 3. 显示历史热门镜像统计（今日）
    echo ""
    echo "📊 历史热门镜像 (今日):"
    echo "----------------------"
    
    # 使用更准确的方法统计
    HISTORICAL_STATS=$(docker logs --since 24h docker-registry 2>&1 | \
        grep -E 'GET /v2/.*/manifests/|response completed.*/manifests/' | \
        sed 's|.*/v2/||g; s|/manifests/.*||g' | \
        grep -v "^$" | \
        sort | uniq -c | sort -rn | head -5)
    
    if [ -n "$HISTORICAL_STATS" ]; then
        echo "$HISTORICAL_STATS" | while read count img; do
            echo -e "  ${YELLOW}$img${NC}: ${GREEN}$count${NC} 次"
        done
    else
        echo "  无镜像拉取历史"
    fi
    
    # 4. 显示Registry状态
    echo ""
    echo "⚡ Registry状态:"
    echo "----------------"
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
        
        # 显示镜像数量
        image_count=$(find /mnt/nvme/registry-data/docker/registry/v2/repositories -maxdepth 2 -type d 2>/dev/null | grep -c "_manifests" || echo "0")
        echo -e "镜像数量: ${CYAN}$image_count${NC} 个"
    else
        echo -e "存储使用: ${RED}路径不存在${NC}"
    fi
    
    # 5. 显示访问统计
    echo ""
    echo "📈 访问统计 (最近1小时):"
    echo "----------------------"
    
    HOUR_STATS=$(docker logs --since 1h docker-registry 2>&1 | \
        grep -c "GET ")
    
    CATALOG_REQUESTS=$(docker logs --since 1h docker-registry 2>&1 | \
        grep -c "_catalog")
    
    MANIFEST_REQUESTS=$(docker logs --since 1h docker-registry 2>&1 | \
        grep -c "manifests")
    
    echo -e "总请求数: ${BLUE}$HOUR_STATS${NC}"
    echo -e "列表查询: ${YELLOW}$CATALOG_REQUESTS${NC}"
    echo -e "镜像拉取: ${GREEN}$MANIFEST_REQUESTS${NC}"
    
    # 6. 显示客户端IP统计
    echo ""
    echo "👥 客户端统计 (今日):"
    echo "-------------------"
    
    CLIENT_STATS=$(docker logs --since 24h docker-registry 2>&1 | \
        grep -o 'remoteaddr="[^"]*"' | cut -d'"' -f2 | cut -d: -f1 | \
        sort | uniq -c | sort -rn | head -3)
    
    if [ -n "$CLIENT_STATS" ]; then
        echo "$CLIENT_STATS" | while read count ip; do
            hostname=$(host "$ip" 2>/dev/null | grep -o "domain name pointer.*" | cut -d' ' -f4 | sed 's/\.$//' | head -1)
            if [ -n "$hostname" ] && [ "$hostname" != "NXDOMAIN" ]; then
                echo -e "  ${CYAN}$hostname${NC} ($ip): ${GREEN}$count${NC} 次"
            else
                echo -e "  ${YELLOW}$ip${NC}: ${GREEN}$count${NC} 次"
            fi
        done
    else
        echo "  无客户端记录"
    fi
    
    # 7. 等待3秒刷新
    echo ""
    echo "=========================================="
    echo -e "${BLUE}监控自动刷新中... (按 Ctrl+C 退出)${NC}"
    sleep 3
done

chmod +x /root/registry-monitor.sh
