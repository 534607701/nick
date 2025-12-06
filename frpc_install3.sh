#!/bin/bash

set -e  # 遇到错误立即退出

# FRP 客户端自动安装脚本 - 增强稳定版 (兼容 0.64.0)
FRP_VERSION="${1:-0.64.0}"
REMOTE_PORT="${2:-39565}"
PROXY_NAME="${3:-ssh}"

echo "开始安装 FRP 客户端 v$FRP_VERSION - 增强稳定版"

# 配置参数（必须与服务端一致）
SERVER_ADDR="67.215.246.67"  # 服务器IP
SERVER_PORT="7000"
AUTH_TOKEN="qazwsx123.0"      # 必须与服务端token一致

# 停止并清理现有服务
cleanup_existing() {
    echo "检查现有 FRP 服务..."
    
    # 停止监控服务
    if systemctl is-active --quiet frpc-monitor.timer 2>/dev/null; then
        echo "停止 FRP 监控定时器..."
        systemctl stop frpc-monitor.timer
    fi
    
    if systemctl is-active --quiet frpc-monitor.service 2>/dev/null; then
        echo "停止 FRP 监控服务..."
        systemctl stop frpc-monitor.service
    fi
    
    # 停止主服务
    if systemctl is-active --quiet frpc 2>/dev/null; then
        echo "停止运行中的 FRP 客户端服务..."
        systemctl stop frpc
        sleep 2
    fi
    
    if systemctl is-enabled --quiet frpc 2>/dev/null; then
        echo "禁用 FRP 客户端服务..."
        systemctl disable frpc
    fi
    
    # 清理监控定时器
    if systemctl is-enabled --quiet frpc-monitor.timer 2>/dev/null; then
        echo "禁用 FRP 监控定时器..."
        systemctl disable frpc-monitor.timer
    fi
    
    # 清理进程
    if pgrep frpc > /dev/null; then
        echo "发现残留的 frpc 进程，正在清理..."
        pkill -9 frpc
        sleep 1
    fi
    
    # 清理遗留配置文件
    if [ -f "/etc/frp/frpc.toml" ]; then
        echo "备份旧配置文件..."
        cp /etc/frp/frpc.toml "/etc/frp/frpc.toml.backup.$(date +%s)"
    fi
    
    echo "现有服务清理完成"
}

# 获取远程端口参数
get_remote_port() {
    if [ -n "$REMOTE_PORT" ] && [ "$REMOTE_PORT" != "39565" ]; then
        if [[ "$REMOTE_PORT" =~ ^[0-9]+$ ]] && [ "$REMOTE_PORT" -ge 1 ] && [ "$REMOTE_PORT" -le 65535 ]; then
            echo "使用指定远程端口: $REMOTE_PORT"
            return 0
        else
            echo "错误: 端口号必须是 1-65535 之间的数字"
            exit 1
        fi
    fi
    
    while true; do
        read -p "请输入远程端口号 (默认: 39565): " INPUT_PORT
        INPUT_PORT=${INPUT_PORT:-39565}
        if [[ "$INPUT_PORT" =~ ^[0-9]+$ ]] && [ "$INPUT_PORT" -ge 1 ] && [ "$INPUT_PORT" -le 65535 ]; then
            REMOTE_PORT=$INPUT_PORT
            break
        else
            echo "错误: 端口号必须是 1-65535 之间的数字"
        fi
    done
}

# 获取代理名称参数
get_proxy_name() {
    if [ -n "$PROXY_NAME" ] && [ "$PROXY_NAME" != "ssh" ]; then
        if [[ "$PROXY_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo "使用指定代理名称: $PROXY_NAME"
            return 0
        else
            echo "错误: 代理名称只能包含字母、数字、下划线和连字符"
            exit 1
        fi
    fi
    
    while true; do
        read -p "请输入代理名称 (默认: ssh_$(hostname)): " INPUT_NAME
        INPUT_NAME=${INPUT_NAME:-"ssh_$(hostname)"}
        if [[ "$INPUT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            PROXY_NAME=$INPUT_NAME
            break
        else
            echo "错误: 代理名称只能包含字母、数字、下划线和连字符"
        fi
    done
}

# 显示配置摘要
show_config_summary() {
    echo ""
    echo "配置确认:"
    echo "服务器地址: $SERVER_ADDR"
    echo "服务器端口: $SERVER_PORT"
    echo "认证令牌: ${AUTH_TOKEN:0:4}****"
    echo "远程端口: $REMOTE_PORT"
    echo "代理名称: $PROXY_NAME"
    echo ""
    
    read -p "确认开始安装？(y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "安装已取消"
        exit 0
    fi
}

# 检查架构
detect_architecture() {
    local ARCH=$(uname -m)
    case $ARCH in
        "x86_64") echo "amd64" ;;
        "aarch64") echo "arm64" ;;
        "armv7l") echo "arm" ;;
        "armv6l") echo "arm" ;;
        *) echo "不支持的架构: $ARCH"; exit 1 ;;
    esac
}

