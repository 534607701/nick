#!/bin/bash

# 配置
AUTH_FILE="/tmp/speedtest_auth.codes"
BACKUP_DIR="/root/auth_backups"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

show_help() {
    echo -e "${BLUE}验证码管理系统 v1.0${NC}"
    echo "使用方法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  generate [数量]  生成指定数量的验证码"
    echo "  list             显示所有可用验证码"
    echo "  count            显示剩余验证码数量"
    echo "  clear            清除所有验证码"
    echo "  backup           备份验证码文件"
    echo "  restore [文件]   从备份恢复"
    echo "  help             显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 generate 5     # 生成5个验证码"
    echo "  $0 list           # 列出所有验证码"
    echo "  $0 count          # 统计剩余数量"
}

generate_codes() {
    local count=${1:-1}
    local codes=()
    
    echo -e "${YELLOW}🎲 生成 $count 个验证码...${NC}"
    
    for ((i=1; i<=count; i++)); do
        # 生成6位数字验证码
        code=$(printf "%06d" $(( RANDOM % 1000000 )))
        codes+=("$code")
        echo "$code" >> "$AUTH_FILE"
        echo -e "${GREEN}✅ 验证码 $i: $code${NC}"
    done
    
    # 显示汇总信息
    echo -e "${BLUE}📊 已生成 $count 个验证码${NC}"
    echo -e "${YELLOW}💡 验证码已保存到: $AUTH_FILE${NC}"
}

list_codes() {
    if [ ! -f "$AUTH_FILE" ] || [ ! -s "$AUTH_FILE" ]; then
        echo -e "${YELLOW}⚠️ 没有可用的验证码${NC}"
        return
    fi
    
    local count=$(wc -l < "$AUTH_FILE")
    echo -e "${BLUE}📋 可用验证码 ($count 个):${NC}"
    echo -e "${PURPLE}"
    cat "$AUTH_FILE" | nl -w2 -s'. '
    echo -e "${NC}"
}

count_codes() {
    if [ ! -f "$AUTH_FILE" ]; then
        echo -e "${YELLOW}📊 剩余验证码: 0${NC}"
        return
    fi
    
    local count=$(wc -l < "$AUTH_FILE" 2>/dev/null || echo 0)
    echo -e "${BLUE}📊 剩余验证码: $count${NC}"
}

clear_codes() {
    if [ -f "$AUTH_FILE" ]; then
        local count=$(wc -l < "$AUTH_FILE")
        rm -f "$AUTH_FILE"
        echo -e "${GREEN}🗑️ 已清除 $count 个验证码${NC}"
    else
        echo -e "${YELLOW}⚠️ 验证码文件不存在${NC}"
    fi
}

backup_codes() {
    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/auth_codes_$(date +%Y%m%d_%H%M%S).bak"
    
    if [ -f "$AUTH_FILE" ]; then
        cp "$AUTH_FILE" "$backup_file"
        echo -e "${GREEN}📦 验证码已备份到: $backup_file${NC}"
    else
        echo -e "${YELLOW}⚠️ 没有验证码可备份${NC}"
    fi
}

restore_codes() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        echo -e "${RED}❌ 请指定备份文件${NC}"
        return 1
    fi
    
    if [ -f "$backup_file" ]; then
        cp "$backup_file" "$AUTH_FILE"
        echo -e "${GREEN}🔄 已从备份恢复验证码: $backup_file${NC}"
    else
        echo -e "${RED}❌ 备份文件不存在: $backup_file${NC}"
    fi
}

# 主程序
case "$1" in
    "generate")
        generate_codes "$2"
        ;;
    "list")
        list_codes
        ;;
    "count")
        count_codes
        ;;
    "clear")
        clear_codes
        ;;
    "backup")
        backup_codes
        ;;
    "restore")
        restore_codes "$2"
        ;;
    "help"|"")
        show_help
        ;;
    *)
        echo -e "${RED}❌ 未知选项: $1${NC}"
        show_help
        ;;
esac
