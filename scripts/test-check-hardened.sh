#!/usr/bin/env bash
# Tests check-hardened against users and groups every Mac does or cannot have.
#
# Usage: test-check-hardened.sh <path to check-hardened>
set -euo pipefail

check="$1"
failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

# root and wheel exist on every Mac.
"$check" root wheel || fail "root and wheel were refused"

# A missing user or a missing group stops the switch, naming both.
missing="check-hardened-test-missing-$$"
for args in "$missing wheel" "root $missing"; do
  status=0
  # shellcheck disable=SC2086 # two words on purpose
  err="$("$check" $args 2>&1)" || status=$?
  [[ $status == 2 ]] || fail "$args: exited $status, not 2"
  [[ $err == *"there is no ${args% *} user or ${args#* } group"* ]] || fail "$args: unexpected error: $err"
  # shellcheck disable=SC2016 # the backticks are literal
  [[ $err == *'Run `av harden brew` first, or set hardenedHomebrew to false'* ]] || fail "$args: error does not say what to do: $err"
done

# Anything but a user and a group is a usage error.
status=0
"$check" root 2>/dev/null || status=$?
[[ $status == 2 ]] || fail "one argument: exited $status, not 2"

if [[ $failures -gt 0 ]]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-hardened tests passed"
