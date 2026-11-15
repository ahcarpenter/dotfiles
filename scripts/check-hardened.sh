#!/usr/bin/env bash
# Stop the switch unless Homebrew looks hardened by `av harden brew`.
#
# Usage: check-hardened <user> <group>
#
# Exits 2 unless both <user> and <group> (automic and vault, which
# `av harden brew` creates) exist. Only reads the directory service.
# configuration.nix runs it before a switch with hardenedHomebrew set.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: check-hardened <user> <group>" >&2
  exit 2
fi

user="$1"
group="$2"

if ! /usr/bin/dscl . -read "/Users/$user" UniqueID >/dev/null 2>&1 ||
  ! /usr/bin/dscl . -read "/Groups/$group" PrimaryGroupID >/dev/null 2>&1; then
  printf >&2 '\e[1;31merror: hardenedHomebrew is set in configuration.nix, but there is no %s user or %s group\e[0m\n' "$user" "$group"
  # shellcheck disable=SC2016
  printf >&2 'Run `av harden brew` first, or set hardenedHomebrew to false. On a fresh Mac, switch with it false first: that installs Automic Vault.\n'
  exit 2
fi
