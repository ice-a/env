#!/usr/bin/env bash
set -u -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ERROR_LOG="${SCRIPT_DIR}/error.log"
ACTION="install"

MIRROR_TUNA="https://mirrors.tuna.tsinghua.edu.cn"
MIRROR_ALIYUN="https://mirrors.aliyun.com"
NPM_REGISTRY="https://registry.npmmirror.com"
NODE_MIRROR="https://npmmirror.com/mirrors/node"
GO_PROXY="https://goproxy.cn,direct"
RUSTUP_DIST_SERVER="https://mirrors.ustc.edu.cn/rust-static"
RUSTUP_UPDATE_ROOT="https://mirrors.ustc.edu.cn/rust-static/rustup"
MINIFORGE_GITHUB="https://github.com/conda-forge/miniforge/releases/latest/download"
MINIFORGE_FALLBACK="${MIRROR_TUNA}/github-release/conda-forge/miniforge/LatestRelease"
NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh"
G_INSTALL_URL="https://raw.githubusercontent.com/voidint/g/master/install.sh"

OS_ID=""
OS_VERSION=""
PKG_MGR=""
ARCH=""
REAL_USER=""
REAL_HOME=""
IS_ROOT=false
MENU_CURSOR=0
declare -A MENU_SELECTED=()

declare -a MENU_ITEMS=(
  "c|C/C++ build tools|1"
  "python|Python + pip|1"
  "javascript|JavaScript / Node.js via nvm|1"
  "rust|Rust via rustup|1"
  "go|Go official binary|1"
  "java|Java OpenJDK|1"
  "docker|Docker Engine|1"
  "mysql|MySQL / MariaDB|0"
  "mongodb|MongoDB|0"
  "redis|Redis|0"
  "git|Git + Git LFS|1"
  "nvm|nvm manager|0"
  "g|g Go version manager|0"
  "miniforge|Miniforge conda manager|0"
)

log_info() { printf "[INFO]  %s\n" "$*"; }
log_warn() { printf "[WARN]  %s\n" "$*"; }
log_error() { printf "[ERROR] %s\n" "$*"; }
log_step() { printf "\n==== %s ====\n" "$*"; }

write_error() {
  local item="$1" phase="$2" code="$3" msg="$4"
  printf "%s level=ERROR item=%s phase=%s exit=%s msg=\"%s\"\n" \
    "$(date +%Y-%m-%dT%H:%M:%S%z)" "$item" "$phase" "$code" "$msg" >>"$ERROR_LOG"
}

usage() {
  cat <<'EOF'
Usage:
  sudo ./dev-env.sh [--install|--uninstall]

Options:
  --install      Install selected tools. This is the default.
  --uninstall    Uninstall selected tools.
  -h, --help     Show this help.

Keys:
  Up / Down      Move cursor
  Space          Select / unselect
  a / A          Select all / unselect all
  Enter          Confirm
EOF
}

detect_os() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-unknown}"
  else
    OS_ID="unknown"
    OS_VERSION="unknown"
  fi

  case "$OS_ID" in
    ubuntu|debian|linuxmint|pop) PKG_MGR="apt" ;;
    centos|rhel|rocky|almalinux|fedora)
      if command -v dnf >/dev/null 2>&1; then PKG_MGR="dnf"; else PKG_MGR="yum"; fi
      ;;
    *) PKG_MGR="unknown" ;;
  esac

  case "$(uname -m)" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) ARCH="unknown" ;;
  esac
}

detect_user() {
  if [[ "$(id -u)" -eq 0 ]]; then
    IS_ROOT=true
    REAL_USER="${SUDO_USER:-root}"
  else
    IS_ROOT=false
    REAL_USER="$(whoami)"
  fi

  if [[ "$REAL_USER" == "root" ]]; then
    REAL_HOME="/root"
  else
    REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
  fi

  if [[ -z "$REAL_HOME" ]]; then
    REAL_HOME="$(eval echo "~${REAL_USER}")"
  fi
}

require_root() {
  if ! $IS_ROOT; then
    log_error "Please run with sudo/root: sudo ./dev-env.sh"
    exit 1
  fi
  if [[ "$PKG_MGR" == "unknown" ]]; then
    log_error "Unsupported Linux distribution: $OS_ID"
    exit 1
  fi
}

run_as_user() {
  if [[ "$REAL_USER" == "root" ]]; then
    "$@"
  else
    sudo -u "$REAL_USER" HOME="$REAL_HOME" "$@"
  fi
}

