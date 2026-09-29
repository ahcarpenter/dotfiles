#!/usr/bin/env bash
# Merge the repo's Claude Code settings into the live settings file.
#
# Usage: merge-claude-settings <repo-settings.json> <live-settings.json>
#
# Live values always win: only keys missing from the live file are added,
# nested objects merge key by key, and arrays or other values keep the live value.
# A missing live file gets the repo copy. A live file that is a symlink (the old
# home-manager link) is replaced by a regular file holding the same settings.
# The live file is backed up before it is changed. An unreadable or invalid live
# file is left untouched with a warning, so the rest of the rebuild still runs.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: merge-claude-settings <repo-settings.json> <live-settings.json>" >&2
  exit 2
fi

repo="$1"
live="$2"

# Add keys from $repo that the input lacks, recursing into objects both sides have.
# shellcheck disable=SC2016 # jq variables, not shell ones
merge_filter='
def merge_missing($repo):
  reduce ($repo | keys_unsorted[]) as $k (.;
    if has($k) | not then .[$k] = $repo[$k]
    elif (.[$k] | type) == "object" and ($repo[$k] | type) == "object"
    then .[$k] |= merge_missing($repo[$k])
    else . end);
merge_missing($repo[0])
'

die() {
  echo "merge-claude-settings: $*" >&2
  exit 1
}

skip() {
  echo "merge-claude-settings: warning: $*" >&2
  exit 0
}

say() {
  echo "merge-claude-settings: $*"
}

is_json_object() {
  jq -e 'type == "object"' "$1" >/dev/null 2>&1
}

if ! is_json_object "$repo"; then
  die "repo settings '$repo' is not a JSON object"
fi

if [[ ! -e "$live" && ! -L "$live" ]]; then
  mkdir -p "$(dirname "$live")"
  install -m 644 "$repo" "$live"
  say "installed repo settings as '$live'"
  exit 0
fi

if [[ ! -f "$live" || ! -r "$live" ]]; then
  skip "'$live' is not a readable file (a broken link or unreadable file?); leaving it untouched"
fi

if ! is_json_object "$live"; then
  skip "'$live' is not a valid JSON object; leaving it untouched - fix or remove it and rebuild"
fi

merged="$(jq --slurpfile repo "$repo" "$merge_filter" "$live")"

if [[ -L "$live" ]]; then
  action="replace the link '$live' with a regular file and add missing repo keys"
elif jq -e --argjson merged "$merged" '. == $merged' "$live" >/dev/null; then
  exit 0
else
  action="add missing repo keys to '$live'"
fi

backup="$live.backup-$(date +%Y%m%d-%H%M%S)"
n=1
while [[ -e "$backup" || -L "$backup" ]]; do
  backup="$live.backup-$(date +%Y%m%d-%H%M%S)-$n"
  n=$((n + 1))
done

# Copy the content (not the link) so the backup survives the repo changing.
cp -L "$live" "$backup"
say "backed up '$live' to '$backup'"

tmp="$(mktemp "$(dirname "$live")/.settings.json.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$merged" >"$tmp"
chmod --reference="$live" "$tmp"
# Rename over the path itself, so an old link is replaced rather than written through.
mv -fT "$tmp" "$live"
trap - EXIT
say "done: $action"
