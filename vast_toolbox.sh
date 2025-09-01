#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 打印带颜色的信息
print_info() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# 安装frp
install_frp() {
    print_info "开始安装frp..."
    wget https://xiaz.soultx.cc/download/install_and_configure_frpc.sh
    chmod +x install_and_configure_frpc.sh
    sudo ./install_and_configure_frpc.sh
    rm install_and_configure_frpc.sh
}

# 卸载frp
uninstall_frp() {
    print_info "开始卸载frp..."
    wget https://xiaz.soultx.cc/download/uninstall_network_monitor.sh
    chmod +x uninstall_network_monitor.sh
    sudo ./uninstall_network_monitor.sh
    rm uninstall_network_monitor.sh
}

# 更新测速软件
update_speedtest() {
    print_info "开始更新测速软件..."
    sudo apt-get install curl -y
    sudo curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
    sudo apt-get install speedtest -y
    sudo apt install python3 -y
    cd /var/lib/vastai_kaalia/latest
    sudo mv speedtest-cli speedtest-cli.old
    sudo wget -O speedtest-cli https://raw.githubusercontent.com/jjziets/vasttools/main/speedtest-cli.py
    sudo chmod +x speedtest-cli
}

# 强制测速
force_speedtest() {
    print_info "开始强制测速..."
    cd /var/lib/vastai_kaalia
    ./send_mach_info.py --speedtest
}

# 安装vastai
install_vastai() {
    print_info "开始安装vastai..."
    sudo apt install python3-pip
    pip install --upgrade vastai
}

# 设置vastai API key
set_vastai_key() {
    print_info "设置vastai API key..."
    read -p "请输入vastai API key: " api_key
    vastai set api-key "$api_key"
}

# 搜索机器
search_machine() {
    print_info "搜索机器..."
    read -p "请输入machine_id: " machine_id
    vastai search offers "machine_id=$machine_id verified=any"
}

# 创建测试机器
create_test_machine() {
    print_info "创建测试机器..."
    read -p "请输入offer ID: " offer_id
    vastai create instance "$offer_id" --image pytorch/pytorch:latest --jupyter --direct --env '-e TZ=PDT -p 22:22 -p 8080:8080'
}

# 禁用自动更新
disable_auto_update() {
    print_info "禁用自动更新..."
    sudo apt purge --auto-remove unattended-upgrades -y
    sudo systemctl disable apt-daily-upgrade.timer
    sudo systemctl mask apt-daily-upgrade.service
    sudo systemctl disable apt-daily.timer
    sudo systemctl mask apt-daily.service
}

# 安装vast服务
install_vast_service() {
    print_info "安装vast服务..."
    wget https://console.vast.ai/install -O install
    sudo python3 install 90abb9d65bdd3669f603d65af4b01cb30dbe99ba9bee06b6caa08dce6adfee8c
    history -d $((HISTCMD-1))
}

# 修复NVML错误
fix_nvml() {
    print_info "修复NVML错误..."
    sudo wget https://raw.githubusercontent.com/jjziets/vasttools/main/nvml_fix.py
    sudo python3 nvml_fix.py
    sudo reboot
}

# 设置端口和IP
set_port_ip() {
    print_info "设置端口和IP..."
    read -p "请输入端口范围(例如: 40180-40259): " port_range
    read -p "请输入公共IP: " public_ip
    sudo bash -c "echo \"$port_range\" > /var/lib/vastai_kaalia/host_port_range"
    sudo bash -c "echo \"$public_ip\" > /var/lib/vastai_kaalia/host_ipaddr"
}

# 安装显卡驱动
install_nvidia_driver() {
    print_info "安装显卡驱动..."
    read -p "请输入驱动版本(例如: 560): " driver_version
    
    # 安装必要的依赖
    print_info "安装必要的依赖..."
    sudo apt install build-essential -y
    
    # 添加NVIDIA驱动源
    print_info "添加NVIDIA驱动源..."
    sudo add-apt-repository ppa:graphics-drivers/ppa -y
    
    # 更新软件包列表
    print_info "更新软件包列表..."
    sudo apt update
    
    # 显示可用的驱动版本
    print_info "可用的驱动版本："
    sudo apt search nvidia-driver | grep nvidia-driver | sort -r
    
    # 安装指定版本的驱动
    print_info "开始安装NVIDIA驱动 $driver_version..."
    sudo apt install "nvidia-driver-$driver_version" -y
    
    print_info "驱动安装完成！"
    print_warn "请重启系统以使驱动生效。"
}

