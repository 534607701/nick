#!/bin/bash

set -euo pipefail  # 添加 -u 防止未定义变量，-o pipefail 管道错误传递
trap 'cleanup $?' EXIT ERR INT TERM  # 添加清理函数

# 版本和配置
readonly SCRIPT_VERSION="1.1.0"
readonly DEFAULT_FRP_VERSION="0.65.0"
readonly DEFAULT_BIND_PORT=7000
readonly DEFAULT_DASHBOARD_PORT=7500
readonly DEFAULT_DASHBOARD_USER="admin"
readonly DEFAULT_DASHBOARD_PWD="admin"

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
        # 清理临时文件
        rm -f /tmp/frp_*.tar.gz 2>/dev/null || true
    fi
}

# 检查依赖并自动安装
check_dependencies() {
    log_info "[1/7] 检查系统依赖..."
    local deps=("wget" "tar" "systemctl" "curl" "grep")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_warn "发现缺少依赖: ${missing_deps[*]}"
        if command -v apt-get &> /dev/null; then
            log_info "正在使用 apt-get 安装依赖..."
            apt-get update
            apt-get install -y "${missing_deps[@]}"
        elif command -v yum &> /dev/null; then
            log_info "正在使用 yum 安装依赖..."
            yum install -y "${missing_deps[@]}"
        elif command -v dnf &> /dev/null; then
            log_info "正在使用 dnf 安装依赖..."
            dnf install -y "${missing_deps[@]}"
        else
            log_error "无法自动安装依赖，请手动安装: ${missing_deps[*]}"
            exit 1
        fi
    fi
    
    # 检查系统版本（用于兼容性提示）
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        log_debug "系统: $PRETTY_NAME"
    fi
    
    log_info "✓ 依赖检查完成"
}

# 检查架构（增强版）
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
    if ss -tuln | grep -q ":$port "; then
        log_error "端口 $port 已被占用"
        ss -tuln | grep ":$port "
        return 1
    fi
    return 0
}

# 验证 IP 地址格式（用于后续增强）
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi
    return 1
}

# 获取配置参数（增强验证）
get_config_params() {
    log_info "[2/7] 配置 FRP 服务端参数"
    
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
    
    # 认证令牌 - 增强安全要求
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
    
    # 仪表板密码 - 增强安全要求
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
    
    # 配置摘要
    echo ""
    log_info "配置摘要:"
    echo -e "FRP 版本: ${GREEN}$FRP_VERSION${NC}"
    echo -e "绑定端口: ${GREEN}$BIND_PORT${NC}"
    echo -e "认证令牌: ${GREEN}${TOKEN:0:4}****${NC}"
    echo -e "仪表板端口: ${GREEN}$DASHBOARD_PORT${NC}"
    echo -e "仪表板用户: ${GREEN}$DASHBOARD_USER${NC}"
    echo -e "仪表板密码: ${GREEN}${DASHBOARD_PWD:0:2}****${NC}"
    echo ""
    
    read -p "确认配置？(Y/n): " CONFIRM
    if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
        log_warn "安装已取消"
        exit 0
    fi
}

