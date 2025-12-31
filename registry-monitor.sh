#!/bin/bash
echo "=========================================="
echo "   Registry 实时监控面板"
echo "=========================================="
echo "启动时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Registry地址: 192.168.0.23:5000"
echo ""

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
    CONNECTIONS=$(ss -tunp | grep :5000 | grep -v LISTEN | wc -l)
    echo "活跃连接数: $CONNECTIONS"
    ss -tunp | grep :5000 | grep -v LISTEN | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | \
        while read count ip; do
            # 尝试解析IP为主机名
            hostname=$(host "$ip" 2>/dev/null | awk '{print $NF}' | sed 's/\.$//')
            if [ -n "$hostname" ] && [ "$hostname" != "NXDOMAIN" ]; then
                echo "  $hostname ($ip): $count 个连接"
            else
                echo "  $ip: $count 个连接"
            fi
        done
    echo ""
    
    # 2. 显示最近5分钟的拉取日志 - 修复日志解析
    echo "📥 最近拉取活动 (最近5分钟):"
    echo "----------------------------"
    
    # 首先检查日志文件位置（如果使用文件驱动）
    LOG_OUTPUT=$(docker logs --since 5m docker-registry 2>&1)
    
    if [ -z "$LOG_OUTPUT" ]; then
        echo "  无最近拉取活动"
    else
        # 解析日志，提取拉取活动
        echo "$LOG_OUTPUT" | \
        grep -E "(response completed|GET.*/manifests/|pull.*manifest|HEAD.*/manifests/)" | \
        grep -E "200|SUCCESS" | \
        tail -10 | \
        while read line; do
            # 尝试多种日志格式解析
            timestamp=$(echo "$line" | sed -n 's/^\([0-9\-:T.]*\).*/\1/p' | head -c 8 | sed 's/T/ /')
            
            # 提取客户端IP
            client_ip=$(echo "$line" | sed -n 's/.*remoteaddr=\([^ ]*\).*/\1/p')
            if [ -z "$client_ip" ]; then
                client_ip=$(echo "$line" | sed -n 's/.*from=\([^ ]*\).*/\1/p')
            fi
            if [ -z "$client_ip" ]; then
                client_ip=$(echo "$line" | sed -n 's/.*client=\([^ ]*\).*/\1/p')
            fi
            
            # 提取镜像信息
            image=$(echo "$line" | sed -n 's/.*GET.*\/v2\/\([^ ]*\)\/manifests\/.*/\1/p')
            if [ -z "$image" ]; then
                image=$(echo "$line" | sed -n 's/.*pull.*manifest.*library\/\([^ ]*\).*/\1/p')
                if [ -n "$image" ]; then
                    image="library/$image"
                fi
            fi
            
            # 如果没有获取到时间戳，使用当前时间
            if [ -z "$timestamp" ]; then
                timestamp=$(date '+%H:%M:%S')
            fi
            
            # 如果获取到了客户端和镜像信息，则显示
            if [ -n "$client_ip" ] && [ -n "$image" ]; then
                # 尝试解析主机名
                hostname=$(echo "$client_ip" | cut -d: -f1 | xargs host 2>/dev/null | awk '{print $NF}' | sed 's/\.$//')
                if [ -n "$hostname" ] && [ "$hostname" != "NXDOMAIN" ]; then
                    echo "  $timestamp - $hostname ($client_ip) 拉取: $image"
                else
                    echo "  $timestamp - $client_ip 拉取: $image"
                fi
            fi
        done
    fi
    
    # 如果上面没输出，尝试更简单的日志解析
    if [ -z "$(docker logs --since 5m docker-registry 2>/dev/null | grep -i pull)" ]; then
        echo "  无拉取活动记录"
    else
        # 备份方法：显示原始拉取日志
        docker logs --since 5m docker-registry 2>/dev/null | grep -i pull | tail -5 | \
        while read line; do
            time_part=$(echo "$line" | awk '{print $1}')
            img_part=$(echo "$line" | grep -o "library/[^ ]*")
            client_part=$(echo "$line" | grep -o "from=[^ ]*" | cut -d= -f2)
            
            if [ -n "$img_part" ] && [ -n "$client_part" ]; then
                echo "  $time_part - $client_part 拉取: $img_part"
            fi
        done
    fi
    
    # 3. 显示热门镜像统计
    echo ""
    echo "🔥 热门镜像统计 (今日):"
    echo "----------------------"
    # 使用多种方法提取镜像信息
    docker logs --since 24h docker-registry 2>/dev/null | \
        grep -E "(GET.*/manifests/|pull.*manifest)" | \
        sed -n 's/.*\/v2\/\([^/]*\/[^/]*\)\/manifests\/.*/\1/p' | \
        sed -n 's/.*pull.*manifest.*library\/\([^ ]*\).*/library\/\1/p' | \
        grep -v "^$" | \
        sort | uniq -c | sort -rn | head -5 | \
        while read count img; do
            echo "  $img: $count 次"
        done
    
    # 4. 显示Registry状态
    echo ""
    echo "📊 Registry状态:"
    echo "---------------"
    echo "容器状态: $(docker inspect -f '{{.State.Status}}' docker-registry 2>/dev/null || echo '容器未运行')"
    
    # 计算运行时长
    if docker inspect docker-registry &>/dev/null; then
        start_time=$(docker inspect -f '{{.State.StartedAt}}' docker-registry)
        start_seconds=$(date -d "$start_time" +%s)
        now_seconds=$(date +%s)
        diff_seconds=$((now_seconds - start_seconds))
        
        hours=$((diff_seconds / 3600))
        minutes=$(( (diff_seconds % 3600) / 60 ))
        seconds=$((diff_seconds % 60))
        
        printf "运行时长: %02d:%02d:%02d\n" $hours $minutes $seconds
    else
        echo "运行时长: 容器未运行"
    fi
    
    echo "存储使用: $(du -sh /mnt/nvme/registry-data 2>/dev/null | cut -f1 || echo 'N/A')"
    
    # 5. 显示Registry配置（可选）
    echo ""
    echo "⚙️  Registry配置:"
    echo "----------------"
    echo "日志级别: $(docker exec docker-registry cat /etc/docker/registry/config.yml 2>/dev/null | grep -i loglevel | awk '{print $2}' || echo 'default')"
    
    # 6. 等待3秒刷新
    echo ""
    echo "=========================================="
    echo "监控自动刷新中... (按 Ctrl+C 退出)"
    sleep 3
done
