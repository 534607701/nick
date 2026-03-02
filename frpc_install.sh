#!/bin/bash

# Axis AI Deploy Script - FRP代理服务器
# 一键安装 - 内网穿透版
# 优化版本 - 支持批量端口映射和多SSH映射

# 预设配置（可修改）
DOMAIN="107.174.186.233"
SERVER_PORT=7000
AUTH_TOKEN="qazwsx123.0"
WEB_PORT=7500
WEB_USER="admin"
WEB_PASSWORD="admin"
PROXY_PREFIX="proxy"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 错误处理函数
handle_error() {
    echo -e "${RED}✗ 错误: $1${NC}"
    exit 1
}

# 成功提示函数
success_msg() {
    echo -e "${GREEN}✓ $1${NC}"
}

# 警告提示函数
warning_msg() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# 信息提示函数
info_msg() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# 检查命令是否存在
check_command() {
    command -v $1 >/dev/null 2>&1 || handle_error "需要 $1 命令，请先安装"
}

echo "═══════════════════════════════════════════════════════════════════════════════════"
echo "║                                                                              ║"
echo "║                 ****隔壁老王**** 一键安装脚本 v2.0                           ║"
echo "║                       （优化版 - 支持多SSH映射）                              ║"
echo "║                                                                              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# 检查必要命令
check_command ping
check_command wget || check_command curl || handle_error "需要 wget 或 curl"

# 步骤1: 网络连通性测试
info_msg "【步骤 1/5】网络连通性测试中..."
echo ""

if ping -c 3 -W 3 $DOMAIN > /dev/null 2>&1; then
    success_msg "网络连通性正常"
    echo ""
else
    warning_msg "网络连通性异常，但继续执行..."
    echo ""
fi

# 步骤2: 获取服务器IP和Token
info_msg "【步骤 2/5】获取服务器配置信息..."
echo ""

