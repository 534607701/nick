#!/bin/bash

# Axis AI Deploy Script - 双服务器极简版（保留原检查机制）
# 自动适配本机IP，无需手动修改

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "════════════════════════════════════════════════════════════════════════"
echo "                    ****隔壁老王**** 安装脚本（保留原机制）"
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

# ========== 清理阶段 ==========
echo -e "${YELLOW}[1/5] 清理旧配置（保留SSH服务）...${NC}"

# 停止 business 相关服务（不停止 SSH）
systemctl stop frpc-business frpc-monitor 2>/dev/null
systemctl disable frpc-business frpc-monitor 2>/dev/null

# 杀掉 business 相关进程
pkill -f "frpc-business.toml" 2>/dev/null
pkill -f "frpc-monitor.sh" 2>/dev/null

# 备份旧的配置文件（带时间戳）
BACKUP_TIME=$(date +%Y%m%d_%H%M%S)
if [ -f "$TARGET_DIR/frpc-business.toml" ]; then
    cp "$TARGET_DIR/frpc-business.toml" "$TARGET_DIR/frpc-business.toml.bak_$BACKUP_TIME"
    echo "  已备份 frpc-business.toml"
fi

# 删除旧的配置文件
rm -f "$TARGET_DIR/frpc-business.toml" 2>/dev/null
rm -f "$TARGET_DIR/vastaictcdn.toml" 2>/dev/null
rm -f "$TARGET_DIR/vastaictcdn.toml.disabled" 2>/dev/null

sleep 2
echo -e "${GREEN}  清理完成${NC}"

# ========== 下载阶段 ==========
echo -e "${YELLOW}[2/5] 检查FRP客户端...${NC}"
if [ ! -f "$PROGRAM" ]; then
    echo -n "  下载FRP客户端... "
    
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
            echo -e "\n  ${YELLOW}下载失败，尝试备用源...${NC}"
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
else
    echo "  客户端已存在"
fi

# ========== 创建SSH配置文件 ==========
echo -e "${YELLOW}[3/5] 生成SSH配置文件...${NC}"
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
echo "  SSH配置已生成"

# ========== 创建业务配置文件 ==========
echo -e "${YELLOW}[4/5] 生成业务配置文件（共$PORT_COUNT个端口）...${NC}"

# 生成带优化参数的业务配置
TIMESTAMP=$(date +%s)
cat > /var/lib/vastai_kaalia/docker_tmp/frpc-business.toml << EOF
# ========== 全局配置 ==========
serverAddr = "$SERVER2_IP"
serverPort = $SERVER_PORT
auth.method = "token"
auth.token = "$AUTH_TOKEN"

# ========== 性能优化（0.65.0版本兼容）==========
transport.poolCount = 50           # 连接池大小，解决频繁掉线
transport.tcpMux = true             # 启用TCP多路复用
heartbeat = 30                      # 心跳间隔30秒
heartbeatTimeout = 90                # 心跳超时90秒

# ========== 代理列表 ==========
EOF

# 批量添加端口（使用带时间戳的代理名避免冲突）
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

echo "  业务配置已生成（使用时间戳${TIMESTAMP}）"

# ========== 创建系统服务 ==========
echo -e "${YELLOW}[5/5] 创建系统服务...${NC}"

# SSH服务（保持不变）
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

# ========== 业务服务配置（保留原检查机制）==========
cat > /etc/systemd/system/frpc-business.service << 'EOF'
[Unit]
Description=FRP Business Client (Enhanced Auto-Restart)
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/lib/vastai_kaalia/docker_tmp

# 主程序
ExecStart=/var/lib/vastai_kaalia/docker_tmp/vastaictcdn -c /var/lib/vastai_kaalia/docker_tmp/frpc-business.toml

# 自动重启配置（原版）
Restart=always
RestartSec=5
StartLimitBurst=10
StartLimitIntervalSec=120

# 进程看护 - 如果30秒无响应就重启（保留）
WatchdogSec=30

# 优雅停止超时
TimeoutStopSec=30

# 文件描述符限制
LimitNOFILE=1048576
LimitNPROC=512

# 核心转储限制
LimitCORE=infinity

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

# ========== 监控脚本（保留原检查间隔）==========
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
    # 1. 检查服务是否active
    if ! systemctl is-active --quiet $SERVICE; then
        log_msg "服务未运行，尝试启动"
        systemctl start $SERVICE
        FAIL_COUNT=$((FAIL_COUNT + 1))
        sleep 10
        continue
    fi
    
    # 2. 检查进程是否存在
    PID=$(pgrep -f "frpc-business.toml")
    if [ -z "$PID" ]; then
        log_msg "进程不存在，重启服务"
        systemctl restart $SERVICE
        FAIL_COUNT=$((FAIL_COUNT + 1))
        sleep 10
        continue
    fi
    
    # 3. 检查最近日志中是否有成功代理
    if ! journalctl -u $SERVICE -n 50 --no-pager 2>/dev/null | grep -q "start proxy success"; then
        log_msg "最近无成功代理记录，可能连接异常"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        
        if [ $FAIL_COUNT -ge $MAX_FAILS ]; then
            log_msg "连续 $MAX_FAILS 次异常，强制重启"
            systemctl restart $SERVICE
            FAIL_COUNT=0
        fi
    else
        # 有成功记录，重置失败计数
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
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 创建定时健康检查（保留原间隔）
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

# 启用服务（只启用business相关，SSH已存在则保留）
echo -n "  启用服务... "
systemctl enable frpc-ssh 2>/dev/null
systemctl enable frpc-business frpc-monitor frpc-healthcheck.timer >/dev/null 2>&1
echo "完成"

# 启动服务
echo -n "  启动服务中... "
systemctl start frpc-business frpc-monitor frpc-healthcheck.timer
systemctl restart frpc-ssh 2>/dev/null  # 重启SSH确保使用新配置
sleep 3
echo "完成"

# 显示最终状态
echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo -e "                     ${GREEN}安装成功！${NC}"
echo "════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "${YELLOW}服务状态：${NC}"
systemctl status frpc-ssh --no-pager | grep "Active"
systemctl status frpc-business --no-pager | grep "Active"
echo ""
echo -e "${YELLOW}监控日志：${NC}"
echo "  tail -f /var/log/frpc-monitor.log"
echo ""

# 删除脚本自身
rm -f "$0" 2>/dev/null
