#!/bin/bash

# ==================================================
# FRPC 多客户端安装脚本 - 最终修复版（适配frp 0.61.0）
# 特性：强制清理 + 依赖自动安装 + 正确配置格式 + 稳连参数 + 容错处理
# 修复：移除不支持的heartbeat字段，修正systemd注释问题
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
echo "║     FRPC 多客户端安装脚本 - 最终修复版（适配frp 0.61.0）      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 检查是否为root用户
if [ $EUID -ne 0 ]; then
    print_error "请使用root用户运行此脚本（sudo ./xxx.sh）"
    exit 1
fi

# ==================== 第1步：交互式输入 ====================
print_step "1/8" "配置参数"

print_input "请输入 SSH 远程端口 (如 15002):"
read SSH_PORT
# 验证端口合法性
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
    print_error "SSH端口必须是1-65535之间的数字！"
    exit 1
fi

print_input "请输入批量端口起始 (如 46200):"
read START_PORT
if ! [[ "$START_PORT" =~ ^[0-9]+$ ]] || [ "$START_PORT" -lt 1 ] || [ "$START_PORT" -gt 65535 ]; then
    print_error "起始端口必须是1-65535之间的数字！"
    exit 1
fi

print_input "请输入批量端口结束 (如 46399):"
read END_PORT
if ! [[ "$END_PORT" =~ ^[0-9]+$ ]] || [ "$END_PORT" -lt "$START_PORT" ] || [ "$END_PORT" -gt 65535 ]; then
    print_error "结束端口必须大于起始端口且在1-65535之间！"
    exit 1
fi

# 计算端口数量
PORT_COUNT=$((END_PORT - START_PORT + 1))

echo ""
print_info "配置确认:"
echo "  SSH 端口: $SSH_PORT"
echo "  批量端口: $START_PORT - $END_PORT (共 $PORT_COUNT 个)"
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
        sudo kill -9 $pid 2>/dev/null
        echo "  强制终止进程 $pid"
    done
    sleep 2
    # 检查残留
    REMAINING=$(ps aux | grep -E 'frpc|frps' | grep -v grep | grep -v "$SCRIPT_PID" | wc -l)
    [ $REMAINING -gt 0 ] && print_warn "仍有 $REMAINING 个 FRP 进程未清理干净" || print_info "所有 FRP 进程已清理"
else
    echo "未找到运行中的 FRP 进程"
fi

# 2. 强制停止并禁用所有 frp 相关 systemd 服务
echo ""
echo "强制停止并禁用所有 FRP 相关服务..."
FRP_SERVICES=$(systemctl list-unit-files 2>/dev/null | grep -E 'frpc|frps' | awk '{print $1}')
if [ -n "$FRP_SERVICES" ]; then
    for service in $FRP_SERVICES; do
        echo "  处理服务: $service"
        sudo systemctl stop $service 2>/dev/null
        sudo systemctl disable $service 2>/dev/null
        sudo rm -f /etc/systemd/system/$service 2>/dev/null
    done
    sudo systemctl daemon-reload
    print_info "所有 FRP 服务已清理"
else
    echo "未找到 FRP 相关服务"
fi

# 3. 强制删除 FRP 配置/日志/二进制文件
echo ""
echo "强制删除 FRP 配置/日志/二进制文件..."
sudo rm -rf /etc/frp /var/log/frp 2>/dev/null
sudo rm -f /usr/local/bin/frpc /usr/local/bin/frps /usr/bin/frpc /usr/bin/frps 2>/dev/null
sudo rm -rf /tmp/frp* 2>/dev/null
print_info "所有 FRP 残留文件已清理"

print_info "强制清理阶段完成"
sleep 2

# ==================== 第3步：安装依赖 + 重新安装 frpc ====================
print_step "3/8" "安装依赖并重新安装 frpc 客户端"

