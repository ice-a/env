#!/usr/bin/env bash
# ============================================================================
# install-langs.sh — Linux 服务器开发环境自动安装工具
# 支持: C/C++, Python, Node.js, Go, Java, Rust, Docker, Git, Make
#       MySQL, MongoDB, Redis
# 特性: 数字选择、命令行参数、国内镜像、错误日志
# ============================================================================
set -u -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ERROR_LOG="${SCRIPT_DIR}/error.log"
TIMESTAMP_FORMAT="%Y-%m-%dT%H:%M:%S%z"

# 镜像源
MIRROR_TUNA="https://mirrors.tuna.tsinghua.edu.cn"
MIRROR_ALIYUN="https://mirrors.aliyun.com"
NPM_MIRROR="https://registry.npmmirror.com"
GO_PROXY="https://goproxy.cn,direct"
NVM_NODE_MIRROR="https://npmmirror.com/mirrors/node"
CONDA_MIRROR="https://github.com/conda-forge/miniforge/releases/latest/download"
RUSTUP_MIRROR="https://mirrors.ustc.edu.cn/rust-static"

OS_ID=""
OS_VERSION=""
PKG_MGR=""
ARCH=""
REAL_USER=""
IS_ROOT=false

declare -a MENU_ITEMS=(
    "cpp|C/C++ (gcc, g++, make, cmake)"
    "python|Python (Miniforge)"
    "node|Node.js (通过 nvm)"
    "go|Go"
    "java|Java (OpenJDK)"
    "rust|Rust (通过 rustup)"
    "docker|Docker"
    "mysql|MySQL"
    "mongodb|MongoDB"
    "redis|Redis"
    "git|Git"
    "make|Make & CMake"
)

log_info() { printf "[INFO]  %s\n" "$*"; }
log_warn() { printf "[WARN]  %s\n" "$*"; }
log_error() { printf "[ERROR] %s\n" "$*"; }
log_step() { printf "\n══════ %s ══════\n" "$*"; }

log_error_to_file() {
    local lang="$1" phase="$2" exit_code="$3" msg="$4"
    local ts
    ts="$(date +"${TIMESTAMP_FORMAT}")"
    echo "${ts} level=ERROR lang=${lang} phase=${phase} exit=${exit_code} msg=\"${msg}\"" >> "${ERROR_LOG}"
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
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
        ubuntu|debian|linuxmint|pop) PKG_MGR="apt" ;;
        centos|rhel|rocky|almalinux|fedora)
            if command -v dnf &>/dev/null; then PKG_MGR="dnf"; else PKG_MGR="yum"; fi ;;
        *) PKG_MGR="unknown" ;;
    esac
    ARCH="$(uname -m)"
}

detect_real_user() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        REAL_USER="${SUDO_USER}"
        IS_ROOT=true
    elif [[ "$(id -u)" -eq 0 ]]; then
        REAL_USER="root"
        IS_ROOT=true
    else
        REAL_USER="$(whoami)"
        IS_ROOT=false
    fi
}

get_user_home() {
    if [[ "${REAL_USER}" == "root" ]]; then echo "/root"; else getent passwd "${REAL_USER}" | cut -d: -f6; fi
}

pkg_update() {
    case "${PKG_MGR}" in
        apt) apt-get update -y ;;
        dnf|yum) dnf check-update -y 2>/dev/null || true ;;
    esac
}

pkg_install() {
    case "${PKG_MGR}" in
        apt) apt-get install -y "$@" ;;
        dnf) dnf install -y "$@" ;;
        yum) yum install -y "$@" ;;
    esac
}

should_use_mirror() {
    ! curl -s --connect-timeout 5 https://www.google.com &>/dev/null
}