pkg_update() {
  case "$PKG_MGR" in
    apt) DEBIAN_FRONTEND=noninteractive apt-get update -y ;;
    dnf) dnf makecache -y ;;
    yum) yum makecache -y ;;
  esac
}

pkg_install() {
  case "$PKG_MGR" in
    apt) DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf) dnf install -y "$@" ;;
    yum) yum install -y "$@" ;;
  esac
}

pkg_remove() {
  case "$PKG_MGR" in
    apt) DEBIAN_FRONTEND=noninteractive apt-get remove -y "$@" 2>/dev/null || true ;;
    dnf) dnf remove -y "$@" 2>/dev/null || true ;;
    yum) yum remove -y "$@" 2>/dev/null || true ;;
  esac
}

append_once() {
  local file="$1" line="$2"
  touch "$file"
  if ! grep -qF "$line" "$file" 2>/dev/null; then
    printf "%s\n" "$line" >>"$file"
  fi
}

download_file() {
  local url="$1" output="$2"
  local i
  for i in 1 2; do
    if curl -fsSL --connect-timeout 10 --max-time 300 -o "$output" "$url"; then
      return 0
    fi
    log_warn "Download failed (${i}/2): $url"
    sleep 2
  done
  return 1
}

download_first_available() {
  local output="$1"
  shift
  local url
  for url in "$@"; do
    [[ -n "$url" ]] || continue
    log_info "Downloading from: $url"
    if download_file "$url" "$output"; then
      return 0
    fi
    log_warn "Source unavailable, trying fallback"
  done
  return 1
}

init_menu() {
  local item key desc selected
  for item in "${MENU_ITEMS[@]}"; do
    IFS='|' read -r key desc selected <<<"$item"
    MENU_SELECTED["$key"]="$selected"
  done
}

draw_menu() {
  local total="${#MENU_ITEMS[@]}"
  local i item key desc selected_count=0

  printf '\033[2J\033[H' >/dev/tty
  printf "\n  Linux Dev Environment %s\n\n" "$ACTION" >/dev/tty
  printf "  ↑ ↓  移动光标    空格  选中/取消选中    a / A  全选 / 全不选    Enter  确认%s\n\n" "$([[ "$ACTION" == install ]] && echo 安装 || echo 卸载)" >/dev/tty

  for ((i=0; i<total; i++)); do
    IFS='|' read -r key desc _ <<<"${MENU_ITEMS[i]}"
    if [[ "${MENU_SELECTED[$key]:-0}" == "1" ]]; then
      selected_count=$((selected_count + 1))
    fi

    if [[ "$i" -eq "$MENU_CURSOR" ]]; then
      printf "  > " >/dev/tty
    else
      printf "    " >/dev/tty
    fi

    if [[ "${MENU_SELECTED[$key]:-0}" == "1" ]]; then
      printf "[*] %s\n" "$desc" >/dev/tty
    else
      printf "[ ] %s\n" "$desc" >/dev/tty
    fi
  done

  printf "\n  已选中: %d\n\n" "$selected_count" >/dev/tty
}

show_menu() {
  init_menu
  draw_menu

  local key rest current_key item k total="${#MENU_ITEMS[@]}"
  while true; do
    if ! IFS= read -r -s -n1 key </dev/tty; then
      key=""
    fi

    if [[ "$key" == $'\033' ]]; then
      IFS= read -r -s -n2 -t 0.1 rest </dev/tty 2>/dev/null || true
      case "$rest" in
        "[A") MENU_CURSOR=$(( (MENU_CURSOR - 1 + total) % total )) ;;
        "[B") MENU_CURSOR=$(( (MENU_CURSOR + 1) % total )) ;;
      esac
    elif [[ "$key" == " " ]]; then
      IFS='|' read -r current_key _ _ <<<"${MENU_ITEMS[MENU_CURSOR]}"
      if [[ "${MENU_SELECTED[$current_key]:-0}" == "1" ]]; then
        MENU_SELECTED["$current_key"]=0
      else
        MENU_SELECTED["$current_key"]=1
      fi
    elif [[ "$key" == "a" ]]; then
      for item in "${MENU_ITEMS[@]}"; do
        IFS='|' read -r k _ _ <<<"$item"
        MENU_SELECTED["$k"]=1
      done
    elif [[ "$key" == "A" ]]; then
      for item in "${MENU_ITEMS[@]}"; do
        IFS='|' read -r k _ _ <<<"$item"
        MENU_SELECTED["$k"]=0
      done
    elif [[ "$key" == $'\n' || "$key" == $'\r' || -z "$key" ]]; then
      break
    fi

    draw_menu
  done

  local selected=()
  for item in "${MENU_ITEMS[@]}"; do
    IFS='|' read -r k _ _ <<<"$item"
    if [[ "${MENU_SELECTED[$k]:-0}" == "1" ]]; then
      selected+=("$k")
    fi
  done

  printf "\n" >/dev/tty
  echo "${selected[*]}"
}

