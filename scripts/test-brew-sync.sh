#!/usr/bin/env bash
# Tests brew-sync against a sample prefix and stand-ins for Automic Vault's
# brew and for launchctl.
#
# Usage: test-brew-sync.sh <path to brew-sync>
set -euo pipefail

sync="$1"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

# A brew that records each call, refuses the commands listed in $work/deny,
# and answers `outdated` with the names in $work/outdated-formula or
# $work/outdated-cask.
cat >"$work/brew" <<'SH'
#!/usr/bin/env bash
work="${0%/brew}"
echo "$*" >>"$work/calls"
if grep -qxF -- "$*" "$work/deny" 2>/dev/null; then
  exit 1
fi
case "$*" in
  "outdated --formula --quiet") cat "$work/outdated-formula" 2>/dev/null || true ;;
  "outdated --cask --quiet") cat "$work/outdated-cask" 2>/dev/null || true ;;
esac
SH
chmod +x "$work/brew"

# A launchctl that records each call. $work/services lists the loaded
# services, one `<label> <state>` per line; `kickstart` fails for the labels
# listed in $work/kickstart-deny.
mkdir "$work/bin"
cat >"$work/bin/launchctl" <<'SH'
#!/usr/bin/env bash
work="${0%/bin/launchctl}"
echo "$*" >>"$work/launchctl-calls"
target="${!#}"
label="${target##*/}"
case "$1" in
  print)
    while read -r loaded state; do
      if [[ $loaded == "$label" ]]; then
        printf '%s = {\n\tactive count = 1\n\tstate = %s\n\n\tendpoints = {\n\t\tstate = active\n\t}\n}\n' "$2" "$state"
        exit 0
      fi
    done <"$work/services"
    echo "Could not find service \"$label\" in domain for user gui: $UID" >&2
    exit 113
    ;;
  kickstart) ! grep -qxF -- "$label" "$work/kickstart-deny" 2>/dev/null ;;
esac
SH
chmod +x "$work/bin/launchctl"
touch "$work/services"
export PATH="$work/bin:$PATH"

reset() {
  rm -f "$work/calls" "$work/deny" "$work/outdated-formula" "$work/outdated-cask" \
    "$work/launchctl-calls" "$work/kickstart-deny"
  : >"$work/services"
}

prefix="$work/prefix"
# Homebrew's library outside <prefix>/Library, as on Intel Macs.
library="$prefix/Homebrew/Library"
# tailscale is installed under another name, as with a formula alias.
mkdir -p "$prefix/Cellar/herdr" "$prefix/Cellar/tailscale-cli/1.0" "$prefix/opt" "$prefix/Caskroom" \
  "$library/Taps/rjyo/homebrew-moshi"
ln -s ../Cellar/tailscale-cli/1.0 "$prefix/opt/tailscale"

items=(
  trusted-tap:rjyo/moshi trusted-tap:automic-vault/isotopes
  formula:herdr formula:tailscale formula:mosh formula:moshi-hook
  cask:claude-code@latest
)

# One `brew update` comes first. Only missing items are installed, in order,
# each with its own command; a refused install warns and the rest still run.
reset
echo "install --formula mosh" >"$work/deny"
"$sync" "$prefix" "$library" "$work/brew" "${items[@]}" 2>"$work/err" || fail "a refused install did not exit 0"
expected="update
trust --tap automic-vault/isotopes
tap automic-vault/isotopes
install --formula mosh
install --formula moshi-hook
install --cask claude-code@latest
outdated --formula --quiet
outdated --cask --quiet"
[[ "$(cat "$work/calls")" == "$expected" ]] || fail "unexpected brew calls: $(cat "$work/calls")"
grep -q "warning: 'brew install --formula mosh' was denied or failed" "$work/err" || fail "refused install gave no warning naming the command"
grep -q "warning: not installed: mosh$" "$work/err" || fail "summary does not name what was not installed"

# A refused trust skips that tap's clone. With no formula or cask listed,
# there is nothing to update or upgrade.
reset
echo "trust --tap automic-vault/isotopes" >"$work/deny"
"$sync" "$prefix" "$library" "$work/brew" trusted-tap:automic-vault/isotopes 2>"$work/err" || fail "a refused trust did not exit 0"
[[ "$(cat "$work/calls")" == "trust --tap automic-vault/isotopes" ]] || fail "unexpected brew calls after a refused trust: $(cat "$work/calls")"

# With everything installed and current, brew only refreshes and checks.
mkdir -p "$library/Taps/automic-vault/homebrew-isotopes" "$prefix/Cellar/mosh" \
  "$prefix/Cellar/moshi-hook" "$prefix/Caskroom/claude-code@latest" "$prefix/Caskroom/codex"
reset
"$sync" "$prefix" "$library" "$work/brew" "${items[@]}" 2>"$work/err" || fail "an up-to-date run did not exit 0"
expected="update
outdated --formula --quiet
outdated --cask --quiet"
[[ "$(cat "$work/calls")" == "$expected" ]] || fail "unexpected brew calls with everything current: $(cat "$work/calls")"
grep -q "everything listed is installed" "$work/err" || fail "an up-to-date run did not say everything is installed"
grep -q "everything listed is up to date" "$work/err" || fail "an up-to-date run did not say everything is up to date"
[[ ! -e "$work/launchctl-calls" ]] || fail "launchctl was called with nothing upgraded: $(cat "$work/launchctl-calls")"

