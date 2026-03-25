#!/bin/bash

set -euo pipefail
trap 'cleanup $?' EXIT ERR INT TERM

# 版本和配置
readonly SCRIPT_VERSION="1.2.0"
readonly DEFAULT_FRP_VERSION="0.65.0"
readonly DEFAULT_BIND_PORT=7000
readonly DEFAULT_DASHBOARD_PORT=7500
readonly DEFAULT_DASHBOARD_USER="admin"
readonly DEFAULT_DASHBOARD_PWD="admin"
readonly DEFAULT_HEARTBEAT_TIMEOUT=180
readonly DEFAULT_TCP_MUX_KEEPALIVE=30

echo "========================================"
echo "          FRP 服务端自动安装脚本 v$SCRIPT_VERSION"
echo "========================================"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo -e "${BLUE}[DEBUG]${NC} $1"; }

# 清理函数
cleanup() {
    local exit_code=$1
    if [[ $exit_code -ne 0 ]]; then
        log_warn "脚本异常退出 (退出码: $exit_code)"
        rm -f /tmp/frp_*.tar.gz 2>/dev/null || true
    fi
}

# 检查依赖并自动安装（增强版）
check_dependencies() {
    log_info "[1/8] 检查系统依赖..."
    
    # 定义需要检查的命令和对应的包名
    declare -A deps_map=(
        ["wget"]="wget"
        ["tar"]="tar"
        ["curl"]="curl"
        ["grep"]="grep"
        ["systemctl"]="systemd"
        ["ss"]="iproute2"
    )
    
    local missing_deps=()
    local missing_cmds=()
    
    # 检查每个命令是否存在
    for cmd in "${!deps_map[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_cmds+=("$cmd")
            # 去重添加包名
            local pkg="${deps_map[$cmd]}"
            if [[ ! " ${missing_deps[@]} " =~ " ${pkg} " ]]; then
                missing_deps+=("$pkg")
            fi
        fi
    done
    
    # 如果没有缺失的依赖，直接返回
    if [ ${#missing_deps[@]} -eq 0 ]; then
        log_info "✓ 所有依赖已满足"
        return 0
    fi
    
    # 有缺失的依赖，开始安装
    log_warn "发现缺少命令: ${missing_cmds[*]}"
    log_warn "需要安装包: ${missing_deps[*]}"
    
    # 检测包管理器并安装
    local pkg_manager=""
    local install_cmd=""
    local update_cmd=""
    
    if command -v apt-get &> /dev/null; then
        pkg_manager="apt-get"
        update_cmd="apt-get update -y"
        install_cmd="apt-get install -y"
    elif command -v yum &> /dev/null; then
        pkg_manager="yum"
        update_cmd="yum makecache -y"
        install_cmd="yum install -y"
    elif command -v dnf &> /dev/null; then
        pkg_manager="dnf"
        update_cmd="dnf makecache -y"
        install_cmd="dnf install -y"
    elif command -v apk &> /dev/null; then
        pkg_manager="apk"
        update_cmd="apk update"
        install_cmd="apk add"
    else
        log_error "无法自动安装依赖，支持的包管理器: apt-get, yum, dnf, apk"
        log_error "请手动安装: ${missing_deps[*]}"
        exit 1
    fi
    
    log_info "检测到包管理器: $pkg_manager"
    
    # 更新软件源（带重试机制）
    log_info "更新软件源..."
    local max_retries=3
    local retry_count=0
    local update_success=false
    
    while [ $retry_count -lt $max_retries ] && [ "$update_success" = false ]; do
        if eval "$update_cmd" &> /dev/null; then
            update_success=true
            log_info "✓ 软件源更新成功"
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                log_warn "软件源更新失败，$retry_count/$max_retries 次重试..."
                sleep 3
            fi
        fi
    done
    
    if [ "$update_success" = false ]; then
        log_warn "软件源更新失败，尝试直接安装依赖..."
    fi
    
    # 安装依赖（带重试机制）
    log_info "开始安装依赖: ${missing_deps[*]}"
    retry_count=0
    local install_success=false
    
    while [ $retry_count -lt $max_retries ] && [ "$install_success" = false ]; do
        if eval "$install_cmd ${missing_deps[*]}" &> /dev/null; then
            install_success=true
            log_info "✓ 依赖安装成功"
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                log_warn "依赖安装失败，$retry_count/$max_retries 次重试..."
                sleep 3
            fi
        fi
    done
    
    if [ "$install_success" = false ]; then
        log_error "依赖安装失败，请手动安装: ${missing_deps[*]}"
        exit 1
    fi
    
    # 验证安装结果
    local still_missing=()
    for cmd in "${missing_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            still_missing+=("$cmd")
        fi
    done
    
    if [ ${#still_missing[@]} -ne 0 ]; then
        log_error "安装后仍然缺失命令: ${still_missing[*]}"
        log_error "请手动检查包名或安装"
        exit 1
    fi
    
    log_info "✓ 依赖检查完成"
}

# 检查架构
detect_architecture() {
    local ARCH=$(uname -m)
    case $ARCH in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armhf) echo "arm" ;;
        armv6l) echo "arm" ;;
        *) 
            log_error "不支持的架构: $ARCH"
            log_error "支持的架构: amd64, arm64, armv7l, armv6l"
            exit 1 
            ;;
    esac
}

# 检查是否以 root 权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 sudo 或以 root 用户运行此脚本"
        exit 1
    fi
}

