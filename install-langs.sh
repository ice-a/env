#!/usr/bin/env bash
# ============================================================================
# install-langs.sh — Linux 服务器开发语言自动安装工具
# 支持: C/C++, Python, Node.js, Go, Java, Rust, Docker, Git, Make
#       MySQL, MongoDB, Redis
# 特性: 版本管理工具、国内镜像切换、错误日志、交互式选择菜单
# ============================================================================
set -u -o pipefail

# ============================================================================
# 全局变量
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ERROR_LOG="${SCRIPT_DIR}/error.log"
TIMESTAMP_FORMAT="%Y-%m-%dT%H:%M:%S%z"

# 镜像源
MIRROR_TUNA="https://mirrors.tuna.tsinghua.edu.cn"
MIRROR_ALIYUN="https://mirrors.aliyun.com"
NPM_MIRROR="https://registry.npmmirror.com"
GO_PROXY="https://goproxy.cn,direct"
NVM_NODE_MIRROR="https://npmmirror.com/mirrors/node"
CONDA_MIRROR="${MIRROR_TUNA}/anaconda/miniconda"
RUSTUP_MIRROR="https://mirrors.ustc.edu.cn/rust-static"

# 检测结果
OS_ID=""
OS_VERSION=""
PKG_MGR=""
ARCH=""
REAL_USER=""
IS_ROOT=false

# 菜单项定义: key|描述|默认选中(1=是,0=否)
declare -a MENU_ITEMS=(
    "cpp|C/C++ (gcc, g++, make, cmake)|1"
    "python|Python (系统版本 或 Miniconda)|1"
    "node|Node.js (通过 nvm)|1"
    "go|Go|1"
    "java|Java (OpenJDK)|1"
    "rust|Rust (通过 rustup)|1"
    "docker|Docker|1"
    "mysql|MySQL|0"
    "mongodb|MongoDB|0"
    "redis|Redis|0"
    "git|Git|0"
    "make|Make & CMake|0"
)

# ============================================================================
# 日志函数
# ============================================================================
log_info() {
    printf "[INFO]  %s\n" "$*"
}

log_warn() {
    printf "[WARN]  %s\n" "$*"
}

log_error() {
    printf "[ERROR] %s\n" "$*"
}

log_step() {
    printf "\n══════ %s ══════\n" "$*"
}

# 写入错误日志
log_error_to_file() {
    local lang="$1" phase="$2" exit_code="$3" msg="$4"
    local ts
    ts="$(date +"${TIMESTAMP_FORMAT}")"
    echo "${ts} level=ERROR lang=${lang} phase=${phase} exit=${exit_code} msg=\"${msg}\"" >> "${ERROR_LOG}"
}

# ============================================================================
# 交互式菜单 (简化版，兼容所有终端)
# ============================================================================
declare -A MENU_SELECTED=()
MENU_CURSOR=0

# 初始化默认选中状态
init_menu_selections() {
    for item in "${MENU_ITEMS[@]}"; do
        IFS='|' read -r key desc default <<< "${item}"
        if [[ "${default}" == "1" ]]; then
            MENU_SELECTED["${key}"]=1
        else
            MENU_SELECTED["${key}"]=0
        fi
    done
}

