#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$repo_root/src"
workflow_dir="$repo_root/workflow"
sign_after_build=false

for arg in "$@"; do
  case "$arg" in
    --sign)
      sign_after_build=true
      ;;
    -h|--help)
      cat <<'EOF'
Usage: scripts/build.sh [--sign]

Build a universal macOS release binary and copy it into workflow/alfred-clop.

Options:
  --sign    Sign workflow/alfred-clop after building. Uses scripts/sign.sh.
EOF
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$arg" >&2
      exit 64
      ;;
  esac
done

cd "$source_dir"
MACOSX_DEPLOYMENT_TARGET=13.0 swift build \
  -c release \
  --arch arm64 \
  --arch x86_64

mkdir -p "$workflow_dir"
binary_path="$(MACOSX_DEPLOYMENT_TARGET=13.0 swift build \
  -c release \
  --arch arm64 \
  --arch x86_64 \
  --show-bin-path)/alfred-clop"
destination="$workflow_dir/alfred-clop"
cp "$binary_path" "$destination"
chmod +x "$destination"

printf 'Built Clop for Alfred: %s\n' "$destination"
file "$destination"

if [[ "$sign_after_build" == true ]]; then
  "$repo_root/scripts/sign.sh"
fi
