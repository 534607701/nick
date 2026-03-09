#!/bin/bash

# Axis AI Deploy Script - 双服务器极简版（完整修复版）
# 自动适配本机IP，无需手动修改

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "════════════════════════════════════════════════════════════════════════"
echo "                    ****隔壁老王**** 安装脚本（完整修复版）"
echo "════════════════════════════════════════════════════════════════════════"
echo ""

# 预设服务器配置
SERVER1_IP="8.141.12.76"
SERVER2_IP="209.146.116.106"
SERVER_PORT=7000
AUTH_TOKEN="qazwsx123.0"

# 获取本机IP
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

# ========== 彻底清理阶段 ==========
echo -e "${YELLOW}[1/5] 彻底清理所有旧配置...${NC}"

# 1. 停止所有相关服务
echo "  停止服务..."
systemctl stop vastaictcdn frpc-business frpc-monitor frpc-ssh 2>/dev/null

# 2. 禁用所有相关服务
echo "  禁用服务..."
systemctl disable vastaictcdn frpc-business frpc-monitor frpc-ssh 2>/dev/null

# 3. 删除所有相关的 service 文件
echo "  删除服务文件..."
rm -f /etc/systemd/system/vastaictcdn.service
rm -f /etc/systemd/system/frpc-business.service
rm -f /etc/systemd/system/frpc-monitor.service
rm -f /etc/systemd/system/frpc-healthcheck.service
rm -f /etc/systemd/system/frpc-healthcheck.timer
rm -f /etc/systemd/system/frpc-ssh.service 2>/dev/null

# 4. 杀掉所有相关进程
echo "  终止进程..."
pkill -f "vastaictcdn"
pkill -f "frpc-business"
pkill -f "frpc-monitor"
pkill -f "frpc-ssh"

# 5. 备份并删除配置文件
echo "  备份配置文件..."
BACKUP_TIME=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/root/frp_backup_$BACKUP_TIME"
mkdir -p "$BACKUP_DIR"

if [ -f "$TARGET_DIR/frpc-business.toml" ]; then
    cp "$TARGET_DIR/frpc-business.toml" "$BACKUP_DIR/frpc-business.toml.bak"
    echo "    已备份 frpc-business.toml"
fi
if [ -f "$TARGET_DIR/frpc-ssh.toml" ]; then
    cp "$TARGET_DIR/frpc-ssh.toml" "$BACKUP_DIR/frpc-ssh.toml.bak"
    echo "    已备份 frpc-ssh.toml"
fi
if [ -f "$TARGET_DIR/vastaictcdn.toml" ]; then
    cp "$TARGET_DIR/vastaictcdn.toml" "$BACKUP_DIR/vastaictcdn.toml.bak"
    echo "    已备份 vastaictcdn.toml"
fi