# 更换Ubuntu源
change_ubuntu_source() {
    print_info "开始更换Ubuntu源为阿里云源..."
    
    # 备份原有源文件
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup
    
    # 获取Ubuntu版本代号
    ubuntu_codename=$(lsb_release -cs)
    
    # 创建新的源文件
    sudo bash -c "cat > /etc/apt/sources.list << 'EOL'
deb http://mirrors.aliyun.com/ubuntu/ ${ubuntu_codename} main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ ${ubuntu_codename}-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ ${ubuntu_codename}-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ ${ubuntu_codename}-proposed main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ ${ubuntu_codename}-backports main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ ${ubuntu_codename} main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ ${ubuntu_codename}-security main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ ${ubuntu_codename}-updates main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ ${ubuntu_codename}-proposed main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ ${ubuntu_codename}-backports main restricted universe multiverse
EOL"
    
    # 更新软件包列表
    print_info "更新软件包列表..."
    sudo apt update
    
    print_info "源更换完成！"
}

# 安装Crash
install_crash() {
    print_info "开始安装Crash..."
    export url='https://fastly.jsdelivr.net/gh/juewuy/ShellCrash@master'
    wget -q --no-check-certificate -O /tmp/install.sh $url/install.sh
    bash /tmp/install.sh
    source /etc/profile &> /dev/null
    print_info "Crash安装完成！"
}

# 显示配置信息
show_config() {
    print_info "配置信息："
    echo -e "${YELLOW}vless://d3d2ce8d-e21d-4a33-8c9a-128bd11e4951@91.149.239.201:32094?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=www.amazon.com&pbk=l7JaeyRlElMvNv4vQckJc2UonD_3s7IOlOPcPJa-vlQ&fp=chrome#233boy-tcp-91.149.239.201${NC}"
    
    echo -e "\n${GREEN}IP配置信息：${NC}"
    echo -e "${YELLOW}1 - IP-CIDR,3.82.152.111/32,🎯 全球直连,no-resolve
2 - IP-CIDR,54.226.244.25/32,🎯 全球直连,no-resolve
3 - IP-CIDR,184.72.136.112/32,🎯 全球直连,no-resolve
4 - IP-CIDR,54.226.244.25/32,🎯 全球直连,no-resolve
5 - IP-CIDR,104.168.56.20/32,🎯 全球直连,no-resolve
6 - IP-CIDR,3.82.84.0/32,🎯 全球直连,no-resolve
7 - IP-CIDR,54.82.106.131/32,🎯 全球直连,no-resolve${NC}"
}

# 管理network_monitor服务
manage_network_monitor() {
    print_info "管理network_monitor服务..."
    echo -e "\n${GREEN}请选择操作：${NC}"
    echo "1. 查看服务状态"
    echo "2. 启动服务"
    echo "3. 停止服务"
    echo "4. 重启服务"
    echo "5. 查看服务日志"
    echo "0. 返回主菜单"
    
    read -p "请选择操作 (0-5): " service_choice
    
    case $service_choice in
        1)
            print_info "正在查看服务状态..."
            sudo systemctl status network_monitor
            ;;
        2)
            print_info "正在启动服务..."
            sudo systemctl start network_monitor
            ;;
        3)
            print_info "正在停止服务..."
            sudo systemctl stop network_monitor
            ;;
        4)
            print_info "正在重启服务..."
            sudo systemctl restart network_monitor
            ;;
        5)
            print_info "正在查看服务日志..."
            sudo journalctl -u network_monitor -n 50 --no-pager
            ;;
        0)
            return
            ;;
        *)
            print_error "无效的选择"
            ;;
    esac
}