switch_apt_mirror() {
    log_info "切换 APT 镜像源到清华 TUNA..."
    local sources="/etc/apt/sources.list"
    if [[ -f "${sources}" ]]; then
        cp "${sources}" "${sources}.bak"
        sed -i "s|http://archive.ubuntu.com|${MIRROR_TUNA}|g" "${sources}"
        sed -i "s|http://security.ubuntu.com|${MIRROR_TUNA}|g" "${sources}"
        apt-get update -y
    fi
}

switch_yum_mirror() {
    log_info "切换 YUM/DNF 镜像源到阿里云..."
    if [[ "${PKG_MGR}" == "dnf" ]]; then
        dnf config-manager --set-disabled base 2>/dev/null || true
        dnf config-manager --add-repo "${MIRROR_ALIYUN}/centos/8/BaseOS/x86_64/os/" 2>/dev/null || true
    fi
}

install_cpp() {
    log_step "安装 C/C++"
    pkg_install gcc g++ gcc-c++ make cmake
    log_info "C/C++ 安装完成"
}
verify_cpp() { command -v gcc &>/dev/null && command -v g++ &>/dev/null; }

install_python() {
    log_step "安装 Python (Miniforge)"
    local user_home="$(get_user_home)"
    local install_dir="${user_home}/miniforge3"
    local installer="/tmp/miniforge.sh"

    if [[ -d "${install_dir}" ]]; then
        log_warn "Miniforge 已安装，跳过"
        return 0
    fi

    log_info "下载 Miniforge..."
    local url="${CONDA_MIRROR}/Miniforge3-Linux-${ARCH}.sh"
    if ! curl -fsSL -o "${installer}" "${url}"; then
        log_error "Miniforge 下载失败: ${url}"
        return 1
    fi

    log_info "安装 Miniforge 到 ${install_dir}..."
    if ! bash "${installer}" -b -p "${install_dir}"; then
        log_error "Miniforge 安装失败"
        return 1
    fi
    rm -f "${installer}"

    sudo -u "${REAL_USER}" "${install_dir}/bin/conda" config --system --set channel_priority strict 2>/dev/null || true
    sudo -u "${REAL_USER}" "${install_dir}/bin/conda" config --system --add channels conda-forge 2>/dev/null || true
    sudo -u "${REAL_USER}" "${install_dir}/bin/conda" init bash 2>/dev/null || true
    log_info "Miniforge 安装完成"
}
verify_python() { [[ -f "$(get_user_home)/miniforge3/bin/python" ]]; }

install_node() {
    log_step "安装 Node.js"
    local user_home="$(get_user_home)"
    if [[ -d "${user_home}/.nvm" ]]; then log_warn "nvm 已安装，跳过"; return 0; fi

    log_info "安装 nvm..."
    sudo -u "${REAL_USER}" curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | sudo -u "${REAL_USER}" bash

    export NVM_DIR="${user_home}/.nvm"
    [ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"
    nvm install --lts
    log_info "Node.js 安装完成"
}
verify_node() { [[ -d "$(get_user_home)/.nvm" ]] && command -v node &>/dev/null; }

install_go() {
    log_step "安装 Go"
    local install_dir="/usr/local"
    if [[ -f "${install_dir}/go/bin/go" ]]; then log_warn "Go 已安装，跳过"; return 0; fi

    log_info "下载 Go..."
    local go_url="https://go.dev/dl/go1.22.4.linux-${ARCH}.tar.gz"
    local tarball="/tmp/go.tar.gz"
    if ! curl -fsSL -o "${tarball}" "${go_url}"; then log_error "Go 下载失败"; return 1; fi

    log_info "解压 Go..."
    rm -rf "${install_dir}/go"
    tar -C "${install_dir}" -xzf "${tarball}"
    rm -f "${tarball}"

    cat > /etc/profile.d/go.sh << 'GOEOF'
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
export GO_PROXY=goproxy.cn,direct
GOEOF
    log_info "Go 安装完成"
}
verify_go() { command -v go &>/dev/null; }

install_java() {
    log_step "安装 Java"
    case "${PKG_MGR}" in
        apt) pkg_install openjdk-17-jdk ;;
        dnf|yum) pkg_install java-17-openjdk-devel ;;
    esac
    log_info "Java 安装完成"
}
verify_java() { command -v java &>/dev/null; }

