#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

OS_TYPE=""

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

success() {
    echo -e "${BLUE}[DONE]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

section() {
    echo
    echo -e "${BOLD}${BLUE}== $1 ==${NC}"
}

detect_system() {
    case "${OSTYPE:-}" in
        linux-gnu*) OS_TYPE="linux" ;;
        darwin*) OS_TYPE="macos" ;;
        *) error "不支持的操作系统: ${OSTYPE:-unknown}，仅支持 Linux 和 macOS。" ;;
    esac
    info "检测到系统: $OS_TYPE"
}

run_privileged() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        error "该步骤需要 root 权限，请安装 sudo 或以 root 身份运行。"
    fi
}

ensure_homebrew() {
    if command -v brew >/dev/null 2>&1; then
        return
    fi

    info "未检测到 Homebrew，开始安装..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

install_dependencies() {
    section "安装依赖"

    if [[ "$OS_TYPE" == "linux" ]]; then
        if command -v apt-get >/dev/null 2>&1; then
            run_privileged apt-get update
            run_privileged apt-get install -y ca-certificates curl
        elif command -v dnf >/dev/null 2>&1; then
            run_privileged dnf install -y ca-certificates curl
        elif command -v yum >/dev/null 2>&1; then
            run_privileged yum install -y ca-certificates curl
        else
            error "当前 Linux 包管理器不受支持，请手动安装 curl 和 ca-certificates。"
        fi
    else
        ensure_homebrew
    fi
}

install_docker_linux() {
    if command -v docker >/dev/null 2>&1; then
        warn "检测到 Docker CLI 已存在，跳过下载安装。"
    else
        local tmp_script
        tmp_script="$(mktemp "/tmp/get-docker.XXXXXX.sh")"

        info "下载 Docker 官方安装脚本..."
        curl -fsSL https://get.docker.com -o "$tmp_script"
        run_privileged sh "$tmp_script"
        rm -f "$tmp_script"
    fi

    run_privileged systemctl enable docker || true
    run_privileged systemctl start docker || true

    if [[ "$(id -u)" -ne 0 ]] && ! id -nG "$USER" | grep -qw docker; then
        info "将用户 $USER 加入 docker 用户组..."
        run_privileged usermod -aG docker "$USER" || warn "加入 docker 用户组失败。"
    fi
}

install_docker_macos() {
    if brew list --cask docker >/dev/null 2>&1; then
        warn "检测到 Docker Desktop 已安装，跳过安装。"
        return
    fi

    info "安装 Docker Desktop..."
    brew install --cask docker
}

install_docker() {
    section "安装 Docker"

    if [[ "$OS_TYPE" == "linux" ]]; then
        install_docker_linux
    else
        install_docker_macos
    fi
}

verify_installation() {
    section "校验安装结果"

    if ! command -v docker >/dev/null 2>&1; then
        error "安装完成后仍未找到 docker 命令。"
    fi

    info "Docker 版本: $(docker --version)"

    if docker compose version >/dev/null 2>&1; then
        info "Docker Compose 版本: $(docker compose version)"
    else
        warn "当前尚未检测到 docker compose 插件。"
    fi

    if ! docker info >/dev/null 2>&1; then
        warn "暂时无法连接 Docker daemon。Linux 可能需要重新登录，macOS 需要先启动 Docker Desktop。"
    fi
}

finalize() {
    section "完成"
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "如果刚加入 docker 用户组，请重新登录后再无 sudo 使用 Docker。"
    else
        echo "首次使用前请先手动启动一次 Docker Desktop。"
    fi
    echo "可执行以下命令快速验证："
    echo "  docker --version && docker compose version"
    success "Docker 安装流程结束。"
}

main() {
    section "Docker 安装脚本"
    detect_system
    install_dependencies
    install_docker
    verify_installation
    finalize
}

main "$@"
