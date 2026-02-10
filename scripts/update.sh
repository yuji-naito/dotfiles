#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BREWFILE="${DOTFILES_DIR}/Brewfile"

if ! command -v brew &>/dev/null; then
  echo "Error: Homebrew is not installed." >&2
  exit 1
fi

echo "Updating Homebrew..."
brew update

echo "Upgrading packages..."
brew upgrade

echo "Dumping Brewfile..."
brew bundle dump --force --file="${BREWFILE}"

echo "Cleaning up unused packages..."
brew bundle cleanup --force --file="${BREWFILE}"
brew cleanup

echo "Done! Brewfile updated: ${BREWFILE}"
