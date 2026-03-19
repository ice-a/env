#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

OS_TYPE=""
LATEST_NVM_VERSION=""

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
            run_privileged apt-get install -y curl ca-certificates
        elif command -v dnf >/dev/null 2>&1; then
            run_privileged dnf install -y curl ca-certificates
        elif command -v yum >/dev/null 2>&1; then
            run_privileged yum install -y curl ca-certificates
        else
            error "当前 Linux 包管理器不受支持，请手动安装 curl 和 ca-certificates。"
        fi
    else
        ensure_homebrew
        brew install curl
    fi
}

get_latest_version() {
    section "获取版本信息"

    local api_url="https://api.github.com/repos/nvm-sh/nvm/releases/latest"
    LATEST_NVM_VERSION="$(curl -fsSL "$api_url" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)"

    if [[ -z "$LATEST_NVM_VERSION" ]]; then
        LATEST_NVM_VERSION="v0.39.7"
        warn "获取最新版本失败，回退到 $LATEST_NVM_VERSION"
    fi

    info "使用的 NVM 版本: $LATEST_NVM_VERSION"
}

append_block_if_missing() {
    local file="$1"
    local marker="$2"
    local block="$3"

    touch "$file"
    if ! grep -qF "$marker" "$file"; then
        printf '\n%s\n' "$block" >> "$file"
    fi
}

append_line_if_missing() {
    local file="$1"
    local line="$2"

    touch "$file"
    if ! grep -qxF "$line" "$file"; then
        printf '%s\n' "$line" >> "$file"
    fi
}

configure_shells() {
    section "配置 Shell 环境"

    local init_block
    init_block=$(cat <<'EOF'
# >>> nvm initialize >>>
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
export NVM_NODEJS_ORG_MIRROR="https://npmmirror.com/mirrors/node"
# <<< nvm initialize <<<
EOF
)

    append_block_if_missing "$HOME/.bashrc" "# >>> nvm initialize >>>" "$init_block"
    append_block_if_missing "$HOME/.zshrc" "# >>> nvm initialize >>>" "$init_block"
    append_line_if_missing "$HOME/.profile" 'export NVM_DIR="$HOME/.nvm"'

    export NVM_DIR="$HOME/.nvm"
    export NVM_NODEJS_ORG_MIRROR="https://npmmirror.com/mirrors/node"
}

install_nvm() {
    section "安装 NVM"

    if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
        warn "检测到 NVM 已存在，跳过下载安装。"
    else
        local primary_url="https://raw.githubusercontent.com/nvm-sh/nvm/${LATEST_NVM_VERSION}/install.sh"
        local mirror_url="https://cdn.jsdelivr.net/gh/nvm-sh/nvm@${LATEST_NVM_VERSION}/install.sh"
        local tmp_script

        tmp_script="$(mktemp "/tmp/install_nvm.XXXXXX.sh")"

        info "下载 NVM 安装脚本..."
        if ! curl -fL "$mirror_url" -o "$tmp_script"; then
            warn "镜像下载失败，尝试从 GitHub 下载..."
            curl -fL "$primary_url" -o "$tmp_script"
        fi

        bash "$tmp_script"
        rm -f "$tmp_script"
    fi

    configure_shells

    # shellcheck disable=SC1091
    source "$HOME/.nvm/nvm.sh"

    info "安装最新 LTS 版本 Node.js..."
    nvm install --lts
    nvm alias default 'lts/*'

    npm config set registry https://registry.npmmirror.com/
}

verify_installation() {
    section "校验安装结果"

    if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
        error "在 $HOME/.nvm 下未找到 nvm.sh"
    fi

    # shellcheck disable=SC1091
    source "$HOME/.nvm/nvm.sh"

    info "NVM 版本: $(nvm --version)"
    info "Node 版本: $(node --version)"
    info "npm 源: $(npm config get registry)"
}

finalize() {
    section "完成"
    echo "下一步可执行："
    echo "  source \"$HOME/.bashrc\"   # 或 source \"$HOME/.zshrc\""
    echo "可执行以下命令快速验证："
    echo "  nvm --version && node --version && npm --version"
    success "NVM 安装流程结束。"
}

main() {
    section "NVM 安装脚本"
    detect_system
    install_dependencies
    get_latest_version
    install_nvm
    verify_installation
    finalize
}

main "$@"
