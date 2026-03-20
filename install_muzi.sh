#!/bin/bash
set -euo pipefail

# 定义颜色常量，用于输出提示
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 全局变量 - 自动识别系统信息
OS_TYPE=""
ARCH_TYPE=""
CONDA_PATH="$HOME/mambaconda"
# 稳定版版本号（动态获取）
LATEST_CONDA_VERSION=""
LATEST_NVM_VERSION=""

# 打印信息函数
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# 打印警告函数
warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 打印错误函数
error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 检查系统类型和架构
detect_system() {
    info "开始检测系统信息..."
    
    # 检测操作系统类型
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS_TYPE="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS_TYPE="macos"
    else
        error "不支持的操作系统：$OSTYPE，仅支持 Linux 和 macOS"
    fi

    # 检测系统架构
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
        ARCH_TYPE="x86_64"
    elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
        ARCH_TYPE="aarch64"
    else
        error "不支持的系统架构：$ARCH，仅支持 x86_64/amd64 和 aarch64/arm64"
    fi

    info "系统检测完成：$OS_TYPE $ARCH_TYPE"
}

# 获取最新稳定版版本号
get_stable_versions() {
    info "开始获取各工具最新稳定版版本号..."
    
    # 获取 Mambaconda 最新稳定版（跳过 pre-release）
    info "获取 Mambaconda 最新稳定版..."
    LATEST_CONDA_INFO=$(curl -s https://api.github.com/repos/conda-forge/miniforge/releases/latest)
    LATEST_CONDA_VERSION=$(echo "$LATEST_CONDA_INFO" | grep -Po '"tag_name": "\K.*?(?=")')
    if [ -z "$LATEST_CONDA_VERSION" ]; then
        error "无法获取 Mambaconda 最新稳定版版本号，请检查网络"
    fi
    info "Mambaconda 最新稳定版：$LATEST_CONDA_VERSION"

    # 获取 NVM 最新稳定版（跳过 pre-release）
    info "获取 NVM 最新稳定版..."
    LATEST_NVM_INFO=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest)
    LATEST_NVM_VERSION=$(echo "$LATEST_NVM_INFO" | grep -Po '"tag_name": "\K.*?(?=")')
    if [ -z "$LATEST_NVM_VERSION" ]; then
        # 备用：使用已知稳定版
        LATEST_NVM_VERSION="v0.39.7"
        warn "无法获取 NVM 最新稳定版，使用备用稳定版：$LATEST_NVM_VERSION"
    fi
    info "NVM 最新稳定版：$LATEST_NVM_VERSION"
}

# 检查是否为 root 用户（macOS 不建议 root）
check_root() {
    if [ "$(id -u)" -eq 0 ]; then
        if [[ "$OS_TYPE" == "macos" ]]; then
            error "macOS 系统禁止使用 root 用户运行此脚本，请使用普通用户"
        else
            warn "当前为 root 用户，将安装到 /root/mambaconda 目录"
        fi
    fi
}

# 安装系统依赖工具
install_dependencies() {
    info "开始安装基础依赖工具..."
    
    if [[ "$OS_TYPE" == "linux" ]]; then
        if command -v apt &> /dev/null; then
            apt update && apt install -y curl wget git ca-certificates --no-install-recommends
        elif command -v yum &> /dev/null; then
            yum install -y curl wget git ca-certificates
        elif command -v dnf &> /dev/null; then
            dnf install -y curl wget git ca-certificates
        else
            error "Linux 系统不支持的包管理器，请手动安装 curl wget git"
        fi
    elif [[ "$OS_TYPE" == "macos" ]]; then
        # 检查是否安装 brew
        if ! command -v brew &> /dev/null; then
            warn "未检测到 Homebrew，正在自动安装..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        brew install curl wget git
    fi
    
    info "基础依赖工具安装完成"
}