install_c() {
  log_step "Install C/C++ build tools"
  case "$PKG_MGR" in
    apt) pkg_install build-essential gcc g++ make cmake gdb pkg-config ;;
    dnf|yum)
      dnf groupinstall -y "Development Tools" 2>/dev/null || yum groupinstall -y "Development Tools" 2>/dev/null || true
      pkg_install gcc gcc-c++ make cmake gdb pkgconfig
      ;;
  esac
}

install_python() {
  log_step "Install Python"
  case "$PKG_MGR" in
    apt) pkg_install python3 python3-pip python3-venv python3-dev ;;
    dnf|yum) pkg_install python3 python3-pip python3-devel ;;
  esac
  mkdir -p "$REAL_HOME/.config/pip"
  printf "[global]\nindex-url = %s/pypi/web/simple\ntrusted-host = mirrors.tuna.tsinghua.edu.cn\n" "$MIRROR_TUNA" >"$REAL_HOME/.config/pip/pip.conf"
  chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config" 2>/dev/null || true
}

install_nvm() {
  log_step "Install nvm"
  if [[ -s "$REAL_HOME/.nvm/nvm.sh" ]]; then
    log_info "nvm already exists"
    return 0
  fi
  local installer="/tmp/nvm-install.sh"
  if ! download_file "$NVM_INSTALL_URL" "$installer"; then
    log_error "nvm install script download failed"
    return 1
  fi
  run_as_user bash "$installer"
  rm -f "$installer"
}

install_javascript() {
  log_step "Install JavaScript / Node.js"
  install_nvm
  local nvm_dir="$REAL_HOME/.nvm"
  run_as_user bash -lc "export NVM_DIR='$nvm_dir'; [ -s '$nvm_dir/nvm.sh' ] && . '$nvm_dir/nvm.sh'; export NVM_NODEJS_ORG_MIRROR='$NODE_MIRROR'; nvm install --lts || { export NVM_NODEJS_ORG_MIRROR='https://nodejs.org/dist'; nvm install --lts; }; nvm alias default lts/*; npm config set registry '$NPM_REGISTRY'"
}

install_rust() {
  log_step "Install Rust"
  if [[ -x "$REAL_HOME/.cargo/bin/rustc" ]]; then
    log_info "Rust already exists"
    return 0
  fi
  local installer="/tmp/rustup-init.sh"
  if ! download_file "https://sh.rustup.rs" "$installer"; then
    log_error "rustup installer download failed"
    return 1
  fi
  run_as_user env RUSTUP_DIST_SERVER="$RUSTUP_DIST_SERVER" RUSTUP_UPDATE_ROOT="$RUSTUP_UPDATE_ROOT" bash "$installer" -y --default-toolchain stable
  mkdir -p "$REAL_HOME/.cargo"
  cat >"$REAL_HOME/.cargo/config.toml" <<EOF
[source.crates-io]
replace-with = 'ustc'

[source.ustc]
registry = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"
EOF
  chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.cargo" "$REAL_HOME/.rustup" 2>/dev/null || true
}

install_go() {
  log_step "Install Go"
  local version tarball url mirror output
  version="$(curl -fsSL --connect-timeout 8 https://go.dev/VERSION?m=text 2>/dev/null | head -1 || true)"
  version="${version:-go1.22.4}"
  tarball="${version}.linux-${ARCH}.tar.gz"
  url="https://go.dev/dl/${tarball}"
  mirror="${MIRROR_ALIYUN}/golang/${tarball}"
  output="/tmp/${tarball}"

  if ! download_first_available "$output" "$url" "$mirror"; then
    log_error "Go download failed"
    return 1
  fi

  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$output"
  rm -f "$output"
  cat >/etc/profile.d/go.sh <<'EOF'
export GOROOT=/usr/local/go
export GOPATH=${HOME}/go
export PATH=${GOROOT}/bin:${GOPATH}/bin:${PATH}
export GOPROXY=https://goproxy.cn,direct
EOF
  append_once "$REAL_HOME/.bashrc" 'export PATH="/usr/local/go/bin:${PATH}"'
  append_once "$REAL_HOME/.bashrc" 'export GOPATH="${HOME}/go"'
  append_once "$REAL_HOME/.bashrc" 'export PATH="${GOPATH}/bin:${PATH}"'
  append_once "$REAL_HOME/.bashrc" "export GOPROXY=${GO_PROXY}"
  chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.bashrc" 2>/dev/null || true
}

