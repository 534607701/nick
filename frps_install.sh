#!/bin/bash

set -e  # 遇到错误立即退出

echo "========================================"
echo "          FRP 服务端自动安装脚本"
echo "========================================"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查依赖并自动安装
check_dependencies() {
    echo -e "${YELLOW}[1/7] 检查系统依赖...${NC}"
    local deps=("wget" "tar" "systemctl")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${YELLOW}发现缺少依赖: ${missing_deps[*]}${NC}"
        if command -v apt-get &> /dev/null; then
            echo "正在使用 apt-get 安装依赖..."
            apt-get update
            apt-get install -y "${missing_deps[@]}"
        elif command -v yum &> /dev/null; then
            echo "正在使用 yum 安装依赖..."
            yum install -y "${missing_deps[@]}"
        else
            echo -e "${RED}错误: 无法自动安装依赖，请手动安装: ${missing_deps[*]}${NC}"
            exit 1
        fi
    fi
    echo -e "${GREEN}✓ 依赖检查完成${NC}"
}

# 检查架构
detect_architecture() {
    local ARCH=$(uname -m)
    case $ARCH in
        "x86_64") echo "amd64" ;;
        "aarch64") echo "arm64" ;;
        "armv7l") echo "arm" ;;
        "armv6l") echo "arm" ;;
        *) 
            echo -e "${RED}错误: 不支持的架构: $ARCH${NC}"
            exit 1 
            ;;
    esac
}

# 检查是否以 root 权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 请使用 sudo 或以 root 用户运行此脚本${NC}"
        exit 1
    fi
}

# 获取配置参数
get_config_params() {
    echo -e "${YELLOW}[2/7] 配置 FRP 服务端参数${NC}"
    
    # 绑定端口
    while true; do
        read -p "绑定端口 (bindPort, 默认: 7000): " BIND_PORT
        BIND_PORT=${BIND_PORT:-7000}
        if [[ "$BIND_PORT" =~ ^[0-9]+$ ]] && [ "$BIND_PORT" -ge 1 ] && [ "$BIND_PORT" -le 65535 ]; then
            break
        else
            echo -e "${RED}错误: 端口号必须是 1-65535 之间的数字${NC}"
        fi
    done
    
    # 认证令牌 - 必须与客户端一致
    while true; do
        read -p "认证令牌 (token, 必须与客户端一致): " TOKEN
        if [[ -z "$TOKEN" ]]; then
            echo -e "${RED}错误: 令牌不能为空${NC}"
        else
            break
        fi
    done
    
    # 仪表板端口
    while true; do
        read -p "仪表板端口 (dashboardPort, 默认: 7500): " DASHBOARD_PORT
        DASHBOARD_PORT=${DASHBOARD_PORT:-7500}
        if [[ "$DASHBOARD_PORT" =~ ^[0-9]+$ ]] && [ "$DASHBOARD_PORT" -ge 1 ] && [ "$DASHBOARD_PORT" -le 65535 ] && [ "$DASHBOARD_PORT" -ne "$BIND_PORT" ]; then
            break
        else
            if [ "$DASHBOARD_PORT" -eq "$BIND_PORT" ]; then
                echo -e "${RED}错误: 仪表板端口不能与绑定端口相同${NC}"
            else
                echo -e "${RED}错误: 端口号必须是 1-65535 之间的数字${NC}"
            fi
        fi
    done
    
    # 仪表板用户名
    read -p "仪表板用户名 (dashboardUser, 默认: admin): " DASHBOARD_USER
    DASHBOARD_USER=${DASHBOARD_USER:-admin}
    
    # 仪表板密码
    while true; do
        read -p "仪表板密码 (dashboardPwd, 默认: admin): " DASHBOARD_PWD
        DASHBOARD_PWD=${DASHBOARD_PWD:-admin}
        if [[ -n "$DASHBOARD_PWD" ]]; then
            break
        else
            echo -e "${RED}错误: 密码不能为空${NC}"
        fi
    done
    
    echo ""
    echo -e "${GREEN}配置摘要:${NC}"
    echo -e "绑定端口: ${GREEN}$BIND_PORT${NC}"
    echo -e "认证令牌: ${GREEN}${TOKEN:0:4}****${NC}"
    echo -e "仪表板端口: ${GREEN}$DASHBOARD_PORT${NC}"
    echo -e "仪表板用户: ${GREEN}$DASHBOARD_USER${NC}"
    echo -e "仪表板密码: ${GREEN}${DASHBOARD_PWD:0:2}****${NC}"
    echo ""
    
    read -p "确认配置？(y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}安装已取消${NC}"
        exit 0
    fi
}

# 下载并安装 FRP
install_frp() {
    echo -e "${YELLOW}[3/7] 下载 FRP...${NC}"
    
    FRP_VERSION="0.65.0"  # 修改为 0.65.0
    FRP_ARCH=$(detect_architecture)
    
    # 创建安装目录
    mkdir -p /opt/frp
    cd /opt/frp
    
    # 清理旧安装
    if [ -d "frp_${FRP_VERSION}_linux_${FRP_ARCH}" ]; then
        echo -e "${YELLOW}发现旧版本，清理中...${NC}"
        systemctl stop frps 2>/dev/null || true
        rm -rf "frp_${FRP_VERSION}_linux_${FRP_ARCH}"
    fi
    
    # 下载 FRP
    if ! wget -q "https://github.com/fatedier/frp/releases/download/v$FRP_VERSION/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz" -O frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz; then
        echo -e "${RED}错误: 下载失败，请检查版本号和网络连接${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}[4/7] 解压文件...${NC}"
    tar -xzf frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz
    cd frp_${FRP_VERSION}_linux_${FRP_ARCH}
    
    # 设置执行权限
    chmod +x frps
    
    # 清理下载包
    rm -f ../frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz
    
    echo -e "${GREEN}✓ FRP 下载安装完成${NC}"
}

