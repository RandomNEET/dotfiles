#!/usr/bin/env bash
# Usage:
#   bash termux/install.sh [--prepare-only]
set -euo pipefail

if [[ "${PREFIX:-}" != /data/data/com.termux/files/usr ]] || ! command -v pkg >/dev/null; then
  echo 'This installer requires Termux.' >&2
  exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err() { echo -e "${RED}[ERR]${NC}   $*"; }
step() { echo -e "\n${CYAN}==>${NC} ${CYAN}$*${NC}"; }

CHEZMOI_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# prerequisites
step "Ensuring prerequisites"

for cmd in git chezmoi; do
  if ! command -v "$cmd" &>/dev/null; then
    info "Installing $cmd…"
    pkg install -y "$cmd"
  fi
done

case "${1:-}" in
  --prepare-only) exit 0 ;;
  '') ;;
  *) echo 'Usage: bash termux/install.sh [--prepare-only]' >&2; exit 1 ;;
esac

# dotfiles
step "Applying dotfiles"

chezmoi init --source "$CHEZMOI_DIR"
chezmoi apply

# shell
step "Configuring shell"

if [[ "$SHELL" != *"zsh"* ]]; then
  info "Switching default shell to zsh…"
  chsh -s zsh
  info "Restart Termux to pick up the change."
else
  info "Already zsh."
fi

# zsh plugins
step "Setting up zsh plugins"

_gh_clone() {
  local dir="$1" repo="$2"
  if [[ ! -d "$dir" ]]; then
    git clone --depth=1 "$repo" "$dir"
  else
    echo "  ${dir##*/}: $(git -C "$dir" describe --tags --always 2>/dev/null || echo 'unknown')"
  fi
}

_gh_clone "$HOME/.local/share/zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions"
_gh_clone "$HOME/.local/share/zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting"

ZVM_DIR="$HOME/.local/share/zsh-vi-mode"
if [[ ! -d "$ZVM_DIR" ]]; then
  git clone --depth=1 "https://github.com/jeffreytse/zsh-vi-mode" "$ZVM_DIR"
  # fix for the escape-sequence style change in newer zsh
  sed -i "s/old_style =~ '.*\\\\a'/old_style == *\$'\\\\e]'[0-9]##';'*\$'\\\\a'/" \
    "$ZVM_DIR/zsh-vi-mode.zsh"
else
  echo "  zsh-vi-mode: $(git -C "$ZVM_DIR" describe --tags --always 2>/dev/null || echo 'unknown')"
fi

# storage
step "Setting up storage links"

if [[ ! -d "$HOME/storage/shared" ]]; then
  warn "Storage not set up. Running termux-setup-storage…"
  termux-setup-storage
  info "Storage permission granted. You may need to restart Termux."
fi

for pair in \
  "Download:dls" \
  "Documents:doc" \
  "Music:mus" \
  "Pictures:pic" \
  "Movies:vid"; do
  src="/storage/emulated/0/${pair%%:*}"
  dst="$HOME/${pair##*:}"

  if [[ -d "$src" ]]; then
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
      continue
    fi
    if [[ -e "$dst" || -L "$dst" ]]; then
      backup="$HOME/.local/state/dotfiles/backups/$(date -u +%Y%m%dT%H%M%S)-$$/storage/${dst##*/}"
      mkdir -p "$(dirname "$backup")"
      mv -- "$dst" "$backup"
      info "Backed up $dst to $backup"
    fi
    ln -s "$src" "$dst"
    info "  $dst → $src"
  else
    warn "  $src not found, skipping $dst"
  fi
done

# font
step "Installing font"

FONT_URL="https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/JetBrainsMono/Ligatures/Regular/JetBrainsMonoNerdFont-Regular.ttf"
FONT_DEST="$HOME/.termux/font.ttf"

if [[ ! -f "$FONT_DEST" ]]; then
  info "Installing JetBrains Mono Nerd Font…"
  curl -fsSL -o "$FONT_DEST" "$FONT_URL"
  info "Done. Run 'termux-reload-settings' or restart Termux."
else
  info "Font already present."
fi

# motd
step "Writing MOTD"

MOTD_FILE="$PREFIX/etc/motd"
cat >"$MOTD_FILE" <<'MOTDEOF'
 _
| |_ ___ _ __ _ __ ___  _   ___  __
| __/ _ \ '__| '_ ` _ \| | | \ \/ /
| ||  __/ |  | | | | | | |_| |>  <
 \__\___|_|  |_| |_| |_|\__,_/_/\_\
MOTDEOF
info "MOTD written to $MOTD_FILE"

# done
echo -e "${GREEN}  dotfiles ready.${NC}"
