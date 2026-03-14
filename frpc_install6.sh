#!/bin/bash

# ==================================================
# FRPC 双客户端安装脚本 - 最终稳定版
# SSH服务: ruichuang.cloud:7000
# CDN服务: nick.dpdns.org:9999
# 特性：交互输入 + 自动监控 + 稳连优化
# ==================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_input() { echo -e "${BLUE}[INPUT]${NC} $1"; }
print_step() { echo -e "${CYAN}[STEP $1]${NC} $2"; }

# 清屏
clear
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        FRPC 双客户端安装脚本 - 最终稳定版                    ║"
echo "║        SSH: ruichuang.cloud:7000                            ║"
echo "║        CDN: nick.dpdns.org:9999                             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 检查root权限
if [ $EUID -ne 0 ]; then
    print_error "请使用root用户运行此脚本（sudo ./xxx.sh）"
    exit 1
fi

# ==================== 第1步：交互式输入 ====================
print_step "1/8" "配置参数"

# 检测当前SSH端口（客户端本地端口）
CURRENT_SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
if [ -z "$CURRENT_SSH_PORT" ]; then
    CURRENT_SSH_PORT=22
fi
print_info "检测到本地SSH端口: $CURRENT_SSH_PORT"

# 输入SSH远程端口
print_input "请输入SSH远程端口 (客户端通过 ruichuang.cloud 连接此端口):"
read SSH_REMOTE_PORT
if ! [[ "$SSH_REMOTE_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_REMOTE_PORT" -lt 1 ] || [ "$SSH_REMOTE_PORT" -gt 65535 ]; then
    print_error "端口必须是1-65535之间的数字！"
    exit 1
fi

# 输入批量端口起始
print_input "请输入批量端口起始 (如 46200):"
read START_PORT
if ! [[ "$START_PORT" =~ ^[0-9]+$ ]] || [ "$START_PORT" -lt 1 ] || [ "$START_PORT" -gt 65535 ]; then
    print_error "起始端口必须是1-65535之间的数字！"
    exit 1
fi

# 输入批量端口结束
print_input "请输入批量端口结束 (如 46399):"
read END_PORT
if ! [[ "$END_PORT" =~ ^[0-9]+$ ]] || [ "$END_PORT" -le "$START_PORT" ] || [ "$END_PORT" -gt 65535 ]; then
    print_error "结束端口必须大于起始端口且在1-65535之间！"
    exit 1
fi

# 计算端口数量
PORT_COUNT=$((END_PORT - START_PORT + 1))

echo ""
print_info "配置确认:"
echo "  SSH本地端口: $CURRENT_SSH_PORT (客户端默认22)"
echo "  SSH远程端口: $SSH_REMOTE_PORT (通过 ruichuang.cloud 连接)"
echo "  批量端口: $START_PORT - $END_PORT (共 $PORT_COUNT 个)"
echo "  SSH服务器: ruichuang.cloud:7000"
echo "  CDN服务器: nick.dpdns.org:9999"
echo "  Token: qazwsx123.0 (统一)"
echo ""

print_input "确认无误？(y/n): "
read CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    print_warn "安装已取消"
    exit 0
fi

# ==================== 第2步：强制清理所有 FRP 残留 ====================
print_step "2/8" "强制清理所有 FRP 残留"

# 记录当前脚本的PID
SCRIPT_PID=$$
print_info "当前脚本PID: $SCRIPT_PID"

# 1. 强制停止所有 frpc/frps 进程
echo "强制停止所有 FRP 相关进程..."
FRP_PIDS=$(ps aux | grep -E 'frpc|frps' | grep -v grep | grep -v "$SCRIPT_PID" | awk '{print $2}')
if [ -n "$FRP_PIDS" ]; then
    echo "找到 FRP 进程: $FRP_PIDS"
    for pid in $FRP_PIDS; do
        kill -9 $pid 2>/dev/null
        echo "  强制终止进程 $pid"
    done
    sleep 2
fi

# 2. 强制停止并禁用所有 frp 相关 systemd 服务
echo "强制停止并禁用所有 FRP 相关服务..."
FRP_SERVICES=$(systemctl list-unit-files 2>/dev/null | grep -E 'frpc|frps' | awk '{print $1}')
if [ -n "$FRP_SERVICES" ]; then
    for service in $FRP_SERVICES; do
        systemctl stop $service 2>/dev/null
        systemctl disable $service 2>/dev/null
        rm -f /etc/systemd/system/$service 2>/dev/null
    done
    systemctl daemon-reload
fi

# 3. 强制删除 FRP 配置/日志/二进制文件
echo "强制删除 FRP 残留文件..."
rm -rf /etc/frp /var/log/frp 2>/dev/null
rm -f /usr/local/bin/frpc /usr/local/bin/frps /usr/bin/frpc /usr/bin/frps 2>/dev/null
rm -rf /tmp/frp* 2>/dev/null

print_info "清理完成"
sleep 2

# ==================== 第3步：安装依赖 + 重新安装 frpc ====================
print_step "3/8" "安装 frpc 客户端"

# 安装依赖
print_info "安装必要依赖..."
apt update -y && apt install -y wget curl tar 2>/dev/null

# 创建目录
mkdir -p /usr/local/bin

# 检测系统架构
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH_STR="amd64" ;;
    aarch64) ARCH_STR="arm64" ;;
    armv7l) ARCH_STR="arm" ;;
    *) print_error "不支持的架构: $ARCH"; exit 1 ;;
