#!/bin/bash

# Axis AI Deploy Script - FRP代理客户端
# 一键安装 - 内网穿透版 (带22端口映射)

# 预设配置（可修改）
DOMAIN="209.146.116.106"
SERVER_PORT=7000
AUTH_TOKEN="qazwsx123.0"
WEB_PORT=7500
WEB_USER="admin"
WEB_PASSWORD="admin"
PROXY_PREFIX="proxy"
SERVER_IP="209.146.116.106"  # 预设服务器IP

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "═══════════════════════════════════════════════════════════════════════════════════"
echo "║                                                                              ║"
echo "║                 ****隔壁老王**** 一键安装脚本 (带SSH映射)                    ║"
echo "║                                                                              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_highlight() { echo -e "${BLUE}[SSH]${NC} $1"; }

# 步骤1: 网络连通性测试
log_info "[1/4] 网络连通性测试中..."
if ping -c 3 -W 3 $DOMAIN > /dev/null 2>&1; then
    log_info "✓ 网络连通性正常"
else
    log_error "✗ 网络连通性异常，无法连接到 $DOMAIN"
    exit 1
fi

# 步骤2: SSH端口映射配置
log_highlight "[2/4] 配置SSH远程访问端口..."

echo ""
echo "你可以通过FRP映射本机的22端口（SSH），实现远程SSH访问这台机器。"
echo ""

while true; do
    read -p "请输入SSH远程访问端口 (例如: 36022, 36023等): " SSH_REMOTE_PORT
    if [[ "$SSH_REMOTE_PORT" =~ ^[0-9]+$ ]] && [ "$SSH_REMOTE_PORT" -ge 1024 ] && [ "$SSH_REMOTE_PORT" -le 65535 ]; then
        # 检查端口是否常用（避免冲突）
        if [ "$SSH_REMOTE_PORT" -eq 22 ] || [ "$SSH_REMOTE_PORT" -eq 80 ] || [ "$SSH_REMOTE_PORT" -eq 443 ]; then
            log_warn "警告: 端口 $SSH_REMOTE_PORT 是常用端口，可能已被占用"
            read -p "确定使用这个端口? (y/n): " confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                break
            fi
        else
            break
        fi
    else
        log_error "请输入有效的端口号 (1024-65535)"
    fi
done

log_highlight "SSH映射配置: 访问 ${SERVER_IP}:${SSH_REMOTE_PORT} 将转发到本机的22端口"
echo ""

# 步骤3: 配置端口范围
log_info "[3/4] 配置业务端口范围..."

# 获取起始端口
while true; do
    read -p "请输入业务起始端口: " START_PORT
    if [[ "$START_PORT" =~ ^[0-9]+$ ]] && [ "$START_PORT" -ge 1024 ] && [ "$START_PORT" -le 65535 ]; then
        # 检查是否与SSH端口冲突
        if [ "$START_PORT" -le "$SSH_REMOTE_PORT" ] && [ "$END_PORT" -ge "$SSH_REMOTE_PORT" ] 2>/dev/null; then
            log_warn "警告: 业务端口范围会包含SSH端口 $SSH_REMOTE_PORT"
        fi
        break
    else
        log_error "请输入有效的端口号 (1024-65535)"
    fi
done

# 获取结束端口
while true; do
    read -p "请输入业务结束端口: " END_PORT
    if [[ "$END_PORT" =~ ^[0-9]+$ ]] && [ "$END_PORT" -ge "$START_PORT" ] && [ "$END_PORT" -le 65535 ]; then
        # 检查是否与SSH端口冲突
        if [ "$SSH_REMOTE_PORT" -ge "$START_PORT" ] && [ "$SSH_REMOTE_PORT" -le "$END_PORT" ]; then
            log_warn "警告: SSH端口 $SSH_REMOTE_PORT 在业务端口范围内"
            read -p "继续使用这个范围? (y/n): " confirm
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                continue
            fi
        fi
        break
    else
        log_error "结束端口必须大于等于起始端口且小于等于65535"
    fi