# 检查端口占用
check_port_available() {
    local port=$1
    if command -v ss &> /dev/null && ss -tuln | grep -q ":$port "; then
        log_error "端口 $port 已被占用"
        ss -tuln | grep ":$port "
        return 1
    elif command -v netstat &> /dev/null && netstat -tuln | grep -q ":$port "; then
        log_error "端口 $port 已被占用"
        netstat -tuln | grep ":$port "
        return 1
    fi
    return 0
}

# 获取配置参数
get_config_params() {
    log_info "[2/8] 配置 FRP 服务端参数"
    
    # FRP 版本选择
    read -p "FRP 版本 (默认: $DEFAULT_FRP_VERSION): " FRP_VERSION
    FRP_VERSION=${FRP_VERSION:-$DEFAULT_FRP_VERSION}
    
    # 验证版本格式
    if ! [[ $FRP_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "版本号格式错误，应为 x.y.z 格式"
        exit 1
    fi
    
    # 绑定端口
    while true; do
        read -p "绑定端口 (bindPort, 默认: $DEFAULT_BIND_PORT): " BIND_PORT
        BIND_PORT=${BIND_PORT:-$DEFAULT_BIND_PORT}
        if [[ "$BIND_PORT" =~ ^[0-9]+$ ]] && [ "$BIND_PORT" -ge 1024 ] && [ "$BIND_PORT" -le 65535 ]; then
            if check_port_available "$BIND_PORT"; then
                break
            fi
        elif [[ "$BIND_PORT" -lt 1024 ]] && [[ "$BIND_PORT" -ge 1 ]]; then
            log_warn "使用 1-1023 端口需要 root 权限，确认继续？(y/N)"
            read -p "" confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                if check_port_available "$BIND_PORT"; then
                    break
                fi
            fi
        else
            log_error "端口号必须是 1-65535 之间的数字"
        fi
    done
    
    # 认证令牌
    while true; do
        read -p "认证令牌 (token, 必须与客户端一致): " TOKEN
        if [[ ${#TOKEN} -lt 8 ]]; then
            log_warn "建议令牌长度至少 8 位以确保安全"
            read -p "继续使用短令牌？(y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                continue
            fi
        fi
        if [[ -n "$TOKEN" ]]; then
            break
        else
            log_error "令牌不能为空"
        fi
    done
    
    # 仪表板端口
    while true; do
        read -p "仪表板端口 (dashboardPort, 默认: $DEFAULT_DASHBOARD_PORT): " DASHBOARD_PORT
        DASHBOARD_PORT=${DASHBOARD_PORT:-$DEFAULT_DASHBOARD_PORT}
        if [[ "$DASHBOARD_PORT" =~ ^[0-9]+$ ]] && [ "$DASHBOARD_PORT" -ge 1 ] && [ "$DASHBOARD_PORT" -le 65535 ] && [ "$DASHBOARD_PORT" -ne "$BIND_PORT" ]; then
            if check_port_available "$DASHBOARD_PORT"; then
                break
            fi
        else
            if [ "$DASHBOARD_PORT" -eq "$BIND_PORT" ]; then
                log_error "仪表板端口不能与绑定端口相同"
            else
                log_error "端口号必须是 1-65535 之间的数字"
            fi
        fi
    done
    
    # 仪表板用户名
    read -p "仪表板用户名 (dashboardUser, 默认: $DEFAULT_DASHBOARD_USER): " DASHBOARD_USER
    DASHBOARD_USER=${DASHBOARD_USER:-$DEFAULT_DASHBOARD_USER}
    
    # 仪表板密码
    while true; do
        read -s -p "仪表板密码 (dashboardPwd, 默认: $DEFAULT_DASHBOARD_PWD): " DASHBOARD_PWD
        echo
        DASHBOARD_PWD=${DASHBOARD_PWD:-$DEFAULT_DASHBOARD_PWD}
        
        if [[ ${#DASHBOARD_PWD} -lt 6 ]]; then
            log_warn "建议密码长度至少 6 位"
            read -p "继续使用？(y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                continue
            fi
        fi
        
        if [[ -n "$DASHBOARD_PWD" ]]; then
            break
        else
            log_error "密码不能为空"
        fi
    done
    
    # 心跳超时配置
    read -p "心跳超时时间 (秒, 默认: $DEFAULT_HEARTBEAT_TIMEOUT): " HEARTBEAT_TIMEOUT
    HEARTBEAT_TIMEOUT=${HEARTBEAT_TIMEOUT:-$DEFAULT_HEARTBEAT_TIMEOUT}
    
    # TCP Mux 保活间隔
    read -p "TCP Mux 保活间隔 (秒, 默认: $DEFAULT_TCP_MUX_KEEPALIVE): " TCP_MUX_KEEPALIVE
    TCP_MUX_KEEPALIVE=${TCP_MUX_KEEPALIVE:-$DEFAULT_TCP_MUX_KEEPALIVE}
    
    # 配置摘要
    echo ""
    log_info "配置摘要:"
    echo -e "FRP 版本: ${GREEN}$FRP_VERSION${NC}"
    echo -e "绑定端口: ${GREEN}$BIND_PORT${NC}"
    echo -e "认证令牌: ${GREEN}${TOKEN:0:4}****${NC}"
    echo -e "仪表板端口: ${GREEN}$DASHBOARD_PORT${NC}"
    echo -e "仪表板用户: ${GREEN}$DASHBOARD_USER${NC}"
    echo -e "仪表板密码: ${GREEN}${DASHBOARD_PWD:0:2}****${NC}"
    echo -e "心跳超时: ${GREEN}$HEARTBEAT_TIMEOUT 秒${NC}"
    echo -e "TCP Mux 保活: ${GREEN}$TCP_MUX_KEEPALIVE 秒${NC}"
    echo ""
    
    read -p "确认配置？(Y/n): " CONFIRM
    if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
        log_warn "安装已取消"
        exit 0
    fi
}

# 下载并安装 FRP
install_frp() {
    log_info "[3/8] 下载 FRP..."
    
    FRP_ARCH=$(detect_architecture)
    
    # 创建安装目录
    mkdir -p /opt/frp
    
    # 备份旧配置
    if [ -f "/opt/frp/frps.toml" ]; then
        local backup_file="/opt/frp/frps.toml.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "备份旧配置到 $backup_file"
        cp /opt/frp/frps.toml "$backup_file"
    fi
    
    # 停止旧服务
    if systemctl is-active --quiet frps 2>/dev/null; then
        log_info "停止旧服务..."
        systemctl stop frps
    fi
    
    # 清理旧版本
    if [ -d "/opt/frp/frp_${FRP_VERSION}_linux_${FRP_ARCH}" ]; then
        log_warn "发现相同版本已安装"
        read -p "重新安装？(y/N): " reinstall
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            log_info "跳过安装，使用现有版本"
            return 0
        fi
        rm -rf "/opt/frp/frp_${FRP_VERSION}_linux_${FRP_ARCH}"
    fi
    
    cd /opt/frp
    
    # 下载 FRP
    local max_retries=3
    local retry_count=0
    local download_url="https://github.com/fatedier/frp/releases/download/v$FRP_VERSION/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"
    
    while [ $retry_count -lt $max_retries ]; do
        if wget --timeout=30 --tries=3 -q "$download_url" -O "frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"; then
            log_info "下载成功"
            break
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                log_warn "下载失败，$retry_count/$max_retries 次重试..."
                sleep 3
            else
                log_error "下载失败，请检查:"
                log_error "- 网络连接"
                log_error "- 版本号: $FRP_VERSION 是否存在"
                log_error "- GitHub 访问"
                exit 1
            fi
        fi
    done
    
    # 验证下载文件
    if ! tar tzf "frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz" &>/dev/null; then
        log_error "下载文件损坏"
        exit 1
    fi
    
    log_info "[4/8] 解压文件..."
    tar -xzf "frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"
    
    # 创建符号链接
    ln -sfn "/opt/frp/frp_${FRP_VERSION}_linux_${FRP_ARCH}" /opt/frp/current
    
    cd "frp_${FRP_VERSION}_linux_${FRP_ARCH}"
    
    # 设置执行权限
    chmod +x frps
    
    # 清理下载包
    rm -f "../frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"
    
    log_info "✓ FRP 下载安装完成"
}

# 创建配置文件（优化版）
create_config() {
    log_info "[5/8] 配置系统服务..."
    
    local INSTALL_DIR="/opt/frp/current"
    
    # 创建优化的 TOML 配置文件
    cat > "/opt/frp/frps.toml" << TOML
# FRP 服务端配置文件
# 生成时间: $(date)
# FRP 版本: $FRP_VERSION

# 基础配置
bindPort = $BIND_PORT
auth.method = "token"
auth.token = "$TOKEN"

# 仪表板配置
webServer.addr = "0.0.0.0"
webServer.port = $DASHBOARD_PORT
webServer.user = "$DASHBOARD_USER"
webServer.password = "$DASHBOARD_PWD"

# 日志配置
log.to = "console"
log.level = "info"
log.maxDays = 3

# 性能优化
transport.tcpMux = true
transport.maxPoolCount = 5
transport.tcpMuxKeepaliveInterval = $TCP_MUX_KEEPALIVE

# 超时配置 - 增强稳定性
transport.heartbeatTimeout = $HEARTBEAT_TIMEOUT

# 连接限制（可选，根据实际情况调整）
# transport.maxPoolCount = 100  # 最大连接池数量
# transport.udpPacketSize = 4096  # UDP 包大小

# 其他优化配置
# server.addr = "0.0.0.0"  # 监听所有地址
# allowPorts = "10000-50000"  # 允许的端口范围（可选）

TOML
    
    # 创建优化的 systemd 服务文件
    cat > /etc/systemd/system/frps.service << SERVICE
[Unit]
Description=Frp Server Service
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=nobody
Group=nogroup
Restart=on-failure
RestartSec=10s
StartLimitBurst=3
StartLimitInterval=60s

# 执行命令
ExecStart=$INSTALL_DIR/frps -c /opt/frp/frps.toml
ExecReload=/bin/kill -HUP \$MAINPID
ExecStop=/bin/kill -SIGTERM \$MAINPID

# 工作目录
WorkingDirectory=/opt/frp

# 文件描述符限制
LimitNOFILE=1048576
LimitNPROC=512

# 内存限制（可选）
# MemoryLimit=512M

# CPU 限制（可选）
# CPUQuota=200%

# 安全设置
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
ReadWritePaths=/opt/frp

# 日志
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE

    log_info "✓ 系统服务配置完成"
}

# 配置防火墙（增强版）
configure_firewall() {
    log_info "[6/8] 配置防火墙..."
    
    local firewall_configured=false
    
    # 检查 ufw
    if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
        ufw allow "$BIND_PORT/tcp" comment "FRP Service Port"
        ufw allow "$DASHBOARD_PORT/tcp" comment "FRP Dashboard Port"
        log_info "✓ ufw 规则已添加"
        firewall_configured=true
    fi
    
    # 检查 firewalld
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port="$BIND_PORT/tcp"
        firewall-cmd --permanent --add-port="$DASHBOARD_PORT/tcp"
        firewall-cmd --reload
        log_info "✓ firewalld 规则已添加"
        firewall_configured=true
    fi
    
    # 检查 iptables
    if command -v iptables &> /dev/null && ! $firewall_configured; then
        log_warn "检测到 iptables 但未配置规则，建议手动添加："
        log_warn "iptables -A INPUT -p tcp --dport $BIND_PORT -j ACCEPT"
        log_warn "iptables -A INPUT -p tcp --dport $DASHBOARD_PORT -j ACCEPT"
        
        # 尝试自动添加 iptables 规则
        read -p "是否自动添加 iptables 规则？(y/N): " auto_iptables
        if [[ "$auto_iptables" =~ ^[Yy]$ ]]; then
            iptables -A INPUT -p tcp --dport "$BIND_PORT" -j ACCEPT
            iptables -A INPUT -p tcp --dport "$DASHBOARD_PORT" -j ACCEPT
            
            # 保存规则
            if command -v iptables-save &> /dev/null; then
                iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
            fi
            log_info "✓ iptables 规则已添加"
            firewall_configured=true
        fi
    fi
    
    if ! $firewall_configured; then
        log_warn "未检测到活动防火墙，请确保端口已开放: $BIND_PORT/tcp 和 $DASHBOARD_PORT/tcp"
    fi
}

# 启动服务（增强版）
start_service() {
    log_info "[7/8] 启动 FRP 服务..."
    
    # 重新加载 systemd
    systemctl daemon-reload
    
    # 启用服务
    systemctl enable frps
    
    # 启动服务
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if systemctl start frps; then
            sleep 3
            
            if systemctl is-active --quiet frps; then
                log_info "✓ FRP 服务端启动成功"
                
                # 检查端口监听
                if command -v ss &> /dev/null; then
                    if ss -tuln | grep -q ":$BIND_PORT"; then
                        log_info "✓ 服务端口监听正常"
                    else
                        log_warn "服务端口未监听，请检查日志"
                    fi
                    
                    if ss -tuln | grep -q ":$DASHBOARD_PORT"; then
                        log_info "✓ 仪表板端口监听正常"
                    else
                        log_warn "仪表板端口未监听，请检查日志"
                    fi
                fi
                
                return 0
            fi
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            log_warn "服务启动失败，$retry_count/$max_retries 次重试..."
            sleep 5
            systemctl reset-failed frps
        fi
    done
    
    log_error "服务启动失败"
    systemctl status frps --no-pager
    journalctl -u frps -n 50 --no-pager
    exit 1
}

# 性能优化检查
performance_check() {
    log_info "[8/8] 性能优化检查..."
    
    # 检查系统参数
    local sysctl_conf="/etc/sysctl.d/99-frp.conf"
    
    # 检查是否需要优化网络参数
    log_info "检查系统网络参数..."
    
    # 检查当前参数
    local current_tw_reuse=$(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null || echo "0")
    local current_tcp_fin_timeout=$(sysctl -n net.ipv4.tcp_fin_timeout 2>/dev/null || echo "60")
    
    if [ "$current_tw_reuse" != "1" ] || [ "$current_tcp_fin_timeout" -gt "30" ]; then
        log_warn "检测到网络参数可以优化以提高 FRP 性能"
        read -p "是否应用网络优化配置？(y/N): " optimize_network
        if [[ "$optimize_network" =~ ^[Yy]$ ]]; then
            cat > "$sysctl_conf" << SYSCTL
# FRP 网络优化配置
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 2048
SYSCTL
            
            sysctl -p "$sysctl_conf"
            log_info "✓ 网络参数已优化"
        fi
    fi
    
    log_info "✓ 性能检查完成"
}

# 显示安装结果（增强版）
show_result() {
    local server_ip=$(curl -s --max-time 5 ifconfig.me || curl -s --max-time 5 icanhazip.com || echo "无法获取")
    
    echo ""
    log_info "========================================"
    log_info "          FRP 服务端安装完成"
    log_info "========================================"
    echo ""
    log_info "=== 安装信息 ==="
    echo -e "版本: ${GREEN}$FRP_VERSION${NC}"
    echo -e "架构: ${GREEN}$FRP_ARCH${NC}"
    echo -e "安装目录: ${GREEN}/opt/frp/frp_${FRP_VERSION}_linux_${FRP_ARCH}${NC}"
    echo -e "配置文件: ${GREEN}/opt/frp/frps.toml${NC}"
    echo ""
    log_info "=== 连接信息 ==="
    echo -e "服务器 IP: ${GREEN}$server_ip${NC}"
    echo -e "服务端端口: ${GREEN}$BIND_PORT${NC}"
    echo -e "认证令牌: ${GREEN}${TOKEN:0:4}****${NC}"
    echo -e "仪表板地址: ${GREEN}http://$server_ip:$DASHBOARD_PORT${NC}"
    echo -e "仪表板用户: ${GREEN}$DASHBOARD_USER${NC}"
    echo -e "仪表板密码: ${GREEN}${DASHBOARD_PWD:0:2}****${NC}"
    echo ""
    log_info "=== 性能配置 ==="
    echo -e "心跳超时: ${GREEN}$HEARTBEAT_TIMEOUT 秒${NC}"
    echo -e "TCP Mux 保活: ${GREEN}$TCP_MUX_KEEPALIVE 秒${NC}"
    echo -e "TCP Mux: ${GREEN}已启用${NC}"
    echo ""
    log_info "=== 服务管理 ==="
    echo -e "启动服务: ${GREEN}systemctl start frps${NC}"
    echo -e "停止服务: ${GREEN}systemctl stop frps${NC}"
    echo -e "重启服务: ${GREEN}systemctl restart frps${NC}"
    echo -e "查看状态: ${GREEN}systemctl status frps${NC}"
    echo -e "查看日志: ${GREEN}journalctl -u frps -f${NC}"
    echo -e "重新加载: ${GREEN}systemctl reload frps${NC}  (热重载)"
    echo -e "查看实时流量: ${GREEN}ss -tuln | grep frps${NC}"
    echo ""
    log_info "=== 防火墙端口 ==="
    echo -e "已开放端口: ${GREEN}$BIND_PORT/tcp (服务端口)${NC}"
    echo -e "已开放端口: ${GREEN}$DASHBOARD_PORT/tcp (仪表板端口)${NC}"
    echo ""
    
    # 显示服务状态
    log_info "=== 服务状态 ==="
    systemctl status frps --no-pager 2>/dev/null || echo "服务状态不可用"
    
    # 显示测试命令
    echo ""
    log_info "=== 测试命令 ==="
    echo -e "测试连接: ${GREEN}curl -v http://$server_ip:$DASHBOARD_PORT${NC}"
    echo -e "测试服务: ${GREEN}telnet $server_ip $BIND_PORT${NC}"
    echo ""
    
    # 显示客户端配置示例
    log_info "=== 客户端配置示例 ==="
    cat << CLIENT
# frpc.toml 配置示例
serverAddr = "$server_ip"
serverPort = $BIND_PORT
auth.method = "token"
auth.token = "$TOKEN"

[[proxies]]
name = "test-tcp"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 6000
CLIENT
}

# 主安装函数
main() {
    # 处理帮助和版本参数
    if [[ $# -gt 0 ]]; then
        case $1 in
            -h|--help)
                echo "使用方法: $0 [选项]"
                echo "选项:"
                echo "  -d, --debug     启用调试模式"
                echo "  -h, --help      显示此帮助"
                echo "  -v, --version   显示版本信息"
                echo "  --auto          自动模式（使用默认配置）"
                exit 0
                ;;
            -v|--version)
                echo "版本: $SCRIPT_VERSION"
                exit 0
                ;;
            -d|--debug)
                DEBUG=true
                shift
                ;;
            --auto)
                AUTO_MODE=true
                # 自动模式下使用默认配置
                FRP_VERSION=$DEFAULT_FRP_VERSION
                BIND_PORT=$DEFAULT_BIND_PORT
                TOKEN=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
                DASHBOARD_PORT=$DEFAULT_DASHBOARD_PORT
                DASHBOARD_USER=$DEFAULT_DASHBOARD_USER
                DASHBOARD_PWD=$(openssl rand -base64 8 | tr -d "=+/" | cut -c1-8)
                HEARTBEAT_TIMEOUT=$DEFAULT_HEARTBEAT_TIMEOUT
                TCP_MUX_KEEPALIVE=$DEFAULT_TCP_MUX_KEEPALIVE
                shift
                ;;
        esac
    fi
    
    check_root
    check_dependencies
    
    if [[ "${AUTO_MODE:-false}" != "true" ]]; then
        get_config_params
    else
        log_info "自动模式：使用默认配置"
        log_info "自动生成令牌: $TOKEN"
    fi
    
    install_frp
    create_config
    configure_firewall
    start_service
    performance_check
    show_result
    
    log_info "安装完成！"
}

# 运行主函数
main "$@"
