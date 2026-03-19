#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

OS_TYPE=""
REMOVE_DOCKER_DATA="${REMOVE_DOCKER_DATA:-0}"

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

uninstall_linux() {
    section "卸载 Docker"
    info "移除 Docker 相关软件包..."

    if command -v apt-get >/dev/null 2>&1; then
        run_privileged apt-get remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras docker-compose || true
        run_privileged rm -f /etc/apt/sources.list.d/docker.list
        run_privileged rm -f /etc/apt/keyrings/docker.asc
    elif command -v dnf >/dev/null 2>&1; then
        run_privileged dnf remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras docker-compose || true
        run_privileged rm -f /etc/yum.repos.d/docker-ce.repo
    elif command -v yum >/dev/null 2>&1; then
        run_privileged yum remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras docker-compose || true
        run_privileged rm -f /etc/yum.repos.d/docker-ce.repo
    else
        warn "当前 Linux 包管理器不受支持，请手动卸载 Docker。"
    fi

    if [[ "$REMOVE_DOCKER_DATA" == "1" ]]; then
        warn "删除 Docker 数据目录..."
        run_privileged rm -rf /var/lib/docker /var/lib/containerd
    else
        warn "默认保留 Docker 数据。如需删除 /var/lib/docker 和 /var/lib/containerd，请设置 REMOVE_DOCKER_DATA=1。"
    fi
}

uninstall_macos() {
    section "卸载 Docker"

    if command -v brew >/dev/null 2>&1 && brew list --cask docker >/dev/null 2>&1; then
        info "移除 Docker Desktop..."
        brew uninstall --cask docker || true
    else
        warn "未检测到 Docker Desktop cask。"
    fi

    if [[ "$REMOVE_DOCKER_DATA" == "1" ]]; then
        warn "删除 Docker Desktop 数据..."
        rm -rf "$HOME/Library/Containers/com.docker.docker"
        rm -rf "$HOME/Library/Application Support/Docker Desktop"
        rm -rf "$HOME/.docker"
    else
        warn "默认保留 Docker Desktop 数据。如需删除用户数据，请设置 REMOVE_DOCKER_DATA=1。"
    fi
}

main() {
    section "Docker 卸载脚本"
    detect_system

    if [[ "$OS_TYPE" == "linux" ]]; then
        uninstall_linux
    else
        uninstall_macos
    fi

    success "Docker 卸载流程结束。"
}

main "$@"
