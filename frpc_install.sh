#!/bin/bash

# ==================================================
# FRPC 多客户端安装脚本 - 简化稳定版
# ==================================================

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
echo "   FRPC 多客户端安装脚本 - 简化版"
echo "================================================"
echo ""

# ==================== 输入配置 ====================
print_input "请输入 SSH 远程端口 (如 15002):"
read -p "> " SSH_PORT

print_input "请输入批量端口起始 (如 46200):"
read -p "> " START_PORT

print_input "请输入批量端口结束 (如 46399):"
read -p "> " END_PORT

# 计算端口数量
PORT_COUNT=$((END_PORT - START_PORT + 1))

echo ""
print_info "配置确认:"
echo "  SSH 端口: $SSH_PORT"
echo "  批量端口: $START_PORT - $END_PORT (共 $PORT_COUNT 个)"
echo ""

print_input "确认无误？(y/n): "
read -p "> " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    exit 0
fi

# ==================== 清理旧服务 ====================
print_info "清理旧服务..."
systemctl stop frpc@vastaictssh.service frpc@vastaictcdn.service 2>/dev/null
pkill -f frpc 2>/dev/null
sleep 2

# 删除旧配置
rm -rf /etc/frp/vastaict*.toml 2>/dev/null
rm -rf /etc/systemd/system/frpc*.service 2>/dev/null
rm -rf /etc/systemd/system/frpc*.timer 2>/dev/null

# ==================== 创建配置目录 ====================
mkdir -p /etc/frp /var/log/frp

# ==================== 创建 SSH 配置 ====================
print_info "创建 SSH 配置文件..."
cat > /etc/frp/vastaictssh.toml << EOF
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

# ==================== 创建 CDN 配置 ====================
print_info "创建 CDN 配置文件..."
cat > /etc/frp/vastaictcdn.toml << EOF
serverAddr = "209.146.116.106"
serverPort = 7000
auth.method = "token"
auth.token = "qazwsx123.0"
log.to = "/var/log/frp/frpc-cdn.log"
log.level = "info"
transport.tcpMux = true
EOF

# 添加批量端口
print_info "添加 $PORT_COUNT 个端口映射..."
for port in $(seq $START_PORT $END_PORT); do
    cat >> /etc/frp/vastaictcdn.toml << EOF

[[proxies]]
name = "tcp_${port}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${port}
remotePort = ${port}
EOF
done

# ==================== 验证配置 ====================
print_info "验证配置..."
/usr/local/bin/frpc -c /etc/frp/vastaictssh.toml -v
/usr/local/bin/frpc -c /etc/frp/vastaictcdn.toml -v

# ==================== 创建服务文件 ====================
print_info "创建 systemd 服务..."
cat > /etc/systemd/system/frpc@.service << 'EOF'
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

# ==================== 启动服务 ====================
print_info "启动服务..."
systemctl daemon-reload
systemctl enable frpc@vastaictssh.service frpc@vastaictcdn.service
systemctl start frpc@vastaictssh.service frpc@vastaictcdn.service

# ==================== 检查状态 ====================
sleep 3
echo ""
print_info "服务状态:"
systemctl status frpc@vastaictssh.service --no-pager | grep Active
systemctl status frpc@vastaictcdn.service --no-pager | grep Active

echo ""
print_info "安装完成！"
echo "配置文件: /etc/frp/vastaictssh.toml"
echo "配置文件: /etc/frp/vastaictcdn.toml"
echo "日志文件: /var/log/frp/frpc-ssh.log"
echo "日志文件: /var/log/frp/frpc-cdn.log"
echo ""
echo "查看日志: tail -f /var/log/frp/frpc-ssh.log"
echo "查看日志: tail -f /var/log/frp/frpc-cdn.log"
