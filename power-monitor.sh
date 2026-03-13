#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}   功耗采集服务安装脚本 v2.0${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 交互式输入机器ID
while true; do
    echo -e "${YELLOW}请输入这台机器的ID (例如: 39206, 39305, 39565 等):${NC}"
    read -p "机器ID: " MACHINE_ID
    
    # 验证输入是否为数字
    if [[ "$MACHINE_ID" =~ ^[0-9]+$ ]]; then
        echo -e "${GREEN}✓ 机器ID: $MACHINE_ID${NC}"
        break
    else
        echo -e "${RED}✗ 机器ID必须是数字，请重新输入${NC}"
    fi
done

echo ""
echo -e "${YELLOW}请确认以下信息：${NC}"
echo -e "  服务器地址: ${GREEN}https://ruichuang.cloud${NC}"
echo -e "  机器ID:     ${GREEN}$MACHINE_ID${NC}"
echo ""
read -p "确认安装？(y/n): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo -e "${RED}安装已取消${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}开始安装...${NC}"

# 1. 创建目录
echo -e "${YELLOW}[1/4] 创建项目目录...${NC}"
mkdir -p /root/power-monitor
cd /root/power-monitor

# 2. 创建采集脚本
echo -e "${YELLOW}[2/4] 创建采集脚本...${NC}"
cat > power_collector.py << 'EOF'
#!/usr/bin/env python3
import subprocess
import json
import time
import urllib.request
import urllib.error
import socket
import os
import sys

# 从环境变量读取机器ID
MACHINE_ID = os.environ.get('MACHINE_ID', '')
SERVER_URL = "https://ruichuang.cloud/wp-json/my-devices/v1/power/update"

def get_gpu_power():
    """获取所有GPU功耗"""
    try:
        result = subprocess.run(
            ['nvidia-smi', '--query-gpu=index,power.draw,name,temperature.gpu,utilization.gpu', 
             '--format=csv,noheader,nounits'],
            capture_output=True, text=True
        )
        gpus = []
        if result.returncode == 0:
            for line in result.stdout.strip().split('\n'):
                if line.strip():
                    parts = [x.strip() for x in line.split(',')]
                    if len(parts) >= 5:
                        try:
                            gpus.append({
                                'index': parts[0],
                                'power': float(parts[1]) if parts[1] else 0,
                                'name': parts[2],
                                'temp': float(parts[3]) if parts[3] else 0,
                                'util': float(parts[4]) if parts[4] else 0
                            })
                        except:
                            continue
        return gpus
    except Exception as e:
        print(f"GPU读取错误: {e}")
        return []

def get_cpu_power():
    """获取CPU功耗"""
    try:
        # 尝试通过sensors获取
        result = subprocess.run(['sensors'], capture_output=True, text=True)
        for line in result.stdout.split('\n'):
            if 'power' in line.lower() and 'w' in line.lower():
                import re
                match = re.search(r'(\d+\.?\d*)\s*W', line, re.IGNORECASE)
                if match:
                    return float(match.group(1))
    except:
        pass
    
    # 默认返回95W（典型CPU TDP）
    return 95

def collect_data():
    """采集所有数据"""
    gpus = get_gpu_power()
    gpu_total = sum(g['power'] for g in gpus)
    cpu_power = get_cpu_power()
    other_power = 50  # 主板、内存、硬盘等估算
    
    total = gpu_total + cpu_power + other_power
    
    return {
        'machine_key': MACHINE_ID,
        'data': {
            'total_power': round(total, 2),
            'cpu_power': round(cpu_power, 2),
            'gpu_count': len(gpus),
            'gpus': gpus,
            'gpu_total': round(gpu_total, 2),
            'other_power': other_power,
            'timestamp': int(time.time()),
            'datetime': time.strftime('%Y-%m-%d %H:%M:%S')
        }
    }

def send_data():
    """发送数据到服务器"""
    try:
        data = collect_data()
        
        # 打印调试信息
        print(f"\n[{time.strftime('%H:%M:%S')}] 采集数据:")
        print(f"  GPU数量: {data['data']['gpu_count']}")
        print(f"  GPU总功耗: {data['data']['gpu_total']}W")
        print(f"  CPU功耗: {data['data']['cpu_power']}W")
        print(f"  总功耗: {data['data']['total_power']}W")
        
        # 转换为JSON
        json_data = json.dumps(data).encode('utf-8')
        
        # 发送请求
        req = urllib.request.Request(
            SERVER_URL,
            data=json_data,
            headers={'Content-Type': 'application/json'},
            method='POST'
        )
        
        with urllib.request.urlopen(req, timeout=10) as response:
            result = json.loads(response.read().decode('utf-8'))
            if result.get('success'):
                print(f"  ✅ 发送成功 - 机器ID: {result.get('machine_id')}")
            else:
                print(f"  ⚠️ 服务器返回: {result}")
            
    except urllib.error.URLError as e:
        print(f"  ❌ 网络错误: {e.reason}")
    except Exception as e:
        print(f"  ❌ 错误: {e}")

def main():
    """主函数"""
    if not MACHINE_ID:
        print("❌ 错误: 未设置机器ID")
        print("请设置环境变量 MACHINE_ID")
        sys.exit(1)
    
    print(f"\n{'='*50}")
    print(f"🚀 功耗采集服务启动")
    print(f"{'='*50}")
    print(f"📌 机器ID: {MACHINE_ID}")
    print(f"🌐 服务器: {SERVER_URL}")
    print(f"{'='*50}\n")
    
    # 测试一次
    send_data()
    
    # 循环采集
    while True:
        time.sleep(30)
        send_data()

if __name__ == "__main__":
    main()
EOF

# 设置执行权限
chmod +x power_collector.py

# 3. 创建系统服务
echo -e "${YELLOW}[3/4] 创建系统服务...${NC}"
cat > /etc/systemd/system/power-monitor.service << EOF
[Unit]
Description=Power Monitor Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/power-monitor
Environment="MACHINE_ID=$MACHINE_ID"
ExecStart=/usr/bin/python3 /root/power-monitor/power_collector.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 4. 启动服务
echo -e "${YELLOW}[4/4] 启动服务...${NC}"
systemctl daemon-reload
systemctl enable power-monitor.service > /dev/null 2>&1
systemctl restart power-monitor.service

# 等待2秒让服务启动
sleep 2

# 显示结果
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ 安装完成！${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查服务状态
if systemctl is-active --quiet power-monitor.service; then
    echo -e "${GREEN}✓ 服务状态: 运行中${NC}"
else
    echo -e "${RED}✗ 服务状态: 未运行${NC}"
fi

echo -e "📌 机器ID: ${GREEN}$MACHINE_ID${NC}"
echo -e "📁 脚本路径: ${YELLOW}/root/power-monitor/power_collector.py${NC}"
echo ""

# 显示最新日志
echo -e "${BLUE}最新日志:${NC}"
journalctl -u power-monitor.service -n 5 --no-pager

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}常用命令:${NC}"
echo -e "  查看状态: ${YELLOW}systemctl status power-monitor.service${NC}"
echo -e "  查看日志: ${YELLOW}journalctl -u power-monitor.service -f${NC}"
echo -e "  重启服务: ${YELLOW}systemctl restart power-monitor.service${NC}"
echo -e "  停止服务: ${YELLOW}systemctl stop power-monitor.service${NC}"
echo -e "${BLUE}========================================${NC}"
