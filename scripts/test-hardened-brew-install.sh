#!/usr/bin/env bash
# Tests hardened-brew-install against a sample prefix and a stand-in for Automic Vault's brew.
#
# Usage: test-hardened-brew-install.sh <path to hardened-brew-install>
set -euo pipefail

install="$1"
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
# tailscale is installed under another name, as with a formula alias.
mkdir -p "$prefix/Cellar/herdr" "$prefix/Cellar/tailscale-cli/1.0" "$prefix/opt" "$prefix/Caskroom" \
  "$prefix/Library/Taps/rjyo/homebrew-moshi" "$prefix/Library/.homebrew-is-managed-by-nix/.git"
ln -s ../Cellar/tailscale-cli/1.0 "$prefix/opt/tailscale"
touch "$prefix/Library/.homebrew-is-managed-by-nix/.git/HEAD"

items=(
  trusted-tap:rjyo/moshi trusted-tap:automic-vault/isotopes
  formula:herdr formula:tailscale formula:mosh formula:moshi-hook
  cask:claude-code@latest
)

# Only missing items are installed, in order, each with its own command;
# a refused install warns and the rest still run.
rm -f "$work/calls"
echo "install --formula mosh" >"$work/deny"
"$install" nobody "$prefix" "$work/brew" "${items[@]}" 2>"$work/err" || fail "a refused install did not exit 0"
expected="trust --tap automic-vault/isotopes
tap automic-vault/isotopes
install --formula mosh
install --formula moshi-hook
install --cask claude-code@latest"
[[ "$(cat "$work/calls")" == "$expected" ]] || fail "unexpected brew calls: $(cat "$work/calls")"
grep -q "warning: 'brew install --formula mosh' was denied or failed" "$work/err" || fail "refused install gave no warning naming the command"
grep -q "warning: not installed: mosh$" "$work/err" || fail "summary does not name what was not installed"

# A refused trust skips that tap's clone.
rm -f "$work/calls"
echo "trust --tap automic-vault/isotopes" >"$work/deny"
"$install" nobody "$prefix" "$work/brew" trusted-tap:automic-vault/isotopes 2>"$work/err" || fail "a refused trust did not exit 0"
[[ "$(cat "$work/calls")" == "trust --tap automic-vault/isotopes" ]] || fail "tap ran after its trust was refused"

# With everything installed, brew is never called.
mkdir -p "$prefix/Library/Taps/automic-vault/homebrew-isotopes" "$prefix/Cellar/mosh" \
  "$prefix/Cellar/moshi-hook" "$prefix/Caskroom/claude-code@latest"
rm -f "$work/calls" "$work/deny"
"$install" nobody "$prefix" "$work/brew" "${items[@]}" 2>"$work/err" || fail "an up-to-date run did not exit 0"
[[ ! -e "$work/calls" ]] || fail "brew was called with everything installed: $(cat "$work/calls")"
grep -q "everything listed is installed" "$work/err" || fail "an up-to-date run did not say so"

# nix-homebrew's fake repository ends up owned like the prefix.
[[ "$(stat -c '%u:%g' "$prefix/Library/.homebrew-is-managed-by-nix/.git/HEAD")" == "$(stat -c '%u:%g' "$prefix")" ]] ||
  fail "fake repository is not owned like the prefix"

# An unknown item is a usage error, and nothing is installed.
rm -f "$work/calls"
if "$install" nobody "$prefix" "$work/brew" formula:jq mas:12345 2>/dev/null; then
  fail "an unknown item did not fail"
fi
[[ ! -e "$work/calls" ]] || fail "brew was called despite an unknown item"

if [[ $failures -gt 0 ]]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all hardened-brew-install tests passed"
