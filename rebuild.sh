#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ln -sfn "$DIR" ~/.dotfiles
sudo darwin-rebuild switch --flake ~/.dotfiles#mac
# Only there with hardened Homebrew: installs what's missing through Automic
# Vault's brew, as you, since it refuses root.
if [ -x /run/current-system/sw/bin/brew-sync ]; then
  /run/current-system/sw/bin/brew-sync
fi