# 获取服务器IP
while true; do
    read -p "请输入服务器IP地址: " SERVER_IP
    if [ -n "$SERVER_IP" ]; then
        if [[ $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            break
        else
            echo -e "${RED}✗ 请输入有效的IP地址${NC}"
        fi
    else
        echo -e "${RED}✗ 服务器IP不能为空${NC}"
    fi
done

# 获取认证Token
while true; do
    read -p "请输入认证Token (默认: $AUTH_TOKEN): " INPUT_TOKEN
    if [ -n "$INPUT_TOKEN" ]; then
        AUTH_TOKEN="$INPUT_TOKEN"
        break
    else
        # 使用默认值
        break
    fi
done

echo ""
info_msg "服务器地址: $SERVER_IP:$SERVER_PORT"
info_msg "认证Token: ${AUTH_TOKEN:0:5}***${AUTH_TOKEN: -3}"
echo ""

# 步骤3: 下载和安装程序
TARGET_DIR="/var/lib/vastai_kaalia/docker_tmp"
PROGRAM="$TARGET_DIR/vastaictcdn"
CONFIG_DIR="/var/lib/vastai_kaalia"
CONFIG_FILE="$TARGET_DIR/vastaictcdn.toml"

info_msg "【步骤 3/5】下载安装程序..."

# 创建目录
mkdir -p "$TARGET_DIR" "$CONFIG_DIR"

# 如果服务已在运行，先停止
if systemctl is-active vastaictcdn > /dev/null 2>&1; then
    info_msg "停止现有服务..."
    systemctl stop vastaictcdn > /dev/null 2>&1
    sleep 2
fi

# 备份原有配置
if [ -f "$CONFIG_FILE" ]; then
    BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    success_msg "原配置文件已备份到 $BACKUP_FILE"
fi

# 获取系统架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    armv7l)
        ARCH="arm"
        ;;
    *)
        handle_error "不支持的架构: $ARCH"
        ;;
esac

# 获取操作系统类型
OS=$(uname -s | tr '[A-Z]' '[a-z]')

# 下载FRP
FRP_VERSION="0.65.0"
FILENAME="frp_${FRP_VERSION}_${OS}_${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILENAME}"

info_msg "正在下载 FRP v${FRP_VERSION} for ${OS}_${ARCH}..."

if command -v wget &> /dev/null; then
    wget --show-progress -q -O "$FILENAME" "$DOWNLOAD_URL" || handle_error "下载失败"
elif command -v curl &> /dev/null; then
    curl -# -L -o "$FILENAME" "$DOWNLOAD_URL" || handle_error "下载失败"
fi
success_msg "下载完成"

# 解压并安装
info_msg "解压文件中..."
tar -zxf "$FILENAME" > /dev/null 2>&1 || handle_error "解压失败"
EXTRACT_DIR="frp_${FRP_VERSION}_${OS}_${ARCH}"

cp "$EXTRACT_DIR/frpc" "$PROGRAM"
chmod +x "$PROGRAM"

# 验证frpc
$PROGRAM --version > /dev/null 2>&1 || handle_error "frpc 执行失败"
success_msg "frpc 安装成功，版本: $($PROGRAM --version)"

# 清理临时文件
rm -rf "$EXTRACT_DIR" "$FILENAME"
echo ""

# 步骤4: 配置端口范围
info_msg "【步骤 4/5】配置端口范围..."
echo ""

# 检查端口是否被占用的函数
check_local_port() {
    local port=$1
    if ss -tln 2>/dev/null | grep -q ":$port "; then
        return 0  # 被占用
    elif netstat -tln 2>/dev/null | grep -q ":$port "; then
        return 0  # 被占用
    else
        return 1  # 空闲
    fi
}

# 获取起始端口
while true; do
    read -p "请输入起始端口: " START_PORT
    if [[ "$START_PORT" =~ ^[0-9]+$ ]] && [ "$START_PORT" -ge 1024 ] && [ "$START_PORT" -le 65535 ]; then
        break
    else
        echo -e "${RED}✗ 请输入有效的端口号 (1024-65535，建议使用1024以上端口)${NC}"
    fi
done

# 获取结束端口
while true; do
    read -p "请输入结束端口: " END_PORT
    if [[ "$END_PORT" =~ ^[0-9]+$ ]] && [ "$END_PORT" -ge "$START_PORT" ] && [ "$END_PORT" -le 65535 ]; then
        PORT_COUNT=$((END_PORT - START_PORT + 1))
        if [ $PORT_COUNT -gt 1000 ]; then
            warning_msg "您正在映射 $PORT_COUNT 个端口，这可能影响性能"
            read -p "是否继续? (y/n): " CONTINUE
            if [[ "$CONTINUE" != "y" && "$CONTINUE" != "Y" ]]; then
                continue
            fi
        fi
        break
    else
        echo -e "${RED}✗ 结束端口必须大于等于起始端口且小于等于65535${NC}"
    fi
done

# 检查本地端口占用
info_msg "检查本地端口占用情况..."
OCCUPIED_PORTS=""
for ((port=$START_PORT; port<=$END_PORT; port+=100)); do
    # 抽样检查，避免检查太多端口
    if check_local_port $port; then
        OCCUPIED_PORTS="$OCCUPIED_PORTS $port"
    fi
done

if [ -n "$OCCUPIED_PORTS" ]; then
    warning_msg "以下端口可能已被占用:$OCCUPIED_PORTS"
    read -p "是否继续? (y/n): " CONTINUE
    if [[ "$CONTINUE" != "y" && "$CONTINUE" != "Y" ]]; then
        exit 0
    fi
fi

# 步骤5: SSH端口映射配置（支持多个）
echo ""
info_msg "【SSH端口映射配置】"
echo "支持配置多个SSH端口映射（例如：22->10022, 2222->20022）"
read -p "是否配置SSH端口映射? (y/n，默认n): " CONFIG_SSH

SSH_COUNT=0
SSH_MAPPINGS_FILE="$CONFIG_DIR/ssh_mappings"
> "$SSH_MAPPINGS_FILE"  # 清空文件

if [[ "$CONFIG_SSH" == "y" || "$CONFIG_SSH" == "Y" ]]; then
    while true; do
        echo ""
        info_msg "配置第 $((SSH_COUNT+1)) 个SSH映射（直接回车结束）"
        
        # 获取本地SSH端口
        while true; do
            read -p "请输入本地SSH端口 (留空结束): " LOCAL_SSH_PORT
            if [ -z "$LOCAL_SSH_PORT" ]; then
                break 2
            fi
            if [[ "$LOCAL_SSH_PORT" =~ ^[0-9]+$ ]] && [ "$LOCAL_SSH_PORT" -ge 1 ] && [ "$LOCAL_SSH_PORT" -le 65535 ]; then
                # 检查本地SSH服务
                if check_local_port $LOCAL_SSH_PORT; then
                    success_msg "本地SSH端口 $LOCAL_SSH_PORT 似乎正在运行"
                else
                    warning_msg "本地端口 $LOCAL_SSH_PORT 可能没有SSH服务在运行"
                fi
                break
            else
                echo -e "${RED}✗ 请输入有效的端口号 (1-65535)${NC}"
            fi
        done
        
        # 获取远程SSH端口
        while true; do
            read -p "请输入远程SSH端口 (建议使用10000-60000): " REMOTE_SSH_PORT
            if [[ "$REMOTE_SSH_PORT" =~ ^[0-9]+$ ]] && [ "$REMOTE_SSH_PORT" -ge 1024 ] && [ "$REMOTE_SSH_PORT" -le 65535 ]; then
                # 检查端口是否在批量映射范围内
                if [ "$REMOTE_SSH_PORT" -ge "$START_PORT" ] && [ "$REMOTE_SSH_PORT" -le "$END_PORT" ]; then
                    warning_msg "远程SSH端口 $REMOTE_SSH_PORT 已在批量端口范围内"
                    read -p "是否继续使用此端口? (y/n): " PORT_CONFIRM
                    if [[ "$PORT_CONFIRM" != "y" && "$PORT_CONFIRM" != "Y" ]]; then
                        continue
                    fi
                fi
                break
            else
                echo -e "${RED}✗ 请输入有效的端口号 (1024-65535)${NC}"
            fi
        done
        
        # 保存映射
        echo "${LOCAL_SSH_PORT}:${REMOTE_SSH_PORT}" >> "$SSH_MAPPINGS_FILE"
        SSH_COUNT=$((SSH_COUNT + 1))
        success_msg "SSH映射已添加: 本地:$LOCAL_SSH_PORT -> 远程:$REMOTE_SSH_PORT"
    done
    
    if [ $SSH_COUNT -gt 0 ]; then
        success_msg "共配置 $SSH_COUNT 个SSH映射"
    fi
fi

echo ""
info_msg "端口配置摘要:"
echo "  - 端口范围: $START_PORT - $END_PORT"
echo "  - 总端口数: $PORT_COUNT 个端口"
if [ $SSH_COUNT -gt 0 ]; then
    echo "  - SSH映射数: $SSH_COUNT 个"
fi
echo ""

read -p "确认配置? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    info_msg "安装已取消"
    exit 0
fi
echo ""

# 生成配置文件
info_msg "生成FRP配置文件..."

cat > $CONFIG_FILE << EOF
# FRP客户端配置文件
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

serverAddr = "$SERVER_IP"
serverPort = $SERVER_PORT

auth.method = "token"
auth.token = "$AUTH_TOKEN"

# 管理面板配置
webServer.addr = "0.0.0.0"
webServer.port = $WEB_PORT
webServer.user = "$WEB_USER"
webServer.password = "$WEB_PASSWORD"
webServer.pprofEnable = false

# 日志配置
log.to = "console"
log.level = "info"
log.maxDays = 3

EOF

# 添加SSH映射
if [ $SSH_COUNT -gt 0 ]; then
    cat >> $CONFIG_FILE << EOF
# SSH端口映射配置
EOF
    INDEX=1
    while IFS=':' read -r local_port remote_port; do
        if [ -n "$local_port" ] && [ -n "$remote_port" ]; then
            cat >> $CONFIG_FILE << EOF

[[proxies]]
name = "ssh-tunnel-${remote_port}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${local_port}
remotePort = ${remote_port}
useEncryption = true
useCompression = true

EOF
        fi
        INDEX=$((INDEX + 1))
    done < "$SSH_MAPPINGS_FILE"
fi

# 添加批量端口映射
cat >> $CONFIG_FILE << EOF
# 批量端口映射 (${START_PORT}-${END_PORT})
EOF

for ((port=$START_PORT; port<=$END_PORT; port++)); do
    cat >> $CONFIG_FILE << EOF

[[proxies]]
name = "${PROXY_PREFIX}-${port}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${port}
remotePort = ${port}
useEncryption = true
useCompression = true

EOF
done

# 验证配置文件
$PROGRAM -c $CONFIG_FILE --verify > /dev/null 2>&1
if [ $? -eq 0 ]; then
    success_msg "配置文件验证通过"
else
    warning_msg "配置文件验证失败，但将继续"
fi

# 保存配置信息
echo "$START_PORT-$END_PORT" > "$CONFIG_DIR/host_port_range"
echo "$SERVER_IP" > "$CONFIG_DIR/host_ipaddr"
echo "$((END_PORT + 1))" > "$CONFIG_DIR/check_port"

success_msg "配置文件生成完成"
echo ""

# 步骤6: 配置和启动服务
info_msg "【步骤 5/5】配置和启动服务..."

# 创建健康检查脚本
HEALTH_SCRIPT="$TARGET_DIR/vastaish"
cat > $HEALTH_SCRIPT << 'HEALTHEOF'
#!/bin/bash
CONFIG_DIR="/var/lib/vastai_kaalia"
LOG_FILE="/var/log/vastaictcdn-health.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

SERVER_IP=$(cat $CONFIG_DIR/host_ipaddr 2>/dev/null || echo "")
LOCAL_PORT=$(cat $CONFIG_DIR/check_port 2>/dev/null || echo "8000")

if [ -z "$SERVER_IP" ]; then
    log "错误: 无法读取服务器IP"
    exit 1
fi

TARGET_URL="http://${SERVER_IP}:${LOCAL_PORT}"
MAX_RETRIES=3
RETRY_INTERVAL=5

# 启动临时HTTP服务器
if ! lsof -i:$LOCAL_PORT | grep -q python3; then
    nohup python3 -m http.server $LOCAL_PORT > /dev/null 2>&1 &
    sleep 2
fi

# 测试连接
if curl -s --max-time 5 "$TARGET_URL" > /dev/null; then
    log "健康检查通过"
    fuser -k ${LOCAL_PORT}/tcp 2>/dev/null
    exit 0
fi

# 重试
success=false
for ((i=1; i<=MAX_RETRIES; i++)); do
    log "重试 $i/$MAX_RETRIES..."
    sleep $RETRY_INTERVAL
    if curl -s --max-time 5 "$TARGET_URL" > /dev/null; then
        success=true
        break
    fi
done

if [ "$success" = false ]; then
    log "健康检查失败，重启服务"
    systemctl restart vastaictcdn
fi

fuser -k ${LOCAL_PORT}/tcp 2>/dev/null
HEALTHEOF

chmod +x $HEALTH_SCRIPT

# 创建SSH健康检查脚本
if [ $SSH_COUNT -gt 0 ]; then
    SSH_HEALTH_SCRIPT="$TARGET_DIR/vastaissh"
    cat > $SSH_HEALTH_SCRIPT << 'SSHHEALTHEOF'
#!/bin/bash
CONFIG_DIR="/var/lib/vastai_kaalia"
LOG_FILE="/var/log/vastaissh-health.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

if [ -f "$CONFIG_DIR/ssh_mappings" ]; then
    while IFS=':' read -r local_port remote_port; do
        if [ -n "$local_port" ] && [ -n "$remote_port" ]; then
            # 检查本地SSH服务
            if ss -tln 2>/dev/null | grep -q ":$local_port " || netstat -tln 2>/dev/null | grep -q ":$local_port "; then
                log "SSH端口 $local_port 正常"
            else
                log "警告: SSH服务没有在端口 $local_port 上运行"
                # 尝试重启SSH服务
                if systemctl is-active sshd >/dev/null 2>&1; then
                    systemctl restart sshd
                    log "已重启 sshd 服务"
                elif systemctl is-active ssh >/dev/null 2>&1; then
                    systemctl restart ssh
                    log "已重启 ssh 服务"
                fi
            fi
        fi
    done < "$CONFIG_DIR/ssh_mappings"
fi
SSHHEALTHEOF
    chmod +x $SSH_HEALTH_SCRIPT
    
    # 创建SSH健康检查定时器
    cat > /etc/systemd/system/vastaissh-health.service << SSHHEALTHSERVICEEOF
[Unit]
Description=Axis AI SSH Health Check
After=network.target

[Service]
Type=oneshot
ExecStart=$SSH_HEALTH_SCRIPT
SSHHEALTHSERVICEEOF

    cat > /etc/systemd/system/vastaissh-health.timer << SSHTIMEREOF
[Unit]
Description=Axis AI SSH Health Check Timer

[Timer]
OnBootSec=3min
OnUnitActiveSec=10min

[Install]
WantedBy=timer.target
SSHTIMEREOF
fi

# 创建systemd服务
cat > /etc/systemd/system/vastaictcdn.service << SERVICEEOF
[Unit]
Description=Axis AI CDN Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Restart=always
RestartSec=10s
StartLimitBurst=5
StartLimitIntervalSec=60
WorkingDirectory=$TARGET_DIR
ExecStart=$PROGRAM -c $CONFIG_FILE
ExecReload=/bin/kill -HUP \$MAINPID
StandardOutput=journal
StandardError=journal
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICEEOF

# 创建健康检查服务
cat > /etc/systemd/system/vastaictcdn-health.service << HEALTHSERVICEEOF
[Unit]
Description=Axis AI CDN Health Check
After=network.target

[Service]
Type=oneshot
ExecStart=$HEALTH_SCRIPT
HEALTHSERVICEEOF

cat > /etc/systemd/system/vastaictcdn-health.timer << TIMEREOF
[Unit]
Description=Axis AI CDN Health Check Timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
RandomizedDelaySec=10

[Install]
WantedBy=timer.target
TIMEREOF

# 创建logrotate配置
cat > /etc/logrotate.d/vastaictcdn << LOGROTATEEOF
/var/log/vastaictcdn*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    sharedscripts
    postrotate
        systemctl kill -s HUP vastaictcdn.service
    endscript
}
LOGROTATEEOF