# Only outdated listed items are upgraded, each with its own command, by the
# name they're listed under: a tap formula and a formula installed through an
# alias are found by the names brew gives them. Up-to-date items (mosh) and
# outdated unlisted ones (protobuf, codex) are left alone. A refused upgrade
# warns and the rest still run. A running service of an upgraded formula,
# labeled with the name it's installed under, is restarted; a stopped one, or
# one whose upgrade was refused, is not.
reset
printf '%s\n' herdr protobuf rjyo/moshi/moshi-hook tailscale-cli >"$work/outdated-formula"
printf '%s\n' claude-code@latest codex >"$work/outdated-cask"
echo "upgrade --formula herdr" >"$work/deny"
printf '%s\n' "sh.brew.herdr running" "homebrew.mxcl.tailscale-cli not running" "sh.brew.moshi-hook running" >"$work/services"
"$sync" "$prefix" "$library" "$work/brew" "${items[@]}" 2>"$work/err" || fail "a refused upgrade did not exit 0"
expected="update
outdated --formula --quiet
upgrade --formula herdr
upgrade --formula tailscale
upgrade --formula moshi-hook
outdated --cask --quiet
upgrade --cask claude-code@latest"
[[ "$(cat "$work/calls")" == "$expected" ]] || fail "unexpected brew calls when upgrading: $(cat "$work/calls")"
grep -q "warning: 'brew upgrade --formula herdr' was denied or failed" "$work/err" || fail "refused upgrade gave no warning naming the command"
grep -q "warning: not upgraded: herdr$" "$work/err" || fail "summary does not name what was not upgraded"
grep -q "everything listed is installed" "$work/err" || fail "an upgrade run did not say everything is installed"
! grep -q "up to date" "$work/err" || fail "a run with outdated items said everything is up to date"
expected="print gui/$UID/sh.brew.tailscale-cli
print gui/$UID/homebrew.mxcl.tailscale-cli
print gui/$UID/sh.brew.moshi-hook
kickstart -k gui/$UID/sh.brew.moshi-hook
print gui/$UID/homebrew.mxcl.moshi-hook"
[[ "$(cat "$work/launchctl-calls")" == "$expected" ]] || fail "unexpected launchctl calls: $(cat "$work/launchctl-calls")"
grep -q "restarting sh.brew.moshi-hook so it runs the upgraded moshi-hook" "$work/err" || fail "a restart was not reported"

# A service that won't restart gets a warning with the command to run.
reset
echo moshi-hook >"$work/outdated-formula"
echo "sh.brew.moshi-hook running" >"$work/services"
echo sh.brew.moshi-hook >"$work/kickstart-deny"
"$sync" "$prefix" "$library" "$work/brew" "${items[@]}" 2>"$work/err" || fail "a failed restart did not exit 0"
grep -q "warning: could not restart sh.brew.moshi-hook; run 'launchctl kickstart -k gui/$UID/sh.brew.moshi-hook' yourself" "$work/err" ||
  fail "failed restart gave no warning naming the command"
grep -q "warning: still running the old version: sh.brew.moshi-hook$" "$work/err" || fail "summary does not name what was not restarted"

# A refused `brew update` warns, and the checks and upgrades still run.
reset
echo update >"$work/deny"
echo claude-code@latest >"$work/outdated-cask"
"$sync" "$prefix" "$library" "$work/brew" "${items[@]}" 2>"$work/err" || fail "a refused update did not exit 0"
expected="update
outdated --formula --quiet
outdated --cask --quiet
upgrade --cask claude-code@latest"
[[ "$(cat "$work/calls")" == "$expected" ]] || fail "unexpected brew calls after a refused update: $(cat "$work/calls")"
grep -q "warning: 'brew update' was denied or failed" "$work/err" || fail "refused update gave no warning"

# A refused check upgrades nothing of that kind, and the other kind still runs.
reset
echo "outdated --formula --quiet" >"$work/deny"
echo herdr >"$work/outdated-formula"
echo claude-code@latest >"$work/outdated-cask"
"$sync" "$prefix" "$library" "$work/brew" "${items[@]}" 2>"$work/err" || fail "a refused check did not exit 0"
expected="update
outdated --formula --quiet
outdated --cask --quiet
upgrade --cask claude-code@latest"
[[ "$(cat "$work/calls")" == "$expected" ]] || fail "unexpected brew calls after a refused check: $(cat "$work/calls")"
grep -q "warning: 'brew outdated --formula --quiet' was denied or failed" "$work/err" || fail "refused check gave no warning naming the command"
! grep -q "up to date" "$work/err" || fail "a run with a refused check said everything is up to date"

# An unknown item is a usage error, and brew is never called.
reset
if "$sync" "$prefix" "$library" "$work/brew" formula:jq mas:12345 2>/dev/null; then
  fail "an unknown item did not fail"
fi
[[ ! -e "$work/calls" ]] || fail "brew was called despite an unknown item"

if [[ $failures -gt 0 ]]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all brew-sync tests passed"
