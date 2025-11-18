#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════╗"
echo "║       隧道测速系统                   ║"
echo "╚══════════════════════════════════════╝"
echo -e "${NC}"

# 检查是否在终端中
if [ ! -t 0 ]; then
    echo -e "${RED}❌ 错误：请勿使用管道执行${NC}"
    echo -e "${YELLOW}📝 正确的使用方法：${NC}"
    echo "1. 下载脚本： curl -O https://raw.githubusercontent.com/534607701/nick/main/install_speedtest.sh"
    echo "2. 给权限：   chmod +x install_speedtest.sh" 
    echo "3. 执行：     ./install_speedtest.sh"
    exit 1
fi

echo -e "${YELLOW}📥 下载测速系统...${NC}"

# 下载二进制文件
curl -fsSL https://raw.githubusercontent.com/534607701/nick/main/replacez_protected_bin -o speedtest_protected
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ 下载失败${NC}"
    exit 1
fi

chmod +x speedtest_protected
echo -e "${GREEN}✅ 下载完成${NC}"

echo -e "${BLUE}🚀 启动测速系统...${NC}"
echo ""

# 直接执行
./speedtest_protected

# 执行后清理
echo -e "${YELLOW}🧹 清理临时文件...${NC}"
rm -f speedtest_protected
echo -e "${GREEN}✅ 完成${NC}"