# 启用并启动服务
systemctl daemon-reload
systemctl enable vastaictcdn.service > /dev/null 2>&1
systemctl enable vastaictcdn-health.timer > /dev/null 2>&1
systemctl start vastaictcdn.service
systemctl start vastaictcdn-health.timer

if [ $SSH_COUNT -gt 0 ]; then
    systemctl enable vastaissh-health.timer > /dev/null 2>&1
    systemctl start vastaissh-health.timer
fi

success_msg "服务配置完成"
echo ""

# 验证服务状态
info_msg "正在验证服务状态..."
sleep 5

if systemctl is-active vastaictcdn.service > /dev/null 2>&1; then
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════════"
    echo -e "${GREEN}║                    ✓ 安装成功！服务运行正常                                ║${NC}"
    echo "═══════════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo " 服务摘要:"
    echo "  - 服务器地址: $SERVER_IP:$SERVER_PORT"
    echo "  - 端口范围: $START_PORT - $END_PORT ($PORT_COUNT 个端口)"
    if [ $SSH_COUNT -gt 0 ]; then
        echo "  - SSH映射数量: $SSH_COUNT 个"
        echo ""
        echo " SSH连接命令:"
        while IFS=':' read -r local_port remote_port; do
            if [ -n "$local_port" ] && [ -n "$remote_port" ]; then
                echo "   ssh -p $remote_port user@$SERVER_IP  (本地端口:$local_port)"
            fi
        done < "$SSH_MAPPINGS_FILE"
    fi
    echo ""
