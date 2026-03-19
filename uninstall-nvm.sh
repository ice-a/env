#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

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

remove_line() {
    local file="$1"
    local line="$2"
    local tmp_file=""

    [[ -f "$file" ]] || return 0

    tmp_file="$(mktemp)"
    awk -v line="$line" '$0 != line { print }' "$file" > "$tmp_file"
    mv "$tmp_file" "$file"
}

main() {
    section "NVM 卸载脚本"

    if [[ -d "$HOME/.nvm" ]]; then
        info "删除 $HOME/.nvm ..."
        rm -rf "$HOME/.nvm"
    else
        warn "目录不存在: $HOME/.nvm"
    fi

    remove_block "$HOME/.bashrc" "# >>> nvm initialize >>>" "# <<< nvm initialize <<<"
    remove_block "$HOME/.zshrc" "# >>> nvm initialize >>>" "# <<< nvm initialize <<<"
    remove_line "$HOME/.profile" 'export NVM_DIR="$HOME/.nvm"'

    if command -v npm >/dev/null 2>&1; then
        npm config delete registry >/dev/null 2>&1 || true
    fi

    success "NVM 卸载流程结束。"
}

main "$@"
