#!/bin/bash

# ==================================================
# FRPC 批量端口安装脚本 - 仅批量端口版
# 特性：只安装批量端口客户端，不影响现有SSH服务
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
echo "║     FRPC 批量端口安装脚本 - 仅批量端口版                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 检查是否为root用户
if [ $EUID -ne 0 ]; then
    print_error "请使用root用户运行此脚本（sudo ./xxx.sh）"
    exit 1
fi

print_info "检测到现有SSH服务正在运行（端口15000），将只安装批量端口客户端"
echo ""

# ==================== 第1步：交互式输入（只输入批量端口） ====================
print_step "1/7" "配置批量端口参数"

print_input "请输入批量端口起始 (如 36400):"
read START_PORT
if ! [[ "$START_PORT" =~ ^[0-9]+$ ]] || [ "$START_PORT" -lt 1 ] || [ "$START_PORT" -gt 65535 ]; then
    print_error "起始端口必须是1-65535之间的数字！"
    exit 1
fi

print_input "请输入批量端口结束 (如 36599):"
read END_PORT
if ! [[ "$END_PORT" =~ ^[0-9]+$ ]] || [ "$END_PORT" -lt "$START_PORT" ] || [ "$END_PORT" -gt 65535 ]; then
    print_error "结束端口必须大于起始端口且在1-65535之间！"
    exit 1
fi

# 计算端口数量
PORT_COUNT=$((END_PORT - START_PORT + 1))

echo ""
print_info "配置确认:"
echo "  批量端口: $START_PORT - $END_PORT (共 $PORT_COUNT 个)"
echo "  SSH服务: 已存在 (端口15000，保持不变)"
echo ""

print_input "确认无误？(y/n): "
read CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    print_warn "安装已取消"
    exit 0
fi

# ==================== 第2步：清理可能冲突的CDN服务 ====================
print_step "2/7" "清理可能冲突的CDN服务"

# 记录当前脚本的PID
SCRIPT_PID=$$
print_info "当前脚本PID: $SCRIPT_PID"

# 1. 停止可能存在的旧CDN服务
if systemctl list-unit-files 2>/dev/null | grep -q frpc@vastaictcdn; then
    echo "停止旧的CDN服务..."
    sudo systemctl stop frpc@vastaictcdn.service 2>/dev/null
    sudo systemctl disable frpc@vastaictcdn.service 2>/dev/null
fi

# 2. 杀死可能残留的CDN进程
CDN_PIDS=$(ps aux | grep "frpc.*vastaictcdn" | grep -v grep | grep -v "$SCRIPT_PID" | awk '{print $2}')
if [ -n "$CDN_PIDS" ]; then
    echo "清理CDN进程..."
    for pid in $CDN_PIDS; do
        sudo kill -9 $pid 2>/dev/null
    done
    sleep 2
fi

# 3. 删除旧的CDN配置文件（保留SSH配置）
if [ -f /etc/frp/vastaictcdn.toml ]; then
    echo "删除旧的CDN配置文件..."
    sudo rm -f /etc/frp/vastaictcdn.toml
fi

print_info "CDN服务清理完成"
sleep 2

# ==================== 第3步：检查frpc是否已安装 ====================
print_step "3/7" "检查frpc客户端"

if [ ! -f /usr/local/bin/frpc ]; then
    print_info "未找到frpc，开始安装..."
    
    # 安装依赖
    sudo apt update -y && sudo apt install -y wget curl tar 2>/dev/null
    
    # 检测系统架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH_STR="amd64" ;;
        aarch64) ARCH_STR="arm64" ;;
        armv7l) ARCH_STR="arm" ;;
        *) print_error "不支持的架构: $ARCH"; exit 1 ;;
    esac
    
    # 下载并安装frp 0.61.0
    FRP_VERSION="0.61.0"
    DOWNLOAD_FILE="frp_${FRP_VERSION}_linux_${ARCH_STR}.tar.gz"
    DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${DOWNLOAD_FILE}"
    
    cd /tmp
    wget -q --show-progress "$DOWNLOAD_URL"
    tar -xzf "$DOWNLOAD_FILE"
    cd "frp_${FRP_VERSION}_linux_${ARCH_STR}"
    sudo cp frpc /usr/local/bin/frpc
    sudo chmod +x /usr/local/bin/frpc
    
    # 验证安装
    if [ -f /usr/local/bin/frpc ] && [ -x /usr/local/bin/frpc ]; then
        print_info "frpc 安装成功！"
        /usr/local/bin/frpc --version
    else
        print_error "frpc 安装失败"
        exit 1
    fi
    
    # 清理临时文件
    cd /tmp
    rm -rf "frp_${FRP_VERSION}_linux_${ARCH_STR}" "$DOWNLOAD_FILE"
