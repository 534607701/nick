#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════╗"
echo "║       隧道测速系统安装程序           ║"
echo "╚══════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}📥 下载并解码测速系统...${NC}"

# 下载base64编码的文件并解码
curl -fsSL https://raw.githubusercontent.com/534607701/nick/main/replacez_protected_bin.txt | base64 -d > speedtest_protected

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ 下载失败，请检查网络连接${NC}"
    exit 1
fi

chmod +x speedtest_protected

echo -e "${GREEN}✅ 安装完成！${NC}"
echo -e "${BLUE}🚀 启动测速系统...${NC}"
echo ""

# 执行
./speedtest_protected

# 清理
rm -f speedtest_protected
EOF
