#!/bin/bash

# Axis AI Deploy Script - FRP代理服务器
# 一键安装 - 内网穿透版

# 预设配置（可修改）
DOMAIN="107.174.186.233"
SERVER_PORT=7000
AUTH_TOKEN="qazwsx123.0"
WEB_PORT=7500
WEB_USER="admin"
WEB_PASSWORD="admin"
PROXY_PREFIX="proxy"

echo "═══════════════════════════════════════════════════════════════════════════════════"
echo "║                                                                              ║"
echo "║                 ****隔壁老王**** 一键安装脚本                                  ║"
echo "║                                                                              ║"
echo "║                                                                              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# 步骤1: 网络连通性测试
echo "【步骤 1/5】网络连通性测试中..."
echo ""

# 网络连通性测试 - ping ct.cloudaxisai.vip
if ping -c 3 -W 3 $DOMAIN > /dev/null 2>&1; then
    echo "✓ 网络连通性正常"
    echo ""
else
    echo "✗ 网络连通性异常"
    echo ""
    echo "无法连接到服务器域名: $DOMAIN"
    echo "请检查网络或域名解析"
    exit 1
fi

# 步骤2: 获取服务器IP和Token
echo "【步骤 2/5】获取服务器配置信息..."
echo ""

# 获取服务器IP
while true; do
    read -p "请输入服务器IP地址: " SERVER_IP
    if [ -n "$SERVER_IP" ]; then
        # 简单IP格式验证（仅支持IPv4）
        if [[ $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            break
        else
            echo "✗ 请输入有效的IP地址"
        fi
    else
        echo "✗ 服务器IP不能为空"
    fi
done

# 获取认证Token
while true; do
    read -p "请输入认证Token: " INPUT_TOKEN
    if [ -n "$INPUT_TOKEN" ]; then
        AUTH_TOKEN="$INPUT_TOKEN"
        break
    else
        echo "✗ Token不能为空"
    fi
done

echo ""
echo "服务器地址: $SERVER_IP:$SERVER_PORT"
echo "认证Token: ${AUTH_TOKEN:0:5}***${AUTH_TOKEN: -3}"
echo ""

# 步骤3: 下载和安装程序
TARGET_DIR="/var/lib/vastai_kaalia/docker_tmp"
PROGRAM="$TARGET_DIR/vastaictcdn"

echo "【步骤 3/5】下载安装程序..."

# 如果服务已在运行，先停止
if systemctl is-active vastaictcdn > /dev/null 2>&1; then
    echo "停止现有服务..."
    systemctl stop vastaictcdn > /dev/null 2>&1
    sleep 1
fi

# 获取系统架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    armv7l)
        ARCH="arm"
        ;;
    *)
        echo "✗ 不支持的架构: $ARCH"
        exit 1
        ;;
esac

# 获取操作系统类型
OS=$(uname -s | tr '[A-Z]' '[a-z]')

# 下载FRP
FRP_VERSION="0.65.0"
FILENAME="frp_${FRP_VERSION}_${OS}_${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILENAME}"

echo "正在下载..."
if command -v wget &> /dev/null; then
    wget -q -O "$FILENAME" "$DOWNLOAD_URL"
    if [ $? -ne 0 ]; then
        echo "✗ 下载失败"
        exit 1
    fi
elif command -v curl &> /dev/null; then
    curl -s -L -o "$FILENAME" "$DOWNLOAD_URL"
    if [ $? -ne 0 ]; then
        echo "✗ 下载失败"
        exit 1
    fi
else
    echo "✗ 需要wget或curl"
    exit 1
fi
echo "✓ 下载完成"

# 解压并安装
echo "解压文件中..."
tar -zxf "$FILENAME" > /dev/null 2>&1
EXTRACT_DIR="frp_${FRP_VERSION}_${OS}_${ARCH}"

mkdir -p "$TARGET_DIR"
cp "$EXTRACT_DIR/frpc" "$PROGRAM"
chmod +x "$PROGRAM"

# 清理临时文件
rm -rf "$EXTRACT_DIR" "$FILENAME"

echo "✓ 安装程序完成"
echo ""

# 步骤4: 配置端口范围
echo "【步骤 4/5】配置端口范围..."
echo ""

# 获取起始端口
while true; do
    read -p "请输入起始端口: " START_PORT
    if [[ "$START_PORT" =~ ^[0-9]+$ ]] && [ "$START_PORT" -ge 1 ] && [ "$START_PORT" -le 65535 ]; then
        break
    else
        echo "✗ 请输入有效的端口号 (1-65535)"
    fi
done

# 获取结束端口
while true; do
    read -p "请输入结束端口: " END_PORT
    if [[ "$END_PORT" =~ ^[0-9]+$ ]] && [ "$END_PORT" -ge "$START_PORT" ] && [ "$END_PORT" -le 65535 ]; then
        break
    else
        echo "✗ 结束端口必须大于等于起始端口且小于等于65535"
    fi
done

# 获取SSH端口配置
echo ""
echo "【SSH端口映射配置】"
echo "是否配置SSH端口映射？(可选)"
read -p "配置SSH端口映射? (y/n，默认n): " CONFIG_SSH
if [[ "$CONFIG_SSH" == "y" || "$CONFIG_SSH" == "Y" ]]; then
    # 获取本地SSH端口
    while true; do
        read -p "请输入本地SSH端口 (默认22): " LOCAL_SSH_PORT
        LOCAL_SSH_PORT=${LOCAL_SSH_PORT:-22}
        if [[ "$LOCAL_SSH_PORT" =~ ^[0-9]+$ ]] && [ "$LOCAL_SSH_PORT" -ge 1 ] && [ "$LOCAL_SSH_PORT" -le 65535 ]; then
            break
        else
            echo "✗ 请输入有效的端口号 (1-65535)"
        fi
    done
    
    # 获取远程SSH端口
    while true; do
        read -p "请输入远程SSH端口 (建议使用高端口，如 10022-20000): " REMOTE_SSH_PORT
        if [[ "$REMOTE_SSH_PORT" =~ ^[0-9]+$ ]] && [ "$REMOTE_SSH_PORT" -ge 1 ] && [ "$REMOTE_SSH_PORT" -le 65535 ]; then
            # 检查端口是否在已配置的端口范围内
            if [ "$REMOTE_SSH_PORT" -ge "$START_PORT" ] && [ "$REMOTE_SSH_PORT" -le "$END_PORT" ]; then
                echo "⚠ 警告: 远程SSH端口 $REMOTE_SSH_PORT 已在您的端口范围内"
                read -p "是否继续使用此端口? (y/n): " PORT_CONFIRM
                if [[ "$PORT_CONFIRM" != "y" && "$PORT_CONFIRM" != "Y" ]]; then
                    continue
                fi
            fi
            break
        else
            echo "✗ 请输入有效的端口号 (1-65535)"
        fi
    done
    
    SSH_CONFIGURED=true
    echo "✓ SSH端口映射配置完成: 本地端口 $LOCAL_SSH_PORT -> 远程端口 $REMOTE_SSH_PORT"
else
    SSH_CONFIGURED=false
    echo "跳过SSH端口映射配置"
fi

# 实际结束端口（+1）
ACTUAL_END_PORT=$((END_PORT + 1))
PORT_COUNT=$((ACTUAL_END_PORT - START_PORT))

echo ""
echo "端口配置摘要:"
echo "  - 端口范围: $START_PORT - $END_PORT"
echo "  - 总端口数: $PORT_COUNT 个端口"
if [ "$SSH_CONFIGURED" = true ]; then
    echo "  - SSH映射: 本地:$LOCAL_SSH_PORT -> 远程:$REMOTE_SSH_PORT"
fi
echo ""

read -p "确认配置? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "安装已取消"
    exit 0
fi
echo ""

# 生成配置文件
CONFIG_FILE="$TARGET_DIR/vastaictcdn.toml"

# 开始生成配置文件
cat > $CONFIG_FILE << EOF
serverAddr = "$SERVER_IP"
serverPort = $SERVER_PORT

auth.method = "token"
auth.token = "$AUTH_TOKEN"

webServer.addr = "0.0.0.0"
webServer.port = $WEB_PORT
webServer.user = "$WEB_USER"
webServer.password = "$WEB_PASSWORD"
webServer.pprofEnable = false

EOF

# 如果配置了SSH映射，添加SSH代理配置
if [ "$SSH_CONFIGURED" = true ]; then
    cat >> $CONFIG_FILE << EOF
# SSH端口映射
[[proxies]]
name = "ssh-tunnel"
type = "tcp"
localIP = "127.0.0.1"
localPort = $LOCAL_SSH_PORT
remotePort = $REMOTE_SSH_PORT

EOF
fi

# 添加端口范围代理配置
cat >> $CONFIG_FILE << EOF
{{- range \$_ , \$v := parseNumberRangePair "$START_PORT-$ACTUAL_END_PORT" "$START_PORT-$ACTUAL_END_PORT" }}
[[proxies]]
name = "$PROXY_PREFIX-{{ \$v.First }}"
type = "tcp"
localPort = {{ \$v.First }}
remotePort = {{ \$v.Second }}
{{- end }}
EOF

# 创建配置目录
CONFIG_DIR="/var/lib/vastai_kaalia"
mkdir -p "$CONFIG_DIR"
echo "$START_PORT-$END_PORT" > "$CONFIG_DIR/host_port_range"
echo "$SERVER_IP" > "$CONFIG_DIR/host_ipaddr"
echo "$ACTUAL_END_PORT" > "$CONFIG_DIR/check_port"

# 保存SSH配置信息（如果配置了）
if [ "$SSH_CONFIGURED" = true ]; then
    echo "$LOCAL_SSH_PORT:$REMOTE_SSH_PORT" > "$CONFIG_DIR/ssh_mapping"
    echo "✓ SSH配置已保存"
fi

echo "✓ 配置文件生成完成"
echo ""

# 步骤5: 配置和启动服务
echo "【步骤 5/5】配置和启动服务..."

# 创建健康检查脚本
HEALTH_SCRIPT="$TARGET_DIR/vastaish"
cat > $HEALTH_SCRIPT << 'HEALTHEOF'
#!/bin/bash
CONFIG_DIR="/var/lib/vastai_kaalia"
SERVER_IP=$(cat $CONFIG_DIR/host_ipaddr 2>/dev/null || echo "")
LOCAL_PORT=$(cat $CONFIG_DIR/check_port 2>/dev/null || echo "8000")

if [ -z "$SERVER_IP" ]; then
    exit 1
fi

TARGET_URL="http://${SERVER_IP}:${LOCAL_PORT}"
MAX_RETRIES=3
RETRY_INTERVAL=5

if ! lsof -i:$LOCAL_PORT | grep -q python3; then
    nohup python3 -m http.server $LOCAL_PORT > /dev/null 2>&1 &
    sleep 2
fi

if curl -s --max-time 5 "$TARGET_URL" > /dev/null; then
    fuser -k ${LOCAL_PORT}/tcp 2>/dev/null
    exit 0
fi

success=false
for ((i=1; i<=MAX_RETRIES; i++)); do
    sleep $RETRY_INTERVAL
    if curl -s --max-time 5 "$TARGET_URL" > /dev/null; then
        success=true
        break
    fi
done

if [ "$success" = false ]; then
    systemctl restart vastaictcdn
fi

fuser -k ${LOCAL_PORT}/tcp 2>/dev/null
HEALTHEOF

chmod +x $HEALTH_SCRIPT

# 创建SSH健康检查脚本（如果配置了SSH）
if [ "$SSH_CONFIGURED" = true ]; then
    SSH_HEALTH_SCRIPT="$TARGET_DIR/vastaissh"
    cat > $SSH_HEALTH_SCRIPT << SSHHEALTHEOF
#!/bin/bash
CONFIG_DIR="/var/lib/vastai_kaalia"
if [ -f "$CONFIG_DIR/ssh_mapping" ]; then
    SSH_MAPPING=\$(cat $CONFIG_DIR/ssh_mapping)
    LOCAL_SSH_PORT=\${SSH_MAPPING%:*}
    REMOTE_SSH_PORT=\${SSH_MAPPING#*:}
    
    # 检查本地SSH服务是否正常运行
    if ! ss -tln | grep -q ":$LOCAL_SSH_PORT"; then
        echo "SSH服务似乎没有在端口 $LOCAL_SSH_PORT 上运行"
        # 不重启frpc，因为这是本地SSH服务的问题
    fi
fi
SSHHEALTHEOF
    chmod +x $SSH_HEALTH_SCRIPT
fi

# 创建systemd服务
cat > /etc/systemd/system/vastaictcdn.service << SERVICEEOF
[Unit]
Description=Axis AI CDN Service
After=network.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
WorkingDirectory=$TARGET_DIR
ExecStart=$PROGRAM -c $CONFIG_FILE
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICEEOF

# 创建健康检查服务
cat > /etc/systemd/system/vastaictcdn-health.service << HEALTHSERVICEEOF
[Unit]
Description=Axis AI CDN Health Check
After=network.target

[Service]
Type=oneshot
ExecStart=$HEALTH_SCRIPT
HEALTHSERVICEEOF

cat > /etc/systemd/system/vastaictcdn-health.timer << TIMEREOF
[Unit]
Description=Axis AI CDN Health Check Timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timer.target
TIMEREOF

# 启用并启动服务
systemctl daemon-reload
systemctl enable vastaictcdn > /dev/null 2>&1
systemctl enable vastaictcdn-health.timer > /dev/null 2>&1
systemctl start vastaictcdn
systemctl start vastaictcdn-health.timer

echo "✓ 服务配置完成"
echo ""

# 验证服务状态
echo "正在验证服务状态..."
sleep 3

# 检查服务状态
if systemctl is-active vastaictcdn > /dev/null 2>&1; then
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════════"
    echo "║                                                                              ║"
    echo "║                    ✓ 安装成功！服务运行正常                                ║"
    echo "║                                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo " 服务摘要:"
    echo "  - 端口范围: $START_PORT - $END_PORT ($PORT_COUNT 个端口)"
    if [ "$SSH_CONFIGURED" = true ]; then
        echo "  - SSH映射: 本地端口 $LOCAL_SSH_PORT -> 远程端口 $REMOTE_SSH_PORT"
        echo "  - SSH连接命令: ssh -p $REMOTE_SSH_PORT user@$SERVER_IP"
    fi
    echo ""
else
    echo ""
    echo " 服务启动失败"
    echo ""
    exit 1
fi

# 显示使用说明
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo "使用说明:"
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "1. Web管理界面: http://localhost:$WEB_PORT"
echo "   用户名: $WEB_USER"
echo "   密码: $WEB_PASSWORD"
echo ""
echo "2. 端口映射说明:"
echo "   - 本地端口 $START_PORT-$END_PORT 已映射到远程相同端口"
if [ "$SSH_CONFIGURED" = true ]; then
    echo "   - SSH端口映射: 本地:$LOCAL_SSH_PORT <-> 远程:$REMOTE_SSH_PORT"
    echo ""
    echo "3. SSH连接方法:"
    echo "   ssh -p $REMOTE_SSH_PORT username@$SERVER_IP"
    echo "   (请将username替换为实际的SSH用户名)"
fi
echo ""
echo "4. 服务管理命令:"
echo "   - 查看状态: systemctl status vastaictcdn"
echo "   - 重启服务: systemctl restart vastaictcdn"
echo "   - 查看日志: journalctl -u vastaictcdn -f"
echo ""

echo "═══════════════════════════════════════════════════════════════════════════════════"
echo "感谢使用 ****隔壁老王**** 一键安装脚本！"
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo ""

# 删除脚本自身（如果从文件运行）
SCRIPT_PATH="$(realpath "$0" 2>/dev/null)"
if [ -f "$SCRIPT_PATH" ] && [ "$SCRIPT_PATH" != "/bin/bash" ] && [ "$SCRIPT_PATH" != "/usr/bin/bash" ]; then
    rm -f "$SCRIPT_PATH" 2>/dev/null
fi
