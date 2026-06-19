#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow_dir="$repo_root/workflow"
dist_dir="$repo_root/dist"
env_file="$repo_root/.release.env"
build_first=true
sign_binary=false
notarize_archive=false
output_path=""

usage() {
  cat <<'EOF'
Usage: scripts/package.sh [options]

Build and package Alfred Clop as a .alfredworkflow archive.

Options:
  --skip-build     Package the current workflow/ directory without rebuilding.
  --sign           Sign workflow/alfred-clop before packaging.
  --notarize       Submit the packaged workflow to Apple's notary service.
                  Requires NOTARYTOOL_PROFILE in .release.env or the shell.
  --output PATH    Write the .alfredworkflow archive to PATH.
  -h, --help       Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build)
      build_first=false
      shift
      ;;
    --sign)
      sign_binary=true
      shift
      ;;
    --notarize)
      notarize_archive=true
      sign_binary=true
      shift
      ;;
    --output)
      output_path="${2:-}"
      if [[ -z "$output_path" ]]; then
        printf 'Missing value for --output.\n' >&2
        exit 64
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ -f "$env_file" ]]; then
  # shellcheck disable=SC1090
  source "$env_file"
fi

version="$(plutil -extract version raw -o - "$workflow_dir/info.plist")"
if [[ -z "$version" ]]; then
  printf 'workflow/info.plist has no version. Set it before packaging.\n' >&2
  exit 65
fi

if [[ "$build_first" == true ]]; then
  if [[ "$sign_binary" == true ]]; then
    "$repo_root/scripts/build.sh" --sign
  else
    "$repo_root/scripts/build.sh"
  fi
elif [[ "$sign_binary" == true ]]; then
  "$repo_root/scripts/sign.sh"
fi

mkdir -p "$dist_dir"
if [[ -z "$output_path" ]]; then
  output_path="$dist_dir/Clop-$version.alfredworkflow"
fi

staging_root="$(mktemp -d)"
cleanup() {
  rm -rf "$staging_root"
}
trap cleanup EXIT

staging_workflow="$staging_root/workflow"
mkdir -p "$staging_workflow"
rsync -a \
  --exclude '.DS_Store' \
  --exclude 'prefs.plist' \
  "$workflow_dir"/ \
  "$staging_workflow"/

rm -f "$output_path"
(
  cd "$staging_workflow"
  /usr/bin/zip -qry --symlinks "$output_path" .
)

printf 'Packaged Alfred Clop: %s\n' "$output_path"
unzip -l "$output_path" | sed -n '1,40p'

if [[ "$notarize_archive" == true ]]; then
  if [[ -z "${NOTARYTOOL_PROFILE:-}" ]]; then
    printf 'Missing NOTARYTOOL_PROFILE.\n' >&2
    printf 'Set it in .release.env or the shell environment.\n' >&2
    exit 78
  fi
  xcrun notarytool submit "$output_path" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait
  printf 'Notarized Alfred Clop archive: %s\n' "$output_path"
fi
