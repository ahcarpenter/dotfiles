#!/usr/bin/env bash
# Tests brew-sync against a sample prefix and a stand-in for Automic Vault's brew.
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

# A brew that records each call and refuses the commands listed in $work/deny.
cat >"$work/brew" <<SH
#!/usr/bin/env bash
echo "\$*" >>"$work/calls"
! grep -qxF -- "\$*" "$work/deny" 2>/dev/null
SH
chmod +x "$work/brew"

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
  formula:automic-vault/isotopes/gh-cli
  cask:claude-code@latest
)

# Only missing items are installed, in order, each with its own command;
# a refused install warns and the rest still run.
rm -f "$work/calls"
echo "install --formula mosh" >"$work/deny"
"$sync" "$prefix" "$library" "$work/brew" "${items[@]}" 2>"$work/err" || fail "a refused install did not exit 0"
expected="trust --tap automic-vault/isotopes
tap automic-vault/isotopes
install --formula mosh
install --formula moshi-hook
install --formula automic-vault/isotopes/gh-cli
install --cask claude-code@latest"
[[ "$(cat "$work/calls")" == "$expected" ]] || fail "unexpected brew calls: $(cat "$work/calls")"
grep -q "warning: 'brew install --formula mosh' was denied or failed" "$work/err" || fail "refused install gave no warning naming the command"
grep -q "warning: not installed: mosh$" "$work/err" || fail "summary does not name what was not installed"

# A refused trust skips that tap's clone.
rm -f "$work/calls"
echo "trust --tap automic-vault/isotopes" >"$work/deny"
"$sync" "$prefix" "$library" "$work/brew" trusted-tap:automic-vault/isotopes 2>"$work/err" || fail "a refused trust did not exit 0"
[[ "$(cat "$work/calls")" == "trust --tap automic-vault/isotopes" ]] || fail "tap ran after its trust was refused"

# With everything installed, brew is never called.
mkdir -p "$library/Taps/automic-vault/homebrew-isotopes" "$prefix/Cellar/mosh" \
  "$prefix/Cellar/moshi-hook" "$prefix/Cellar/gh-cli" "$prefix/Caskroom/claude-code@latest"
rm -f "$work/calls" "$work/deny"
"$sync" "$prefix" "$library" "$work/brew" "${items[@]}" 2>"$work/err" || fail "an up-to-date run did not exit 0"
[[ ! -e "$work/calls" ]] || fail "brew was called with everything installed: $(cat "$work/calls")"
grep -q "everything listed is installed" "$work/err" || fail "an up-to-date run did not say so"

# An unknown item is a usage error, and nothing is installed.
rm -f "$work/calls"
if "$sync" "$prefix" "$library" "$work/brew" formula:jq mas:12345 2>/dev/null; then
  fail "an unknown item did not fail"
fi
[[ ! -e "$work/calls" ]] || fail "brew was called despite an unknown item"

if [[ $failures -gt 0 ]]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all brew-sync tests passed"