else
    echo -e "${RED}"
    echo " 服务启动失败，查看日志:"
    echo " journalctl -u vastaictcdn.service -n 50 --no-pager"
    echo -e "${NC}"
    exit 1
fi

# 显示使用说明
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo "使用说明:"
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "1. Web管理界面: http://localhost:$WEB_PORT"
echo "   用户名: $WEB_USER"
echo "   密码: $WEB_PASSWORD"
echo ""
echo "2. 服务管理命令:"
echo "   - 查看状态: systemctl status vastaictcdn.service"
echo "   - 重启服务: systemctl restart vastaictcdn.service"
echo "   - 查看日志: journalctl -u vastaictcdn.service -f"
echo "   - 重载配置: systemctl reload vastaictcdn.service"
echo ""
echo "3. 配置文件位置: $CONFIG_FILE"
echo "4. 日志文件: /var/log/vastaictcdn*.log"
echo ""
echo "5. 防火墙配置（如果需要）:"
echo "   firewall-cmd --add-port=$START_PORT-$END_PORT/tcp --permanent"
echo "   firewall-cmd --reload"
echo ""

if [ $SSH_COUNT -gt 0 ]; then
    echo "6. SSH健康检查日志: /var/log/vastaissh-health.log"
    echo ""
fi

echo "═══════════════════════════════════════════════════════════════════════════════════"
echo -e "${GREEN}感谢使用 ****隔壁老王**** 一键安装脚本 v2.0！${NC}"
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo ""

# 删除脚本自身
SCRIPT_PATH="$(realpath "$0" 2>/dev/null)"
if [ -f "$SCRIPT_PATH" ] && [ "$SCRIPT_PATH" != "/bin/bash" ] && [ "$SCRIPT_PATH" != "/usr/bin/bash" ]; then
    rm -f "$SCRIPT_PATH" 2>/dev/null
fi
