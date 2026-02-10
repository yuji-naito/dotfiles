#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Install Homebrew if not present
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add Homebrew to PATH
  if [ "$(uname)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]; then
    # macOS Apple Silicon
    (echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> "${HOME}/.zprofile"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ "$(uname)" = "Linux" ]; then
    # Linux
    (echo; echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"') >> "${HOME}/.profile"
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
else
  echo "Homebrew is already installed, skip installation."
fi

# Install packages from Brewfile
brew bundle install --file="${DOTFILES_DIR}/Brewfile"

# macOS: Last loginを非表示
if [ "$(uname)" = "Darwin" ]; then
  touch "${HOME}/.hushlogin"
fi
