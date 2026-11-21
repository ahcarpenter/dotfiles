#!/usr/bin/env bash
# Install what's missing from the Homebrew lists and upgrade what's outdated,
# through Automic Vault's brew.
#
# Usage: brew-sync <prefix> <library> <brew> <item>...
#
# Items are `tap:<name>`, `trusted-tap:<name>`, `formula:<name>` and `cask:<name>`,
# in install order. <library> is Homebrew's Library directory, which is not
# under <prefix> on every Mac (/usr/local/Homebrew/Library on Intel). Hardened
# Homebrew refuses `brew bundle`, so each item gets its own command through
# <brew> (Automic Vault's brew, which asks for approval).
#
# A run first refreshes Homebrew's package lists with one `brew update`, as
# nix-darwin's `homebrew.onActivation.autoUpdate` does before `brew bundle`.
# It then installs each missing item, asks `brew outdated` which formulae and
# casks are outdated, and upgrades each listed one that is. It never upgrades
# or removes anything that isn't listed, though brew may upgrade a listed
# formula's dependencies along with it. When an upgraded formula's Homebrew
# service is running in your login session, it is restarted, so it doesn't
# keep running the old version the upgrade removed. A denied or failed command
# prints a warning and the rest carry on.
#
# Run it as yourself, as rebuild.sh does after a switch: Automic Vault's brew
# refuses root and asks for approval in your session.
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: brew-sync <prefix> <library> <brew> <item>..." >&2
  exit 2
fi

prefix="$1"
library="$2"
brew="$3"
shift 3

say() {
  echo "brew-sync: $*" >&2
}

warn() {
  echo "brew-sync: warning: $*" >&2
}

installed() {
  local kind="$1" name="$2"
  local token="${name##*/}"
  case "$kind" in
    tap | trusted-tap)
      local owner="${name%%/*}" repo="${name#*/}"
      [[ -d "$library/Taps/${owner,,}/homebrew-${repo#homebrew-}" ]]
      ;;
    formula) [[ -d "$prefix/Cellar/$token" || -e "$prefix/opt/$token" ]] ;;
    cask) [[ -d "$prefix/Caskroom/$token" ]] ;;
  esac
}

# The name a listed formula is installed under: <prefix>/opt/<name> links into
# its keg, and so does the link for an alias.
keg_name() {
  local token="${1##*/}" target
  if target="$(readlink "$prefix/opt/$token")"; then
    target="${target%/*}"
    echo "${target##*/}"
  else
    echo "$token"
  fi
}

# Whether `brew outdated`'s list of names ($3) includes a listed item. brew
# names a tap's formula <user>/<tap>/<name>, and a formula installed through
# an alias by its own name.
is_outdated() {
  local kind="$1" list="$3"
  local names=("${2##*/}") line name
  if [[ $kind == formula ]]; then
    names+=("$(keg_name "$2")")
  fi
  while IFS= read -r line; do
    for name in "${names[@]}"; do
      if [[ "${line##*/}" == "$name" ]]; then
        return 0
      fi
    done
  done <<<"$list"
  return 1
}

# An upgrade removes the old keg, but a running service keeps running the old
# version until it restarts. Hardened Homebrew can't run `brew services`, so a
# formula's service is a LaunchAgent you loaded into your login session
# yourself, under one of the labels Homebrew gives it.
restart_service() {
  local token label status
  token="$(keg_name "$1")"
  for label in "sh.brew.$token" "homebrew.mxcl.$token"; do
    status="$(launchctl print "gui/$UID/$label" 2>/dev/null)" || continue
    [[ $'\n'"$status"$'\n' == *$'\n\tstate = running\n'* ]] || continue
    say "restarting $label so it runs the upgraded $token"
    if ! launchctl kickstart -k "gui/$UID/$label"; then
      warn "could not restart $label; run 'launchctl kickstart -k gui/$UID/$label' yourself"
      not_restarted+=("$label")
    fi
  done
}

upgrade_outdated() {
  local kind="$1"
  shift
  [[ $# -gt 0 ]] || return 0
  local list name
  if ! list="$("$brew" outdated "--$kind" --quiet)"; then
    warn "'brew outdated --$kind --quiet' was denied or failed; no $kind was checked for an upgrade"
    unchecked=$((unchecked + 1))
    return 0
  fi
  for name in "$@"; do
    is_outdated "$kind" "$name" "$list" || continue
    stale=$((stale + 1))
    say "upgrading $kind $name through Automic Vault's brew (approve it in Automic Vault)"
    if ! "$brew" upgrade "--$kind" "$name"; then
      warn "'brew upgrade --$kind $name' was denied or failed; run it yourself to upgrade $name"
      not_upgraded+=("$name")
      continue
    fi
    if [[ $kind == formula ]]; then
      restart_service "$name"
    fi
  done
}

formulae=()
casks=()
for item in "$@"; do
  case "${item%%:*}" in
    tap | trusted-tap) ;;
    formula) formulae+=("${item#*:}") ;;
    cask) casks+=("${item#*:}") ;;
    *)
      echo "brew-sync: unknown item '$item'" >&2
      exit 2
      ;;
  esac
done

if [[ $EUID -eq 0 ]]; then
  echo "brew-sync: run it as yourself, not root: Automic Vault's brew refuses root" >&2
  exit 2
fi

if [[ ${#formulae[@]} -gt 0 || ${#casks[@]} -gt 0 ]]; then
  say "refreshing Homebrew's package lists through Automic Vault's brew"
  if ! "$brew" update; then
    warn "'brew update' was denied or failed; upgrades are checked against the package lists brew already has"
  fi
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
    if ! "$brew" $command; then
      warn "'brew $command' was denied or failed; run it yourself to install $name"
      failed+=("$name")
      break
    fi
  done
done

stale=0
unchecked=0
not_upgraded=()
not_restarted=()
upgrade_outdated formula "${formulae[@]}"
upgrade_outdated cask "${casks[@]}"

if [[ $missing -eq 0 ]]; then
  say "everything listed is installed"
elif [[ ${#failed[@]} -gt 0 ]]; then
  warn "not installed: ${failed[*]}"
fi
if [[ $stale -eq 0 && $unchecked -eq 0 ]]; then
  say "everything listed is up to date"
elif [[ ${#not_upgraded[@]} -gt 0 ]]; then
  warn "not upgraded: ${not_upgraded[*]}"
fi
if [[ ${#not_restarted[@]} -gt 0 ]]; then
  warn "still running the old version: ${not_restarted[*]}"
fi