# 检查是否以 root 权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "请使用 sudo 或以 root 用户运行此脚本"
        exit 1
    fi
}

# 清理旧的端口配置文件
cleanup_port_configs() {
    echo "清理旧端口配置..."
    
    # 查找并清理旧的端口配置文件
    if [ -f "/etc/frp/ports.conf" ]; then
        echo "备份并清理旧端口配置..."
        mv /etc/frp/ports.conf "/etc/frp/ports.conf.backup.$(date +%s)"
    fi
    
    # 清理主配置中的批量端口
    if [ -f "/etc/frp/frpc.toml" ]; then
        # 只保留SSH配置，移除其他端口配置
        grep -E "^(serverAddr|serverPort|auth.token|\[\[proxies\]\].*ssh_)" /etc/frp/frpc.toml > /tmp/frpc_simple.toml 2>/dev/null || true
        
        if [ -s /tmp/frpc_simple.toml ]; then
            mv /tmp/frpc_simple.toml /etc/frp/frpc.toml
            echo "已清理批量端口配置"
        fi
    fi
}

# 简单端口生成函数（仅生成配置，不合并）
generate_ports_simple() {
    echo ""
    echo "=== 端口配置生成器 ==="
    echo "注意：生成端口配置但不会自动启用"
    echo ""
    
    read -p "是否要生成批量端口配置？(y/N): " GEN_PORTS
    if [[ ! "$GEN_PORTS" =~ ^[Yy]$ ]]; then
        echo "跳过端口生成"
        return 0
    fi
    
    read -p "请输入起始端口 (默认: 16386): " user_start_port
    read -p "请输入生成端口数量 (默认: 10): " user_count
    
    # 设置默认值
    START_PORT=${user_start_port:-16386}
    COUNT=${user_count:-10}
    PORT_CONF_FILE="/etc/frp/ports.conf"
    
    # 验证输入
    if ! [[ "$START_PORT" =~ ^[0-9]+$ ]]; then
        echo "错误: 起始端口必须是数字!"
        return 1
    fi
    
    if ! [[ "$COUNT" =~ ^[0-9]+$ ]]; then
        echo "错误: 端口数量必须是数字!"
        return 1
    fi
    
    # 验证端口范围
    if [ "$START_PORT" -lt 1024 ] || [ "$START_PORT" -gt 65535 ]; then
        echo "错误: 起始端口必须在 1024-65535 范围内!"
        return 1
    fi
    
    END_PORT=$((START_PORT + COUNT - 1))
    if [ "$END_PORT" -gt 65535 ]; then
        echo "错误: 结束端口 $END_PORT 超出范围!"
        return 1
    fi
    
    echo ""
    echo "生成端口配置..."
    echo "起始端口: $START_PORT"
    echo "结束端口: $END_PORT"
    echo "生成数量: $COUNT"
    echo "输出文件: $PORT_CONF_FILE"
    echo ""
    
    read -p "确认生成？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消"
        return 0
    fi
    
    # 生成配置
    echo "# 批量端口配置" > "$PORT_CONF_FILE"
    echo "# 生成时间: $(date)" >> "$PORT_CONF_FILE"
    echo "# 起始端口: $START_PORT, 数量: $COUNT" >> "$PORT_CONF_FILE"
    echo "# 注意: 这些端口需要本地有服务监听才能正常工作" >> "$PORT_CONF_FILE"
    echo "" >> "$PORT_CONF_FILE"
    
    for ((i=0; i<COUNT; i++)); do
        PORT=$((START_PORT + i))
        
        cat >> "$PORT_CONF_FILE" << EOF
# 端口: $PORT
# [[proxies]]
# name = "port_${PORT}_tcp"
# type = "tcp"
# localIP = "127.0.0.1"
# localPort = $PORT
# remotePort = $PORT

EOF
    done
    
    echo "✅ 端口配置生成完成!"
    echo "文件: $PORT_CONF_FILE"
    echo ""
    echo "⚠️  注意: 这些端口配置已被注释，需要手动:"
    echo "1. 编辑 $PORT_CONF_FILE 取消需要的配置注释"
    echo "2. 将配置复制到 /etc/frp/frpc.toml"
    echo "3. 重启服务: systemctl restart frpc"
}