esac

# 下载并安装 frp 0.61.0
FRP_VERSION="0.61.0"
DOWNLOAD_FILE="frp_${FRP_VERSION}_linux_${ARCH_STR}.tar.gz"
DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${DOWNLOAD_FILE}"

print_info "系统架构: ${ARCH_STR}"
cd /tmp

if ! wget -q --show-progress "$DOWNLOAD_URL"; then
    print_error "下载失败，请检查网络"
    exit 1
fi

tar -xzf "$DOWNLOAD_FILE"
cd "frp_${FRP_VERSION}_linux_${ARCH_STR}"
cp frpc /usr/local/bin/frpc
chmod +x /usr/local/bin/frpc

# 验证安装
/usr/local/bin/frpc --version && print_info "frpc 安装成功"

# 清理临时文件
cd /tmp
rm -rf "frp_${FRP_VERSION}_linux_${ARCH_STR}" "$DOWNLOAD_FILE"

# ==================== 第4步：创建配置目录 ====================
print_step "4/8" "创建配置目录"
mkdir -p /etc/frp /var/log/frp
print_info "目录创建完成"

# ==================== 第5步：生成配置文件 ====================
print_step "5/8" "生成配置文件"

# SSH 配置（ruichuang.cloud）
print_info "创建 SSH 配置文件..."
cat > /etc/frp/vastaictssh.toml << EOF
# SSH 客户端配置 - ruichuang.cloud
serverAddr = "ruichuang.cloud"
serverPort = 7000
auth.method = "token"
auth.token = "qazwsx123.0"

# 日志配置
log.to = "/var/log/frp/frpc-ssh.log"
log.level = "info"
log.maxDays = 7

# 稳连参数
transport.heartbeatInterval = 30
transport.heartbeatTimeout = 90
transport.tcpMux = true
transport.poolCount = 5
loginFailExit = false

# SSH 端口映射
[[proxies]]
name = "ssh_proxy_${SSH_REMOTE_PORT}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${CURRENT_SSH_PORT}    # 本地SSH端口（22或检测到的）
remotePort = ${SSH_REMOTE_PORT}    # 远程访问端口
EOF

# 验证 SSH 配置
if /usr/local/bin/frpc verify -c /etc/frp/vastaictssh.toml; then
    print_info "SSH 配置验证通过"
else
    print_error "SSH 配置验证失败"
    exit 1
fi

# CDN 配置（nick.dpdns.org）
print_info "创建 CDN 配置文件..."
cat > /etc/frp/vastaictcdn.toml << EOF
# CDN 客户端配置 - nick.dpdns.org
serverAddr = "nick.dpdns.org"
serverPort = 9999
auth.method = "token"
auth.token = "qazwsx123.0"

# 日志配置
log.to = "/var/log/frp/frpc-cdn.log"
log.level = "info"
log.maxDays = 7

# 稳连参数
transport.heartbeatInterval = 30
transport.heartbeatTimeout = 90
transport.tcpMux = true
transport.poolCount = 5
loginFailExit = false

# 批量端口映射
EOF

# 添加批量端口
print_info "添加 $PORT_COUNT 个端口映射..."
count=0
for port in $(seq $START_PORT $END_PORT); do
    cat >> /etc/frp/vastaictcdn.toml << EOF

[[proxies]]
name = "frp_port_${port}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${port}
remotePort = ${port}
EOF
    count=$((count + 1))
    [ $((count % 50)) -eq 0 ] && echo "  已添加 $count 个端口..."
done
echo "  共添加 $count 个端口"

# 验证 CDN 配置
if /usr/local/bin/frpc verify -c /etc/frp/vastaictcdn.toml; then
    print_info "CDN 配置验证通过"
else
    print_error "CDN 配置验证失败"
    exit 1
fi

# ==================== 第6步：创建 systemd 服务 ====================
print_step "6/8" "创建 systemd 服务"

cat > /etc/systemd/system/frpc@.service << 'EOF'
[Unit]
Description=FRPC Client for %I
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/frpc -c /etc/frp/%i.toml
Restart=always
RestartSec=3
StartLimitBurst=10
StartLimitInterval=60
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
print_info "服务文件创建完成"

