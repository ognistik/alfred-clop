#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary_path="$repo_root/workflow/alfred-clop"
env_file="$repo_root/.release.env"

if [[ -f "$env_file" ]]; then
  # shellcheck disable=SC1090
  source "$env_file"
fi

if [[ ! -f "$binary_path" ]]; then
  printf 'Missing binary: %s\n' "$binary_path" >&2
  printf 'Run ./scripts/build.sh first.\n' >&2
  exit 66
fi

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  printf 'Missing DEVELOPER_ID_APPLICATION.\n' >&2
  printf 'Set it in .release.env or the shell environment.\n' >&2
  exit 78
fi

if [[ -n "${DEVELOPER_ID_PROVISIONING_PROFILE:-}" ]]; then
  printf 'Note: DEVELOPER_ID_PROVISIONING_PROFILE is set but not used for this command-line executable.\n'
fi

codesign \
  --force \
  --sign "$DEVELOPER_ID_APPLICATION" \
  --timestamp \
  --options runtime \
  "$binary_path"

codesign --verify --strict --verbose=2 "$binary_path"
codesign -dv --verbose=2 "$binary_path" 2>&1 | sed -n '1,40p'

printf 'Signed Alfred Clop binary: %s\n' "$binary_path"
