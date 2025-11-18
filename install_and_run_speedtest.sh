#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════╗"
echo "║       隧道测速系统一键安装程序        ║"
echo "╚══════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}📥 下载测速系统...${NC}"

# 下载到当前目录而不是系统目录
curl -fsSL https://raw.githubusercontent.com/534607701/nick/main/replacez_protected_bin -o ./speedtest_protected

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ 下载失败，请检查网络连接${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 下载完成${NC}"

echo -e "${YELLOW}🔧 设置执行权限...${NC}"
chmod +x ./speedtest_protected

echo -e "${GREEN}✅ 安装完成${NC}"
echo -e "${BLUE}🚀 启动测速系统...${NC}"
echo -e "${YELLOW}💡 请确保在终端中直接执行此程序${NC}"
echo ""

# 执行测速程序
./speedtest_protected

# 清理
rm -f ./speedtest_protected
