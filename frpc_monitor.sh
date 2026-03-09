#!/bin/bash

# FRPC 实时监控脚本 - 查看是否稳定、是否掉线
clear

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}           FRPC 实时监控 - 查看稳定性 & 是否掉线           ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""
echo -e "监控服务：${GREEN}frpc@vastaictssh${NC}   ${GREEN}frpc@vastaictcdn${NC}"
echo -e "刷新频率：每 1 秒自动刷新"
echo -e "退出方式：按 ${YELLOW}Ctrl + C${NC}"
echo ""

while true; do
    # 时间
    echo -e "${BLUE}【$(date '+%Y-%m-%d %H:%M:%S')】${NC}"
    echo "======================================================"

    # 1. SSH 代理状态
    echo -e "${YELLOW}[1] SSH 代理状态 frpc@vastaictssh.service${NC}"
    ssh_status=$(systemctl is-active frpc@vastaictssh.service)
    if [ "$ssh_status" = "active" ]; then
        echo -e "状态: ${GREEN}运行中 (active)${NC}"
    else
        echo -e "状态: ${RED}已掉线 / 未运行 ($ssh_status)${NC}"
    fi
    systemctl status frpc@vastaictssh.service --no-pager | grep -E 'Active|Tasks|Memory' | head -3

    echo ""

    # 2. CDN 批量端口状态
    echo -e "${YELLOW}[2] CDN 批量端口 frpc@vastaictcdn.service${NC}"
    cdn_status=$(systemctl is-active frpc@vastaictcdn.service)
    if [ "$cdn_status" = "active" ]; then
        echo -e "状态: ${GREEN}运行中 (active)${NC}"
    else
        echo -e "状态: ${RED}已掉线 / 未运行 ($cdn_status)${NC}"
    fi
    systemctl status frpc@vastaictcdn.service --no-pager | grep -E 'Active|Tasks|Memory' | head -3

    echo ""
    echo "======================================================"

    # 3. 最新日志（判断是否重连、掉线）
    echo -e "${YELLOW}[3] SSH 代理最新日志（最后5行）${NC}"
    tail -n 5 /var/log/frp/frpc-ssh.log 2>/dev/null || echo "暂无日志"

    echo ""
    echo -e "${YELLOW}[4] CDN 批量端口最新日志（最后5行）${NC}"
    tail -n 5 /var/log/frp/frpc-cdn.log 2>/dev/null || echo "暂无日志"

    echo ""
    echo -e "${BLUE}======================================================${NC}"
    echo "正在监控... 按 Ctrl+C 退出"
    echo ""

    sleep 1
    clear
done
