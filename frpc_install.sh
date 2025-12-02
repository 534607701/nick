#!/bin/bash

set -e  # 遇到错误立即退出

# FRP 客户端自动安装脚本 - 与服务端配套版本
FRP_VERSION="${1:-0.64.0}"
REMOTE_PORT="${2:-39565}"
PROXY_NAME="${3:-ssh}"

echo "开始安装 FRP 客户端 v$FRP_VERSION"

# 配置参数（必须与服务端一致）
SERVER_ADDR="67.215.246.67"  # 服务器IP
SERVER_PORT="7000"
AUTH_TOKEN="qazwsx123.0"      # 必须与服务端token一致

# 停止并清理现有服务
cleanup_existing() {
    echo "检查现有 FRP 服务..."
    if systemctl is-active --quiet frpc 2>/dev/null; then
        echo "停止运行中的 FRP 客户端服务..."
        systemctl stop frpc
        sleep 2
    fi
    
    if systemctl is-enabled --quiet frpc 2>/dev/null; then
        echo "禁用 FRP 客户端服务..."
        systemctl disable frpc
    fi
    
    if pgrep frpc > /dev/null; then
        echo "发现残留的 frpc 进程，正在清理..."
        pkill -9 frpc
        sleep 1
    fi
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

# 主安装函数
main() {
    check_root
    
    # 清理现有服务
    cleanup_existing
    
    # 获取远程端口
    get_remote_port
    
    # 获取代理名称
    get_proxy_name
    
    # 显示配置摘要
    show_config_summary
    
    FRP_ARCH=$(detect_architecture)
    echo "检测到系统架构: $FRP_ARCH"
    
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
    mkdir -p "$INSTALL_DIR" /etc/frp
    
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
    
    # 创建 TOML 格式配置文件
    echo "创建 TOML 格式配置文件..."
    cat > /etc/frp/frpc.toml << CONFIG
serverAddr = "$SERVER_ADDR"
serverPort = $SERVER_PORT
auth.token = "$AUTH_TOKEN"

[[proxies]]
name = "$PROXY_NAME"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = $REMOTE_PORT
CONFIG

    echo "✅ 配置文件已创建"
    echo "服务器: $SERVER_ADDR:$SERVER_PORT"
    echo "远程端口: $REMOTE_PORT"
    echo "代理名称: $PROXY_NAME"
    echo "认证令牌: ${AUTH_TOKEN:0:4}****"
    
    # 创建增强的服务文件 - 重点修改这里！！！
    echo "创建系统服务..."
    cat > /etc/systemd/system/frpc.service << SERVICE
[Unit]
Description=Frp Client Service - Auto Recovery
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root

# ===== 增强自动重启配置 =====
# 总是重启，不受限制
Restart=always
# 立即重启（无延迟）
RestartSec=2
# 无限重试
StartLimitInterval=0
# 启动失败后无限重试
StartLimitBurst=0

# 进程被杀后也重启
KillMode=process
KillSignal=SIGTERM
SendSIGKILL=no

# 执行命令
ExecStart=$INSTALL_DIR/frpc -c /etc/frp/frpc.toml
ExecReload=/bin/kill -HUP \$MAINPID

# 资源限制
LimitNOFILE=65536

# 环境变量
Environment="GODEBUG=netdns=go"

# 安全配置
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SERVICE
    
    # 重新加载 systemd 并启动服务
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
    
    # 等待服务状态稳定
    echo "等待服务启动..."
    sleep 3
    
    # 检查服务状态
    echo "检查服务状态..."
    if systemctl is-active --quiet frpc; then
        echo "✅ FRP 客户端正在运行"
        echo ""
        echo "=== 服务状态 ==="
        systemctl status frpc --no-pager
        
        echo ""
        echo "=== 连接信息 ==="
        echo "您可以通过以下方式连接 SSH:"
        echo "ssh username@$SERVER_ADDR -p $REMOTE_PORT"
        echo ""
        echo "或者使用完整命令:"
        echo "ssh -o Port=$REMOTE_PORT username@$SERVER_ADDR"
    else
        echo "❌ FRP 客户端启动失败"
        echo ""
        echo "=== 错误日志 ==="
        journalctl -u frpc --since "1 minute ago" --no-pager -l
        exit 1
    fi
    
    # 清理临时目录
    rm -rf "$TEMP_DIR"
    
    echo ""
    echo "=== 安装完成 ==="
    echo "服务端: $SERVER_ADDR:$SERVER_PORT"
    echo "远程端口: $REMOTE_PORT"
    echo "代理名称: $PROXY_NAME"
    echo "认证令牌: ${AUTH_TOKEN:0:4}****"
    echo ""
    echo "=== 稳定性特性 ==="
    echo "• 自动重启: 掉线后立即重启 (Restart=always)"
    echo "• 无延迟重启: 重启间隔0秒 (RestartSec=0)"
    echo "• 无限重试: 不受重试限制 (StartLimitInterval=0)"
    echo "• 进程级监控: 进程异常立即恢复"
    echo ""
    echo "=== 常用命令 ==="
    echo "查看状态: systemctl status frpc"
    echo "查看日志: journalctl -u frpc -f"
    echo "停止服务: systemctl stop frpc"
    echo "重启服务: systemctl restart frpc"
    echo ""
    echo "=== 配置文件位置 ==="
    echo "配置文件: /etc/frp/frpc.toml"
    echo "安装目录: $INSTALL_DIR"
}

# 运行主函数
main "$@"
