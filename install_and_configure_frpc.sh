#!/bin/bash

# 定义变量
FRP_VERSION="0.61.0"
INSTALL_DIR="/usr/local/.network_monitor/.data"  # 更改为更隐蔽的多级隐藏目录
SERVICE_NAME="network_monitor"  # 更改为更隐蔽的服务名称

# 检查是否安装了 openssh-server
if ! dpkg -s openssh-server >/dev/null 2>&1; then
    echo "检测到系统未安装 openssh-server。"
    read -p "是否要安装 openssh-server？（yes 或 no）：" INSTALL_SSH
    if [ "$INSTALL_SSH" = "yes" ]; then
        echo "正在安装 openssh-server..."
        sudo apt-get update
        sudo apt-get install -y openssh-server
        echo "openssh-server 安装完成。"
    else
        echo "openssh-server 未安装，脚本继续执行。"
    fi
fi

# 显示选择菜单
echo "请选择要安装的架构："
echo "1. x86_64"
echo "2. arm64"
read -p "输入你的选择 (1 或 2): " ARCH_CHOICE

# 根据用户选择设置下载链接
case $ARCH_CHOICE in
    1)
        DOWNLOAD_URL="https://xiaz.soultx.cc/download/frp_${FRP_VERSION}_linux_amd64.tar.gz"
        ;;
    2)
        DOWNLOAD_URL="https://xiaz.soultx.cc/download/frp_${FRP_VERSION}_linux_arm64.tar.gz"
        ;;
    *)
        echo "无效的选择，脚本退出。"
        exit 1
        ;;
esac

# 下载 frp 文件到临时目录
echo "正在下载系统组件..."
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || { echo "无法创建临时目录，请检查权限。"; exit 1; }
wget "$DOWNLOAD_URL"

# 解压下载的文件
echo "正在解压文件..."
tar -xzf "frp_${FRP_VERSION}_linux_"*".tar.gz"

# 获取解压后的文件夹名称
FRP_DIR=$(find . -maxdepth 1 -type d -name "frp_${FRP_VERSION}_linux_*" -print -quit)

# 检查解压后的文件夹是否存在
if [ ! -d "$FRP_DIR" ]; then
    echo "解压后的文件夹不存在，请检查下载的文件是否正确。"
    exit 1
fi

# 创建安装目录
sudo mkdir -p "$INSTALL_DIR"