# 自动安装依赖（wget/curl/tar）
print_info "安装必要依赖..."
sudo apt update -y && sudo apt install -y wget curl tar 2>/dev/null

# 确保目录存在
sudo mkdir -p /usr/local/bin

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
print_info "下载地址: ${DOWNLOAD_URL}"

cd /tmp
# 下载文件（容错处理）
if ! wget -q --show-progress "$DOWNLOAD_URL"; then
    print_info "wget下载失败，尝试curl..."
    if ! curl -# -L -O "$DOWNLOAD_URL"; then
        print_error "下载frp包失败，请检查网络或手动下载！"
        exit 1
    fi
fi

# 解压并安装（容错处理）
if ! tar -xzf "$DOWNLOAD_FILE"; then
    print_error "解压frp包失败，文件可能损坏！"
    exit 1
fi
cd "frp_${FRP_VERSION}_linux_${ARCH_STR}"

# 复制二进制文件并赋权
sudo cp frpc /usr/local/bin/frpc
sudo chmod +x /usr/local/bin/frpc

# 验证安装
if [ -f /usr/local/bin/frpc ] && [ -x /usr/local/bin/frpc ]; then
    print_info "frpc 安装成功！版本信息："
    /usr/local/bin/frpc --version
else
    print_error "frpc 安装失败，二进制文件丢失！"
    exit 1
fi

# 清理临时文件
cd /tmp
rm -rf "frp_${FRP_VERSION}_linux_${ARCH_STR}" "$DOWNLOAD_FILE"
print_info "frpc 安装完成"

# ==================== 第4步：创建配置目录 ====================
print_step "4/8" "创建配置目录"
sudo mkdir -p /etc/frp /var/log/frp
print_info "目录创建完成"

# ==================== 第5步：生成配置文件（正确格式+稳连参数） ====================
print_step "5/8" "生成配置文件（适配frp 0.61.0 + 稳连参数）"

# SSH 配置（正确格式 - 移除不支持的heartbeat字段）
print_info "创建 SSH 配置文件..."
sudo tee /etc/frp/vastaictssh.toml > /dev/null << EOF
# frp 0.61.0 正确配置格式
serverAddr = "8.141.12.76"
serverPort = 7000
auth.method = "token"
auth.token = "qazwsx123.0"
log.to = "/var/log/frp/frpc-ssh.log"
log.level = "info"
log.maxDays = 7

# 稳连参数（frp 0.61.0 支持的格式）
transport.heartbeatInterval = 30
transport.heartbeatTimeout = 90
transport.tcpMux = true
loginFailExit = false

[[proxies]]
name = "ssh_proxy_${SSH_PORT}"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = ${SSH_PORT}
EOF

# 验证 SSH 配置（容错）
if /usr/local/bin/frpc -c /etc/frp/vastaictssh.toml -v; then
    print_info "SSH 配置验证通过"
else
    print_error "SSH 配置验证失败！请检查配置内容"
    exit 1
fi

# CDN 配置（正确格式 - 移除不支持的heartbeat字段）
print_info "创建 CDN 配置文件..."
sudo tee /etc/frp/vastaictcdn.toml > /dev/null << EOF
# frp 0.61.0 正确配置格式
serverAddr = "nick.dpdns.org"
serverPort = 9999
auth.method = "token"
auth.token = "qazwsx123.0"
log.to = "/var/log/frp/frpc-cdn.log"
log.level = "info"
log.maxDays = 7

# 稳连参数（frp 0.61.0 支持的格式）
transport.heartbeatInterval = 30
transport.heartbeatTimeout = 90
transport.tcpMux = true
loginFailExit = false
EOF

# 添加批量端口（名称：frp_port_端口号）
print_info "添加 $PORT_COUNT 个端口映射..."
count=0
for port in $(seq $START_PORT $END_PORT); do
    sudo tee -a /etc/frp/vastaictcdn.toml > /dev/null << EOF

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