install_rust() {
    log_step "安装 Rust"
    local user_home="$(get_user_home)"
    if [[ -d "${user_home}/.cargo" ]]; then log_warn "Rust 已安装，跳过"; return 0; fi

    log_info "安装 rustup..."
    sudo -u "${REAL_USER}" curl --proto '=https' --tlsv1.2 -fsSL "https://rsproxy.cn/rustup-init.sh" -o /tmp/rustup-init.sh
    sudo -u "${REAL_USER}" bash /tmp/rustup-init.sh -y --default-host "${ARCH}-unknown-linux-gnu"
    rm -f /tmp/rustup-init.sh
    log_info "Rust 安装完成"
}
verify_rust() { [[ -f "$(get_user_home)/.cargo/bin/rustc" ]]; }

install_docker() {
    log_step "安装 Docker"
    if command -v docker &>/dev/null; then log_warn "Docker 已安装，跳过"; return 0; fi

    case "${PKG_MGR}" in
        apt)
            pkg_install apt-transport-https ca-certificates curl gnupg lsb-release
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update -y
            pkg_install docker-ce docker-ce-cli containerd.io
            ;;
        dnf|yum)
            pkg_install yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            pkg_install docker-ce docker-ce-cli containerd.io
            ;;
    esac
    systemctl enable docker 2>/dev/null || true
    systemctl start docker 2>/dev/null || true
    [[ -n "${SUDO_USER:-}" ]] && usermod -aG docker "${SUDO_USER}"
    log_info "Docker 安装完成"
}
verify_docker() { command -v docker &>/dev/null; }

install_mysql() {
    log_step "安装 MySQL"
    pkg_install mysql-server
    systemctl enable mysqld 2>/dev/null || true
    systemctl start mysqld 2>/dev/null || true
    log_info "MySQL 安装完成"
}
verify_mysql() { command -v mysql &>/dev/null; }

install_mongodb() {
    log_step "安装 MongoDB"
    case "${PKG_MGR}" in
        apt)
            pkg_install gnupg curl
            curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
            echo "deb [signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list
            apt-get update -y
            pkg_install mongodb-org
            ;;
        dnf|yum)
            cat > /etc/yum.repos.d/mongodb-org-7.0.repo << 'MONGOEOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc
MONGOEOF
            pkg_install mongodb-org
            ;;
    esac
    systemctl enable mongod 2>/dev/null || true
    systemctl start mongod 2>/dev/null || true
    log_info "MongoDB 安装完成"
}
verify_mongodb() { command -v mongod &>/dev/null; }

install_redis() {
    log_step "安装 Redis"
    pkg_install redis
    systemctl enable redis 2>/dev/null || systemctl enable redis-server 2>/dev/null || true
    systemctl start redis 2>/dev/null || systemctl start redis-server 2>/dev/null || true
    log_info "Redis 安装完成"
}
verify_redis() { command -v redis-server &>/dev/null; }

install_git() {
    log_step "安装 Git"
    pkg_install git
    sudo -u "${REAL_USER}" git config --global init.defaultBranch main
    sudo -u "${REAL_USER}" git config --global core.autocrlf input
    log_info "Git 安装完成"
}
verify_git() { command -v git &>/dev/null; }

install_make() {
    log_step "安装 Make & CMake"
    pkg_install make cmake autoconf automake libtool
    log_info "Make & CMake 安装完成"
}
verify_make() { command -v make &>/dev/null && command -v cmake &>/dev/null; }

