#!/bin/bash

set -e  # 遇到错误立即退出

# FRP 客户端完全卸载脚本（无确认，自动执行）
echo "开始卸载 FRP 客户端..."

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 显示颜色信息
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否以 root 权限运行，如果不是则自动使用 sudo
check_root() {
    if [[ $EUID -ne 0 ]]; then
        info "需要 root 权限，尝试使用 sudo..."
        # 重新使用 sudo 执行脚本
        exec sudo bash "$0" "$@"
        exit $?
    fi
}

# 停止并禁用服务
stop_service() {
    info "停止 FRP 客户端服务..."
    
    if systemctl is-active --quiet frpc 2>/dev/null; then
        systemctl stop frpc
        sleep 2
        info "FRP 服务已停止"
    else
        warn "FRP 服务未运行"
    fi
    
    if systemctl is-enabled --quiet frpc 2>/dev/null; then
        systemctl disable frpc
        info "FRP 服务已禁用"
    else
        warn "FRP 服务未启用"
    fi
}

# 清理进程
clean_processes() {
    info "清理 FRP 进程..."
    
    local count=0
    # 查找并杀死所有 frpc 进程
    while pgrep frpc > /dev/null; do
        pkill -9 frpc
        sleep 1
        count=$((count + 1))
        
        if [ $count -gt 3 ]; then
            warn "强制清理 frpc 进程..."
            pkill -9 frpc 2>/dev/null || true
            break
        fi
    done
    
    if [ $count -gt 0 ]; then
        info "清理了 $count 批 frpc 进程"
    else
        info "未找到运行的 frpc 进程"
    fi
}

# 删除服务文件
remove_service_file() {
    info "删除系统服务文件..."
    
    local service_files=(
        "/etc/systemd/system/frpc.service"
        "/lib/systemd/system/frpc.service"
        "/usr/lib/systemd/system/frpc.service"
    )
    
    for file in "${service_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            info "已删除: $file"
        fi
    done
    
    # 重新加载 systemd
    if systemctl daemon-reload; then
        info "systemd 配置已重新加载"
    fi
}

# 删除配置文件
remove_config_files() {
    info "删除配置文件..."
    
    local config_dirs=(
        "/etc/frp"
        "/usr/local/etc/frp"
        "$HOME/.frp"
    )
    
    for dir in "${config_dirs[@]}"; do
        if [ -d "$dir" ]; then
            rm -rf "$dir"
            info "已删除配置目录: $dir"
        fi
    done
    
    # 删除可能的配置文件备份
    local config_backups=(
        "/etc/frp.*.backup"
        "/etc/frp/frpc.toml.backup.*"
        "/etc/frp/ports.conf.backup.*"
    )
    
    for pattern in "${config_backups[@]}"; do
        if ls $pattern 2>/dev/null; then
            rm -f $pattern
            info "已删除备份文件: $pattern"
        fi
    done
}

# 删除二进制文件
remove_binaries() {
    info "删除 FRP 二进制文件..."
    
    # 查找可能的安装目录
    local install_dirs=(
        "/opt/frp"
        "/usr/local/frp"
        "/usr/local/bin/frpc"
        "/usr/bin/frpc"
        "/bin/frpc"
    )
    
    # 查找所有 frpc 文件
    info "搜索 FRP 安装文件..."
    find /opt /usr/local /usr/bin /bin -name "frpc" -type f 2>/dev/null | while read -r file; do
        info "发现文件: $file"
        rm -f "$file"
        info "已删除: $file"
    done
    
    # 删除安装目录
    for dir in "${install_dirs[@]}"; do
        if [ -d "$dir" ]; then
            rm -rf "$dir"
            info "已删除目录: $dir"
        fi
    done
}

# 清理日志文件
clean_logs() {
    info "清理日志文件..."
    
    local log_files=(
        "/var/log/frpc.log"
        "/var/log/frp.log"
        "/tmp/frpc.log"
        "/tmp/frp.log"
    )
    
    for file in "${log_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            info "已删除日志: $file"
        fi
    done
    
    # 清理 journal 日志
    if command -v journalctl >/dev/null 2>&1; then
        journalctl --vacuum-time=1s --unit=frpc 2>/dev/null || true
        info "已清理 systemd 日志"
    fi
}

# 清理临时文件
clean_temp_files() {
    info "清理临时文件..."
    
    # 清理临时目录中的 frp 文件
    find /tmp -name "frp*" -type d -maxdepth 1 2>/dev/null | while read -r dir; do
        rm -rf "$dir"
        info "已删除临时目录: $dir"
    done
    
    find /tmp -name "frp*.tar.gz" -type f 2>/dev/null | while read -r file; do
        rm -f "$file"
        info "已删除临时文件: $file"
    done
}

# 显示卸载摘要
show_uninstall_summary() {
    echo ""
    echo "========================================="
    echo "          FRP 客户端卸载完成"
    echo "========================================="
    echo ""
    echo "已清理的内容:"
    echo "✅ 停止并禁用系统服务"
    echo "✅ 清理所有运行进程"
    echo "✅ 删除服务配置文件"
    echo "✅ 删除 FRP 配置文件"
    echo "✅ 删除二进制文件和安装目录"
    echo "✅ 清理日志文件"
    echo "✅ 清理临时文件"
    echo ""
    echo "验证命令:"
    echo "• 检查服务状态: systemctl status frpc"
    echo "• 检查进程: pgrep frpc"
    echo "• 检查文件: ls -la /etc/frp/ 2>/dev/null || echo '配置目录不存在'"
    echo ""
    echo "如果需要重新安装，请运行安装脚本。"
    echo "========================================="
}

# 验证卸载
verify_uninstall() {
    info "验证卸载结果..."
    
    local verification_passed=true
    
    # 检查服务
    if systemctl is-active --quiet frpc 2>/dev/null; then
        error "❌ FRP 服务仍在运行"
        verification_passed=false
    else
        info "✅ FRP 服务已停止"
    fi
    
    # 检查进程
    if pgrep frpc >/dev/null; then
        error "❌ 发现 frpc 进程"
        verification_passed=false
    else
        info "✅ 无 frpc 进程运行"
    fi
    
    # 检查配置文件目录
    if [ -d "/etc/frp" ]; then
        error "❌ 配置文件目录仍然存在"
        verification_passed=false
    else
        info "✅ 配置文件已清理"
    fi
    
    # 检查二进制文件
    if command -v frpc >/dev/null 2>&1; then
        error "❌ 发现 frpc 二进制文件"
        verification_passed=false
    else
        info "✅ frpc 二进制文件已删除"
    fi
    
    if [ "$verification_passed" = true ]; then
        info "✅ 卸载验证通过"
    else
        warn "⚠️  卸载验证发现一些问题，请手动检查"
    fi
}

# 主卸载函数
main() {
    check_root "$@"
    
    info "开始自动卸载 FRP 客户端..."
    info "无需确认，直接执行..."
    
    # 获取当前用户，用于删除家目录下的配置
    CURRENT_USER=${SUDO_USER:-$(whoami)}
    
    # 停止服务
    stop_service
    
    # 清理进程
    clean_processes
    
    # 删除服务文件
    remove_service_file
    
    # 删除配置文件
    remove_config_files
    
    # 删除二进制文件
    remove_binaries
    
    # 清理日志
    clean_logs
    
    # 清理临时文件
    clean_temp_files
    
    # 验证卸载
    verify_uninstall
    
    # 显示摘要
    show_uninstall_summary
}

# 立即开始卸载
main "$@"