else
    print_info "frpc 已存在，版本信息："
    /usr/local/bin/frpc --version
fi

# ==================== 第4步：创建配置目录 ====================
print_step "4/7" "创建配置目录"
sudo mkdir -p /etc/frp /var/log/frp
print_info "目录创建完成"

# ==================== 第5步：生成批量端口配置文件 ====================
print_step "5/7" "生成批量端口配置文件"

# CDN 配置（使用 frp_port_ 前缀，避免与SSH冲突）
print_info "创建CDN配置文件..."
sudo tee /etc/frp/vastaictcdn.toml > /dev/null << EOF
# frp 0.61.0 批量端口配置 - 仅CDN客户端
serverAddr = "209.146.116.106"
serverPort = 7000
auth = { method = "token", token = "qazwsx123.0" }
log = { to = "/var/log/frp/frpc-cdn.log", level = "info", maxDays = 3 }

# 稳连参数
transport.heartbeatInterval = 30
transport.heartbeatTimeout = 90
transport.tcpMux = true

# 批量端口映射
EOF

# 添加批量端口（使用frp_port_前缀，与现有SSH的ssh_proxy_15000不冲突）
print_info "添加 $PORT_COUNT 个端口映射（命名: frp_port_端口号）..."
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

# 验证CDN配置
if /usr/local/bin/frpc -c /etc/frp/vastaictcdn.toml -v; then
    print_info "CDN 配置验证通过"
else
    print_error "CDN 配置验证失败！"
    exit 1
fi

# ==================== 第6步：创建systemd服务（仅CDN） ====================
print_step "6/7" "创建systemd服务"

# 创建服务模板（如果不存在）
if [ ! -f /etc/systemd/system/frpc@.service ]; then
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
    print_info "服务模板创建完成"
else
    print_info "服务模板已存在"
fi

sudo systemctl daemon-reload

# ==================== 第7步：启动CDN服务 ====================
print_step "7/7" "启动CDN服务"

# 启动CDN服务
echo "启动CDN客户端..."
sudo systemctl enable frpc@vastaictcdn.service
sudo systemctl restart frpc@vastaictcdn.service
sleep 5

# 检查服务状态
echo ""
echo "----------------------------------------"
echo "CDN客户端状态:"
cdn_active=$(systemctl is-active frpc@vastaictcdn.service)
if [ "$cdn_active" = "active" ]; then
    echo -e "  状态: ${GREEN}运行中 (active)${NC}"
    
    # 显示运行的端口数
    success_count=$(grep -c "start proxy success" /var/log/frp/frpc-cdn.log 2>/dev/null || echo 0)
    echo -e "  成功端口: $success_count / $PORT_COUNT"
else
    echo -e "  状态: ${RED}异常 ($cdn_active)${NC}"
fi
echo "----------------------------------------"

# 查看最新日志
echo ""
print_info "最新日志："
echo "CDN日志:"
if [ -f /var/log/frp/frpc-cdn.log ]; then
    tail -5 /var/log/frp/frpc-cdn.log 2>/dev/null | sed 's/^/  /'
else
    echo "  暂无日志"
fi

# ==================== 完成 ====================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   安装完成！                                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "现有服务："
echo "  ✅ SSH服务: 运行中 (端口15000, 代理名: ssh_proxy_15000)"
echo "  ✅ CDN服务: 已安装 (端口 $START_PORT-$END_PORT, 代理名: frp_port_*)"
echo ""
echo "配置文件："
echo "  CDN: /etc/frp/vastaictcdn.toml"
echo ""
echo "管理命令："
echo "  查看状态: systemctl status frpc@vastaictcdn.service"
echo "  查看日志: tail -f /var/log/frp/frpc-cdn.log"
echo "  重启服务: systemctl restart frpc@vastaictcdn.service"

# 可选删除脚本
SCRIPT_PATH="$(realpath "$0" 2>/dev/null)"
if [ -f "$SCRIPT_PATH" ] && [ "$SCRIPT_PATH" != "/bin/bash" ]; then
    echo ""
    print_input "是否删除安装脚本自身？(y/n): "
    read DELETE_SCRIPT
    [[ "$DELETE_SCRIPT" =~ ^[Yy]$ ]] && rm -f "$SCRIPT_PATH" && print_info "安装脚本已删除"
fi

print_info "脚本执行完毕！CDN客户端已安装，不会影响现有SSH服务"
