#!/usr/bin/env bash
set -euo pipefail
if [[ "${PREFIX:-}" == /data/data/com.termux/files/usr ]]; then
  platform=termux
else
  echo 'Unsupported shell environment. Use Termux, or install.ps1 on native Windows.' >&2
  exit 1
fi
skip_update=false
case "${1:-}" in
  '') ;;
  --skip-update) skip_update=true ;;
  *) echo 'Usage: bash install.sh [--skip-update]' >&2; exit 1 ;;
esac
repo_url="${DOTFILES_REPO:-https://github.com/RandomNEET/dotfiles}"
repo_dir="${DOTFILES_DIR:-$HOME/.local/share/chezmoi}"
local_root=''
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  local_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -e "$local_root/.git" && -z "${DOTFILES_DIR:-}" ]]; then
    repo_dir="$local_root"
  fi
fi

# Platform prerequisites live in the platform installer, including first bootstrap.
bootstrap="${local_root:-$repo_dir}/$platform/install.sh"
scratch=''
trap 'if [[ -n "$scratch" ]]; then rm -rf -- "$scratch"; fi' EXIT
if [[ ! -f "$bootstrap" ]]; then
  scratch="$(mktemp -d)"
  bootstrap="$scratch/install.sh"
  curl -fsSL "https://raw.githubusercontent.com/RandomNEET/dotfiles/main/$platform/install.sh" -o "$bootstrap"
fi
bash "$bootstrap" --prepare-only

if [[ ! -e "$repo_dir/.git" ]]; then
  mkdir -p "$(dirname -- "$repo_dir")"
  git clone "$repo_url" "$repo_dir"
elif [[ "$skip_update" == false ]]; then
  git -C "$repo_dir" pull --ff-only
fi
git -C "$repo_dir" config --local pull.ff only
bash "$repo_dir/$platform/install.sh"
