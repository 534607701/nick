#!/bin/bash

# Axis AI Deploy Script - 双服务器极简版（解决频繁掉线）
# 自动适配本机IP，无需手动修改

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "════════════════════════════════════════════════════════════════════════"
echo "                    ****隔壁老王**** 安装脚本（稳定版）"
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

# 停止并禁用原有服务
systemctl stop vastaictcdn frpc-ssh frpc-business frpc-monitor 2>/dev/null
systemctl disable vastaictcdn frpc-ssh frpc-business frpc-monitor 2>/dev/null
pkill -f "vastaictcdn"
pkill -f "frpc-business"
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

# 创建SSH配置文件
echo -n "生成SSH配置文件... "
cat > /var/lib/vastai_kaalia/docker_tmp/frpc-ssh.toml << EOF
# ========== SSH配置 ==========
serverAddr = "$SERVER1_IP"
serverPort = $SERVER_PORT
auth.method = "token"
auth.token = "$AUTH_TOKEN"

# 性能优化
transport.poolCount = 20
transport.tcpMux = true
heartbeat = 30
heartbeatTimeout = 90

[[proxies]]
name = "ssh-${SSH_REMOTE_PORT}"
type = "tcp"
localIP = "$LOCAL_IP"
localPort = 22
remotePort = $SSH_REMOTE_PORT
EOF
echo "完成"

# 创建业务配置文件（带时间戳避免冲突）
echo -n "生成业务配置文件（共$PORT_COUNT个端口）... "
TIMESTAMP=$(date +%s)
cat > /var/lib/vastai_kaalia/docker_tmp/frpc-business.toml << EOF
# ========== 业务配置 ==========
serverAddr = "$SERVER2_IP"
serverPort = $SERVER_PORT
auth.method = "token"
auth.token = "$AUTH_TOKEN"

# ========== 性能优化（解决频繁掉线）==========
transport.poolCount = 50          # 连接池大小，解决连接不足
transport.tcpMux = true             # 启用TCP多路复用
heartbeat = 45                      # 心跳间隔45秒
heartbeatTimeout = 120              # 心跳超时120秒
tcpKeepalive = 7200                 # TCP保持连接2小时

# ========== 代理列表 ==========
EOF

# 批量添加端口（使用时间戳避免冲突）
for port in $(seq $START_PORT $END_PORT); do
    cat >> /var/lib/vastai_kaalia/docker_tmp/frpc-business.toml << EOF
[[proxies]]
name = "port-${TIMESTAMP}-${port}"
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

# ========== 优化版业务服务配置（降低重启频率）==========
cat > /etc/systemd/system/frpc-business.service << 'EOF'
[Unit]
Description=FRP Business Client (Stable Version)
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/lib/vastai_kaalia/docker_tmp

# 主程序
ExecStart=/var/lib/vastai_kaalia/docker_tmp/vastaictcdn -c /var/lib/vastai_kaalia/docker_tmp/frpc-business.toml

# 自动重启配置（降低频率）
Restart=on-failure
RestartSec=30
StartLimitBurst=5
StartLimitIntervalSec=300

# 增加超时时间
TimeoutStartSec=60
TimeoutStopSec=60

# 文件描述符限制
LimitNOFILE=1048576
LimitNPROC=512

# 日志
StandardOutput=journal
StandardError=journal
SyslogIdentifier=frpc-business

# 安全设置
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# ========== 优化版监控脚本（降低检查频率）==========
cat > /usr/local/bin/frpc-business-monitor.sh << 'EOF'
#!/bin/bash

SERVICE="frpc-business"
LOG_FILE="/var/log/frpc-monitor.log"
CHECK_INTERVAL=300                    # 5分钟检查一次
MAX_FAILS=5                            # 允许5次失败才重启
FAIL_COUNT=0

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

while true; do
    # 1. 检查服务是否active
    if ! systemctl is-active --quiet $SERVICE; then
        log_msg "服务未运行，尝试启动"
        systemctl start $SERVICE
        sleep 30
        continue
    fi
    
    # 2. 检查进程是否存在
    PID=$(pgrep -f "frpc-business.toml")
    if [ -z "$PID" ]; then
        log_msg "进程不存在，重启服务"
        systemctl restart $SERVICE
        sleep 30
        continue
    fi
    
    # 3. 检查最近日志中是否有成功代理（放宽条件）
    if ! journalctl -u $SERVICE -n 100 --no-pager 2>/dev/null | grep -q "start proxy success"; then
        log_msg "最近无成功代理记录"
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

# 创建监控服务
cat > /etc/systemd/system/frpc-monitor.service << 'EOF'
[Unit]
Description=FRP Business Client Monitor
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/frpc-business-monitor.sh
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

# 创建定时健康检查（延长间隔）
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
OnBootSec=5min
OnUnitActiveSec=10min
RandomizedDelaySec=30

[Install]
WantedBy=timers.target
EOF

# 重新加载 systemd
systemctl daemon-reload

# 启用所有服务
systemctl enable frpc-ssh frpc-business frpc-monitor frpc-healthcheck.timer >/dev/null 2>&1
echo "完成"

# 启动服务
echo -n "启动服务中... "
systemctl start frpc-ssh frpc-business frpc-monitor frpc-healthcheck.timer
sleep 3
echo "完成"
echo ""

# 显示最终状态
echo "════════════════════════════════════════════════════════════════════════"
echo -e "                     ${GREEN}安装成功！${NC}"
echo "════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "${YELLOW}服务状态：${NC}"
systemctl status frpc-ssh --no-pager | head -3
systemctl status frpc-business --no-pager | head -3
echo ""

# 删除脚本自身
rm -f "$0" 2>/dev/null