# ==================== 第7步：添加监控脚本 ====================
print_step "7/8" "添加自动监控脚本"

cat > /usr/local/bin/frpc-monitor.sh << 'EOF'
#!/bin/bash
LOG_FILE="/var/log/frp/frpc-monitor.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# 检查SSH服务
if ! systemctl is-active --quiet frpc@vastaictssh; then
    echo "$DATE - SSH服务异常，正在重启..." >> $LOG_FILE
    systemctl restart frpc@vastaictssh
fi

# 检查CDN服务
if ! systemctl is-active --quiet frpc@vastaictcdn; then
    echo "$DATE - CDN服务异常，正在重启..." >> $LOG_FILE
    systemctl restart frpc@vastaictcdn
fi

# 检查进程
if ! pgrep -f "frpc -c /etc/frp/vastaictcdn.toml" > /dev/null; then
    echo "$DATE - CDN进程不存在，正在重启..." >> $LOG_FILE
    systemctl restart frpc@vastaictcdn
fi

if ! pgrep -f "frpc -c /etc/frp/vastaictssh.toml" > /dev/null; then
    echo "$DATE - SSH进程不存在，正在重启..." >> $LOG_FILE
    systemctl restart frpc@vastaictssh
fi

echo "$DATE - 检查完成" >> $LOG_FILE
EOF

chmod +x /usr/local/bin/frpc-monitor.sh

# 添加定时任务（每分钟检查）
(crontab -l 2>/dev/null | grep -v "frpc-monitor"; echo "* * * * * /usr/local/bin/frpc-monitor.sh >/dev/null 2>&1") | crontab -
print_info "监控脚本已添加，每分钟自动检查"

# ==================== 第8步：启动服务 ====================
print_step "8/8" "启动服务"

# 启动SSH服务
echo "启动 SSH 客户端..."
systemctl enable frpc@vastaictssh
systemctl start frpc@vastaictssh
sleep 3

# 启动CDN服务
echo "启动 CDN 客户端..."
systemctl enable frpc@vastaictcdn
systemctl start frpc@vastaictcdn
sleep 5

# 检查状态
echo ""
echo "----------------------------------------"
echo "SSH 客户端状态 (ruichuang.cloud:7000):"
if systemctl is-active --quiet frpc@vastaictssh; then
    echo -e "  状态: ${GREEN}运行中${NC}"
    echo "  最近日志:"
    tail -2 /var/log/frp/frpc-ssh.log 2>/dev/null | sed 's/^/    /' || echo "    暂无日志"
else
    echo -e "  状态: ${RED}异常${NC}"
    journalctl -u frpc@vastaictssh -n 3 --no-pager | sed 's/^/    /'
fi

echo ""
echo "CDN 客户端状态 (nick.dpdns.org:9999):"
if systemctl is-active --quiet frpc@vastaictcdn; then
    echo -e "  状态: ${GREEN}运行中${NC}"
    echo "  最近日志:"
    tail -2 /var/log/frp/frpc-cdn.log 2>/dev/null | sed 's/^/    /' || echo "    暂无日志"
else
    echo -e "  状态: ${RED}异常${NC}"
    journalctl -u frpc@vastaictcdn -n 3 --no-pager | sed 's/^/    /'
fi
echo "----------------------------------------"

# ==================== 完成 ====================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   安装完成！                                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "配置信息："
echo "  SSH客户端: ruichuang.cloud:7000"
echo "  SSH本地端口: $CURRENT_SSH_PORT → 远程端口: $SSH_REMOTE_PORT"
echo "  CDN客户端: nick.dpdns.org:9999"
echo "  批量端口: $START_PORT - $END_PORT (共 $PORT_COUNT 个)"
echo "  Token: qazwsx123.0"
echo ""
echo "配置文件："
echo "  SSH: /etc/frp/vastaictssh.toml"
echo "  CDN: /etc/frp/vastaictcdn.toml"
echo ""
echo "常用命令："
echo "  查看状态: systemctl status frpc@vastaictssh frpc@vastaictcdn"
echo "  查看日志: tail -f /var/log/frp/frpc-ssh.log /var/log/frp/frpc-cdn.log"
echo "  重启服务: systemctl restart frpc@vastaictssh frpc@vastaictcdn"
echo "  监控日志: tail -f /var/log/frp/frpc-monitor.log"
echo ""

# 可选删除脚本
SCRIPT_PATH="$(realpath "$0" 2>/dev/null)"
if [ -f "$SCRIPT_PATH" ] && [ "$SCRIPT_PATH" != "/bin/bash" ]; then
    echo ""
    print_input "是否删除安装脚本自身？(y/n): "
    read DELETE_SCRIPT
    [[ "$DELETE_SCRIPT" =~ ^[Yy]$ ]] && rm -f "$SCRIPT_PATH" && print_info "安装脚本已删除"
fi

print_info "脚本执行完毕！"