run_language_step() {
    local lang="$1" func_name="$2" verify_func="$3"
    local start_time=$(date +%s)

    log_info "开始安装 ${lang}..."
    if "${func_name}"; then
        if "${verify_func}"; then
            local elapsed=$(( $(date +%s) - start_time ))
            log_info "✅ ${lang} 安装成功 (${elapsed}s)"
            return 0
        else
            log_warn "${lang} 安装完成但验证失败"
            log_error_to_file "${lang}" "verify" 1 "verification failed"
            return 1
        fi
    else
        local exit_code=$?
        log_error "${lang} 安装失败 (exit: ${exit_code})"
        log_error_to_file "${lang}" "install" "${exit_code}" "installation failed"
        return ${exit_code}
    fi
}

show_number_menu() {
    echo ""
    printf "  ╔══════════════════════════════════════════════════════╗\n"
    printf "  ║        Linux 开发环境自动安装工具                   ║\n"
    printf "  ╚══════════════════════════════════════════════════════╝\n"
    echo ""
    printf "  输入要安装的项目编号（空格分隔），或直接回车安装全部\n"
    echo ""
    printf "  示例: 1 2 3  或  1-5  或  all\n"
    echo ""

    local total=${#MENU_ITEMS[@]}
    for ((i=0; i<total; i++)); do
        IFS='|' read -r key desc <<< "${MENU_ITEMS[i]}"
        printf "  %2d) %s\n" "$((i+1))" "${desc}"
    done

    echo ""
    printf "  请输入: "
}

parse_selection() {
    local input="$1"
    local total=${#MENU_ITEMS[@]}
    local selections=()

    if [[ -z "${input}" || "${input}" == "all" ]]; then
        for ((i=0; i<total; i++)); do
            IFS='|' read -r key _ <<< "${MENU_ITEMS[i]}"
            selections+=("${key}")
        done
        echo "${selections[*]}"
        return
    fi

    IFS=' ' read -ra parts <<< "${input}"
    for part in "${parts[@]}"; do
        if [[ "${part}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start="${BASH_REMATCH[1]}"
            local end="${BASH_REMATCH[2]}"
            for ((i=start; i<=end; i++)); do
                if [[ ${i} -ge 1 && ${i} -le ${total} ]]; then
                    IFS='|' read -r key _ <<< "${MENU_ITEMS[i-1]}"
                    selections+=("${key}")
                fi
            done
        elif [[ "${part}" =~ ^[0-9]+$ ]]; then
            if [[ ${part} -ge 1 && ${part} -le ${total} ]]; then
                IFS='|' read -r key _ <<< "${MENU_ITEMS[part-1]}"
                selections+=("${key}")
            fi
        fi
    done
    echo "${selections[*]}"
}

usage() {
    cat << 'USAGEEOF'
用法: sudo ./install-langs.sh [选项]

选项:
  -h, --help     显示帮助
  -i, --items    要安装的项目（逗号分隔或编号）
  -y, --yes      跳过确认

示例:
  sudo ./install-langs.sh              # 交互式选择
  sudo ./install-langs.sh -i 1,2,3     # 安装编号 1,2,3
  sudo ./install-langs.sh -i cpp,go    # 安装指定项目
  sudo ./install-langs.sh -i all -y    # 全部安装，跳过确认

USAGEEOF
    echo "可用项目:"
    local total=${#MENU_ITEMS[@]}
    for ((i=0; i<total; i++)); do
        IFS='|' read -r key desc <<< "${MENU_ITEMS[i]}"
        printf "  %2d) %-10s %s\n" "$((i+1))" "${key}" "${desc}"
    done
}

main() {
    local selections=""
    local auto_confirm=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -i|--items)
                if [[ -n "${2:-}" ]]; then selections="$2"; shift 2
                else log_error "-i 需要参数"; exit 1; fi
                ;;
            -y|--yes) auto_confirm=true; shift ;;
            *) log_error "未知选项: $1"; usage; exit 1 ;;
        esac
    done

    echo ""
    log_info "Linux 开发环境自动安装工具 v2.0"
    echo ""

    detect_os
    detect_real_user

    log_info "系统: ${OS_ID} ${OS_VERSION}"
    log_info "架构: ${ARCH}"
    log_info "包管理器: ${PKG_MGR}"
    log_info "用户: ${REAL_USER}"

    if ! ${IS_ROOT}; then
        log_error "需要 root 权限运行: sudo $0"
        exit 1
    fi

    if [[ "${PKG_MGR}" == "unknown" ]]; then
        log_error "不支持的系统: ${OS_ID}"
        exit 1
    fi

    log_step "网络检测"
    if should_use_mirror; then
        log_warn "网络问题，切换国内镜像..."
        case "${PKG_MGR}" in
            apt) switch_apt_mirror ;;
            dnf|yum) switch_yum_mirror ;;
        esac
    else
        log_info "网络正常"
    fi

    log_info "更新包索引..."
    pkg_update 2>/dev/null || log_warn "包索引更新失败"

    if [[ -z "${selections}" ]]; then
        show_number_menu
        read -r input
        selections=$(parse_selection "${input}")
    else
        selections=$(parse_selection "${selections//,/ }")
    fi

    if [[ -z "${selections}" ]]; then
        log_error "未选择任何项目"
        exit 1
    fi

    echo ""
    log_info "将安装: ${selections}"

    if ! ${auto_confirm}; then
        read -rp "确认继续? [Y/n]: " confirm
        [[ "${confirm}" =~ ^[nN] ]] && { log_info "已取消"; exit 0; }
    fi

    echo "# 错误日志 - $(date +"${TIMESTAMP_FORMAT}")" > "${ERROR_LOG}"
    echo "" >> "${ERROR_LOG}"

    local total=0 success=0 failed=0 failed_list=()

    for lang in ${selections}; do
        ((total++))
        case "${lang}" in
            cpp) run_language_step "C/C++" install_cpp verify_cpp && ((success++)) || { ((failed++)); failed_list+=("C/C++"); } ;;
            python) run_language_step "Python" install_python verify_python && ((success++)) || { ((failed++)); failed_list+=("Python"); } ;;
            node) run_language_step "Node.js" install_node verify_node && ((success++)) || { ((failed++)); failed_list+=("Node.js"); } ;;
            go) run_language_step "Go" install_go verify_go && ((success++)) || { ((failed++)); failed_list+=("Go"); } ;;
            java) run_language_step "Java" install_java verify_java && ((success++)) || { ((failed++)); failed_list+=("Java"); } ;;
            rust) run_language_step "Rust" install_rust verify_rust && ((success++)) || { ((failed++)); failed_list+=("Rust"); } ;;
            docker) run_language_step "Docker" install_docker verify_docker && ((success++)) || { ((failed++)); failed_list+=("Docker"); } ;;
            mysql) run_language_step "MySQL" install_mysql verify_mysql && ((success++)) || { ((failed++)); failed_list+=("MySQL"); } ;;
            mongodb) run_language_step "MongoDB" install_mongodb verify_mongodb && ((success++)) || { ((failed++)); failed_list+=("MongoDB"); } ;;
            redis) run_language_step "Redis" install_redis verify_redis && ((success++)) || { ((failed++)); failed_list+=("Redis"); } ;;
            git) run_language_step "Git" install_git verify_git && ((success++)) || { ((failed++)); failed_list+=("Git"); } ;;
            make) run_language_step "Make & CMake" install_make verify_make && ((success++)) || { ((failed++)); failed_list+=("Make & CMake"); } ;;
        esac
    done

    echo ""
    log_step "安装汇总"
    log_info "总计: ${total}  成功: ${success}  失败: ${failed}"

    if [[ ${failed} -gt 0 ]]; then
        log_warn "失败: ${failed_list[*]}"
        log_warn "错误日志: ${ERROR_LOG}"
    fi

    [[ ${success} -gt 0 ]] && log_info "请运行 'source ~/.bashrc' 使环境生效"
    echo ""
}

main "$@"
