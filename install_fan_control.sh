#!/bin/bash
# 一键安装智能风扇控制系统

set -e

echo "=========================================="
echo "超微服务器智能风扇控制系统 - 一键安装"
echo "=========================================="

# 1. 下载脚本
echo "[1/5] 下载脚本..."
sudo wget -O /usr/local/bin/fan_smart_control.sh https://raw.githubusercontent.com/534607701/nick/main/fan_smart_control.sh

# 2. 赋予执行权限
echo "[2/5] 设置执行权限..."
sudo chmod +x /usr/local/bin/fan_smart_control.sh

# 3. 检查并安装依赖
echo "[3/5] 检查依赖..."
if ! command -v ipmitool &> /dev/null; then
    echo "安装 ipmitool..."
    sudo apt update && sudo apt install -y ipmitool
fi

if ! command -v nvidia-smi &> /dev/null; then
    echo "⚠ 警告: nvidia-smi 未找到，请确保 NVIDIA 驱动已安装"
fi

# 4. 创建 systemd 服务
echo "[4/5] 创建 systemd 服务..."
sudo tee /etc/systemd/system/fan-control.service > /dev/null <<EOF
[Unit]
Description=Smart Fan Control for Supermicro Server
After=multi-user.target nvidia-persistenced.service
Wants=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/fan_smart_control.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 5. 启动服务
echo "[5/5] 启动服务..."
sudo systemctl daemon-reload
sudo systemctl enable fan-control
sudo systemctl restart fan-control

echo ""
echo "=========================================="
echo "✅ 安装完成！"
echo "=========================================="
echo ""
echo "查看状态: sudo systemctl status fan-control"
echo "查看日志: sudo journalctl -u fan-control -f"
echo "停止服务: sudo systemctl stop fan-control"
echo ""
echo "当前风扇转速:"
sleep 3
sudo ipmitool sdr type fan 2>/dev/null | grep -E "FAN[1-8]" || echo "等待 BMC 响应..."