# 安装监控脚本
install_monitoring() {
    echo ""
    echo "=== 安装监控系统 ==="
    
    # 创建监控脚本目录
    mkdir -p /usr/local/bin
    
    # 创建监控脚本
    cat > /usr/local/bin/frpc-monitor.sh << 'MONITOR_SCRIPT'
#!/bin/bash
# FRP客户端监控脚本 - 简化版

SERVER_ADDR="67.215.246.67"
SERVER_PORT="7000"
LOG_FILE="/var/log/frpc-monitor.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

check_frpc() {
    # 检查进程
    if ! pgrep -f "frpc.*toml" > /dev/null; then
        log "ERROR: FRPC进程不存在"
        return 1
    fi
    
    # 检查服务状态
    if ! systemctl is-active --quiet frpc; then
        log "ERROR: FRPC服务未运行"
        return 1
    fi
    
    # 检查连接（简化版）
    if ! timeout 5 nc -z "$SERVER_ADDR" "$SERVER_PORT" 2>/dev/null; then
        log "WARNING: 无法连接到FRP服务器"
        return 2
    fi
    
    return 0
}

restart_frpc() {
    log "尝试重启FRPC服务..."
    
    # 停止服务
    systemctl stop frpc
    sleep 2
    
    # 确保进程停止
    pkill -9 frpc 2>/dev/null || true
    sleep 1
    
    # 启动服务
    systemctl start frpc
    sleep 5
    
    # 检查是否启动成功
    if systemctl is-active --quiet frpc; then
        log "FRPC重启成功"
        return 0
    else
        log "FRPC重启失败"
        return 1
    fi
}

main() {
    log "=== FRPC健康检查开始 ==="
    
    # 检查FRPC状态
    check_result=$(check_frpc)
    case $? in
        0)
            log "FRPC状态正常"
            ;;
        1)
            log "FRPC异常，尝试重启..."
            restart_frpc
            ;;
        2)
            log "服务器连接问题，但进程正常"
            ;;
        *)
            log "未知状态"
            ;;
    esac
    
    log "=== FRPC健康检查完成 ==="
    echo "" >> "$LOG_FILE"
}

# 运行主函数
main "$@"
MONITOR_SCRIPT
    
    chmod +x /usr/local/bin/frpc-monitor.sh
    
    # 创建监控服务文件
    cat > /etc/systemd/system/frpc-monitor.service << 'MONITOR_SERVICE'
[Unit]
Description=FRPC健康检查服务
After=frpc.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/frpc-monitor.sh
User=root

[Install]
WantedBy=multi-user.target
MONITOR_SERVICE
    
    # 创建监控定时器
    cat > /etc/systemd/system/frpc-monitor.timer << 'MONITOR_TIMER'
[Unit]
Description=FRPC监控定时器

[Timer]
OnCalendar=*:0/10  # 每10分钟检查一次
Persistent=true

[Install]
WantedBy=timers.target
MONITOR_TIMER
    
    # 启用并启动监控定时器
    systemctl daemon-reload
    systemctl enable frpc-monitor.timer
    systemctl start frpc-monitor.timer
    
    echo "✅ 监控系统安装完成"
}

# 配置日志轮转
setup_logrotate() {
    echo ""
    echo "=== 配置日志轮转 ==="
    
    cat > /etc/logrotate.d/frpc << 'LOGROTATE'
/var/log/frpc*.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    create 644 root root
}
LOGROTATE
    
    echo "✅ 日志轮转配置完成"
}

# 安装简化版FRP服务
install_simple_frpc_service() {
    echo ""
    echo "=== 安装FRP服务 ==="
    
    FRP_ARCH=$(detect_architecture)
    INSTALL_DIR="/opt/frp/frp_${FRP_VERSION}_linux_${FRP_ARCH}"
    
    cat > /etc/systemd/system/frpc.service << 'SIMPLE_SERVICE'
[Unit]
Description=Frp Client Service
After=network.target

[Service]
Type=simple
User=root
Restart=always
RestartSec=10
StartLimitInterval=0
StartLimitBurst=0

ExecStart=/opt/frp/frp_0.64.0_linux_amd64/frpc -c /etc/frp/frpc.toml
ExecReload=/bin/kill -HUP $MAINPID

# 资源限制
LimitNOFILE=65536

# 安全配置
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SIMPLE_SERVICE
    
    # 替换安装目录
    sed -i "s|/opt/frp/frp_0.64.0_linux_amd64|$INSTALL_DIR|g" /etc/systemd/system/frpc.service
    
    systemctl daemon-reload
    echo "✅ FRP服务配置完成"
}

# 创建兼容0.64.0的配置文件
create_compatible_config() {
    echo "创建兼容FRP 0.64.0的配置文件..."
    
    cat > /etc/frp/frpc.toml << CONFIG
# FRP 客户端配置 - FRP v0.64.0
# 生成时间: $(date)
# 主机名: $(hostname)

serverAddr = "$SERVER_ADDR"
serverPort = $SERVER_PORT
auth.token = "$AUTH_TOKEN"

# SSH 连接
[[proxies]]
name = "$PROXY_NAME"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = $REMOTE_PORT
CONFIG
    
    echo "✅ 配置文件已创建"
}