# 6. 删除所有配置文件
echo "  删除旧配置文件..."
rm -f "$TARGET_DIR"/*.toml
rm -f "$TARGET_DIR"/*.toml.bak*
rm -f "$TARGET_DIR"/*.disabled

# 7. 重新加载 systemd
systemctl daemon-reload

# 8. 等待2秒
sleep 2

# 9. 确认清理结果
echo -e "${GREEN}  清理完成，备份文件在: $BACKUP_DIR${NC}"
echo ""

# ========== 下载阶段 ==========
echo -e "${YELLOW}[2/5] 下载FRP客户端...${NC}"

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

echo -n "  下载中... "
cd /tmp

# 尝试主下载源
if command -v wget >/dev/null 2>&1; then
    wget -q --show-progress -O "$FILENAME" "$DOWNLOAD_URL"
    if [ $? -ne 0 ]; then
        echo -e "\n  ${YELLOW}主源下载失败，尝试GitHub源...${NC}"
        wget -q --show-progress -O "$FILENAME" "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILENAME}"
    fi
else
    curl -# -L -o "$FILENAME" "$DOWNLOAD_URL"
    if [ $? -ne 0 ]; then
        echo -e "\n  ${YELLOW}主源下载失败，尝试GitHub源...${NC}"
        curl -# -L -o "$FILENAME" "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILENAME}"
    fi
fi

# 检查下载是否成功
if [ ! -f "$FILENAME" ]; then
    echo -e "${RED}下载失败，请检查网络${NC}"
    exit 1
fi

echo "  解压安装..."
tar -zxf "$FILENAME" >/dev/null 2>&1
cp "frp_${FRP_VERSION}_linux_${ARCH}/frpc" "$PROGRAM"
chmod +x "$PROGRAM"
rm -rf "frp_${FRP_VERSION}_linux_${ARCH}" "$FILENAME"
cd - >/dev/null
echo -e "${GREEN}  客户端安装完成${NC}"

# ========== 创建SSH配置文件 ==========
echo -e "${YELLOW}[3/5] 生成SSH配置文件...${NC}"
cat > "$TARGET_DIR/frpc-ssh.toml" << EOF
# ========== SSH配置 ==========
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
echo "  SSH配置已生成"

# ========== 创建业务配置文件 ==========
echo -e "${YELLOW}[4/5] 生成业务配置文件（共$PORT_COUNT个端口）...${NC}"

# 生成带优化参数的业务配置
TIMESTAMP=$(date +%s)
cat > "$TARGET_DIR/frpc-business.toml" << EOF
# ========== 业务配置 ==========
serverAddr = "$SERVER2_IP"
serverPort = $SERVER_PORT
auth.method = "token"
auth.token = "$AUTH_TOKEN"

# ========== 性能优化 ==========
transport.poolCount = 50
transport.tcpMux = true
heartbeat = 30
heartbeatTimeout = 90

# ========== 代理列表 ==========
EOF

# 批量添加端口
for port in $(seq $START_PORT $END_PORT); do
    cat >> "$TARGET_DIR/frpc-business.toml" << EOF
[[proxies]]
name = "port-${TIMESTAMP}-${port}"
type = "tcp"
localIP = "$LOCAL_IP"
localPort = $port
remotePort = $port
EOF
done

echo "  业务配置已生成（使用时间戳${TIMESTAMP}）"

# ========== 创建系统服务 ==========
echo -e "${YELLOW}[5/5] 创建系统服务...${NC}"

# SSH服务
cat > /etc/systemd/system/frpc-ssh.service << EOF
[Unit]
Description=FRP SSH Client
After=network.target

[Service]
Type=simple
User=root
ExecStart=$PROGRAM -c $TARGET_DIR/frpc-ssh.toml
Restart=always
RestartSec=10
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

# 业务服务
cat > /etc/systemd/system/frpc-business.service << 'EOF'
[Unit]
Description=FRP Business Client
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/lib/vastai_kaalia/docker_tmp
ExecStart=/var/lib/vastai_kaalia/docker_tmp/vastaictcdn -c /var/lib/vastai_kaalia/docker_tmp/frpc-business.toml
Restart=always
RestartSec=5
StartLimitBurst=10
StartLimitIntervalSec=120
WatchdogSec=30
TimeoutStopSec=30
LimitNOFILE=1048576
LimitNPROC=512
LimitCORE=infinity
StandardOutput=journal
StandardError=journal
SyslogIdentifier=frpc-business
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# 监控脚本
cat > /usr/local/bin/frpc-business-monitor.sh << 'EOF'
#!/bin/bash

SERVICE="frpc-business"
LOG_FILE="/var/log/frpc-monitor.log"
CHECK_INTERVAL=60
MAX_FAILS=3
FAIL_COUNT=0

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

while true; do
    if ! systemctl is-active --quiet $SERVICE; then
        log_msg "服务未运行，尝试启动"
        systemctl start $SERVICE
        FAIL_COUNT=$((FAIL_COUNT + 1))
        sleep 10
        continue
    fi
    
    PID=$(pgrep -f "frpc-business.toml")
    if [ -z "$PID" ]; then
        log_msg "进程不存在，重启服务"
        systemctl restart $SERVICE
        FAIL_COUNT=$((FAIL_COUNT + 1))
        sleep 10
        continue
    fi
    
    if ! journalctl -u $SERVICE -n 50 --no-pager 2>/dev/null | grep -q "start proxy success"; then
        log_msg "最近无成功代理记录，可能连接异常"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        
        if [ $FAIL_COUNT -ge $MAX_FAILS ]; then
            log_msg "连续 $MAX_FAILS 次异常，强制重启"
            systemctl restart $SERVICE
            FAIL_COUNT=0
        fi
    else
        FAIL_COUNT=0
        log_msg "服务运行正常"
    fi
    
    sleep $CHECK_INTERVAL
done
EOF

chmod +x /usr/local/bin/frpc-business-monitor.sh

# 监控服务
cat > /etc/systemd/system/frpc-monitor.service << 'EOF'
[Unit]
Description=FRP Business Client Monitor
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/frpc-business-monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 健康检查
cat > /etc/systemd/system/frpc-healthcheck.service << 'EOF'
[Unit]
Description=FRP Business Health Check
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'if ! systemctl is-active frpc-business >/dev/null; then systemctl restart frpc-business; fi'
EOF

cat > /etc/systemd/system/frpc-healthcheck.timer << 'EOF'
[Unit]
Description=FRP Business Health Check Timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=3min
RandomizedDelaySec=10

[Install]
WantedBy=timers.target
EOF

# 重新加载 systemd
systemctl daemon-reload

# 启用服务
echo -n "  启用服务... "
systemctl enable frpc-ssh frpc-business frpc-monitor frpc-healthcheck.timer >/dev/null 2>&1
echo "完成"

# 启动服务
echo -n "  启动服务中... "
systemctl start frpc-ssh frpc-business frpc-monitor frpc-healthcheck.timer
sleep 3
echo "完成"

# 显示最终状态
echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo -e "                     ${GREEN}安装成功！${NC}"
echo "════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "${YELLOW}服务状态：${NC}"
systemctl status frpc-ssh --no-pager | head -3
systemctl status frpc-business --no-pager | head -3
echo ""
echo -e "${YELLOW}监控日志：${NC}"
echo "  tail -f /var/log/frpc-monitor.log"
echo ""
echo -e "${YELLOW}备份文件：${NC}"
echo "  $BACKUP_DIR"

# 删除脚本自身
rm -f "$0" 2>/dev/null
