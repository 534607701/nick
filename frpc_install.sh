#!/bin/bash

# ==================================================
# FRPC 安装脚本 - 超级防御版
# 特性：每一步都有保护，防止中断
# ==================================================

# 设置错误处理
set -e
trap 'echo "错误发生在第 $LINENO 行"' ERR

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_input() { echo -e "${BLUE}[INPUT]${NC} $1"; }

# 清屏
clear
echo "================================================"
echo "   FRPC 多客户端安装脚本 - 超级防御版"
echo "================================================"
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

# ==================== 第1步：清理旧服务 ====================
echo ""
print_info "【第1步】清理旧服务..."

# 逐个停止服务，避免一次性操作太多
sudo systemctl stop frpc@vastaictssh.service 2>/dev/null || true
sudo systemctl stop frpc@vastaictcdn.service 2>/dev/null || true
sleep 1

# 逐个杀死进程
sudo pkill -f "frpc.*vastaictssh" 2>/dev/null || true
sudo pkill -f "frpc.*vastaictcdn" 2>/dev/null || true
sudo pkill -f frpc 2>/dev/null || true
sleep 2

print_info "清理完成"

# ==================== 第2步：检查并安装 frpc ====================
echo ""
print_info "【第2步】检查 frpc..."

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
    wget -q "https://github.com/fatedier/frp/releases/download/v0.61.0/${FRP_FILE}"
    tar -xzf ${FRP_FILE}
    
    DIR_NAME=$(echo $FRP_FILE | sed 's/.tar.gz//')
    sudo cp ${DIR_NAME}/frpc /usr/local/bin/
    sudo chmod +x /usr/local/bin/frpc
    
    # 清理
    rm -rf ${DIR_NAME} ${FRP_FILE}
    
    print_info "frpc 安装完成"
else
    print_info "frpc 已存在"
fi

# 验证 frpc
/usr/local/bin/frpc --version || {
    print_error "frpc 无法运行"
    exit 1
}

# ==================== 第3步：创建配置目录 ====================
echo ""
print_info "【第3步】创建配置目录..."

sudo mkdir -p /etc/frp
sudo mkdir -p /var/log/frp
sudo chmod 755 /etc/frp /var/log/frp

print_info "目录创建完成"

# ==================== 第4步：创建 SSH 配置 ====================
echo ""
print_info "【第4步】创建 SSH 配置文件..."

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

# 验证 SSH 配置
/usr/local/bin/frpc -c /etc/frp/vastaictssh.toml -v || {
    print_error "SSH 配置验证失败"
    exit 1
}

print_info "SSH 配置创建完成"

# ==================== 第5步：创建 CDN 配置 ====================
echo ""
print_info "【第5步】创建 CDN 配置文件..."

# 先创建基础配置
sudo tee /etc/frp/vastaictcdn.toml > /dev/null << EOF
serverAddr = "209.146.116.106"
serverPort = 7000
auth.method = "token"
auth.token = "qazwsx123.0"
log.to = "/var/log/frp/frpc-cdn.log"
log.level = "info"
transport.tcpMux = true
EOF

# 分批添加端口，避免一次性写入太多
print_info "添加端口映射 (每次50个)..."
batch_size=50
current=$START_PORT

while [ $current -le $END_PORT ]; do
    batch_end=$((current + batch_size - 1))
    [ $batch_end -gt $END_PORT ] && batch_end=$END_PORT
    
    print_info "添加端口 $current - $batch_end..."
    
    for port in $(seq $current $batch_end); do
        sudo tee -a /etc/frp/vastaictcdn.toml > /dev/null << EOF

[[proxies]]
name = "tcp_${port}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${port}
remotePort = ${port}
EOF
    done
    
    current=$((batch_end + 1))
    sleep 1
done

# 验证 CDN 配置
/usr/local/bin/frpc -c /etc/frp/vastaictcdn.toml -v || {
    print_error "CDN 配置验证失败"
    exit 1
}

print_info "CDN 配置创建完成"

# ==================== 第6步：创建 systemd 服务 ====================
echo ""
print_info "【第6步】创建 systemd 服务..."

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

# ==================== 第7步：启动服务 ====================
echo ""
print_info "【第7步】启动服务..."

# 先启动 SSH
sudo systemctl enable frpc@vastaictssh.service
sudo systemctl start frpc@vastaictssh.service
sleep 2

# 再启动 CDN
sudo systemctl enable frpc@vastaictcdn.service
sudo systemctl start frpc@vastaictcdn.service
sleep 3

# ==================== 第8步：检查状态 ====================
echo ""
print_info "【第8步】检查服务状态..."

echo "----------------------------------------"
echo "SSH 客户端状态:"
sudo systemctl status frpc@vastaictssh.service --no-pager | grep Active || echo "  未运行"

echo ""
echo "CDN 客户端状态:"
sudo systemctl status frpc@vastaictcdn.service --no-pager | grep Active || echo "  未运行"
echo "----------------------------------------"

# ==================== 第9步：查看日志 ====================
echo ""
print_info "【第9步】查看最新日志..."

echo "SSH 日志:"
sudo tail -5 /var/log/frp/frpc-ssh.log 2>/dev/null || echo "  暂无日志"
echo ""
echo "CDN 日志:"
sudo tail -5 /var/log/frp/frpc-cdn.log 2>/dev/null || echo "  暂无日志"

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
