#!/bin/bash

# Axis AI Deploy Script - 双服务器极简版
# 自动适配本机IP，无需手动修改

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "════════════════════════════════════════════════════════════════════════"
echo "                    ****隔壁老王**** 安装脚本"
echo "════════════════════════════════════════════════════════════════════════"
echo ""

# 预设服务器配置（隐藏不显示）
SERVER1_IP="8.141.12.76"
SERVER2_IP="209.146.116.106"
SERVER_PORT=7000
AUTH_TOKEN="qazwsx123.0"

# 获取本机IP（自动适配）
echo -n "正在检测本机IP... "
LOCAL_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)

if [ -z "$LOCAL_IP" ]; then
    echo -e "${YELLOW}无法自动获取IP${NC}"
    read -p "请输入本机内网IP: " LOCAL_IP
    while [ -z "$LOCAL_IP" ]; do
        echo -e "${RED}IP不能为空${NC}"
        read -p "请输入本机内网IP: " LOCAL_IP
    done
else
    echo -e "${GREEN}$LOCAL_IP${NC}"
fi
echo ""

# 输入SSH端口
read -p "请输入SSH远程端口: " SSH_REMOTE_PORT
while ! [[ "$SSH_REMOTE_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_REMOTE_PORT" -lt 1024 ] || [ "$SSH_REMOTE_PORT" -gt 65535 ]; do
    echo -e "${RED}端口必须是1024-65535之间的数字${NC}"
    read -p "请输入SSH远程端口: " SSH_REMOTE_PORT
done

# 输入业务端口范围
echo ""
read -p "请输入业务起始端口: " START_PORT
while ! [[ "$START_PORT" =~ ^[0-9]+$ ]] || [ "$START_PORT" -lt 1024 ] || [ "$START_PORT" -gt 65535 ]; do
    echo -e "${RED}端口必须是1024-65535之间的数字${NC}"
    read -p "请输入业务起始端口: " START_PORT
done

read -p "请输入业务结束端口: " END_PORT
while ! [[ "$END_PORT" =~ ^[0-9]+$ ]] || [ "$END_PORT" -lt "$START_PORT" ] || [ "$END_PORT" -gt 65535 ]; do
    echo -e "${RED}结束端口必须大于等于起始端口且≤65535${NC}"
    read -p "请输入业务结束端口: " END_PORT
done

PORT_COUNT=$((END_PORT - START_PORT + 1))
echo -e "\n${YELLOW}配置确认:${NC}"
echo "  本机IP: $LOCAL_IP"
echo "  SSH端口: $SSH_REMOTE_PORT"
echo "  业务端口: $START_PORT-$END_PORT (共$PORT_COUNT个)"
echo ""
read -p "确认安装? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "安装取消"
    exit 0
fi

echo ""
echo "开始安装..."

# 定义目录
TARGET_DIR="/var/lib/vastai_kaalia/docker_tmp"
PROGRAM="$TARGET_DIR/vastaictcdn"

# 创建目录
mkdir -p "$TARGET_DIR" 2>/dev/null

# 停止并禁用原有服务
systemctl stop vastaictcdn frpc-ssh frpc-business 2>/dev/null
systemctl disable vastaictcdn frpc-ssh frpc-business 2>/dev/null
sleep 2

# 检查FRP程序是否存在，如果不存在则下载
if [ ! -f "$PROGRAM" ]; then
    echo -n "下载FRP客户端... "
    
    # 获取系统架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l) ARCH="arm" ;;
        *) echo -e "${RED}不支持的架构: $ARCH${NC}"; exit 1 ;;
    esac
    
    FRP_VERSION="0.65.0"
    FILENAME="frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"
    DOWNLOAD_URL="http://8.141.12.76/sever/${FILENAME}"
    
    cd /tmp
    if command -v wget >/dev/null 2>&1; then
        wget -q --show-progress -O "$FILENAME" "$DOWNLOAD_URL"
        if [ $? -ne 0 ]; then
            echo -e "\n${YELLOW}下载失败，尝试备用源...${NC}"
            wget -q --show-progress -O "$FILENAME" "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILENAME}"
        fi
    else
        curl -# -L -o "$FILENAME" "$DOWNLOAD_URL"
    fi
    
    tar -zxf "$FILENAME" >/dev/null 2>&1
    cp "frp_${FRP_VERSION}_linux_${ARCH}/frpc" "$PROGRAM"
    chmod +x "$PROGRAM"
    rm -rf "frp_${FRP_VERSION}_linux_${ARCH}" "$FILENAME"
    cd - >/dev/null
    echo "完成"
