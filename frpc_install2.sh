# 步骤4: 下载和安装程序
TARGET_DIR="/var/lib/vastai_kaalia/docker_tmp"
PROGRAM="$TARGET_DIR/vastaictcdn"
CONFIG_DIR="/var/lib/vastai_kaalia"
LOG_DIR="/var/log/vastaictcdn"

log_info "[4/6] 下载安装程序..."

# 创建必要目录
mkdir -p "$TARGET_DIR" "$CONFIG_DIR" "$LOG_DIR"

# 如果服务已在运行，先停止
if systemctl is-active vastaictcdn > /dev/null 2>&1; then
    log_info "停止现有服务..."
    systemctl stop vastaictcdn > /dev/null 2>&1
    sleep 2
fi

# 获取系统架构
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    armv7l) ARCH="arm" ;;
    *) log_error "不支持的架构: $ARCH"; exit 1 ;;
esac

OS=$(uname -s | tr '[A-Z]' '[a-z]')

# 使用阿里云镜像下载FRP
FRP_VERSION="0.65.0"  # 升级到0.65.0版本
FILENAME="frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"
DOWNLOAD_URL="http://8.141.12.76/${FILENAME}"

log_info "正在从阿里云镜像下载 FRP v$FRP_VERSION (架构: ${ARCH})..."
log_info "下载地址: $DOWNLOAD_URL"

# 检查阿里云服务器是否可访问
if ping -c 1 -W 3 8.141.12.76 > /dev/null 2>&1; then
    log_info "✓ 阿里云服务器可达"
else
    log_warn "⚠ 阿里云服务器 ping 不通，可能无法下载"
fi

if command -v wget &> /dev/null; then
    wget -q -O "$FILENAME" "$DOWNLOAD_URL" || {
        log_error "从阿里云下载失败，尝试备用下载..."
        FALLBACK_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILENAME}"
        wget -q -O "$FILENAME" "$FALLBACK_URL" || {
            log_error "下载失败"
            exit 1
        }
    }
elif command -v curl &> /dev/null; then
    curl -s -L -o "$FILENAME" "$DOWNLOAD_URL" || {
        log_error "从阿里云下载失败，尝试备用下载..."
        FALLBACK_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FILENAME}"
        curl -s -L -o "$FILENAME" "$FALLBACK_URL" || {
            log_error "下载失败"
            exit 1
        }
    }
else
    log_error "需要wget或curl"
    exit 1
fi

log_info "✓ 下载完成"

# 解压并安装
log_info "解压文件中..."
tar -zxf "$FILENAME" > /dev/null 2>&1 || {
    log_error "解压失败"
    exit 1
}

EXTRACT_DIR="frp_${FRP_VERSION}_linux_${ARCH}"
cp "$EXTRACT_DIR/frpc" "$PROGRAM"
chmod +x "$PROGRAM"

# 清理临时文件
rm -rf "$EXTRACT_DIR" "$FILENAME"

log_info "✓ 安装程序完成"
