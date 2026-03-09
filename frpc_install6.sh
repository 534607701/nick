#!/bin/bash

# ==================================================
# FRPC 多客户端安装脚本 - 强制清理重装版
# 特性：强制清理所有FRP残留 + 自动安装 + 自定义端口名称
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
echo "║     FRPC 多客户端安装脚本 - 强制清理重装版                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ==================== 第1步：交互式输入 ====================
print_step "1/8" "配置参数"

print_input "请输入 SSH 远程端口 (如 15002):"
read SSH_PORT

print_input "请输入批量端口起始 (如 46200):"
read START_PORT

print_input "请输入批量端口结束 (如 46399):"
read END_PORT

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

# ==================== 第2步：强制清理所有 FRP 残留（核心优化） ====================
print_step "2/8" "强制清理所有 FRP 残留"

# 记录当前脚本的PID
SCRIPT_PID=$$
print_info "当前脚本PID: $SCRIPT_PID"

# 1. 强制停止所有 frpc/frps 进程（不管名称，直接杀）
echo "强制停止所有 FRP 相关进程..."
FRP_PIDS=$(ps aux | grep -E 'frpc|frps' | grep -v grep | grep -v "$SCRIPT_PID" | awk '{print $2}')
if [ -n "$FRP_PIDS" ]; then
    echo "找到 FRP 进程: $FRP_PIDS"
    for pid in $FRP_PIDS; do
        echo "  强制终止进程 $pid"
        sudo kill -9 $pid 2>/dev/null
    done
    sleep 2
    # 再次检查残留
    REMAINING=$(ps aux | grep -E 'frpc|frps' | grep -v grep | grep -v "$SCRIPT_PID" | wc -l)
    if [ $REMAINING -gt 0 ]; then
        print_warn "仍有 $REMAINING 个 FRP 进程未清理干净，可能是权限问题"
    else
        print_info "所有 FRP 进程已清理"
    fi
else
    echo "未找到运行中的 FRP 进程"
fi

# 2. 强制停止并禁用所有 frp 相关 systemd 服务（通配符匹配）
echo ""
echo "强制停止并禁用所有 FRP 相关服务..."
FRP_SERVICES=$(systemctl list-unit-files | grep -E 'frpc|frps' | awk '{print $1}')
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

# 3. 强制删除所有 FRP 配置文件、日志、二进制文件
echo ""
echo "强制删除 FRP 配置/日志/二进制文件..."

# 删除配置目录
if [ -d "/etc/frp" ]; then
    sudo rm -rf /etc/frp
    print_info "已删除配置目录: /etc/frp"
fi

# 删除日志目录
if [ -d "/var/log/frp" ]; then
    sudo rm -rf /var/log/frp
    print_info "已删除日志目录: /var/log/frp"
fi

# 删除二进制文件（全路径查找）
FRP_BINS=$(which frpc frps 2>/dev/null)
if [ -n "$FRP_BINS" ]; then
    for bin in $FRP_BINS; do
        sudo rm -f $bin
        echo "  已删除二进制文件: $bin"
    done
fi
# 额外清理常见路径
sudo rm -f /usr/local/bin/frpc /usr/local/bin/frps /usr/bin/frpc /usr/bin/frps 2>/dev/null
print_info "FRP 二进制文件已强制清理"

# 4. 清理临时文件
sudo rm -rf /tmp/frp* 2>/dev/null
print_info "临时文件已清理"

print_info "强制清理阶段完成 - 所有旧 FRP 残留已删除"
sleep 2

# ==================== 第3步：重新安装 frpc（超级修复版） ====================
print_step "3/8" "重新安装 frpc 客户端"

# 确保目录存在
sudo mkdir -p /usr/local/bin

# 开始下载安装
print_info "开始下载安装 frpc..."

# 检测系统架构
ARCH=$(uname -m)
case $ARCH in
    x86_64) 
        ARCH_STR="amd64"
        ;;
    aarch64) 
        ARCH_STR="arm64"
        ;;
    armv7l) 
        ARCH_STR="arm"
        ;;
    *) 
        print_error "不支持的架构: $ARCH"
        exit 1
        ;;
esac

FRP_VERSION="0.61.0"
DOWNLOAD_FILE="frp_${FRP_VERSION}_linux_${ARCH_STR}.tar.gz"
DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${DOWNLOAD_FILE}"

print_info "系统架构: ${ARCH_STR}"
print_info "下载地址: ${DOWNLOAD_URL}"

cd /tmp
if command -v wget &>/dev/null; then
    wget -q --show-progress "$DOWNLOAD_URL"
elif command -v curl &>/dev/null; then
    curl -# -L -O "$DOWNLOAD_URL"
else
    print_error "请安装 wget 或 curl"
    exit 1
fi

print_info "解压并安装 frpc..."
tar -xzf "$DOWNLOAD_FILE"
cd "frp_${FRP_VERSION}_linux_${ARCH_STR}"

# 直接复制二进制文件
sudo cp frpc /usr/local/bin/frpc
sudo chmod +x /usr/local/bin/frpc

