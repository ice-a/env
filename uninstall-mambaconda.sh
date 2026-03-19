#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

CONDA_PATH="${CONDA_PATH:-$HOME/mambaconda}"

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

success() {
    echo -e "${BLUE}[DONE]${NC} $1"
}

section() {
    echo
    echo -e "${BOLD}${BLUE}== $1 ==${NC}"
}

remove_block() {
    local file="$1"
    local begin="$2"
    local end="$3"
    local tmp_file=""

    [[ -f "$file" ]] || return 0

    tmp_file="$(mktemp)"
    awk -v begin="$begin" -v end="$end" '
        index($0, begin) { skip=1; next }
        index($0, end)   { skip=0; next }
        !skip            { print }
    ' "$file" > "$tmp_file"
    mv "$tmp_file" "$file"
}

main() {
    section "Mambaconda 卸载脚本"

    if [[ -d "$CONDA_PATH" ]]; then
        info "删除 $CONDA_PATH ..."
        rm -rf "$CONDA_PATH"
    else
        warn "目录不存在: $CONDA_PATH"
    fi

    if [[ -f "$HOME/.condarc" ]]; then
        info "删除 $HOME/.condarc ..."
        rm -f "$HOME/.condarc"
    fi

    remove_block "$HOME/.bashrc" "# >>> mambaconda initialize >>>" "# <<< mambaconda initialize <<<"
    remove_block "$HOME/.zshrc" "# >>> mambaconda initialize >>>" "# <<< mambaconda initialize <<<"

    success "Mambaconda 卸载流程结束。"
}

main "$@"