install_g() {
  log_step "Install g Go version manager"
  local installer="/tmp/g-install.sh"
  if ! download_file "$G_INSTALL_URL" "$installer"; then
    log_error "g installer download failed"
    return 1
  fi
  run_as_user bash "$installer"
  rm -f "$installer"
}

install_java() {
  log_step "Install Java"
  case "$PKG_MGR" in
    apt) pkg_install openjdk-17-jdk || pkg_install default-jdk ;;
    dnf|yum) pkg_install java-17-openjdk-devel ;;
  esac
}

install_docker() {
  log_step "Install Docker"
  if command -v docker >/dev/null 2>&1; then
    log_info "Docker already exists"
    return 0
  fi
  case "$PKG_MGR" in
    apt)
      pkg_install ca-certificates curl gnupg lsb-release
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      chmod a+r /etc/apt/keyrings/docker.gpg
      local codename
      codename="$(lsb_release -cs 2>/dev/null || echo jammy)"
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" >/etc/apt/sources.list.d/docker.list
      pkg_update
      pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    dnf|yum)
      pkg_install yum-utils
      yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null || dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
  esac
  systemctl enable --now docker 2>/dev/null || true
  usermod -aG docker "$REAL_USER" 2>/dev/null || true
}

install_mysql() {
  log_step "Install MySQL / MariaDB"
  case "$PKG_MGR" in
    apt) pkg_install mysql-server mysql-client || pkg_install mariadb-server mariadb-client ;;
    dnf|yum) pkg_install mysql-server mysql || pkg_install mariadb-server mariadb ;;
  esac
  systemctl enable --now mysql 2>/dev/null || systemctl enable --now mysqld 2>/dev/null || systemctl enable --now mariadb 2>/dev/null || true
}

install_mongodb() {
  log_step "Install MongoDB"
  case "$PKG_MGR" in
    apt)
      pkg_install gnupg curl
      curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
      local codename
      codename="$(lsb_release -cs 2>/dev/null || echo jammy)"
      echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${codename}/mongodb-org/7.0 multiverse" >/etc/apt/sources.list.d/mongodb-org-7.0.list
      pkg_update
      pkg_install mongodb-org
      ;;
    dnf|yum)
      cat >/etc/yum.repos.d/mongodb-org-7.0.repo <<'EOF'
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
  systemctl enable --now mongod 2>/dev/null || true
}

install_redis() {
  log_step "Install Redis"
  case "$PKG_MGR" in
    apt) pkg_install redis-server redis-tools || pkg_install redis ;;
    dnf|yum) pkg_install epel-release 2>/dev/null || true; pkg_install redis ;;
  esac
  systemctl enable --now redis-server 2>/dev/null || systemctl enable --now redis 2>/dev/null || true
}

install_git() {
  log_step "Install Git"
  pkg_install git git-lfs
  run_as_user git config --global init.defaultBranch main 2>/dev/null || true
  run_as_user git config --global core.autocrlf input 2>/dev/null || true
}

install_miniforge() {
  log_step "Install Miniforge"
  if [[ -x "$REAL_HOME/miniforge3/bin/conda" ]]; then
    log_info "Miniforge already exists"
    return 0
  fi
  local arch_name installer_name installer github fallback
  case "$ARCH" in
    amd64) arch_name="x86_64" ;;
    arm64) arch_name="aarch64" ;;
    *) log_error "Unsupported architecture for Miniforge: $ARCH"; return 1 ;;
  esac
  installer_name="Miniforge3-Linux-${arch_name}.sh"
  installer="/tmp/${installer_name}"
  github="${MINIFORGE_GITHUB}/${installer_name}"
  fallback="${MINIFORGE_FALLBACK}/${installer_name}"
  if ! download_first_available "$installer" "$github" "$fallback"; then
    log_error "Miniforge download failed"
    return 1
  fi
  run_as_user bash "$installer" -b -p "$REAL_HOME/miniforge3"
  rm -f "$installer"
  run_as_user "$REAL_HOME/miniforge3/bin/conda" init bash 2>/dev/null || true
}

uninstall_c() {
  log_step "Uninstall C/C++ build tools"
  pkg_remove build-essential gcc g++ gcc-c++ make cmake gdb pkg-config pkgconfig
}

uninstall_python() {
  log_step "Uninstall Python"
  pkg_remove python3-pip python3-venv python3-dev python3-devel
}