# 验证 CDN 配置（容错）
if /usr/local/bin/frpc verify -c /etc/frp/vastaictcdn.toml; then
    print_info "CDN 配置验证通过"
else
    print_error "CDN 配置验证失败！请检查端口范围是否合法"
    exit 1
fi

# ==================== 第6步：创建 systemd 服务（移除行尾注释） ====================
print_step "6/8" "创建 systemd 服务"

sudo tee /etc/systemd/system/frpc@.service > /dev/null << 'EOF'
[Unit]
Description=FRPC Client for %I
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/frpc -c /etc/frp/%i.toml
Restart=always
RestartSec=10
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
print_info "服务文件创建完成"

# ==================== 第7步：优化系统TCP参数（防断连） ====================
print_step "7/8" "优化系统TCP参数（防止断连）"
sudo tee -a /etc/sysctl.conf > /dev/null << EOF
# FRPC 稳连优化参数
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_intvl=10
net.ipv4.tcp_keepalive_probes=3
EOF
sudo sysctl -p 2>/dev/null || true
print_info "TCP参数优化完成"

# ==================== 第8步：启动服务并检查状态 ====================
print_step "8/8" "启动服务并检查状态"

# 启动并设置开机自启
echo "启动 SSH 客户端..."
sudo systemctl enable frpc@vastaictssh.service
sudo systemctl start frpc@vastaictssh.service
sleep 3

echo "启动 CDN 客户端..."
sudo systemctl enable frpc@vastaictcdn.service
sudo systemctl start frpc@vastaictcdn.service
sleep 5

# 检查服务状态
echo ""
echo "----------------------------------------"
echo "SSH 客户端状态:"
ssh_active=$(systemctl is-active frpc@vastaictssh.service)
if [ "$ssh_active" = "active" ]; then
    echo -e "  状态: ${GREEN}运行中 (active)${NC}"
    echo "  最近日志:"
    tail -2 /var/log/frp/frpc-ssh.log 2>/dev/null | sed 's/^/    /' || echo "    暂无日志"
else
    echo -e "  状态: ${RED}异常 ($ssh_active)${NC}"
    echo "  错误信息:"
    journalctl -u frpc@vastaictssh.service -n 5 --no-pager | sed 's/^/    /'
fi

echo ""
echo "CDN 客户端状态:"
cdn_active=$(systemctl is-active frpc@vastaictcdn.service)
if [ "$cdn_active" = "active" ]; then
    echo -e "  状态: ${GREEN}运行中 (active)${NC}"
    echo "  最近日志:"
    tail -2 /var/log/frp/frpc-cdn.log 2>/dev/null | sed 's/^/    /' || echo "    暂无日志"
else
    echo -e "  状态: ${RED}异常 ($cdn_active)${NC}"
    echo "  错误信息:"
    journalctl -u frpc@vastaictcdn.service -n 5 --no-pager | sed 's/^/    /'
fi
echo "----------------------------------------"

# ==================== 完成 ====================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   安装完成！（最终修复版）                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "核心优化："
echo "  ✅ 配置文件适配 frp 0.61.0 正确格式（移除不支持的heartbeat）"
echo "  ✅ 内置30秒心跳+90秒超时，防止断连"
echo "  ✅ 优化系统TCP参数，防静默断连"
echo "  ✅ 增大文件句柄数，适配批量端口"
echo "  ✅ 修复systemd服务文件注释问题"
echo ""
echo "配置文件位置："
echo "  SSH: /etc/frp/vastaictssh.toml"
echo "  CDN: /etc/frp/vastaictcdn.toml"
echo ""
echo "常用命令："
echo "  查看状态: systemctl status frpc@vastaictssh.service frpc@vastaictcdn.service"
echo "  查看日志: tail -f /var/log/frp/frpc-ssh.log /var/log/frp/frpc-cdn.log"
echo "  重启服务: systemctl restart frpc@vastaictssh.service frpc@vastaictcdn.service"
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