# 绘制菜单 (使用 printf，不依赖 tput)
draw_menu() {
    local total=${#MENU_ITEMS[@]}

    # 清屏 (兼容方式)
    printf '\033[2J\033[H'

    # 标题
    printf "\n"
    printf "  ╔══════════════════════════════════════════════════════╗\n"
    printf "  ║        Linux 开发语言自动安装工具                   ║\n"
    printf "  ╚══════════════════════════════════════════════════════╝\n"
    printf "\n"

    # 操作提示
    printf "  ↑↓ 移动光标    空格 选中/取消    a 全选    Enter 确认\n"
    printf "\n"

    # 绘制菜单项
    for ((i=0; i<total; i++)); do
        IFS='|' read -r key desc default <<< "${MENU_ITEMS[i]}"

        # 光标位置标记
        if [[ ${i} -eq ${MENU_CURSOR} ]]; then
            printf "  > "
        else
            printf "    "
        fi

        # 选中状态 checkbox
        if [[ "${MENU_SELECTED[${key}]:-0}" == "1" ]]; then
            printf "[*] %s\n" "${desc}"
        else
            printf "[ ] %s\n" "${desc}"
        fi
    done

    # 底部统计
    printf "\n"
    local selected_count=0
    for key in "${!MENU_SELECTED[@]}"; do
        if [[ "${MENU_SELECTED[${key}]}" == "1" ]]; then
            ((selected_count++))
        fi
    done
    printf "  已选中: %d 项\n" "${selected_count}"
    printf "\n"
}

# 主菜单交互循环
show_interactive_menu() {
    init_menu_selections

    local total=${#MENU_ITEMS[@]}

    # 首次绘制
    draw_menu

    # 输入循环 - 使用简单可靠的 read 方式
    while true; do
        # 读取单个字符 (不回显)
        local key
        read -r -n1 -s key

        # 方向键检测: ESC [ A/B
        if [[ "${key}" == $'\033' ]]; then
            # 读取后续字节
            read -r -n2 -s key 2>/dev/null
            case "${key}" in
                "[A") # 上
                    MENU_CURSOR=$(( (MENU_CURSOR - 1 + total) % total ))
                    ;;
                "[B") # 下
                    MENU_CURSOR=$(( (MENU_CURSOR + 1) % total ))
                    ;;
            esac
        elif [[ "${key}" == " " ]]; then
            # 空格 - 切换选中
            local current_key
            IFS='|' read -r current_key _ _ <<< "${MENU_ITEMS[MENU_CURSOR]}"
            if [[ "${MENU_SELECTED[${current_key}]:-0}" == "1" ]]; then
                MENU_SELECTED["${current_key}"]=0
            else
                MENU_SELECTED["${current_key}"]=1
            fi
        elif [[ "${key}" == "a" || "${key}" == "A" ]]; then
            # 全选/全不选
            local all_selected=true
            for item in "${MENU_ITEMS[@]}"; do
                IFS='|' read -r k _ _ <<< "${item}"
                if [[ "${MENU_SELECTED[${k}]:-0}" != "1" ]]; then
                    all_selected=false
                    break
                fi
            done
            for item in "${MENU_ITEMS[@]}"; do
                IFS='|' read -r k _ _ <<< "${item}"
                if ${all_selected}; then
                    MENU_SELECTED["${k}"]=0
                else
                    MENU_SELECTED["${k}"]=1
                fi
            done
        elif [[ -z "${key}" ]]; then
            # Enter - 确认
            break
        fi

        draw_menu
    done

    # 返回选中的项目
    local selections=()
    for item in "${MENU_ITEMS[@]}"; do
        IFS='|' read -r key _ _ <<< "${item}"
        if [[ "${MENU_SELECTED[${key}]:-0}" == "1" ]]; then
            selections+=("${key}")
        fi
    done

    printf "\n"
    echo "${selections[*]}"
}

# ============================================================================
# 系统检测
# ============================================================================
detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
    elif [[ -f /etc/redhat-release ]]; then
        OS_ID="centos"
        OS_VERSION=$(grep -oP '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
    fi

    case "${OS_ID}" in
        ubuntu|debian|linuxmint|pop)
            PKG_MGR="apt" ;;
        centos|rhel|rocky|almalinux|fedora)
            if command -v dnf &>/dev/null; then
                PKG_MGR="dnf"
            else
                PKG_MGR="yum"
            fi ;;
        *)
            PKG_MGR="unknown" ;;
    esac

    ARCH="$(uname -m)"
    case "${ARCH}" in
        x86_64|amd64)  ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *)             ARCH="unknown" ;;
    esac
}

detect_real_user() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        REAL_USER="${SUDO_USER}"
    else
        REAL_USER="$(whoami)"
    fi

    if [[ "$(id -u)" -eq 0 ]]; then
        IS_ROOT=true
    fi
}

get_user_home() {
    eval echo "~${REAL_USER}"
}

# ============================================================================
# 网络检测与镜像切换
# ============================================================================
should_use_mirror() {
    if curl -sSf --connect-timeout 5 --max-time 10 "https://go.dev" &>/dev/null; then
        return 1
    fi
    return 0
}

switch_apt_mirror() {
    local mirror_url="${MIRROR_TUNA}/ubuntu"
    local sources_list="/etc/apt/sources.list"
    local backup="${sources_list}.bak.$(date +%s)"

    if grep -q "mirrors.tuna.tsinghua.edu.cn" "${sources_list}" 2>/dev/null; then
        log_info "APT 已使用清华镜像源"
        return 0
    fi

    log_info "切换 APT 到清华镜像源..."
    cp "${sources_list}" "${backup}"

    local codename
    codename=$(lsb_release -cs 2>/dev/null || echo "jammy")

    cat > "${sources_list}" <<EOF
# 清华大学镜像源 (auto-generated by install-langs.sh)
deb ${mirror_url} ${codename} main restricted universe multiverse
deb ${mirror_url} ${codename}-updates main restricted universe multiverse
deb ${mirror_url} ${codename}-backports main restricted universe multiverse
deb ${mirror_url} ${codename}-security main restricted universe multiverse
EOF

    if ! pkg_update 2>/dev/null; then
        log_warn "镜像源更新失败，恢复原始源..."
        cp "${backup}" "${sources_list}"
        pkg_update 2>/dev/null
        return 1
    fi
}