uninstall_nvm() {
  log_step "Uninstall nvm"
  rm -rf "$REAL_HOME/.nvm"
}

uninstall_javascript() {
  log_step "Uninstall JavaScript / Node.js"
  uninstall_nvm
}

uninstall_rust() {
  log_step "Uninstall Rust"
  if [[ -x "$REAL_HOME/.cargo/bin/rustup" ]]; then
    run_as_user "$REAL_HOME/.cargo/bin/rustup" self uninstall -y 2>/dev/null || true
  fi
  rm -rf "$REAL_HOME/.cargo" "$REAL_HOME/.rustup"
}

uninstall_go() {
  log_step "Uninstall Go"
  rm -rf /usr/local/go
  rm -f /etc/profile.d/go.sh
}

uninstall_g() {
  log_step "Uninstall g Go version manager"
  rm -rf "$REAL_HOME/.g"
}

uninstall_java() {
  log_step "Uninstall Java"
  pkg_remove openjdk-17-jdk default-jdk java-17-openjdk-devel
}

uninstall_docker() {
  log_step "Uninstall Docker"
  systemctl stop docker 2>/dev/null || true
  pkg_remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker docker.io
  rm -f /etc/apt/sources.list.d/docker.list /etc/yum.repos.d/docker-ce.repo
}

uninstall_mysql() {
  log_step "Uninstall MySQL / MariaDB"
  systemctl stop mysql 2>/dev/null || systemctl stop mysqld 2>/dev/null || systemctl stop mariadb 2>/dev/null || true
  pkg_remove mysql-server mysql-client mysql-community-server mysql-community-client mariadb-server mariadb mariadb-client
}

uninstall_mongodb() {
  log_step "Uninstall MongoDB"
  systemctl stop mongod 2>/dev/null || true
  pkg_remove mongodb-org
  rm -f /etc/apt/sources.list.d/mongodb-org-7.0.list /etc/yum.repos.d/mongodb-org-7.0.repo
}

uninstall_redis() {
  log_step "Uninstall Redis"
  systemctl stop redis-server 2>/dev/null || systemctl stop redis 2>/dev/null || true
  pkg_remove redis redis-server redis-tools
}

uninstall_git() {
  log_step "Uninstall Git"
  pkg_remove git git-lfs
}

uninstall_miniforge() {
  log_step "Uninstall Miniforge"
  rm -rf "$REAL_HOME/miniforge3"
}

run_item() {
  local item="$1"
  local fn="${ACTION}_${item}"
  local start code
  start="$(date +%s)"

  if ! declare -F "$fn" >/dev/null 2>&1; then
    log_error "No handler: $fn"
    return 1
  fi

  if "$fn"; then
    log_info "$item ${ACTION} complete ($(( $(date +%s) - start ))s)"
    return 0
  fi

  code=$?
  write_error "$item" "$ACTION" "$code" "handler failed"
  return "$code"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --install) ACTION="install"; shift ;;
      --uninstall|--remove) ACTION="uninstall"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
  done
}

main() {
  parse_args "$@"
  detect_os
  detect_user
  require_root

  log_info "System: ${OS_ID} ${OS_VERSION}, package manager: ${PKG_MGR}, arch: ${ARCH}, user: ${REAL_USER}"
  log_info "Updating package index..."
  pkg_update 2>/dev/null || log_warn "Package index update failed, continuing"

  local selections confirm item total=0 ok=0 fail=0 failed_items=()
  selections="$(show_menu)"

  if [[ -z "$selections" ]]; then
    log_error "No item selected"
    exit 1
  fi

  log_info "Selected for ${ACTION}: ${selections}"
  read -rp "Confirm ${ACTION}? [Y/n]: " confirm
  if [[ "$confirm" =~ ^[nN] ]]; then
    log_info "Cancelled"
    exit 0
  fi

  printf "# dev-env.sh error log - %s\n\n" "$(date +%Y-%m-%dT%H:%M:%S%z)" >"$ERROR_LOG"

  for item in $selections; do
    total=$((total + 1))
    if run_item "$item"; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1))
      failed_items+=("$item")
    fi
  done

  log_step "Summary"
  log_info "Total: $total  OK: $ok  Failed: $fail"
  if [[ "$fail" -gt 0 ]]; then
    log_warn "Failed items: ${failed_items[*]}"
    log_warn "See: $ERROR_LOG"
  fi
  if [[ "$ACTION" == "install" && "$ok" -gt 0 ]]; then
    log_info "Run 'source ~/.bashrc' or log in again to refresh PATH"
  fi
}

main "$@"
