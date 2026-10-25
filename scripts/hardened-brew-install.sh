#!/usr/bin/env bash
# Install what's missing from the Homebrew lists through Automic Vault's brew.
#
# Usage: hardened-brew-install <user> <prefix> <brew> <item>...
#
# Items are `tap:<name>`, `trusted-tap:<name>`, `formula:<name>` and `cask:<name>`,
# in install order. Hardened Homebrew refuses `brew bundle`, and the user can't
# write the prefix, so each missing item gets its own command through <brew>
# (Automic Vault's brew, which asks for approval). Installed items are left
# alone: nothing is upgraded or removed. A denied or failed install prints a
# warning and the rest carry on, so the rebuild never stops here.
#
# Run as root, as during a rebuild: brew commands then run as <user> in that
# user's login context, since Automic Vault's brew refuses root and asks for
# approval through the user's session. Before installing, nix-homebrew's fake
# repository is handed back to the prefix's owner: nix-homebrew recreates it
# owned by <user> on every rebuild, inside the prefix Automic Vault protects.
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: hardened-brew-install <user> <prefix> <brew> <item>..." >&2
  exit 2
fi

user="$1"
prefix="$2"
brew="$3"
shift 3

say() {
  echo "hardened-brew-install: $*" >&2
}

warn() {
  echo "hardened-brew-install: warning: $*" >&2
}

run_brew() {
  if [[ $EUID -eq 0 ]]; then
    # In the user's login context, where Automic Vault's approval service runs.
    (cd / && /bin/launchctl asuser "$(id -u "$user")" /usr/bin/sudo --user="$user" -- "$brew" "$@")
  else
    (cd / && "$brew" "$@")
  fi
}

installed() {
  local kind="$1" name="$2"
  local token="${name##*/}"
  case "$kind" in
    tap | trusted-tap)
      local owner="${name%%/*}" repo="${name#*/}"
      [[ -d "$prefix/Library/Taps/${owner,,}/homebrew-${repo#homebrew-}" ]]
      ;;
    formula) [[ -d "$prefix/Cellar/$token" || -e "$prefix/opt/$token" ]] ;;
    cask) [[ -d "$prefix/Caskroom/$token" ]] ;;
  esac
}

for item in "$@"; do
  case "${item%%:*}" in
    tap | trusted-tap | formula | cask) ;;
    *)
      echo "hardened-brew-install: unknown item '$item'" >&2
      exit 2
      ;;
  esac
done

repo="$prefix/Library/.homebrew-is-managed-by-nix"
if [[ -d "$repo" && ! -L "$repo" ]]; then
  chown -R "$(stat -c '%u:%g' "$prefix")" "$repo"
fi

missing=0
failed=()
for item in "$@"; do
  kind="${item%%:*}"
  name="${item#*:}"
  if installed "$kind" "$name"; then
    continue
  fi
  missing=$((missing + 1))

  case "$kind" in
    trusted-tap) commands=("trust --tap $name" "tap $name") ;;
    tap) commands=("tap $name") ;;
    formula) commands=("install --formula $name") ;;
    cask) commands=("install --cask $name") ;;
  esac

  say "installing $kind $name through Automic Vault's brew (approve it in Automic Vault)"
  for command in "${commands[@]}"; do
    # shellcheck disable=SC2086 # each command is brew's own words, split on purpose
    if ! run_brew $command; then
      warn "'brew $command' was denied or failed; run it yourself to install $name"
      failed+=("$name")
      break
    fi
  done
done

if [[ $missing -eq 0 ]]; then
  say "everything listed is installed"
elif [[ ${#failed[@]} -gt 0 ]]; then
  warn "not installed: ${failed[*]}"
fi