done

PORT_COUNT=$((END_PORT - START_PORT + 1))
log_info "业务端口配置摘要:"
log_info "  - 端口范围: $START_PORT - $END_PORT"
log_info "  - 总端口数: $PORT_COUNT 个端口"
log_highlight "SSH映射端口: $SSH_REMOTE_PORT (独立配置)"
echo ""

read -p "确认配置? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    log_warn "安装已取消"
    exit 0
fi

# 步骤4: 下载和安装程序
TARGET_DIR="/var/lib/vastai_kaalia/docker_tmp"
PROGRAM="$TARGET_DIR/vastaictcdn"
CONFIG_DIR="/var/lib/vastai_kaalia"
LOG_DIR="/var/log/vastaictcdn"

log_info "[4/4] 下载安装程序..."

# 创建必要目录
mkdir -p "$TARGET_DIR" "$CONFIG_DIR" "$LOG_DIR"

# 如果服务已在运行，先停止
if systemctl is-active vastaictcdn > /dev/null 2>&1; then
    log_info "停止现有服务..."
    systemctl stop vastaictcdn > /dev/null 2>&1
    sleep 2
fi

# 获取系统架构
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    armv7l) ARCH="arm" ;;
    *) log_error "不支持的架构: $ARCH"; exit 1 ;;
esac

OS=$(uname -s | tr '[A-Z]' '[a-z]')

# 使用阿里云镜像下载FRP
FRP_VERSION="0.65.0"
FILENAME="frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"
DOWNLOAD_URL="http://8.141.12.76/sever/${FILENAME}"

log_info "正在从阿里云镜像下载 FRP v$FRP_VERSION (架构: ${ARCH})..."
log_info "下载地址: $DOWNLOAD_URL"

# 检查阿里云服务器是否可访问
if ping -c 1 -W 3 8.141.12.76 > /dev/null 2>&1; then
    log_info "✓ 阿里云服务器可达"
else
    log_warn "⚠ 阿里云服务器 ping 不通，可能无法下载"
fi

if command -v wget &> /dev/null; then
    wget -q --show-progress -O "$FILENAME" "$DOWNLOAD_URL" || {
        log_error "从阿里云下载失败，尝试备用下载..."
        FALLBACK_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILENAME}"
        wget -q --show-progress -O "$FILENAME" "$FALLBACK_URL" || {
            log_error "下载失败"
            exit 1
        }
    }
elif command -v curl &> /dev/null; then
    curl -# -L -o "$FILENAME" "$DOWNLOAD_URL" || {
        log_error "从阿里云下载失败，尝试备用下载..."
        FALLBACK_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILENAME}"
        curl -# -L -o "$FILENAME" "$FALLBACK_URL" || {
            log_error "下载失败"
            exit 1
        }
    }
else
    log_error "需要wget或curl"
    exit 1
fi

log_info "✓ 下载完成"

# 解压并安装
log_info "解压文件中..."
tar -zxf "$FILENAME" > /dev/null 2>&1 || {
    log_error "解压失败"
    exit 1
}

EXTRACT_DIR="frp_${FRP_VERSION}_linux_${ARCH}"
cp "$EXTRACT_DIR/frpc" "$PROGRAM"
chmod +x "$PROGRAM"

# 清理临时文件
rm -rf "$EXTRACT_DIR" "$FILENAME"

log_info "✓ 安装程序完成"

# 生成配置文件（展开所有端口）
CONFIG_FILE="$TARGET_DIR/vastaictcdn.toml"

# 创建基础配置
cat > $CONFIG_FILE << EOF
serverAddr = "$SERVER_IP"
serverPort = $SERVER_PORT
auth.method = "token"
auth.token = "$AUTH_TOKEN"
EOF

