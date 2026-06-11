#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$repo_root/src"
workflow_dir="$repo_root/workflow"

cd "$source_dir"
swift build -c release

mkdir -p "$workflow_dir"
binary_path="$(swift build -c release --show-bin-path)/alfred-clop"
destination="$workflow_dir/alfred-clop"
cp "$binary_path" "$destination"
chmod +x "$destination"

printf 'Built Alfred Clop: %s\n' "$destination"