# 安装 mambaconda 并配置清华源（仅稳定版）
install_mambaconda() {
    info "开始安装 Mambaconda（稳定版 $LATEST_CONDA_VERSION）..."
    # 检查是否已安装 conda
    if command -v conda &> /dev/null; then
        warn "检测到已安装 conda，跳过安装步骤"
        configure_conda_env
        return
    fi
    # Miniforge3-26.1.0-0-Linux-x86_64.sh
    # 构建安装包名称
    if [[ "$OS_TYPE" == "linux" ]]; then
        MAMBAFORGE_PACKAGE="Miniforge3-${LATEST_CONDA_VERSION}-Linux-${ARCH_TYPE}.sh"
    elif [[ "$OS_TYPE" == "macos" ]]; then
        if [[ "$ARCH_TYPE" == "x86_64" ]]; then
            MAMBAFORGE_PACKAGE="Miniforge3-${LATEST_CONDA_VERSION}-MacOSX-x86_64.sh"
        else
            MAMBAFORGE_PACKAGE="Miniforge3-${LATEST_CONDA_VERSION}-MacOSX-arm64.sh"
        fi
    fi
    # https://github.com/conda-forge/miniforge/releases/download/26.1.0-0/Miniforge3-26.1.0-0-Linux-x86_64.sh
    # 构建下载 URL（仅稳定版）
    GITHUB_URL="https://github.com/conda-forge/miniforge/releases/download/${LATEST_CONDA_VERSION}/${MAMBAFORGE_PACKAGE}"
    USTC_URL="https://mirrors.ustc.edu.cn/github-release/conda-forge/miniforge/${LATEST_CONDA_VERSION}/${MAMBAFORGE_PACKAGE}"
    BACKUP_URL="https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniforge3-Linux-${ARCH_TYPE}.sh"

    # 下载安装包（使用中科大镜像源）
    info "下载 Mambaconda 安装包（中科大源）..."
    if ! wget -q "$USTC_URL" -O "/tmp/$MAMBAFORGE_PACKAGE"; then
        info "中科大源下载失败，尝试 GitHub 官方源..."
        if ! wget -q "$GITHUB_URL" -O "/tmp/$MAMBAFORGE_PACKAGE"; then
            info "GitHub 源下载失败，尝试备用源..."
            if ! wget -q "$BACKUP_URL" -O "/tmp/$MAMBAFORGE_PACKAGE"; then
                error "所有源下载 mambaconda 安装包均失败，请手动下载稳定版安装包到 /tmp 目录后重新运行"
            fi
        fi
    fi
    
    # 静默安装（不修改 shell 配置文件）
    bash "/tmp/$MAMBAFORGE_PACKAGE" -b -p "$CONDA_PATH" || error "mambaconda 安装失败"
    
    # 删除安装包
    rm -f "/tmp/$MAMBAFORGE_PACKAGE"

    # 配置 conda 环境变量
    configure_conda_env

    # 激活 conda
    source "$CONDA_PATH/etc/profile.d/conda.sh"
    source "$CONDA_PATH/etc/profile.d/mamba.sh"

    # 配置清华源
    info "配置 conda 清华源..."
    cat > "$HOME/.condarc" << EOF
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  msys2: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  bioconda: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  menpo: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch-lts: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  simpleitk: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
EOF

    # 更新 conda 并安装 Python 3.10
    info "安装 Python 3.10..."
    conda install -y python=3.10 || error "Python 3.10 安装失败"

    # 初始化 conda 到 shell
    conda init bash
    if command -v zsh &> /dev/null; then
        conda init zsh
    fi
    if [[ "$OS_TYPE" == "macos" ]] && command -v fish &> /dev/null; then
        conda init fish
    fi

    info "Mambaconda 稳定版安装并配置完成"
}