# 先添加SSH端口映射（独立配置，更醒目）
cat >> $CONFIG_FILE << SSHBLOCK

# ========== SSH远程访问配置 ==========
# 通过 ${SERVER_IP}:${SSH_REMOTE_PORT} 访问本机SSH
[[proxies]]
name = "ssh-access"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = $SSH_REMOTE_PORT
# ====================================
SSHBLOCK

# 再添加业务端口代理配置
if [ $PORT_COUNT -gt 0 ]; then
    cat >> $CONFIG_FILE << INNER

# ========== 业务端口映射 ==========
INNER
    for port in $(seq $START_PORT $END_PORT); do
        cat >> $CONFIG_FILE << INNER

[[proxies]]
name = "$PROXY_PREFIX-$port"
type = "tcp"
localIP = "127.0.0.1"
localPort = $port
remotePort = $port
INNER
    done
fi

# 保存配置信息
echo "$START_PORT-$END_PORT" > "$CONFIG_DIR/host_port_range"
echo "$SERVER_IP" > "$CONFIG_DIR/host_ipaddr"
echo "$((END_PORT + 1))" > "$CONFIG_DIR/check_port"
echo "$SSH_REMOTE_PORT" > "$CONFIG_DIR/ssh_port"  # 保存SSH端口

log_info "✓ 配置文件生成完成"
log_info "  - SSH映射端口: $SSH_REMOTE_PORT"
log_info "  - 业务端口: $PORT_COUNT 个"

# 配置和启动服务
log_info "配置和启动服务..."

# 创建健康检查脚本（增强版，包含SSH检查）
HEALTH_SCRIPT="$TARGET_DIR/vastaish"
cat > $HEALTH_SCRIPT << 'HEALTHEOF'
#!/bin/bash
CONFIG_DIR="/var/lib/vastai_kaalia"
LOG_FILE="/var/log/vastaictcdn/health.log"
SERVER_IP=$(cat $CONFIG_DIR/host_ipaddr 2>/dev/null || echo "")
LOCAL_PORT=$(cat $CONFIG_DIR/check_port 2>/dev/null || echo "8000")
SSH_PORT=$(cat $CONFIG_DIR/ssh_port 2>/dev/null || echo "")

# 日志函数
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

if [ -z "$SERVER_IP" ]; then
    exit 1
fi

# 检查服务进程
if ! pgrep -f "vastaictcdn" > /dev/null; then
    log_msg "服务进程不存在，重启服务"
    systemctl restart vastaictcdn
    exit 0
fi

# 检查SSH映射（如果有配置）
if [ -n "$SSH_PORT" ]; then
    if nc -z -w 3 $SERVER_IP $SSH_PORT 2>/dev/null; then
        log_msg "SSH映射检查正常 (端口 $SSH_PORT)"
    else
        log_msg "SSH映射检查失败 (端口 $SSH_PORT)"
    fi
fi

# 启动临时HTTP服务用于测试
TARGET_URL="http://${SERVER_IP}:${LOCAL_PORT}"
if ! lsof -i:$LOCAL_PORT | grep -q python3; then
    nohup python3 -m http.server $LOCAL_PORT > /dev/null 2>&1 &
    sleep 2
fi

# 测试连接
if curl -s --max-time 5 "$TARGET_URL" > /dev/null; then
    log_msg "业务连接测试正常"
else
    log_msg "业务连接测试失败，重启服务"
    systemctl restart vastaictcdn
fi

# 清理临时服务
fuser -k ${LOCAL_PORT}/tcp 2>/dev/null
exit 0
HEALTHEOF

chmod +x $HEALTH_SCRIPT

# 创建systemd服务
cat > /etc/systemd/system/vastaictcdn.service << SERVICEEOF
[Unit]
Description=Axis AI CDN Service (with SSH)
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$TARGET_DIR
ExecStart=$PROGRAM -c $CONFIG_FILE
Restart=always
RestartSec=10
LimitNOFILE=1048576

