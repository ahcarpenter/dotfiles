#!/usr/bin/env bash
# Tests merge-claude-settings against sample files in a temporary directory.
#
# Usage: test-merge-claude-settings.sh <path to merge-claude-settings>
set -euo pipefail

merge="$1"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

# Asserts that jq filter $2 is true for JSON file $1.
check() {
  jq -e "$2" "$1" >/dev/null || fail "$3"
}

backups() {
  find "$(dirname "$1")" -maxdepth 1 -name "$(basename "$1").backup-*" | sort
}

cat >"$work/repo.json" <<'JSON'
{
  "theme": "dark-ansi",
  "repoOnly": true,
  "permissions": { "allow": ["Bash(ls)"], "defaultMode": "plan", "deny": ["Read(.env)"] },
  "nested": { "a": { "b": 1, "c": 2 } },
  "statusLine": { "type": "command", "command": "repo" }
}
JSON

# Repo-only keys are added; live values, nested keys and arrays win; a backup is kept.
dir="$work/merge"; mkdir -p "$dir"
cat >"$dir/settings.json" <<'JSON'
{
  "theme": "light",
  "liveOnly": 42,
  "permissions": { "allow": ["Bash(git status)"], "defaultMode": "default" },
  "nested": { "a": { "b": 99 } },
  "statusLine": "live-string"
}
JSON
chmod 600 "$dir/settings.json"
cp "$dir/settings.json" "$work/merge-original.json"
"$merge" "$work/repo.json" "$dir/settings.json" >/dev/null
live="$dir/settings.json"
check "$live" '.repoOnly == true' "repo-only key not added"
check "$live" '.theme == "light"' "live top-level value not kept"
check "$live" '.liveOnly == 42' "live-only key lost"
check "$live" '.permissions.allow == ["Bash(git status)"]' "live array not kept"
check "$live" '.permissions.defaultMode == "default"' "live nested value not kept"
check "$live" '.permissions.deny == ["Read(.env)"]' "repo-only nested key not added"
check "$live" '.nested.a == {"b": 99, "c": 2}' "deeply nested merge wrong"
check "$live" '.statusLine == "live-string"' "live non-object value not kept over repo object"
check "$live" '(keys_unsorted | .[0:5]) == ["theme","liveOnly","permissions","nested","statusLine"]' "live key order not kept"
[[ "$(stat -c %a "$live" 2>/dev/null || stat -f %Lp "$live")" == 600 ]] || fail "file mode not kept"
mapfile -t found < <(backups "$live")
if [[ ${#found[@]} -ne 1 ]]; then
  fail "expected one backup, found ${#found[@]}"
else
  cmp -s "${found[0]}" "$work/merge-original.json" || fail "backup does not match the original live file"
fi

# A second run changes nothing and makes no new backup.
cp "$live" "$work/merged-once.json"
"$merge" "$work/repo.json" "$live" >/dev/null
cmp -s "$live" "$work/merged-once.json" || fail "second run changed the file"
mapfile -t found < <(backups "$live")
[[ ${#found[@]} -eq 1 ]] || fail "second run made another backup"

# A missing live file gets the repo copy, byte for byte.
dir="$work/missing"
"$merge" "$work/repo.json" "$dir/settings.json" >/dev/null
cmp -s "$dir/settings.json" "$work/repo.json" || fail "missing live file did not get the repo copy"
[[ ! -L "$dir/settings.json" ]] || fail "missing live file became a link"

# The old home-manager link becomes a regular file with the same settings,
# and the file it pointed at is never written.
dir="$work/link"; mkdir -p "$dir"
cat >"$work/linked-target.json" <<'JSON'
{ "theme": "dark-ansi", "statusLine": { "type": "command", "command": "today" } }
JSON
cp "$work/linked-target.json" "$work/linked-target-original.json"
ln -s "$work/linked-target.json" "$dir/settings.json"
"$merge" "$work/repo.json" "$dir/settings.json" >/dev/null
live="$dir/settings.json"
[[ -f "$live" && ! -L "$live" ]] || fail "old link was not replaced by a regular file"
check "$live" '.statusLine.command == "today"' "settings held through the old link were not kept"
check "$live" '.repoOnly == true' "repo-only key not added when replacing the old link"
cmp -s "$work/linked-target.json" "$work/linked-target-original.json" || fail "link target was written through"
mapfile -t found < <(backups "$live")
if [[ ${#found[@]} -ne 1 ]]; then
  fail "expected one backup of the old link, found ${#found[@]}"
else
  [[ ! -L "${found[0]}" ]] || fail "backup of the old link is a link, not a copy"
  cmp -s "${found[0]}" "$work/linked-target-original.json" || fail "backup of the old link does not hold its settings"
fi

# An invalid live file is left untouched with a warning, and the merge exits 0.
for bad in 'not json {' '["an", "array"]'; do
  dir="$work/invalid"; rm -rf "$dir"; mkdir -p "$dir"
  printf '%s\n' "$bad" >"$dir/settings.json"
  cp "$dir/settings.json" "$work/invalid-original"
  "$merge" "$work/repo.json" "$dir/settings.json" >/dev/null 2>"$work/err" || fail "invalid live file '$bad' did not exit 0"
  grep -q "warning: '$dir/settings.json' is not a valid JSON object" "$work/err" || fail "invalid live file gave no warning naming the file and reason"
  cmp -s "$dir/settings.json" "$work/invalid-original" || fail "invalid live file was changed"
  [[ -z "$(backups "$dir/settings.json")" ]] || fail "invalid live file was backed up or copied"
done

# A broken link is left untouched with a warning, and the merge exits 0.
dir="$work/broken"; mkdir -p "$dir"
ln -s "$work/does-not-exist.json" "$dir/settings.json"
"$merge" "$work/repo.json" "$dir/settings.json" >/dev/null 2>"$work/err" || fail "broken link did not exit 0"
grep -q "warning: '$dir/settings.json' is not a readable file" "$work/err" || fail "broken link gave no warning naming the file and reason"
[[ "$(readlink "$dir/settings.json")" == "$work/does-not-exist.json" ]] || fail "broken link was changed"

if [[ $failures -gt 0 ]]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all merge-claude-settings tests passed"
