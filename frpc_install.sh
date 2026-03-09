#!/bin/bash

# ==================================================
# FRPC 多客户端安装脚本 - 最终版
# 特性：无自动清理，完全手动控制
# ==================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_input() { echo -e "${BLUE}[INPUT]${NC} $1"; }

# 清屏
clear
echo "================================================"
echo "   FRPC 多客户端安装脚本 - 最终版"
echo "================================================"
echo ""

# ==================== 首先询问是否清理 ====================
print_warn "是否要停止现有的 frpc 服务？(y/n): "
read -p "> " CLEAN_FRPC
if [[ "$CLEAN_FRPC" =~ ^[Yy]$ ]]; then
    echo "停止 frpc 服务..."
    sudo systemctl stop frpc@vastaictssh.service 2>/dev/null
    sudo systemctl stop frpc@vastaictcdn.service 2>/dev/null
    sleep 2
fi

print_warn "是否要删除旧的配置文件？(y/n): "
read -p "> " CLEAN_CONFIG
if [[ "$CLEAN_CONFIG" =~ ^[Yy]$ ]]; then
    echo "删除配置文件..."
    sudo rm -rf /etc/frp/vastaict*.toml 2>/dev/null
fi

echo ""

# ==================== 输入配置 ====================
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
    exit 0
fi

# ==================== 检查 frpc ====================
echo ""
print_info "【第1步】检查 frpc..."

if [ ! -f /usr/local/bin/frpc ]; then
    print_info "未找到 frpc，开始下载..."
    
    # 检测架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) FRP_FILE="frp_0.61.0_linux_amd64.tar.gz" ;;
        aarch64) FRP_FILE="frp_0.61.0_linux_arm64.tar.gz" ;;
        armv7l) FRP_FILE="frp_0.61.0_linux_arm.tar.gz" ;;
        *) print_error "不支持的架构: $ARCH"; exit 1 ;;
    esac
    
    cd /tmp
    echo "下载 $FRP_FILE ..."
    wget -q --show-progress "https://github.com/fatedier/frp/releases/download/v0.61.0/${FRP_FILE}"
    
    echo "解压中..."
    tar -xzf ${FRP_FILE}
    
    DIR_NAME=$(echo $FRP_FILE | sed 's/.tar.gz//')
    sudo cp ${DIR_NAME}/frpc /usr/local/bin/
    sudo chmod +x /usr/local/bin/frpc
    
    # 清理
    rm -rf ${DIR_NAME} ${FRP_FILE}
    
    print_info "frpc 安装完成"
else
    print_info "frpc 已存在"
    /usr/local/bin/frpc --version
fi

# ==================== 创建配置目录 ====================
echo ""
print_info "【第2步】创建配置目录..."

sudo mkdir -p /etc/frp
sudo mkdir -p /var/log/frp

print_info "目录创建完成"

# ==================== 创建 SSH 配置 ====================
echo ""
print_info "【第3步】创建 SSH 配置文件..."

sudo tee /etc/frp/vastaictssh.toml > /dev/null << EOF
serverAddr = "8.141.12.76"
serverPort = 7000
auth.method = "token"
auth.token = "qazwsx123.0"
log.to = "/var/log/frp/frpc-ssh.log"
log.level = "info"

[[proxies]]
name = "ssh_proxy"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = ${SSH_PORT}
EOF

# 验证配置
/usr/local/bin/frpc -c /etc/frp/vastaictssh.toml -v || {
    print_error "SSH 配置验证失败"
    exit 1
}
print_info "SSH 配置验证通过"

# ==================== 创建 CDN 配置 ====================
echo ""
print_info "【第4步】创建 CDN 配置文件..."

# 写入基础配置
sudo tee /etc/frp/vastaictcdn.toml > /dev/null << EOF
serverAddr = "209.146.116.106"
serverPort = 7000
auth.method = "token"
auth.token = "qazwsx123.0"
log.to = "/var/log/frp/frpc-cdn.log"
log.level = "info"
transport.tcpMux = true
EOF

# 添加端口映射
echo "添加 $PORT_COUNT 个端口映射..."
count=0
for port in $(seq $START_PORT $END_PORT); do
    sudo tee -a /etc/frp/vastaictcdn.toml > /dev/null << EOF

[[proxies]]
name = "tcp_${port}"
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

# 验证配置
/usr/local/bin/frpc -c /etc/frp/vastaictcdn.toml -v || {
    print_error "CDN 配置验证失败"
    exit 1
}
print_info "CDN 配置验证通过"

# ==================== 创建 systemd 服务 ====================
echo ""
print_info "【第5步】创建 systemd 服务..."

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

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
print_info "服务文件创建完成"

# ==================== 启动服务 ====================
echo ""
print_info "【第6步】启动服务..."

# 启动 SSH
echo "启动 SSH 客户端..."
sudo systemctl enable frpc@vastaictssh.service
sudo systemctl start frpc@vastaictssh.service
sleep 3

# 检查 SSH 状态
if systemctl is-active --quiet frpc@vastaictssh.service; then
    echo "  ✅ SSH 客户端运行中"
else
    echo "  ❌ SSH 客户端启动失败"
    sudo journalctl -u frpc@vastaictssh.service -n 5 --no-pager
fi

# 启动 CDN
echo "启动 CDN 客户端..."
sudo systemctl enable frpc@vastaictcdn.service
sudo systemctl start frpc@vastaictcdn.service
sleep 5

# 检查 CDN 状态
if systemctl is-active --quiet frpc@vastaictcdn.service; then
    echo "  ✅ CDN 客户端运行中"
else
    echo "  ❌ CDN 客户端启动失败"
    sudo journalctl -u frpc@vastaictcdn.service -n 5 --no-pager
fi

# ==================== 最终状态 ====================
echo ""
print_info "【第7步】最终状态"

echo "----------------------------------------"
echo "SSH 客户端:"
systemctl status frpc@vastaictssh.service --no-pager | grep Active

echo ""
echo "CDN 客户端:"
systemctl status frpc@vastaictcdn.service --no-pager | grep Active
echo "----------------------------------------"

# ==================== 日志查看 ====================
echo ""
print_info "最新日志："

echo "SSH 日志:"
if [ -f /var/log/frp/frpc-ssh.log ]; then
    tail -3 /var/log/frp/frpc-ssh.log 2>/dev/null
else
    echo "  暂无日志"
fi

echo ""
echo "CDN 日志:"
if [ -f /var/log/frp/frpc-cdn.log ]; then
    tail -3 /var/log/frp/frpc-cdn.log 2>/dev/null
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
