#!/bin/bash
# registry-manager.sh

REGISTRY_DATA="/data/registry"
REGISTRY_PORT="5000"

case "$1" in
    start)
        echo "启动 Docker Registry..."
        docker run -d \
          -p 127.0.0.1:${REGISTRY_PORT}:5000 \
          --restart=always \
          --name registry \
          -v ${REGISTRY_DATA}:/var/lib/registry \
          registry:2
        ;;
    stop)
        echo "停止 Docker Registry..."
        docker stop registry
        docker rm registry
        ;;
    restart)
        echo "重启 Docker Registry..."
        $0 stop
        $0 start
        ;;
    status)
        echo "Registry 状态："
        docker ps | grep registry
        echo ""
        echo "存储使用情况："
        du -sh ${REGISTRY_DATA}
        echo ""
        echo "镜像列表："
        curl -s http://localhost:${REGISTRY_PORT}/v2/_catalog | python3 -m json.tool
        ;;
    cleanup)
        echo "清理未使用的镜像..."
        docker system prune -af
        ;;
    push)
        if [ -z "$2" ]; then
            echo "用法: $0 push <镜像名> [标签]"
            exit 1
        fi
        IMAGE=$2
        TAG=${3:-latest}
        
        echo "推送镜像: ${IMAGE}:${TAG}"
        docker pull ${IMAGE}:${TAG}
        docker tag ${IMAGE}:${TAG} 192.168.0.23:${REGISTRY_PORT}/${IMAGE}:${TAG}
        docker push 192.168.0.23:${REGISTRY_PORT}/${IMAGE}:${TAG}
        ;;
    list)
        echo "已缓存的镜像："
        docker images | grep "192.168.0.23"
        echo ""
        echo "Registry 中的镜像："
        curl -s http://localhost:${REGISTRY_PORT}/v2/_catalog | python3 -m json.tool
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status|cleanup|push|list}"
        echo ""
        echo "示例："
        echo "  $0 start             # 启动 registry"
        echo "  $0 push ubuntu 20.04 # 推送 ubuntu:20.04 到 registry"
        echo "  $0 list              # 列出所有镜像"
        exit 1
        ;;
esac