# 创建配置文件（使用命令行参数，不创建 TOML 文件）
create_config() {
    echo -e "${YELLOW}[5/7] 配置系统服务...${NC}"
    
    FRP_VERSION="0.65.0"  # 修改为 0.65.0
    FRP_ARCH=$(detect_architecture)
    INSTALL_DIR="/opt/frp/frp_${FRP_VERSION}_linux_${FRP_ARCH}"
    
    # 创建 systemd 服务文件（使用命令行参数）
    cat > /etc/systemd/system/frps.service << SERVICE
[Unit]
Description=Frp Server Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStart=$INSTALL_DIR/frps \\
  --bind-port $BIND_PORT \\
  --token "$TOKEN" \\
  --dashboard-port $DASHBOARD_PORT \\
  --dashboard-user "$DASHBOARD_USER" \\
  --dashboard-pwd "$DASHBOARD_PWD" \\
  --log-level info \\
  --log-max-days 3

WorkingDirectory=$INSTALL_DIR
LimitNOFILE=1048576

# 安全设置
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
SERVICE

    echo -e "${GREEN}✓ 系统服务配置完成${NC}"
}

# 配置防火墙
configure_firewall() {
    echo -e "${YELLOW}[6/7] 配置防火墙...${NC}"
    
    # 检查 ufw 是否可用
    if command -v ufw &> /dev/null; then
        ufw allow $BIND_PORT/tcp comment "FRP Service Port"
        ufw allow $DASHBOARD_PORT/tcp comment "FRP Dashboard Port"
        echo -e "${GREEN}✓ 防火墙规则已添加${NC}"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=$BIND_PORT/tcp
        firewall-cmd --permanent --add-port=$DASHBOARD_PORT/tcp
        firewall-cmd --reload
        echo -e "${GREEN}✓ 防火墙规则已添加 (firewalld)${NC}"
    else
        echo -e "${YELLOW}⚠ 未检测到 ufw 或 firewalld，请手动开放端口: $BIND_PORT/tcp 和 $DASHBOARD_PORT/tcp${NC}"
    fi
}

# 启动服务
start_service() {
    echo -e "${YELLOW}[7/7] 启动 FRP 服务...${NC}"
    
    # 重新加载 systemd
    systemctl daemon-reload
    
    # 启用并启动服务
    systemctl enable frps
    
    if systemctl start frps; then
        echo -e "${GREEN}✓ FRP 服务端启动成功${NC}"
        
        # 等待服务启动
        sleep 2
        
        # 检查服务状态
        if systemctl is-active --quiet frps; then
            echo -e "${GREEN}✓ 服务运行正常${NC}"
        else
            echo -e "${RED}❌ 服务启动后异常停止${NC}"
            journalctl -u frps -n 20 --no-pager
            exit 1
        fi
    else
        echo -e "${RED}❌ 服务启动失败${NC}"
        systemctl status frps --no-pager
        journalctl -u frps -n 20 --no-pager
        exit 1
    fi
}

# 显示安装结果
show_result() {
    FRP_VERSION="0.65.0"  # 修改为 0.65.0
    FRP_ARCH=$(detect_architecture)
    
    echo ""
    echo -e "${GREEN}========================================"
    echo "          FRP 服务端安装完成"
    echo -e "========================================${NC}"
    echo ""
    echo -e "${YELLOW}=== 安装信息 ===${NC}"
    echo -e "版本: ${GREEN}$FRP_VERSION${NC}"
    echo -e "架构: ${GREEN}$FRP_ARCH${NC}"
    echo -e "安装目录: ${GREEN}/opt/frp/frp_${FRP_VERSION}_linux_${FRP_ARCH}${NC}"
    echo ""
    echo -e "${YELLOW}=== 连接信息 ===${NC}"
    echo -e "服务端端口: ${GREEN}$BIND_PORT${NC}"
    echo -e "认证令牌: ${GREEN}${TOKEN:0:4}****${NC}"
    echo -e "仪表板地址: ${GREEN}http://服务器IP:$DASHBOARD_PORT${NC}"
    echo -e "仪表板用户: ${GREEN}$DASHBOARD_USER${NC}"
    echo -e "仪表板密码: ${GREEN}${DASHBOARD_PWD:0:2}****${NC}"
    echo ""
    echo -e "${YELLOW}=== 服务管理 ===${NC}"
    echo -e "启动服务: ${GREEN}systemctl start frps${NC}"
    echo -e "停止服务: ${GREEN}systemctl stop frps${NC}"
    echo -e "重启服务: ${GREEN}systemctl restart frps${NC}"
    echo -e "查看状态: ${GREEN}systemctl status frps${NC}"
    echo -e "查看日志: ${GREEN}journalctl -u frps -f${NC}"
    echo ""
    echo -e "${YELLOW}=== 防火墙端口 ===${NC}"
    echo -e "已开放端口: ${GREEN}$BIND_PORT/tcp (服务端口)${NC}"
    echo -e "已开放端口: ${GREEN}$DASHBOARD_PORT/tcp (仪表板端口)${NC}"
    echo ""
    
    # 显示服务状态
    echo -e "${YELLOW}=== 服务状态 ===${NC}"
    systemctl status frps --no-pager
}

# 主安装函数
main() {
    check_root
    check_dependencies
    get_config_params
    install_frp
    create_config
    configure_firewall
    start_service
    show_result
}

# 运行主函数
main "$@"