fi

# 创建SSH配置文件（名称带端口号）
echo -n "生成SSH配置文件... "
cat > /var/lib/vastai_kaalia/docker_tmp/frpc-ssh.toml << EOF
serverAddr = "$SERVER1_IP"
serverPort = $SERVER_PORT
auth.method = "token"
auth.token = "$AUTH_TOKEN"

[[proxies]]
name = "ssh-${SSH_REMOTE_PORT}"
type = "tcp"
localIP = "$LOCAL_IP"
localPort = 22
remotePort = $SSH_REMOTE_PORT
EOF
echo "完成"

# 创建业务配置文件
echo -n "生成业务配置文件（共$PORT_COUNT个端口）... "
cat > /var/lib/vastai_kaalia/docker_tmp/frpc-business.toml << EOF
serverAddr = "$SERVER2_IP"
serverPort = $SERVER_PORT
auth.method = "token"
auth.token = "$AUTH_TOKEN"

EOF

# 批量添加端口
for port in $(seq $START_PORT $END_PORT); do
    cat >> /var/lib/vastai_kaalia/docker_tmp/frpc-business.toml << EOF
[[proxies]]
name = "port-$port"
type = "tcp"
localIP = "$LOCAL_IP"
localPort = $port
remotePort = $port

EOF
done
echo "完成"

# 创建SSH服务
echo -n "创建系统服务... "
cat > /etc/systemd/system/frpc-ssh.service << EOF
[Unit]
Description=FRP SSH Client
After=network.target

[Service]
Type=simple
User=root
ExecStart=$PROGRAM -c /var/lib/vastai_kaalia/docker_tmp/frpc-ssh.toml
Restart=always
RestartSec=10
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

# 创建业务服务
cat > /etc/systemd/system/frpc-business.service << EOF
[Unit]
Description=FRP Business Client
After=network.target

[Service]
Type=simple
User=root
ExecStart=$PROGRAM -c /var/lib/vastai_kaalia/docker_tmp/frpc-business.toml
Restart=always
RestartSec=10
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable frpc-ssh frpc-business >/dev/null 2>&1
echo "完成"

# 启动服务
echo -n "启动服务中... "
systemctl start frpc-ssh frpc-business
sleep 3
echo "完成"
echo ""

# 显示结果（简化版，不显示IP）
echo "════════════════════════════════════════════════════════════════════════"
echo -e "                          ${GREEN}安装完成！${NC}"
echo "════════════════════════════════════════════════════════════════════════"
echo ""
echo " 📋 配置信息:"
echo "   - 本机IP: $LOCAL_IP"
echo ""
echo " 🔑 SSH远程端口: $SSH_REMOTE_PORT"
echo " 🌐 业务端口范围: $START_PORT ~ $END_PORT (共$PORT_COUNT个)"
echo ""
echo " 📊 服务状态:"
systemctl status frpc-ssh --no-pager -l | grep "Active:" | sed 's/^/   /'
systemctl status frpc-business --no-pager -l | grep "Active:" | sed 's/^/   /'
echo ""
echo " 📝 常用命令:"
echo "   - 查看SSH日志: journalctl -u frpc-ssh -f"
echo "   - 查看业务日志: journalctl -u frpc-business -f"
echo "   - 重启SSH服务: systemctl restart frpc-ssh"
echo "   - 重启业务服务: systemctl restart frpc-business"
echo ""

# 测试连接（简化版）
echo -n "测试SSH端口连通性... "
if nc -z -w 3 $SERVER1_IP $SSH_REMOTE_PORT 2>/dev/null; then
    echo -e "${GREEN}✓ 正常${NC}"
else
    echo -e "${YELLOW}⚠ 等待启动${NC}"
fi

echo ""
echo "配置文件位置:"
echo "  SSH: /var/lib/vastai_kaalia/docker_tmp/frpc-ssh.toml"
echo "  业务: /var/lib/vastai_kaalia/docker_tmp/frpc-business.toml"
echo ""

# 删除脚本自身
rm -f "$0" 2>/dev/null