# 格式化并挂载设备
format_and_mount_device() {
    print_info "开始格式化并挂载设备..."
    
    # 列出所有块设备
    print_info "正在扫描块设备..."
    BLOCK_DEVICES=$(lsblk -d -o NAME | grep -v NAME)
    if [ -z "$BLOCK_DEVICES" ]; then
        print_error "未找到任何块设备！"
        return 1
    fi
    
    # 显示可用的块设备
    print_info "找到以下块设备："
    echo "$BLOCK_DEVICES"
    
    # 提示用户选择一个设备
    read -p "请输入要格式化和挂载的设备名称（例如 sda、vdb、nvme0n1 等）：" DEVICE_NAME
    
    # 检查设备名称是否有效
    DEVICE="/dev/$DEVICE_NAME"
    if [ ! -e "$DEVICE" ]; then
        print_error "错误：设备 $DEVICE 不存在！"
        return 1
    fi
    
    # 格式化设备为 XFS
    print_info "正在格式化设备 $DEVICE 为 XFS 文件系统..."
    sudo mkfs.xfs -f "$DEVICE"
    if [ $? -ne 0 ]; then
        print_error "格式化失败！"
        return 1
    fi
    print_info "格式化完成！"
    
    # 创建挂载点
    print_info "正在创建挂载点 /var/lib/docker..."
    sudo mkdir -p /var/lib/docker
    if [ $? -ne 0 ]; then
        print_error "创建挂载点失败！"
        return 1
    fi
    print_info "挂载点创建完成！"
    
    # 挂载设备
    print_info "正在挂载设备 $DEVICE 到 /var/lib/docker..."
    sudo mount "$DEVICE" /var/lib/docker
    if [ $? -ne 0 ]; then
        print_error "挂载失败！"
        return 1
    fi
    print_info "挂载完成！"
    
    # 获取设备的 UUID
    UUID=$(sudo blkid -s UUID -o value "$DEVICE")
    if [ -z "$UUID" ]; then
        print_error "无法获取设备的 UUID！"
        return 1
    fi
    print_info "设备的 UUID 是：$UUID"
    
    # 提示用户是否写入 /etc/fstab
    print_info "是否将以下内容写入 /etc/fstab？"
    echo "UUID=$UUID /var/lib/docker xfs loop,rw,auto,pquota 0 0"
    read -p "请输入 y 确认，或 n 取消：" CONFIRM
    
    if [ "$CONFIRM" == "y" ]; then
        print_info "正在写入 /etc/fstab..."
        echo "UUID=$UUID /var/lib/docker xfs loop,rw,auto,pquota 0 0" | sudo tee -a /etc/fstab > /dev/null
        if [ $? -ne 0 ]; then
            print_error "写入 /etc/fstab 失败！"
            return 1
        fi
        print_info "写入完成！"
    else
        print_info "已取消写入 /etc/fstab。"
    fi
    
    print_info "脚本执行完毕！"
}

# 主菜单
show_menu() {
    echo -e "\n${GREEN}=== Vast.ai 工具箱 ===${NC}"
    echo "1. 安装frp"
    echo "2. 卸载frp"
    echo "3. 更新测速软件"
    echo "4. 强制测速"
    echo "5. 安装vastai"
    echo "6. 设置vastai API key"
    echo "7. 搜索机器"
    echo "8. 创建测试机器"
    echo "9. 禁用自动更新"
    echo "10. 安装vast服务"
    echo "11. 修复NVML错误"
    echo "12. 设置端口和IP"
    echo "13. 安装显卡驱动"
    echo "14. 更换Ubuntu源"
    echo "15. 安装Crash"
    echo "16. 显示配置信息"
    echo "17. 管理network_monitor服务"
    echo "18. 格式化并挂载设备"
    echo "0. 退出"
    echo -e "\n"
}

# 主循环
while true; do
    show_menu
    read -p "请选择操作 (0-18): " choice
    
    case $choice in
        1) install_frp ;;
        2) uninstall_frp ;;
        3) update_speedtest ;;
        4) force_speedtest ;;
        5) install_vastai ;;
        6) set_vastai_key ;;
        7) search_machine ;;
        8) create_test_machine ;;
        9) disable_auto_update ;;
        10) install_vast_service ;;
        11) fix_nvml ;;
        12) set_port_ip ;;
        13) install_nvidia_driver ;;
        14) change_ubuntu_source ;;
        15) install_crash ;;
        16) show_config ;;
        17) manage_network_monitor ;;
        18) format_and_mount_device ;;
        0) 
            print_info "感谢使用，再见！"
            exit 0
            ;;
        *) 
            print_error "无效的选择，请重试"
            ;;
    esac
    
    echo -e "\n按回车键继续..."
    read
done 