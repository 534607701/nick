#!/bin/bash

set -e  # 遇到错误立即退出

# FRP 客户端自动安装脚本 - 与服务端配套版本
FRP_VERSION="${1:-0.64.0}"
REMOTE_PORT="${2:-39565}"
PROXY_NAME="${3:-ssh}"

echo "开始安装 FRP 客户端 v$FRP_VERSION"

# 配置参数（必须与服务端一致）
SERVER_ADDR="140.238.196.24"  # 服务器IP
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
    if [ -n "$REMOTE_PORT" ] && [ "$REMOTE_PORT" != "11111" ]; then
        if [[ "$REMOTE_PORT" =~ ^[0-9]+$ ]] && [ "$REMOTE_PORT" -ge 1 ] && [ "$REMOTE_PORT" -le 65535 ]; then
            echo "使用指定远程端口: $REMOTE_PORT"
            return 0
        else
            echo "错误: 端口号必须是 1-65535 之间的数字"
            exit 1
        fi
    fi
    
    while true; do
        read -p "请输入远程端口号 (默认: 11111): " INPUT_PORT
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

# 端口生成函数
generate_ports() {
    echo ""
    echo "=== 端口配置生成器 ==="
    echo "可选步骤: 为批量端口映射生成配置"
    echo ""
    
    read -p "是否要生成批量端口配置？(y/N): " GEN_PORTS
    if [[ ! "$GEN_PORTS" =~ ^[Yy]$ ]]; then
        echo "跳过端口生成"
        return 0
    fi
    
    read -p "请输入起始端口 (默认: 16386): " user_start_port
    read -p "请输入生成端口数量 (默认: 200): " user_count
    
    # 设置默认值（如果用户输入为空）
    START_PORT=${user_start_port:-16386}
    COUNT=${user_count:-200}
    PORT_CONF_FILE="/etc/frp/ports.conf"
    
    # 验证输入是否为数字
    if ! [[ "$START_PORT" =~ ^[0-9]+$ ]]; then
        echo "错误: 起始端口必须是数字!"
        exit 1
    fi
    
    if ! [[ "$COUNT" =~ ^[0-9]+$ ]]; then
        echo "错误: 端口数量必须是数字!"
        exit 1
    fi
    
    # 验证端口范围
    if [ "$START_PORT" -lt 1024 ] || [ "$START_PORT" -gt 65535 ]; then
        echo "错误: 起始端口必须在 1024-65535 范围内!"
        exit 1
    fi
    
    END_PORT=$((START_PORT + COUNT - 1))
    if [ "$COUNT" -lt 1 ] || [ "$END_PORT" -gt 65535 ]; then
        echo "错误: 端口数量无效或超出可用端口范围!"
        echo "起始端口: $START_PORT, 结束端口: $END_PORT, 最大端口: 65535"
        exit 1
    fi
    
    echo ""
    echo "开始生成端口配置..."
    echo "起始端口: $START_PORT"
    echo "结束端口: $END_PORT"
    echo "生成数量: $COUNT"
    echo "输出文件: $PORT_CONF_FILE"
    echo ""
    
    # 询问用户是否继续
    read -p "确认生成配置？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消端口生成"
        return 0
    fi
    
    # 清空或创建输出文件
    echo "# 自动生成的端口配置" > "$PORT_CONF_FILE"
    echo "# 生成时间: $(date)" >> "$PORT_CONF_FILE"
    echo "# 起始端口: $START_PORT, 数量: $COUNT" >> "$PORT_CONF_FILE"
    echo "" >> "$PORT_CONF_FILE"
    
    # 生成配置
    for ((i=0; i<COUNT; i++)); do
        PORT=$((START_PORT + i))
        
        cat >> "$PORT_CONF_FILE" << EOF
[[proxies]]
name = "port_${PORT}_tcp"
type = "tcp"
localIP = "127.0.0.1"
localPort = $PORT
remotePort = $PORT

EOF
        
        # 显示进度
        if (( (i + 1) % 50 == 0 )); then
            echo "已生成 $((i + 1))/$COUNT 个配置"
        fi
    done
    
    echo ""
    echo "✅ 端口配置生成完成!"
    echo "📁 文件: $PORT_CONF_FILE"
    echo "📊 大小: $(du -h "$PORT_CONF_FILE" | cut -f1)"
    echo "📈 行数: $(wc -l < "$PORT_CONF_FILE")"
    
    # 询问是否将端口配置合并到主配置文件
    read -p "是否将端口配置合并到主配置文件？(Y/n): " MERGE_CONFIRM
    MERGE_CONFIRM=${MERGE_CONFIRM:-Y}
    
    if [[ "$MERGE_CONFIRM" =~ ^[Yy]$ ]]; then
        echo "合并端口配置到主配置文件..."
        
        # 备份原配置文件
        cp /etc/frp/frpc.toml /etc/frp/frpc.toml.backup.$(date +%s)
        
        # 合并配置
        {
            echo "serverAddr = \"$SERVER_ADDR\""
            echo "serverPort = $SERVER_PORT"
            echo "auth.token = \"$AUTH_TOKEN\""
            echo ""
            echo "# SSH 主连接"
            echo "[[proxies]]"
            echo "name = \"$PROXY_NAME\""
            echo "type = \"tcp\""
            echo "localIP = \"127.0.0.1\""
            echo "localPort = 22"
            echo "remotePort = $REMOTE_PORT"
            echo ""
            echo "# 批量端口映射 (共 $COUNT 个)"
            cat "$PORT_CONF_FILE"
        } > /etc/frp/frpc.toml
        
        echo "✅ 端口配置已合并到 /etc/frp/frpc.toml"
    else
        echo "端口配置保存为独立文件: $PORT_CONF_FILE"
        echo "您可以手动将其内容添加到 /etc/frp/frpc.toml 文件中"
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
    
    # 创建增强的服务文件
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
# 重启延迟2秒
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
    
    # 生成端口配置
    generate_ports
    
    # 如果修改了配置文件，需要重启服务
    if [[ "$MERGE_CONFIRM" =~ ^[Yy]$ ]] 2>/dev/null; then
        echo ""
        echo "检测到配置文件已更新，正在重启 FRP 服务..."
        systemctl restart frpc
        sleep 2
        
        if systemctl is-active --quiet frpc; then
            echo "✅ FRP 服务重启成功"
        else
            echo "❌ FRP 服务重启失败"
            journalctl -u frpc -n 20 --no-pager
        fi
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
    echo "• 重启延迟: 2秒后重启 (RestartSec=2)"
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
    echo "主配置文件: /etc/frp/frpc.toml"
    echo "端口配置文件: /etc/frp/ports.conf"
    echo "安装目录: $INSTALL_DIR"
    echo ""
    
    if [ -f "/etc/frp/ports.conf" ]; then
        echo "=== 端口统计 ==="
        PORT_COUNT=$(grep -c "^\[\[proxies\]\]" /etc/frp/frpc.toml)
        echo "总代理数量: $PORT_COUNT (包括SSH)"
        echo "批量端口: $(grep -c "^\[\[proxies\]\]" /etc/frp/ports.conf)"
        echo ""
        echo "批量端口范围: $START_PORT - $END_PORT"
        echo "每个端口映射为: port_<端口号>_tcp"
    fi
}

# 运行主函数
main "$@"
