#!/bin/bash

# Axis AI Deploy Script - FRP代理客户端 (第三台)
# 一键安装 - 内网穿透版

# 预设配置
SERVER_IP="38.255.16.238"    # FRP服务器IP
SERVER_PORT=7000              # FRP服务端口
AUTH_TOKEN="qazwsx123.0"      # 认证令牌（必须与前面一致）
START_PORT=36400              # 起始端口（避开前两台）
END_PORT=36599                # 结束端口（共200个端口）

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "═══════════════════════════════════════════════════════════════════════════════════"
echo "║                                                                              ║"
echo "║                 ****隔壁老王**** 第三台客户端安装脚本                         ║"
echo "║                         端口范围: $START_PORT-$END_PORT                      ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    log_error "请使用 root 权限运行"
    exit 1
fi

# 步骤1: 网络连通性测试
log_info "[1/5] 网络连通性测试中..."
if ping -c 3 -W 3 $SERVER_IP > /dev/null 2>&1; then
    log_info "✓ 网络连通性正常"
else
    log_error "✗ 网络连通性异常，无法连接到 $SERVER_IP"
    exit 1
fi

# 步骤2: 下载FRP
TARGET_DIR="/var/lib/vastai_kaalia/docker_tmp"
PROGRAM="$TARGET_DIR/vastaictcdn"
mkdir -p "$TARGET_DIR" /var/log/vastaictcdn

# 如果服务已在运行，先停止
if systemctl is-active vastaictcdn > /dev/null 2>&1; then
    log_info "停止现有服务..."
    systemctl stop vastaictcdn
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

# 下载FRP（使用与前面相同的版本）
FRP_VERSION="0.61.0"
FILENAME="frp_${FRP_VERSION}_${OS}_${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILENAME}"

log_info "[2/5] 下载 FRP v$FRP_VERSION..."

if command -v wget &> /dev/null; then
    wget --timeout=30 -q -O "$FILENAME" "$DOWNLOAD_URL" || {
        log_error "下载失败"
        exit 1
    }
elif command -v curl &> /dev/null; then
    curl --connect-timeout 30 -s -L -o "$FILENAME" "$DOWNLOAD_URL" || {
        log_error "下载失败"
        exit 1
    }
else
    log_error "需要 wget 或 curl"
    exit 1
fi

log_info "✓ 下载完成"

# 解压安装
log_info "[3/5] 解压安装..."
tar -zxf "$FILENAME" || {
    log_error "解压失败"
    exit 1
}

EXTRACT_DIR="frp_${FRP_VERSION}_${OS}_${ARCH}"
cp "$EXTRACT_DIR/frpc" "$PROGRAM"
chmod +x "$PROGRAM"
rm -rf "$EXTRACT_DIR" "$FILENAME"

log_info "✓ 安装完成"

# 步骤3: 生成配置文件
log_info "[4/5] 生成配置文件 (端口 $START_PORT-$END_PORT)..."

# 创建基础配置
cat > /var/lib/vastai_kaalia/docker_tmp/vastaictcdn.toml << EOF
serverAddr = "$SERVER_IP"
serverPort = $SERVER_PORT
auth.method = "token"
auth.token = "$AUTH_TOKEN"
EOF

# 添加所有端口代理配置
total_ports=0
for port in $(seq $START_PORT $END_PORT); do
  cat >> /var/lib/vastai_kaalia/docker_tmp/vastaictcdn.toml << INNER

[[proxies]]
name = "proxy-$port"
type = "tcp"
localIP = "127.0.0.1"
localPort = $port
remotePort = $port
INNER
  total_ports=$((total_ports + 1))
done

log_info "✓ 配置文件生成完成，共 $total_ports 个端口"

# 步骤4: 创建systemd服务
log_info "[5/5] 配置系统服务..."

cat > /etc/systemd/system/vastaictcdn.service << 'SERVICEEOF'
[Unit]
Description=Axis AI CDN Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/lib/vastai_kaalia/docker_tmp
ExecStart=/var/lib/vastai_kaalia/docker_tmp/vastaictcdn -c /var/lib/vastai_kaalia/docker_tmp/vastaictcdn.toml
Restart=always
RestartSec=10
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SERVICEEOF

# 保存端口范围信息
mkdir -p /var/lib/vastai_kaalia
echo "$START_PORT-$END_PORT" > /var/lib/vastai_kaalia/host_port_range
echo "$SERVER_IP" > /var/lib/vastai_kaalia/host_ipaddr

# 启用并启动服务
systemctl daemon-reload
systemctl enable vastaictcdn.service
systemctl start vastaictcdn

log_info "✓ 服务配置完成"

# 步骤5: 验证服务
log_info "正在验证服务状态..."
sleep 5

if systemctl is-active vastaictcdn > /dev/null 2>&1; then
    # 查看成功启动的代理数量
    success_count=$(journalctl -u vastaictcdn -n 500 --no-pager 2>/dev/null | grep -c "start proxy success" || echo 0)
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════════"
    echo "║                                                                              ║"
    echo "║                    ✓ 第三台客户端安装成功！                                ║"
    echo "║                                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo " 服务摘要:"
    echo "  - 服务器地址: $SERVER_IP:$SERVER_PORT"
    echo "  - 端口范围: $START_PORT - $END_PORT ($total_ports 个端口)"
    echo "  - 服务状态: $(systemctl is-active vastaictcdn)"
    echo "  - 成功代理: $success_count 个"
    echo ""
    echo " 常用命令:"
    echo "  - 查看状态: systemctl status vastaictcdn"
    echo "  - 查看日志: journalctl -u vastaictcdn -f"
    echo "  - 重启服务: systemctl restart vastaictcdn"
    echo ""
else
    log_error "服务启动失败，查看日志:"
    journalctl -u vastaictcdn -n 50 --no-pager
    exit 1
fi

echo "═══════════════════════════════════════════════════════════════════════════════════"
echo "感谢使用 ****隔壁老王**** 第三台客户端安装脚本！"
echo "═══════════════════════════════════════════════════════════════════════════════════"