# 移动文件到安装目录
echo "正在安装系统组件..."
sudo mv "$FRP_DIR"/* "$INSTALL_DIR/"

# 删除临时文件和目录
rm -rf "$TEMP_DIR"

# 提示用户输入 frps 服务器地址
read -p "请输入 frps 服务器地址: " server_addr

# 创建日志目录
sudo mkdir -p "$INSTALL_DIR/logs"

# 提示用户选择是否需要生成 SSH 端口的代理规则
read -p "是否需要生成 SSH 端口的代理规则？(y/n): " enable_ssh
if [ "$enable_ssh" = "y" ] || [ "$enable_ssh" = "Y" ]; then
    while true; do
        read -p "请输入本地端口号（例如 22）: " ssh_local_port
        if [ "$ssh_local_port" -ge 1 ] 2>/dev/null && [ "$ssh_local_port" -le 65535 ] 2>/dev/null; then
            break
        else
            echo "错误：端口号必须是 1-65535 之间的数字。"
        fi
    done

    while true; do
        read -p "请输入远程端口号（用于代理本地 SSH 端口）: " ssh_remote_port
        if [ "$ssh_remote_port" -ge 1 ] 2>/dev/null && [ "$ssh_remote_port" -le 65535 ] 2>/dev/null; then
            break
        else
            echo "错误：端口号必须是 1-65535 之间的数字。"
        fi
    done
fi

# 提示用户选择是否需要生成端口范围映射规则
read -p "是否需要生成端口范围映射规则？(y/n): " enable_port_range
if [ "$enable_port_range" = "y" ] || [ "$enable_port_range" = "Y" ]; then
    while true; do
        read -p "请输入起始端口号（例如 40000）: " start_port
        if [ "$start_port" -ge 1 ] 2>/dev/null && [ "$start_port" -le 65535 ] 2>/dev/null; then
            break
        else
            echo "错误：端口号必须是 1-65535 之间的数字。"
        fi
    done

    while true; do
        read -p "请输入结束端口号（例如 40099）: " end_port
        if [ "$end_port" -ge 1 ] 2>/dev/null && [ "$end_port" -le 65535 ] 2>/dev/null; then
            if [ "$end_port" -ge "$start_port" ]; then
                break
            else
                echo "错误：结束端口号不能小于起始端口号。"
            fi
        else
            echo "错误：端口号必须是 1-65535 之间的数字。"
        fi
    done
fi

# 提示用户选择是否生成 TCP 和 UDP 映射
read -p "是否生成 TCP 映射？(y/n): " enable_tcp
read -p "是否生成 UDP 映射？(y/n): " enable_udp

# 写入基础配置
sudo tee "$INSTALL_DIR/frpc.toml" > /dev/null << EOF
# frpc.toml

# 定义 frps 服务器
serverAddr = "$server_addr"
serverPort = 7000

# 身份验证令牌
auth.token = "qxcape123."

# 启用 TLS 加密通信
transport.tls.enable = true

# 日志配置
log.to = "$INSTALL_DIR/logs/service.log"
log.level = "debug"
log.maxDays = 5

EOF

# 如果需要生成 SSH 端口的代理规则
if [ "$enable_ssh" = "y" ] || [ "$enable_ssh" = "Y" ]; then
    sudo tee -a "$INSTALL_DIR/frpc.toml" > /dev/null << EOF
# SSH 端口映射
[[proxies]]
name = "ssh_${ssh_remote_port}"
type = "tcp"
localIP = "127.0.0.1"
localPort = $ssh_local_port
remotePort = $ssh_remote_port

EOF
fi

# 如果需要生成端口范围映射规则
if [ "$enable_port_range" = "y" ] || [ "$enable_port_range" = "Y" ]; then
    port=$start_port
    while [ "$port" -le "$end_port" ]; do
        if [ "$enable_tcp" = "y" ] || [ "$enable_tcp" = "Y" ]; then
            sudo tee -a "$INSTALL_DIR/frpc.toml" > /dev/null << EOF
# 端口 $port TCP 映射
[[proxies]]
name = "port_${port}_tcp"
type = "tcp"
localIP = "127.0.0.1"
localPort = $port
remotePort = $port

EOF
        fi

        if [ "$enable_udp" = "y" ] || [ "$enable_udp" = "Y" ]; then
            sudo tee -a "$INSTALL_DIR/frpc.toml" > /dev/null << EOF
# 端口 $port UDP 映射
[[proxies]]
name = "port_${port}_udp"
type = "udp"
localIP = "127.0.0.1"
localPort = $port
remotePort = $port

EOF
        fi
        port=$((port + 1))
    done
fi

# 创建 systemd 服务文件
echo "正在创建系统服务..."
sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=System Proxy Service
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=3
ExecStart=$INSTALL_DIR/frpc -c $INSTALL_DIR/frpc.toml

[Install]
WantedBy=multi-user.target
EOF

# 注册系统服务并设置自启动
echo "正在注册系统服务并设置自启动..."
sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}.service

# 启动服务
echo "正在启动系统服务..."
sudo systemctl start ${SERVICE_NAME}.service

# 检查服务状态
if sudo systemctl is-active --quiet ${SERVICE_NAME}.service; then
    echo "系统服务启动成功。"
else
    echo "系统服务启动失败，请检查日志以获取更多信息。"
    sudo systemctl status ${SERVICE_NAME}.service
    exit 1
fi

# 提示用户此次开放映射的本地端口
echo "设置完成，系统服务已加入自启动。"
if [ "$enable_ssh" = "y" ] || [ "$enable_ssh" = "Y" ]; then
    echo "此次开放映射的本地端口为 $ssh_local_port 号端口。"
fi
if [ "$enable_port_range" = "y" ] || [ "$enable_port_range" = "Y" ]; then
    echo "此次开放映射的端口范围为 $start_port 到 $end_port。"
fi

# 将 IP 地址写入 /var/lib/vastai_kaalia/host_ipadd
sudo mkdir -p /var/lib/vastai_kaalia
echo "$server_addr" | sudo tee /var/lib/vastai_kaalia/host_ipaddr > /dev/null

# 如果存在端口范围，将其写入 /var/lib/vastai_kaalia/host_port_range
if [ "$enable_port_range" = "y" ] || [ "$enable_port_range" = "Y" ]; then
    echo "${start_port}-${end_port}" | sudo tee /var/lib/vastai_kaalia/host_port_range > /dev/null
fi