# 显示安装总结
show_installation_summary() {
    echo ""
    echo "================================================"
    echo "✅ FRP客户端安装完成！"
    echo "================================================"
    echo ""
    echo "=== 核心配置 ==="
    echo "服务器地址: $SERVER_ADDR:$SERVER_PORT"
    echo "远程端口: $REMOTE_PORT"
    echo "代理名称: $PROXY_NAME"
    echo "认证令牌: ${AUTH_TOKEN:0:4}****"
    echo ""
    
    echo "=== 服务状态 ==="
    systemctl status frpc --no-pager | grep -A 2 "Active:"
    echo ""
    
    echo "=== 文件位置 ==="
    echo "主配置文件: /etc/frp/frpc.toml"
    echo "安装目录: /opt/frp/frp_${FRP_VERSION}_linux_${FRP_ARCH}"
    echo "监控脚本: /usr/local/bin/frpc-monitor.sh"
    echo ""
    
    echo "=== 测试连接 ==="
    echo "SSH连接命令:"
    echo "  ssh username@$SERVER_ADDR -p $REMOTE_PORT"
    echo ""
    echo "端口测试:"
    echo "  nc -zv $SERVER_ADDR $REMOTE_PORT"
    echo ""
    
    echo "=== 常用命令 ==="
    echo "查看状态: systemctl status frpc"
    echo "查看日志: journalctl -u frpc -f"
    echo "重启服务: systemctl restart frpc"
    echo "停止服务: systemctl stop frpc"
    echo ""
    
    echo "=== 监控系统 ==="
    echo "监控每10分钟运行一次"
    echo "查看监控日志: tail -f /var/log/frpc-monitor.log"
    echo "================================================"
}

# 主安装函数
main() {
    check_root
    
    echo "================================================"
    echo "FRP客户端安装程序 v0.64.0兼容版"
    echo "================================================"
    
    # 清理现有服务
    cleanup_existing
    
    # 获取配置参数
    get_remote_port
    get_proxy_name
    show_config_summary
    
    FRP_ARCH=$(detect_architecture)
    echo "检测到系统架构: $FRP_ARCH"
    
    # 清理旧端口配置
    cleanup_port_configs
    
    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # 下载 FRP
    echo "下载 FRP v$FRP_VERSION..."
    if ! wget -q "https://github.com/fatedier/frp/releases/download/v$FRP_VERSION/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz" -O frp.tar.gz; then
        echo "❌ FRP 下载失败，请检查网络连接和版本号"
        exit 1
    fi
    
    # 解压
    echo "解压文件..."
    tar -xzf frp.tar.gz
    cd "frp_${FRP_VERSION}_linux_${FRP_ARCH}"
    
    # 创建安装目录
    local INSTALL_DIR="/opt/frp/frp_${FRP_VERSION}_linux_${FRP_ARCH}"
    mkdir -p "$INSTALL_DIR" /etc/frp /var/log
    
    # 安装二进制文件
    echo "安装 FRP 到 $INSTALL_DIR..."
    cp frpc "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/frpc"
    
    # 测试二进制文件
    echo "测试 FRP 客户端..."
    if ! "$INSTALL_DIR/frpc" --version >/dev/null 2>&1; then
        echo "❌ FRP 客户端二进制文件测试失败"
        exit 1
    fi
    echo "✅ FRP 客户端二进制文件测试成功"
    
    # 创建配置文件
    create_compatible_config
    
    # 安装服务
    install_simple_frpc_service
    
    # 启动服务
    echo "启动 FRP 服务..."
    systemctl daemon-reload
    systemctl enable frpc
    
    if systemctl start frpc; then
        echo "✅ FRP 客户端服务启动成功"
    else
        echo "❌ FRP 客户端服务启动失败"
        journalctl -u frpc -n 20 --no-pager
        exit 1
    fi
    
    # 等待并检查服务状态
    sleep 3
    
    if systemctl is-active --quiet frpc; then
        echo "✅ FRP 客户端正在运行"
        
        # 简单连接测试
        echo "测试服务器连接..."
        if timeout 3 nc -z "$SERVER_ADDR" "$SERVER_PORT" 2>/dev/null; then
            echo "✅ 服务器连接正常"
        else
            echo "⚠️  服务器连接测试失败，但服务正在运行"
        fi
    else
        echo "❌ FRP 客户端启动失败"
        journalctl -u frpc --since "1 minute ago" --no-pager -l
        exit 1
    fi
    
    # 可选：生成端口配置（不自动启用）
    generate_ports_simple
    
    # 安装监控系统
    install_monitoring
    
    # 配置日志轮转
    setup_logrotate
    
    # 清理临时目录
    rm -rf "$TEMP_DIR"
    
    # 显示安装总结
    show_installation_summary
}

# 运行主函数
main "$@"