switch_yum_mirror() {
    local repo_dir="/etc/yum.repos.d"
    local backup_dir="${repo_dir}.bak.$(date +%s)"

    if ls "${repo_dir}"/*.repo &>/dev/null && grep -ql "mirrors.aliyun.com" "${repo_dir}"/*.repo 2>/dev/null; then
        log_info "YUM/DNF 已使用阿里云镜像源"
        return 0
    fi

    log_info "切换 YUM/DNF 到阿里云镜像源..."
    cp -r "${repo_dir}" "${backup_dir}"

    for repo_file in "${repo_dir}"/*.repo; do
        [[ -f "${repo_file}" ]] || continue
        sed -i 's|mirrorlist=|#mirrorlist=|g' "${repo_file}"
        sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://mirrors.aliyun.com|g' "${repo_file}"
    done

    if ! pkg_update 2>/dev/null; then
        log_warn "镜像源更新失败，恢复原始源..."
        rm -rf "${repo_dir}"
        mv "${backup_dir}" "${repo_dir}"
        return 1
    fi
}

# ============================================================================
# 包管理器抽象
# ============================================================================
pkg_update() {
    case "${PKG_MGR}" in
        apt) apt-get update -y ;;
        dnf) dnf makecache -y ;;
        yum) yum makecache -y ;;
        *)   log_error "不支持的包管理器: ${PKG_MGR}"; return 1 ;;
    esac
}

pkg_install() {
    local packages=("$@")
    case "${PKG_MGR}" in
        apt) apt-get install -y "${packages[@]}" ;;
        dnf) dnf install -y "${packages[@]}" ;;
        yum) yum install -y "${packages[@]}" ;;
        *)   log_error "不支持的包管理器: ${PKG_MGR}"; return 1 ;;
    esac
}

# ============================================================================
# 环境变量工具
# ============================================================================
append_once() {
    local file="$1" line="$2"
    touch "${file}" 2>/dev/null || true
    if ! grep -qF "${line}" "${file}" 2>/dev/null; then
        echo "${line}" >> "${file}"
    fi
}

ensure_path_entry() {
    local entry="$1"
    local profile_file="$2"
    append_once "${profile_file}" "export PATH=\"${entry}:\${PATH}\""
}

download_file() {
    local url="$1" output="$2"
    local retries=2

    for ((i=1; i<=retries; i++)); do
        if curl -fsSL --connect-timeout 10 --max-time 300 -o "${output}" "${url}"; then
            return 0
        fi
        log_warn "下载失败 (尝试 ${i}/${retries}): ${url}"
        sleep 2
    done

    return 1
}

# ============================================================================
# 安装函数: C/C++
# ============================================================================
install_cpp() {
    log_step "安装 C/C++ 开发环境"

    case "${PKG_MGR}" in
        apt)
            pkg_install build-essential gcc g++ make gdb pkg-config cmake
            ;;
        dnf|yum)
            if dnf groupinstall -y "Development Tools" 2>/dev/null || \
               yum groupinstall -y "Development Tools" 2>/dev/null; then
                pkg_install gcc gcc-c++ make gdb cmake
            fi
            ;;
    esac
}

verify_cpp() {
    command -v gcc &>/dev/null && command -v g++ &>/dev/null && command -v make &>/dev/null
}

# ============================================================================
# 安装函数: Python
# ============================================================================
install_python_system() {
    log_step "安装 Python (系统版本)"

    case "${PKG_MGR}" in
        apt)
            pkg_install python3 python3-pip python3-venv python3-dev
            ;;
        dnf|yum)
            pkg_install python3 python3-pip python3-devel
            ;;
    esac

    # 配置 PyPI 国内镜像
    local user_home
    user_home="$(get_user_home)"
    local pip_conf="${user_home}/.config/pip/pip.conf"
    mkdir -p "$(dirname "${pip_conf}")"
    cat > "${pip_conf}" <<EOF
[global]
index-url = ${MIRROR_TUNA}/pypi/web/simple
trusted-host = mirrors.tuna.tsinghua.edu.cn
EOF
    chown "${REAL_USER}:${REAL_USER}" "${pip_conf}" 2>/dev/null || true
    log_info "已配置 PyPI 清华镜像源"
}

install_miniconda() {
    log_step "安装 Miniconda"

    local user_home
    user_home="$(get_user_home)"
    local install_dir="${user_home}/miniconda3"
    local installer="/tmp/miniconda.sh"

    if [[ -d "${install_dir}" ]]; then
        log_warn "Miniconda 已安装于 ${install_dir}，跳过"
        return 0
    fi

    local url="${CONDA_MIRROR}/Miniconda3-latest-Linux-${ARCH}.sh"
    if ! download_file "${url}" "${installer}"; then
        log_error "Miniconda 下载失败"
        return 1
    fi

    log_info "安装 Miniconda 到 ${install_dir}..."
    if ! bash "${installer}" -b -p "${install_dir}"; then
        log_error "Miniconda 安装失败"
        rm -f "${installer}"
        return 1
    fi
    rm -f "${installer}"

    # 配置 Conda 国内镜像
    local condarc="${user_home}/.condarc"
    cat > "${condarc}" <<EOF
channels:
  - defaults
show_channel_urls: true
default_channels:
  - ${MIRROR_TUNA}/anaconda/pkgs/main
  - ${MIRROR_TUNA}/anaconda/pkgs/r
  - ${MIRROR_TUNA}/anaconda/pkgs/msys2
custom_channels:
  conda-forge: ${MIRROR_TUNA}/anaconda/cloud
  pytorch: ${MIRROR_TUNA}/anaconda/cloud
EOF
    chown "${REAL_USER}:${REAL_USER}" "${condarc}" 2>/dev/null || true

    sudo -u "${REAL_USER}" "${install_dir}/bin/conda" init bash 2>/dev/null || true

    log_info "Miniconda 安装完成，已配置清华镜像源"
}

install_python() {
    echo ""
    echo "  Python 安装选项:"
    echo "    1) 系统 Python + pip（推荐）"
    echo "    2) Miniconda（版本管理）"
    echo ""
    read -rp "  请选择 [1/2，默认 1]: " choice
    choice="${choice:-1}"

    case "${choice}" in
        1) install_python_system ;;
        2) install_miniconda ;;
        *) log_warn "无效选择，使用系统 Python"; install_python_system ;;
    esac
}

verify_python() {
    command -v python3 &>/dev/null || command -v conda &>/dev/null
}

# ============================================================================
# 安装函数: Node.js
# ============================================================================
install_node() {
    log_step "安装 nvm + Node.js"

    local user_home
    user_home="$(get_user_home)"
    local nvm_dir="${user_home}/.nvm"

    if [[ -d "${nvm_dir}" ]]; then
        log_warn "nvm 已安装于 ${nvm_dir}"
        export NVM_DIR="${nvm_dir}"
        [ -s "${nvm_dir}/nvm.sh" ] && . "${nvm_dir}/nvm.sh"
        return 0
    fi

    export NVM_NODEJS_ORG_MIRROR="${NVM_NODE_MIRROR}"
    export NVM_DIR="${nvm_dir}"

    local installer="/tmp/nvm-install.sh"
    if ! download_file "https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh" "${installer}"; then
        log_error "nvm 安装脚本下载失败"
        return 1
    fi

    log_info "安装 nvm..."
    sudo -u "${REAL_USER}" bash "${installer}" 2>/dev/null
    rm -f "${installer}"

    [ -s "${nvm_dir}/nvm.sh" ] && . "${nvm_dir}/nvm.sh"

    log_info "安装 Node.js LTS..."
    NVM_NODEJS_ORG_MIRROR="${NVM_NODE_MIRROR}" nvm install --lts 2>/dev/null || {
        log_warn "通过镜像安装失败，尝试官方源..."
        NVM_NODEJS_ORG_MIRROR="https://nodejs.org/dist" nvm install --lts 2>/dev/null
    }
    nvm use --lts 2>/dev/null || true
    nvm alias default lts/* 2>/dev/null || true

    if command -v npm &>/dev/null; then
        sudo -u "${REAL_USER}" npm config set registry "${NPM_MIRROR}" 2>/dev/null || true
        log_info "已配置 npm 镜像源: ${NPM_MIRROR}"
    fi

    log_info "nvm + Node.js 安装完成"
}

verify_node() {
    command -v node &>/dev/null || {
        local user_home
        user_home="$(get_user_home)"
        [[ -s "${user_home}/.nvm/nvm.sh" ]]
    }
}

# ============================================================================
# 安装函数: Go
# ============================================================================
install_go() {
    log_step "安装 Go"

    local go_version
    go_version=$(curl -sSf "https://go.dev/VERSION?m=text" 2>/dev/null | head -1)
    if [[ -z "${go_version}" ]]; then
        go_version="go1.22.4"
        log_warn "无法获取最新版本，使用默认: ${go_version}"
    fi

    local go_tar="${go_version}.linux-${ARCH}.tar.gz"
    local install_dir="/usr/local"

    if [[ -f "${install_dir}/go/bin/go" ]]; then
        local installed_version
        installed_version=$("${install_dir}/go/bin/go" version 2>/dev/null | awk '{print $3}')
        if [[ "${installed_version}" == "${go_version}" ]]; then
            log_info "Go ${go_version} 已安装，跳过"
            return 0
        fi
    fi

    local url="https://go.dev/dl/${go_tar}"
    local mirror_url="${MIRROR_ALIYUN}/golang/${go_tar}"
    local output="/tmp/${go_tar}"

    log_info "下载 Go ${go_version}..."
    if ! download_file "${url}" "${output}"; then
        log_warn "官方源下载失败，尝试阿里云镜像..."
        if ! download_file "${mirror_url}" "${output}"; then
            log_error "Go 下载失败（官方源和镜像均失败）"
            return 1
        fi
    fi

    rm -rf "${install_dir}/go"
    log_info "解压 Go 到 ${install_dir}..."
    if ! tar -C "${install_dir}" -xzf "${output}"; then
        log_error "Go 解压失败"
        rm -f "${output}"
        return 1
    fi
    rm -f "${output}"

    local profile_file="/etc/profile.d/golang.sh"
    cat > "${profile_file}" <<'EOF'
export GOROOT=/usr/local/go
export GOPATH=${HOME}/go
export PATH=${GOROOT}/bin:${GOPATH}/bin:${PATH}
EOF
    chmod 644 "${profile_file}"

    local user_home
    user_home="$(get_user_home)"
    local user_profile="${user_home}/.bashrc"
    ensure_path_entry "/usr/local/go/bin" "${user_profile}"
    append_once "${user_profile}" 'export GOPATH="${HOME}/go"'
    ensure_path_entry '${GOPATH}/bin' "${user_profile}"
    chown "${REAL_USER}:${REAL_USER}" "${user_profile}" 2>/dev/null || true

    append_once "${user_profile}" "export GOPROXY=${GO_PROXY}"
    chown "${REAL_USER}:${REAL_USER}" "${user_profile}" 2>/dev/null || true

    log_info "Go ${go_version} 安装完成，已配置 GOPROXY=${GO_PROXY}"
}

verify_go() {
    command -v go &>/dev/null || [[ -f /usr/local/go/bin/go ]]
}

# ============================================================================
# 安装函数: Java
# ============================================================================
install_java() {
    log_step "安装 Java (OpenJDK)"

    local java_version="${1:-17}"

    case "${PKG_MGR}" in
        apt)
            pkg_install "openjdk-${java_version}-jdk" || pkg_install default-jdk
            ;;
        dnf|yum)
            pkg_install "java-${java_version}-openjdk-devel" || pkg_install java-17-openjdk-devel
            ;;
    esac

    # 配置 JAVA_HOME
    local java_home
    java_home=$(dirname $(dirname $(readlink -f $(command -v javac))))
    if [[ -n "${java_home}" ]]; then
        local profile_file="/etc/profile.d/java.sh"
        cat > "${profile_file}" <<EOF
export JAVA_HOME=${java_home}
export PATH=\${JAVA_HOME}/bin:\${PATH}
EOF
        chmod 644 "${profile_file}"

        local user_home
        user_home="$(get_user_home)"
        local user_profile="${user_home}/.bashrc"
        append_once "${user_profile}" "export JAVA_HOME=${java_home}"
        ensure_path_entry '${JAVA_HOME}/bin' "${user_profile}"
        chown "${REAL_USER}:${REAL_USER}" "${user_profile}" 2>/dev/null || true
    fi

    log_info "Java OpenJDK ${java_version} 安装完成"
}

verify_java() {
    command -v java &>/dev/null && command -v javac &>/dev/null
}

# ============================================================================
# 安装函数: Rust
# ============================================================================
install_rust() {
    log_step "安装 Rust (通过 rustup)"

    local user_home
    user_home="$(get_user_home)"
    local cargo_dir="${user_home}/.cargo"

    if [[ -f "${cargo_dir}/bin/rustc" ]]; then
        log_warn "Rust 已安装于 ${cargo_dir}，跳过"
        return 0
    fi

    export RUSTUP_DIST_SERVER="${RUSTUP_MIRROR}"
    export RUSTUP_UPDATE_ROOT="${RUSTUP_MIRROR}/rustup"

    local installer="/tmp/rustup-init.sh"
    if ! download_file "https://sh.rustup.rs" "${installer}"; then
        log_error "Rust 安装脚本下载失败"
        return 1
    fi

    log_info "安装 Rust..."
    sudo -u "${REAL_USER}" RUSTUP_DIST_SERVER="${RUSTUP_MIRROR}" \
        RUSTUP_UPDATE_ROOT="${RUSTUP_MIRROR}/rustup" \
        bash "${installer}" -y --default-toolchain stable 2>/dev/null
    rm -f "${installer}"

    # 配置 crates.io 国内镜像
    local cargo_config="${cargo_dir}/config"
    mkdir -p "${cargo_dir}"
    cat > "${cargo_config}" <<EOF
[source.crates-io]
replace-with = 'ustc'

[source.ustc]
registry = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"
EOF
    chown -R "${REAL_USER}:${REAL_USER}" "${cargo_dir}" 2>/dev/null || true

    local user_profile="${user_home}/.bashrc"
    ensure_path_entry '${HOME}/.cargo/bin' "${user_profile}"
    chown "${REAL_USER}:${REAL_USER}" "${user_profile}" 2>/dev/null || true

    log_info "Rust 安装完成，已配置 USTC crates.io 镜像"
}

verify_rust() {
    local user_home
    user_home="$(get_user_home)"
    command -v rustc &>/dev/null || [[ -f "${user_home}/.cargo/bin/rustc" ]]
}

# ============================================================================
# 安装函数: Docker
# ============================================================================
install_docker() {
    log_step "安装 Docker"

    if command -v docker &>/dev/null; then
        log_warn "Docker 已安装，跳过"
        return 0
    fi

    case "${PKG_MGR}" in
        apt)
            pkg_install ca-certificates curl gnupg lsb-release
            local keyring="/etc/apt/keyrings/docker.gpg"
            mkdir -p /etc/apt/keyrings
            if [[ ! -f "${keyring}" ]]; then
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o "${keyring}" 2>/dev/null
                chmod a+r "${keyring}"
            fi
            local codename
            codename=$(lsb_release -cs 2>/dev/null || echo "jammy")
            echo "deb [arch=$(dpkg --print-architecture) signed-by=${keyring}] https://download.docker.com/linux/ubuntu ${codename} stable" \
                > /etc/apt/sources.list.d/docker.list
            pkg_update
            pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        dnf|yum)
            pkg_install yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null || \
            dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null
            pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
    esac

    systemctl start docker 2>/dev/null || true
    systemctl enable docker 2>/dev/null || true
    usermod -aG docker "${REAL_USER}" 2>/dev/null || true

    # 配置 Docker 国内镜像
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.ccs.tencentyun.com"
  ]
}
EOF

    systemctl restart docker 2>/dev/null || true

    log_info "Docker 安装完成，已配置国内镜像加速"
    log_warn "请重新登录或运行 'newgrp docker' 以使用 docker 命令"
}

verify_docker() {
    command -v docker &>/dev/null
}

# ============================================================================
# 安装函数: MySQL
# ============================================================================
install_mysql() {
    log_step "安装 MySQL"

    case "${PKG_MGR}" in
        apt)
            # 设置 MySQL APT 仓库
            local mysql_deb="/tmp/mysql-apt-config.deb"
            if ! download_file "https://dev.mysql.com/get/mysql-apt-config_0.8.30-1_all.deb" "${mysql_deb}"; then
                log_warn "下载 MySQL APT 配置失败，使用系统默认版本"
                pkg_install mysql-server mysql-client
            else
                DEBIAN_FRONTEND=noninteractive dpkg -i "${mysql_deb}" 2>/dev/null
                rm -f "${mysql_deb}"
                pkg_update
                pkg_install mysql-server mysql-client
            fi
            ;;
        dnf|yum)
            # 添加 MySQL 仓库
            local mysql_rpm="/tmp/mysql80-community-release.rpm"
            if ! download_file "https://dev.mysql.com/get/mysql80-community-release-el8-9.noarch.rpm" "${mysql_rpm}"; then
                log_warn "下载 MySQL 仓库配置失败，使用 MariaDB 替代"
                pkg_install mariadb-server mariadb
            else
                rpm -ivh "${mysql_rpm}" 2>/dev/null
                rm -f "${mysql_rpm}"
                # 禁用默认 MySQL 模块，启用 8.0
                dnf module disable mysql -y 2>/dev/null || true
                pkg_install mysql-community-server mysql-community-client
            fi
            ;;
    esac

    # 启动 MySQL
    systemctl start mysql 2>/dev/null || systemctl start mysqld 2>/dev/null || true
    systemctl enable mysql 2>/dev/null || systemctl enable mysqld 2>/dev/null || true

    # 安全配置提示
    log_info "MySQL 安装完成"
    log_warn "请运行 'mysql_secure_installation' 进行安全配置"
    log_warn "首次登录密码请查看: /var/log/mysqld.log 或使用 sudo mysql"
}

verify_mysql() {
    command -v mysql &>/dev/null
}

# ============================================================================
# 安装函数: MongoDB
# ============================================================================
install_mongodb() {
    log_step "安装 MongoDB"

    case "${PKG_MGR}" in
        apt)
            # 导入 MongoDB GPG key
            curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
                gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg 2>/dev/null

            # 添加仓库
            local codename
            codename=$(lsb_release -cs 2>/dev/null || echo "jammy")
            echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${codename}/mongodb-org/7.0 multiverse" \
                > /etc/apt/sources.list.d/mongodb-org-7.0.list

            pkg_update
            pkg_install mongodb-org
            ;;
        dnf|yum)
            cat > /etc/yum.repos.d/mongodb-org-7.0.repo <<'EOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/$releasever/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc
EOF
            pkg_install mongodb-org
            ;;
    esac

    # 启动 MongoDB
    systemctl start mongod 2>/dev/null || true
    systemctl enable mongod 2>/dev/null || true

    # 配置 MongoDB 国内镜像 (用于工具安装)
    append_once "$(get_user_home)/.bashrc" 'export MONGODB_TOOLS_REPO="https://mirrors.tuna.tsinghua.edu.cn/mongodb"'

    log_info "MongoDB 7.0 安装完成"
    log_warn "MongoDB 默认无需密码，生产环境请配置认证"
}

verify_mongodb() {
    command -v mongod &>/dev/null || command -v mongosh &>/dev/null
}

# ============================================================================
# 安装函数: Redis
# ============================================================================
install_redis() {
    log_step "安装 Redis"

    case "${PKG_MGR}" in
        apt)
            # 添加 Redis 仓库
            curl -fsSL https://packages.redis.io/gpg | \
                gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg 2>/dev/null
            echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" \
                > /etc/apt/sources.list.d/redis.list
            pkg_update
            pkg_install redis
            ;;
        dnf|yum)
            pkg_install epel-release 2>/dev/null || true
            pkg_install redis
            ;;
    esac

    # 启动 Redis
    systemctl start redis 2>/dev/null || systemctl start redis-server 2>/dev/null || true
    systemctl enable redis 2>/dev/null || systemctl enable redis-server 2>/dev/null || true

    # 配置 Redis 国内镜像 (用于客户端库)
    append_once "$(get_user_home)/.bashrc" 'export REDIS_CLIENT_REPO="https://mirrors.tuna.tsinghua.edu.cn/redis"'

    log_info "Redis 安装完成"
    log_warn "Redis 默认监听 127.0.0.1:6379，生产环境请配置密码"
}

verify_redis() {
    command -v redis-server &>/dev/null || command -v redis-cli &>/dev/null
}

# ============================================================================
# 安装函数: Git
# ============================================================================
install_git() {
    log_step "安装 Git"

    case "${PKG_MGR}" in
        apt|dnf|yum)
            pkg_install git git-lfs
            ;;
    esac

    local user_home
    user_home="$(get_user_home)"
    local gitconfig="${user_home}/.gitconfig"

    if [[ ! -f "${gitconfig}" ]] || ! grep -q "\[user\]" "${gitconfig}" 2>/dev/null; then
        sudo -u "${REAL_USER}" git config --global init.defaultBranch main
        sudo -u "${REAL_USER}" git config --global core.autocrlf input
    fi

    log_info "Git 安装完成"
}

verify_git() {
    command -v git &>/dev/null
}

# ============================================================================
# 安装函数: Make & CMake
# ============================================================================
install_make() {
    log_step "安装 Make & CMake"

    case "${PKG_MGR}" in
        apt|dnf|yum)
            pkg_install make cmake autoconf automake libtool
            ;;
    esac

    log_info "Make & CMake 安装完成"
}

verify_make() {
    command -v make &>/dev/null && command -v cmake &>/dev/null
}

# ============================================================================
# 通用安装/验证包装器
# ============================================================================
run_language_step() {
    local lang="$1" func_name="$2" verify_func="$3"
    local start_time
    start_time=$(date +%s)

    log_info "开始安装 ${lang}..."

    if "${func_name}"; then
        if "${verify_func}"; then
            local elapsed=$(( $(date +%s) - start_time ))
            log_info "✅ ${lang} 安装成功 (${elapsed}s)"
            return 0
        else
            log_warn "${lang} 安装完成但验证失败"
            log_error_to_file "${lang}" "verify" 1 "installation completed but verification failed"
            return 1
        fi
    else
        local exit_code=$?
        log_error "${lang} 安装失败 (exit code: ${exit_code})"
        log_error_to_file "${lang}" "install" "${exit_code}" "installation function returned non-zero"
        return ${exit_code}
    fi
}

# ============================================================================
# 主流程
# ============================================================================
main() {
    echo ""
    log_info "Linux 开发语言自动安装工具 v2.1"
    echo ""

    # 系统检测
    detect_os
    detect_real_user

    log_info "系统: ${OS_ID} ${OS_VERSION}"
    log_info "架构: ${ARCH}"
    log_info "包管理器: ${PKG_MGR}"
    log_info "用户: ${REAL_USER}"

    # 权限检查
    if ! ${IS_ROOT}; then
        log_error "此脚本需要 root 或 sudo 权限运行"
        log_error "请使用: sudo $0"
        exit 1
    fi

    if [[ "${PKG_MGR}" == "unknown" ]]; then
        log_error "不支持的 Linux 发行版: ${OS_ID}"
        log_error "支持: Ubuntu, Debian, CentOS, RHEL, Rocky, AlmaLinux"
        exit 1
    fi

    # 网络检测与镜像切换
    log_step "网络检测"
    if should_use_mirror; then
        log_warn "检测到网络问题，尝试切换国内镜像源..."
        case "${PKG_MGR}" in
            apt)     switch_apt_mirror ;;
            dnf|yum) switch_yum_mirror ;;
        esac
    else
        log_info "网络连接正常"
    fi

    # 更新包索引
    log_info "更新包索引..."
    pkg_update 2>/dev/null || log_warn "包索引更新失败，继续执行..."

    # 交互式菜单选择
    local selections
    selections=$(show_interactive_menu)

    if [[ -z "${selections}" ]]; then
        log_error "未选择任何项目，退出"
        exit 1
    fi

    # 确认安装
    echo ""
    log_info "将安装: ${selections}"
    read -rp "确认继续? [Y/n]: " confirm
    if [[ "${confirm}" =~ ^[nN] ]]; then
        log_info "用户取消，退出"
        exit 0
    fi

    # 初始化错误日志
    echo "# install-langs.sh 错误日志 - $(date +"${TIMESTAMP_FORMAT}")" > "${ERROR_LOG}"
    echo "# 格式: timestamp level=ERROR lang=xxx phase=xxx exit=xxx msg=\"xxx\"" >> "${ERROR_LOG}"
    echo "" >> "${ERROR_LOG}"

    # 执行安装
    local total=0
    local success=0
    local failed=0
    local failed_list=()

    for lang in ${selections}; do
        ((total++))
        case "${lang}" in
            cpp)
                if run_language_step "C/C++" install_cpp verify_cpp; then ((success++)); else ((failed++)); failed_list+=("C/C++"); fi
                ;;
            python)
                if run_language_step "Python" install_python verify_python; then ((success++)); else ((failed++)); failed_list+=("Python"); fi
                ;;
            node)
                if run_language_step "Node.js" install_node verify_node; then ((success++)); else ((failed++)); failed_list+=("Node.js"); fi
                ;;
            go)
                if run_language_step "Go" install_go verify_go; then ((success++)); else ((failed++)); failed_list+=("Go"); fi
                ;;
            java)
                if run_language_step "Java" install_java verify_java; then ((success++)); else ((failed++)); failed_list+=("Java"); fi
                ;;
            rust)
                if run_language_step "Rust" install_rust verify_rust; then ((success++)); else ((failed++)); failed_list+=("Rust"); fi
                ;;
            docker)
                if run_language_step "Docker" install_docker verify_docker; then ((success++)); else ((failed++)); failed_list+=("Docker"); fi
                ;;
            mysql)
                if run_language_step "MySQL" install_mysql verify_mysql; then ((success++)); else ((failed++)); failed_list+=("MySQL"); fi
                ;;
            mongodb)
                if run_language_step "MongoDB" install_mongodb verify_mongodb; then ((success++)); else ((failed++)); failed_list+=("MongoDB"); fi
                ;;
            redis)
                if run_language_step "Redis" install_redis verify_redis; then ((success++)); else ((failed++)); failed_list+=("Redis"); fi
                ;;
            git)
                if run_language_step "Git" install_git verify_git; then ((success++)); else ((failed++)); failed_list+=("Git"); fi
                ;;
            make)
                if run_language_step "Make & CMake" install_make verify_make; then ((success++)); else ((failed++)); failed_list+=("Make & CMake"); fi
                ;;
        esac
    done

    # 输出汇总
    echo ""
    log_step "安装汇总"
    log_info "总计: ${total}  成功: ${success}  失败: ${failed}"

    if [[ ${failed} -gt 0 ]]; then
        log_warn "失败的项目: ${failed_list[*]}"
        log_warn "详细错误请查看: ${ERROR_LOG}"
    fi

    if [[ ${success} -gt 0 ]]; then
        log_info "请运行 'source ~/.bashrc' 或重新登录以使环境变量生效"
    fi

    echo ""
}

# ============================================================================
# 入口
# ============================================================================
main "$@"