# 验证安装
if [ -f /usr/local/bin/frpc ] && [ -x /usr/local/bin/frpc ]; then
    print_info "frpc 安装成功"
    /usr/local/bin/frpc --version
else
    print_error "frpc 安装失败"
    exit 1
fi

# 清理临时文件
cd /tmp
rm -rf "frp_${FRP_VERSION}_linux_${ARCH_STR}" "$DOWNLOAD_FILE"

print_info "frpc 安装完成"

# ==================== 第4步：创建配置目录 ====================
print_step "4/8" "创建配置目录"

sudo mkdir -p /etc/frp
sudo mkdir -p /var/log/frp
print_info "目录创建完成"

# ==================== 第5步：生成配置文件（核心优化：自定义端口名称） ====================
print_step "5/8" "生成配置文件（自定义端口名称）"

# SSH 配置
print_info "创建 SSH 配置文件..."
sudo tee /etc/frp/vastaictssh.toml > /dev/null << EOF
serverAddr = "8.141.12.76"
serverPort = 7000
auth.method = "token"
auth.token = "qazwsx123.0"
log.to = "/var/log/frp/frpc-ssh.log"
log.level = "info"

[[proxies]]
name = "ssh_proxy_${SSH_PORT}"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = ${SSH_PORT}
EOF

# 验证 SSH 配置
/usr/local/bin/frpc -c /etc/frp/vastaictssh.toml -v || {
    print_error "SSH 配置验证失败"
    exit 1
}
print_info "SSH 配置验证通过"

# CDN 配置基础
print_info "创建 CDN 配置文件..."
sudo tee /etc/frp/vastaictcdn.toml > /dev/null << EOF
serverAddr = "209.146.116.106"
serverPort = 7000
auth.method = "token"
auth.token = "qazwsx123.0"
log.to = "/var/log/frp/frpc-cdn.log"
log.level = "info"
transport.tcpMux = true
EOF

# 添加批量端口（核心优化：端口名称改为 frp_port_xxx 替换 tcp_xxx）
print_info "添加 $PORT_COUNT 个端口映射（名称：frp_port_端口号）..."
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
    if [ $((count % 50)) -eq 0 ]; then
        echo "  已添加 $count 个端口..."
    fi
done
echo "  共添加 $count 个端口"

# 验证 CDN 配置
/usr/local/bin/frpc -c /etc/frp/vastaictcdn.toml -v || {
    print_error "CDN 配置验证失败"
    exit 1
}
print_info "CDN 配置验证通过"

# ==================== 第6步：创建 systemd 服务 ====================
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
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
print_info "服务文件创建完成"

# ==================== 第7步：启动服务 ====================
print_step "7/8" "启动服务"

# 启动 SSH
echo "启动 SSH 客户端..."
sudo systemctl enable frpc@vastaictssh.service
sudo systemctl start frpc@vastaictssh.service
sleep 3

# 启动 CDN
echo "启动 CDN 客户端..."
sudo systemctl enable frpc@vastaictcdn.service
sudo systemctl start frpc@vastaictcdn.service
sleep 5

# ==================== 第8步：检查状态 ====================
print_step "8/8" "检查服务状态"

echo ""
echo "----------------------------------------"
echo "SSH 客户端状态:"
systemctl status frpc@vastaictssh.service --no-pager | grep Active

echo ""
echo "CDN 客户端状态:"
systemctl status frpc@vastaictcdn.service --no-pager | grep Active
echo "----------------------------------------"

# 查看日志
echo ""
print_info "最新日志："

echo "SSH 日志:"
if [ -f /var/log/frp/frpc-ssh.log ]; then
    tail -3 /var/log/frp/frpc-ssh.log 2>/dev/null | sed 's/^/  /'
else
    echo "  暂无日志"
fi

echo ""
echo "CDN 日志:"
if [ -f /var/log/frp/frpc-cdn.log ]; then
    tail -3 /var/log/frp/frpc-cdn.log 2>/dev/null | sed 's/^/  /'
else
    echo "  暂无日志"
fi

# ==================== 完成 ====================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   安装完成！                                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "配置文件:"
echo "  /etc/frp/vastaictssh.toml"
echo "  /etc/frp/vastaictcdn.toml"
echo ""
echo "查看日志:"
echo "  tail -f /var/log/frp/frpc-ssh.log"
echo "  tail -f /var/log/frp/frpc-cdn.log"
echo ""
echo "端口名称规则: frp_port_端口号（如 frp_port_46200）"
echo ""

# 可选：删除安装脚本
SCRIPT_PATH="$(realpath "$0" 2>/dev/null)"
if [ -f "$SCRIPT_PATH" ] && [ "$SCRIPT_PATH" != "/bin/bash" ] && [ "$SCRIPT_PATH" != "/usr/bin/bash" ]; then
    echo ""
    print_input "是否删除安装脚本自身？(y/n): "
    read DELETE_SCRIPT
    if [[ "$DELETE_SCRIPT" =~ ^[Yy]$ ]]; then
        rm -f "$SCRIPT_PATH" 2>/dev/null
        print_info "安装脚本已删除"
    fi
fi

print_info "脚本执行完毕！"
