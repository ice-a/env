#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

OS_TYPE=""
ARCH_TYPE=""
CONDA_PATH="${CONDA_PATH:-$HOME/mambaconda}"
LATEST_CONDA_VERSION=""

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
    section "检测系统信息"

    case "${OSTYPE:-}" in
        linux-gnu*) OS_TYPE="linux" ;;
        darwin*) OS_TYPE="macos" ;;
        *) error "不支持的操作系统: ${OSTYPE:-unknown}，仅支持 Linux 和 macOS。" ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64) ARCH_TYPE="x86_64" ;;
        arm64|aarch64)
            if [[ "$OS_TYPE" == "macos" ]]; then
                ARCH_TYPE="arm64"
            else
                ARCH_TYPE="aarch64"
            fi
            ;;
        *) error "不支持的系统架构: $(uname -m)" ;;
    esac

    info "检测到平台: $OS_TYPE $ARCH_TYPE"
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
            run_privileged apt-get install -y curl wget ca-certificates bzip2
        elif command -v dnf >/dev/null 2>&1; then
            run_privileged dnf install -y curl wget ca-certificates bzip2
        elif command -v yum >/dev/null 2>&1; then
            run_privileged env LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-${LANG:-en_US.UTF-8}}" yum --setopt=history_record=false install -y curl wget ca-certificates bzip2
        else
            error "当前 Linux 包管理器不受支持，请手动安装 curl、wget、ca-certificates 和 bzip2。"
        fi
    else
        ensure_homebrew
        brew install curl wget
    fi
}

get_latest_version() {
    section "获取版本信息"

    local api_url="https://api.github.com/repos/conda-forge/miniforge/releases/latest"
    LATEST_CONDA_VERSION="$(curl -fsSL "$api_url" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)"

    if [[ -z "$LATEST_CONDA_VERSION" ]]; then
        error "无法获取最新的 Miniforge 版本。"
    fi

    info "最新 Miniforge 版本: $LATEST_CONDA_VERSION"
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

configure_shells() {
    section "配置 Shell 环境"

    local bash_block zsh_block

    bash_block=$(cat <<EOF
# >>> mambaconda initialize >>>
__conda_setup="\$('$CONDA_PATH/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ \$? -eq 0 ]; then
    eval "\$__conda_setup"
else
    if [ -f "$CONDA_PATH/etc/profile.d/conda.sh" ]; then
        . "$CONDA_PATH/etc/profile.d/conda.sh"
    else
        export PATH="$CONDA_PATH/bin:\$PATH"
    fi
fi
unset __conda_setup
# <<< mambaconda initialize <<<
EOF
)

    zsh_block=$(cat <<EOF
# >>> mambaconda initialize >>>
__conda_setup="\$('$CONDA_PATH/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ \$? -eq 0 ]; then
    eval "\$__conda_setup"
else
    if [ -f "$CONDA_PATH/etc/profile.d/conda.sh" ]; then
        . "$CONDA_PATH/etc/profile.d/conda.sh"
    else
        export PATH="$CONDA_PATH/bin:\$PATH"
    fi
fi
unset __conda_setup
# <<< mambaconda initialize <<<
EOF
)

    append_block_if_missing "$HOME/.bashrc" "# >>> mambaconda initialize >>>" "$bash_block"
    append_block_if_missing "$HOME/.zshrc" "# >>> mambaconda initialize >>>" "$zsh_block"

    export PATH="$CONDA_PATH/bin:$PATH"
}

write_condarc() {
    section "写入 Conda 配置"
    info "生成 ~/.condarc 并写入镜像配置..."

    cat > "$HOME/.condarc" <<'EOF'
channels:
  - conda-forge
  - defaults
show_channel_urls: true
channel_priority: flexible
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  bioconda: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  menpo: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  msys2: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
EOF
}

install_mambaconda() {
    section "安装 Mambaconda"
    info "安装目录: $CONDA_PATH"

    if [[ -x "$CONDA_PATH/bin/conda" ]]; then
        warn "检测到已有 Conda 安装，跳过下载安装。"
    else
        local package_name=""
        local tmp_script=""
        local github_url=""
        local mirror_url=""

        if [[ "$OS_TYPE" == "linux" ]]; then
            package_name="Miniforge3-${LATEST_CONDA_VERSION}-Linux-${ARCH_TYPE}.sh"
        else
            package_name="Miniforge3-${LATEST_CONDA_VERSION}-MacOSX-${ARCH_TYPE}.sh"
        fi

        github_url="https://github.com/conda-forge/miniforge/releases/download/${LATEST_CONDA_VERSION}/${package_name}"
        mirror_url="https://mirrors.ustc.edu.cn/github-release/conda-forge/miniforge/${LATEST_CONDA_VERSION}/${package_name}"
        tmp_script="$(mktemp "/tmp/${package_name}.XXXXXX")"

        info "下载 Mambaconda 安装脚本..."
        if ! curl -fL "$mirror_url" -o "$tmp_script"; then
            warn "中科大镜像下载失败，尝试从 GitHub 下载..."
            curl -fL "$github_url" -o "$tmp_script"
        fi

        bash "$tmp_script" -b -p "$CONDA_PATH"
        rm -f "$tmp_script"
    fi

    configure_shells
    write_condarc

    # shellcheck disable=SC1091
    source "$CONDA_PATH/etc/profile.d/conda.sh"

    info "安装 Python 3.10..."
    conda install -y python=3.10
}

verify_installation() {
    section "校验安装结果"

    if [[ ! -x "$CONDA_PATH/bin/conda" ]]; then
        error "未在 $CONDA_PATH/bin/conda 找到 conda 可执行文件"
    fi

    # shellcheck disable=SC1091
    source "$CONDA_PATH/etc/profile.d/conda.sh"

    info "Conda 版本: $(conda --version)"
    info "Python 版本: $(python --version 2>&1)"
}

finalize() {
    section "完成"
    echo "下一步可执行："
    echo "  source \"$HOME/.bashrc\"   # 或 source \"$HOME/.zshrc\""
    echo "可执行以下命令快速验证："
    echo "  conda --version && python --version"
    success "Mambaconda 安装流程结束。"
}

main() {
    section "Mambaconda 安装脚本"
    detect_system
    install_dependencies
    get_latest_version
    install_mambaconda
    verify_installation
    finalize
}

main "$@"
