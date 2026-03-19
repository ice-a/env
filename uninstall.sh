#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

usage() {
    cat <<'EOF'
用法:
  bash uninstall.sh                # 交互式选择卸载项
  bash uninstall.sh all            # 卸载全部工具
  bash uninstall.sh docker         # 仅卸载 Docker
  bash uninstall.sh nvm            # 仅卸载 NVM
  bash uninstall.sh mambaconda     # 仅卸载 Mambaconda
  bash uninstall.sh docker nvm     # 卸载多个指定工具
  bash uninstall.sh --help
EOF
}

run_script() {
    local script_name="$1"
    local script_path="$SCRIPT_DIR/$script_name"

    if [[ ! -f "$script_path" ]]; then
        error "未找到脚本: $script_path"
    fi

    section "执行 $script_name"
    bash "$script_path"
}

uninstall_docker() {
    run_script "uninstall-docker.sh"
}

uninstall_nvm() {
    run_script "uninstall-nvm.sh"
}

uninstall_mambaconda() {
    run_script "uninstall-mambaconda.sh"
}

uninstall_targets() {
    local target

    for target in "$@"; do
        case "$target" in
            docker) uninstall_docker ;;
            nvm) uninstall_nvm ;;
            mambaconda) uninstall_mambaconda ;;
            all)
                uninstall_docker
                uninstall_nvm
                uninstall_mambaconda
                ;;
            *)
                error "未知卸载目标: $target"
                ;;
        esac
    done
}

interactive_uninstall() {
    local reply=""
    local selected=()

    section "交互式卸载"

    read -r -p "是否卸载 Docker? [y/N]: " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        selected+=("docker")
    fi

    read -r -p "是否卸载 NVM? [y/N]: " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        selected+=("nvm")
    fi

    read -r -p "是否卸载 Mambaconda? [y/N]: " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        selected+=("mambaconda")
    fi

    if [[ ${#selected[@]} -eq 0 ]]; then
        warn "未选择任何卸载项。"
        return
    fi

    uninstall_targets "${selected[@]}"
    success "所选卸载项已执行完成。"
}

main() {
    section "环境卸载入口"

    if [[ $# -eq 0 ]]; then
        interactive_uninstall
        return
    fi

    case "${1:-}" in
        -h|--help)
            usage
            return
            ;;
    esac

    uninstall_targets "$@"
    success "卸载流程执行完成。"
}

main "$@"