# 配置 conda 环境变量
configure_conda_env() {
    info "配置 conda 环境变量..."
    # 检查 .bashrc 中是否已有 conda 配置
    if ! grep -q "conda initialize" "$HOME/.bashrc"; then
        cat >> "$HOME/.bashrc" << EOF

# >>> conda initialize >>>
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
# <<< conda initialize <<<
EOF
    fi

    # 配置 zsh（如果存在）
    if command -v zsh &> /dev/null && ! grep -q "conda initialize" "$HOME/.zshrc"; then
        cat >> "$HOME/.zshrc" << EOF

# >>> conda initialize >>>
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
# <<< conda initialize <<<
EOF
    fi

    # 立即生效环境变量
    export PATH="$CONDA_PATH/bin:$PATH"
    info "conda 环境变量配置完成"
}

# 安装 nvm 并配置淘宝源（仅稳定版）
install_nvm() {
    info "开始安装 NVM（稳定版 $LATEST_NVM_VERSION）..."
    # 检查是否已安装 nvm
    if [ -d "$HOME/.nvm" ]; then
        warn "检测到已安装 nvm，跳过安装步骤"
        configure_nvm_env
        return
    fi

    # 构建 nvm 安装脚本 URL（仅稳定版）
    NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/${LATEST_NVM_VERSION}/install.sh"
    NVM_MIRROR_URL="https://cdn.jsdelivr.net/gh/nvm-sh/nvm@${LATEST_NVM_VERSION}/install.sh"

    # 下载并安装 nvm（使用国内镜像源）
    info "下载 NVM 安装脚本（稳定版）..."
    if ! wget -q "$NVM_MIRROR_URL" -O "/tmp/install_nvm.sh"; then
        info "镜像源下载失败，尝试 GitHub 官方源..."
        if ! wget -q "$NVM_INSTALL_URL" -O "/tmp/install_nvm.sh"; then
            error "下载 NVM 稳定版安装脚本失败，请检查网络"
        fi
    fi
    
    bash "/tmp/install_nvm.sh" || error "nvm 安装失败"
    
    # 删除安装包
    rm -f "/tmp/install_nvm.sh"

    # 配置 nvm 环境变量
    configure_nvm_env

    # 激活 nvm
    export NVM_DIR="$HOME/.nvm"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        . "$NVM_DIR/nvm.sh"
    fi
    if [ -s "$NVM_DIR/bash_completion" ]; then
        . "$NVM_DIR/bash_completion"
    fi

    # 配置 nvm 镜像源（淘宝源）
    info "配置 nvm 淘宝镜像源..."
    echo 'export NVM_NODEJS_ORG_MIRROR="https://npmmirror.com/mirrors/node"' >> "$HOME/.bashrc"
    if command -v zsh &> /dev/null; then
        echo 'export NVM_NODEJS_ORG_MIRROR="https://npmmirror.com/mirrors/node"' >> "$HOME/.zshrc"
    fi
    export NVM_NODEJS_ORG_MIRROR="https://npmmirror.com/mirrors/node"

    # 安装 Node LTS 稳定版
    info "安装 Node LTS 稳定版..."
    # 直接安装 LTS 稳定版，无需手动解析版本号
    nvm install --lts || error "Node LTS 版本安装失败"
    # 设置默认版本为 LTS
    nvm alias default lts/* || error "设置 Node 默认版本失败"

    # 配置 npm 淘宝源
    info "配置 npm 淘宝源..."
    npm config set registry https://registry.npmmirror.com/ || error "配置 npm 源失败"
    # 持久化 npm 配置（全局生效）
    npm config set registry https://registry.npmmirror.com/ --global

    info "NVM 稳定版安装并配置完成"
    # # 安装 Node LTS 稳定版（跳过 pre-release）
    # info "安装 Node LTS 稳定版..."
    # # 获取 Node LTS 稳定版版本号（跳过 pre）
    # NODE_LTS_VERSION=$(nvm ls-remote --lts | grep -v "-rc" | grep -v "-beta" | tail -1 | awk '{print $1}')
    # if [ -z "$NODE_LTS_VERSION" ]; then
    #     # 备用：直接安装 lts
    #     nvm install --lts || error "Node LTS 版本安装失败"
    # else
    #     nvm install "$NODE_LTS_VERSION" || error "Node LTS 版本安装失败"
    # fi
    # nvm alias default lts/* || error "设置 Node 默认版本失败"

    # # 配置 npm 淘宝源
    # info "配置 npm 淘宝源..."
    # npm config set registry https://registry.npmmirror.com/ || error "配置 npm 源失败"
    # # 持久化 npm 配置
    # npm config set registry https://registry.npmmirror.com/ --global

    # info "NVM 稳定版安装并配置完成"
}

# 配置 nvm 环境变量
configure_nvm_env() {
    info "配置 nvm 环境变量..."
    # 检查 .bashrc 中是否已有 nvm 配置
    if ! grep -q "NVM_DIR" "$HOME/.bashrc"; then
        cat >> "$HOME/.bashrc" << EOF

# >>> nvm initialize >>>
export NVM_DIR="$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"
# <<< nvm initialize <<<
EOF
    fi

    # 配置 zsh（如果存在）
    if command -v zsh &> /dev/null && ! grep -q "NVM_DIR" "$HOME/.zshrc"; then
        cat >> "$HOME/.zshrc" << EOF

# >>> nvm initialize >>>
export NVM_DIR="$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"
# <<< nvm initialize <<<
EOF
    fi

    # 立即生效环境变量
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    info "nvm 环境变量配置完成"
}

# 验证安装结果
verify_installation() {
    info "开始验证安装结果..."
    
    # 临时关闭未定义变量检查，避免 PS1 报错
    set +u
    # 重新加载环境变量
    source "$HOME/.bashrc"
    # 恢复严格模式
    set -u
    
    source "$CONDA_PATH/etc/profile.d/conda.sh"

    # 验证 conda
    if command -v conda &> /dev/null; then
        info "✅ Mambaconda 安装成功：$(conda --version)"
        info "✅ Python 版本：$(python --version)"
    else
        warn "❌ Mambaconda 验证失败，请手动执行 source $CONDA_PATH/etc/profile.d/conda.sh"
    fi

    # 验证 nvm/node
    if command -v nvm &> /dev/null; then
        info "✅ NVM 安装成功：$(nvm --version)"
        info "✅ Node 版本：$(node --version)"
        info "✅ NPM 源：$(npm config get registry)"
    else
        warn "❌ NVM 验证失败，请手动执行 source $HOME/.nvm/nvm.sh"
    fi
}

# 清理和提示
finalize() {
    info "========== 安装配置全部完成 =========="
    info "已安装的稳定版："
    info "  - Mambaconda: $LATEST_CONDA_VERSION (Python 3.10)"
    info "  - NVM: $LATEST_NVM_VERSION (Node LTS 稳定版)"
    info "请执行以下命令使配置立即生效："
    
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "source $HOME/.bashrc"
    elif [[ "$OS_TYPE" == "macos" ]]; then
        echo "source $HOME/.zshrc"
    fi
    
    info "验证安装的命令："
    echo "conda --version && python --version"
    echo "nvm --version && node --version && npm --version"
    echo "npm config get registry && conda config --show-sources"
}

# 主执行流程
main() {
    info "========== 开始自动安装稳定版 mambaconda 和 nvm =========="
    
    # 1. 检测系统信息
    detect_system
    
    # 2. 检查用户权限
    check_root
    
    # 3. 安装基础依赖
    install_dependencies
    
    # 4. 获取最新稳定版版本号（跳过 pre-release）
    get_stable_versions
    
    # 5. 安装 mambaconda 稳定版
    install_mambaconda
    
    # 6. 安装 nvm 稳定版
    install_nvm

    # 7. 验证安装结果
    verify_installation

    # 8. 最终提示
    finalize
}

# 执行主函数
main