# 下载并安装 FRP（增强版）
install_frp() {
    log_info "[3/7] 下载 FRP..."
    
    FRP_ARCH=$(detect_architecture)
    
    # 创建安装目录
    mkdir -p /opt/frp
    
    # 备份旧配置（如果存在）
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
    
    # 清理旧版本（保留配置）
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
    
    # 下载 FRP（带重试机制）
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
    
    log_info "[4/7] 解压文件..."
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

# 创建配置文件（同时支持命令行和配置文件）
create_config() {
    log_info "[5/7] 配置系统服务..."
    
    local INSTALL_DIR="/opt/frp/current"
    
    # 创建 TOML 配置文件（FRP 0.52.0+ 推荐使用）
    cat > "/opt/frp/frps.toml" << TOML
# FRP 服务端配置文件
# 生成时间: $(date)
# FRP 版本: $FRP_VERSION

# 基础配置
bindPort = $BIND_PORT
auth.method = "token"
auth.token = "$TOKEN"

# 仪表板配置
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

# 超时设置
transport.tcpMuxKeepaliveInterval = 30

# HTTP 代理设置（如果需要）
# vhostHTTPPort = 80
# vhostHTTPSPort = 443
TOML
    
    # 创建 systemd 服务文件（使用配置文件方式，更稳定）
    cat > /etc/systemd/system/frps.service << SERVICE
[Unit]
Description=Frp Server Service
After=network-online.target
Wants=network-online.target

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
    log_info "[6/7] 配置防火墙..."
    
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
    
    # 检查 iptables（作为备选）
    if command -v iptables &> /dev/null && ! $firewall_configured; then
        log_warn "检测到 iptables 但未配置规则，建议手动添加："
        log_warn "iptables -A INPUT -p tcp --dport $BIND_PORT -j ACCEPT"
        log_warn "iptables -A INPUT -p tcp --dport $DASHBOARD_PORT -j ACCEPT"
    fi
    
    if ! $firewall_configured; then
        log_warn "未检测到活动防火墙，请确保端口已开放: $BIND_PORT/tcp 和 $DASHBOARD_PORT/tcp"
    fi
}

# 启动服务（增强版）
start_service() {
    log_info "[7/7] 启动 FRP 服务..."
    
    # 重新加载 systemd
    systemctl daemon-reload
    
    # 启用服务
    systemctl enable frps
    
    # 启动服务（带重试）
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if systemctl start frps; then
            # 等待服务完全启动
            sleep 3
            
            # 检查服务状态
            if systemctl is-active --quiet frps; then
                log_info "✓ FRP 服务端启动成功"
                
                # 验证服务可访问性
                if ss -tuln | grep -q ":$BIND_PORT"; then
                    log_info "✓ 服务端口监听正常"
                else
                    log_warn "服务端口未监听，请检查日志"
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

# 显示安装结果
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
    log_info "=== 服务管理 ==="
    echo -e "启动服务: ${GREEN}systemctl start frps${NC}"
    echo -e "停止服务: ${GREEN}systemctl stop frps${NC}"
    echo -e "重启服务: ${GREEN}systemctl restart frps${NC}"
    echo -e "查看状态: ${GREEN}systemctl status frps${NC}"
    echo -e "查看日志: ${GREEN}journalctl -u frps -f${NC}"
    echo -e "重新加载: ${GREEN}systemctl reload frps${NC}  (热重载)"
    echo ""
    log_info "=== 防火墙端口 ==="
    echo -e "已开放端口: ${GREEN}$BIND_PORT/tcp (服务端口)${NC}"
    echo -e "已开放端口: ${GREEN}$DASHBOARD_PORT/tcp (仪表板端口)${NC}"
    echo ""
    
    # 显示服务状态
    log_info "=== 服务状态 ==="
    systemctl status frps --no-pager
    
    # 显示测试命令
    echo ""
    log_info "=== 测试命令 ==="
    echo -e "测试连接: ${GREEN}curl -v http://$server_ip:$DASHBOARD_PORT${NC}"
}

# 主安装函数
main() {
    # 显示帮助 - 先检查参数是否存在
    if [[ $# -gt 0 ]] && [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "使用方法: $0 [选项]"
        echo "选项:"
        echo "  -d, --debug     启用调试模式"
        echo "  -h, --help      显示此帮助"
        echo "  -v, --version   显示版本信息"
        exit 0
    fi
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--debug)
                DEBUG=true
                shift
                ;;
            -v|--version)
                echo "版本: $SCRIPT_VERSION"
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done
    
    check_root
    check_dependencies
    get_config_params
    install_frp
    create_config
    configure_firewall
    start_service
    show_result
    
    log_info "安装完成！"
}

# 运行主函数
main "$@"
