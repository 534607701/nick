cat > install_and_run_speedtest.sh << 'EOF'
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

# 下载保护版测速程序
if sudo curl -fsSL https://raw.githubusercontent.com/534607701/nick/main/replacez_protected_bin -o /usr/local/bin/speedtest_protected; then
    echo -e "${GREEN}✅ 下载完成${NC}"
else
    echo -e "${RED}❌ 下载失败，请检查网络连接或文件是否存在${NC}"
    exit 1
fi

echo -e "${YELLOW}🔧 设置执行权限...${NC}"
sudo chmod +x /usr/local/bin/speedtest_protected

echo -e "${GREEN}✅ 安装完成${NC}"
echo -e "${BLUE}🚀 启动测速系统...${NC}"
echo ""

# 执行测速程序
exec speedtest_protected
EOF

# 给脚本执行权限
chmod +x install_and_run_speedtest.sh
