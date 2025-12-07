#!/bin/bash
# monitor-registry.sh

REGISTRY="192.168.0.23:5000"

echo "=== Docker Registry 监控 ==="
echo "时间: $(date)"
echo ""

# Docker 服务状态
echo "1. Docker 服务状态:"
systemctl is-active docker
echo ""

# Registry 容器状态
echo "2. Registry 容器状态:"
docker ps | grep registry
echo ""

# 镜像数量
echo "3. 镜像仓库统计:"
curl -s http://${REGISTRY}/v2/_catalog | jq '.repositories | length' 2>/dev/null || 
  curl -s http://${REGISTRY}/v2/_catalog | grep -o '"repositories"' | wc -l
echo ""

# 存储使用情况
echo "4. 存储使用情况:"
du -sh /data/registry
echo ""

# 网络连接
echo "5. Registry 端口监听:"
netstat -tlnp | grep 5000
echo ""

# 最近操作日志
echo "6. 最近操作日志:"
docker logs --tail 10 registry 2>/dev/null || echo "无日志"
