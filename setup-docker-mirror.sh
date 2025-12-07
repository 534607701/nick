#!/bin/bash

# 配置客户端使用Docker Registry代理
MIRROR_ADDR="192.168.0.23:5000"

echo "=== 配置Docker客户端使用Registry代理 ==="

# 1. 检查Docker是否安装
if ! command -v docker &> /dev/null; then
    echo "错误: Docker未安装"
    exit 1
fi

# 2. 备份现有配置
CONFIG_FILE="/etc/docker/daemon.json"
if [ -f "$CONFIG_FILE" ]; then
    BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    sudo cp "$CONFIG_FILE" "$BACKUP_FILE"
    echo "已备份原有配置: $BACKUP_FILE"
fi

# 3. 创建新的配置
echo "配置Registry镜像: http://$MIRROR_ADDR"
sudo tee "$CONFIG_FILE" > /dev/null <<EOF
{
  "registry-mirrors": ["http://$MIRROR_ADDR"],
  "insecure-registries": ["$MIRROR_ADDR"]
}
EOF

# 4. 重启Docker服务
echo "重启Docker服务..."
if systemctl is-active docker &> /dev/null; then
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    echo "Docker已重启"
else
    echo "警告: Docker服务未运行"
fi

# 5. 验证配置
echo -e "\n=== 验证配置 ==="
if docker info 2>/dev/null | grep -A5 "Registry Mirrors"; then
    echo "✅ 配置成功！"
    echo "Registry代理已启用: http://$MIRROR_ADDR"
else
    echo "❌ 配置可能未生效，请检查Docker服务状态"
fi

# 6. 测试连接
echo -e "\n=== 测试连接 ==="
if timeout 10 docker pull hello-world &> /dev/null; then
    echo "✅ 连接测试成功！"
else
    echo "⚠️  连接测试失败，请检查网络连通性"
fi