# 日志处理
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vastaictcdn

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
User=root
HEALTHSERVICEEOF

# 创建定时器
cat > /etc/systemd/system/vastaictcdn-health.timer << TIMEREOF
[Unit]
Description=Axis AI CDN Health Check Timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
RandomizedDelaySec=10

[Install]
WantedBy=timers.target
TIMEREOF

# 创建日志轮转配置
cat > /etc/logrotate.d/vastaictcdn << LOGROTATEEOF
/var/log/vastaictcdn/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    sharedscripts
    postrotate
        systemctl kill -s HUP vastaictcdn.service || true
    endscript
}
LOGROTATEEOF

# 启用并启动服务
systemctl daemon-reload
systemctl enable vastaictcdn.service > /dev/null 2>&1
systemctl enable vastaictcdn-health.timer > /dev/null 2>&1
systemctl start vastaictcdn.service
systemctl start vastaictcdn-health.timer

log_info "✓ 服务配置完成"

# 验证服务状态
log_info "正在验证服务状态..."
sleep 5

if systemctl is-active vastaictcdn > /dev/null 2>&1; then
    success_count=$(journalctl -u vastaictcdn -n 300 --no-pager 2>/dev/null | grep -c "start proxy success" || echo 0)
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════════"
    echo "║                                                                              ║"
    echo "║                    ✓ 安装成功！服务运行正常                                ║"
    echo "║                                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo " 📋 服务摘要:"
    echo "  - 服务器地址: $SERVER_IP:$SERVER_PORT"
    echo "  - 认证Token: ${AUTH_TOKEN:0:5}***${AUTH_TOKEN: -3}"
    echo ""
    echo " 🔑 SSH远程访问:"
    echo "  - 命令: ssh -p $SSH_REMOTE_PORT root@$SERVER_IP"
    echo "  - 示例: ssh -p $SSH_REMOTE_PORT root@$SERVER_IP"
    echo "  - 说明: 访问服务端的 $SSH_REMOTE_PORT 端口会转发到本机的22端口"
    echo ""
    echo " 🌐 业务端口范围:"
    echo "  - 端口范围: $START_PORT - $END_PORT ($PORT_COUNT 个端口)"
    echo "  - 服务状态: $(systemctl is-active vastaictcdn)"
    echo "  - 成功代理: $success_count 个"
    echo ""
    echo " 📝 常用命令:"
    echo "  - 查看状态: systemctl status vastaictcdn"
    echo "  - 查看日志: journalctl -u vastaictcdn -f"
    echo "  - 重启服务: systemctl restart vastaictcdn"
    echo "  - 测试SSH: nc -zv $SERVER_IP $SSH_REMOTE_PORT"
    echo ""
    
    # 测试SSH端口是否可访问
    if nc -z -w 3 $SERVER_IP $SSH_REMOTE_PORT 2>/dev/null; then
        log_highlight "✓ SSH端口 $SSH_REMOTE_PORT 已可访问"
    else
        log_warn "⚠ SSH端口 $SSH_REMOTE_PORT 暂时无法访问，等待服务启动..."
    fi
    echo ""
else
    log_error "服务启动失败，查看日志:"
    journalctl -u vastaictcdn -n 50 --no-pager
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo "感谢使用 ****隔壁老王**** 一键安装脚本 (带SSH映射版)！"
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "SSH远程访问命令:"
echo -e "${BLUE}ssh -p $SSH_REMOTE_PORT root@$SERVER_IP${NC}"
echo ""

# 删除脚本自身
SCRIPT_PATH="$(realpath "$0" 2>/dev/null)"
if [ -f "$SCRIPT_PATH" ] && [ "$SCRIPT_PATH" != "/bin/bash" ] && [ "$SCRIPT_PATH" != "/usr/bin/bash" ]; then
    rm -f "$SCRIPT_PATH" 2>/dev/null
fi
