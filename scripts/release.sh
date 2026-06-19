#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow_dir="$repo_root/workflow"
publish=false
asset_path=""
notes_file=""
generated_notes_file=""

cleanup() {
  if [[ -n "$generated_notes_file" ]]; then
    rm -f "$generated_notes_file"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: scripts/release.sh [options]

Create a GitHub release for the current workflow version. Releases are draft by
default so the asset and notes can be reviewed before publishing.

Options:
  --asset PATH       Use an existing .alfredworkflow asset.
  --notes-file PATH  Use release notes from PATH.
  --publish          Publish immediately instead of creating a draft.
  -h, --help         Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --asset)
      asset_path="${2:-}"
      if [[ -z "$asset_path" ]]; then
        printf 'Missing value for --asset.\n' >&2
        exit 64
      fi
      shift 2
      ;;
    --notes-file)
      notes_file="${2:-}"
      if [[ -z "$notes_file" ]]; then
        printf 'Missing value for --notes-file.\n' >&2
        exit 64
      fi
      shift 2
      ;;
    --publish)
      publish=true
      shift
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

if ! command -v gh >/dev/null 2>&1; then
  printf 'GitHub CLI is required: https://cli.github.com/\n' >&2
  exit 69
fi

version="$(plutil -extract version raw -o - "$workflow_dir/info.plist")"
if [[ -z "$version" ]]; then
  printf 'workflow/info.plist has no version. Set it before releasing.\n' >&2
  exit 65
fi

tag="v$version"
if [[ -z "$asset_path" ]]; then
  asset_path="$repo_root/dist/Clop-$version.alfredworkflow"
fi
if [[ ! -f "$asset_path" ]]; then
  printf 'Missing release asset: %s\n' "$asset_path" >&2
  printf 'Run ./scripts/package.sh --sign --notarize first, or pass --asset.\n' >&2
  exit 66
fi

release_args=(
  release create "$tag"
  "$asset_path"
  --title "Clop for Alfred $version"
)

if [[ -n "$notes_file" ]]; then
  release_args+=(--notes-file "$notes_file")
elif [[ -f "$repo_root/CHANGELOG.md" ]]; then
  generated_notes_file="$(mktemp)"
  if ! awk -v version="$version" '
    BEGIN {
      in_release = 0
      found = 0
    }
    /^## / {
      if (in_release) {
        exit
      }

      if (index($0, "[v" version "]") > 0 ||
          $0 ~ "^## v" version "([[:space:]]|$)" ||
          $0 ~ "^## " version "([[:space:]]|$)") {
        in_release = 1
        found = 1
        next
      }
    }
    in_release && $0 == "---" {
      exit
    }
    in_release {
      print
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$repo_root/CHANGELOG.md" | sed -e '/./,$!d' -e :a -e '/^\n*$/{$d;N;ba' -e '}' > "$generated_notes_file"; then
    printf 'CHANGELOG.md has no release section for v%s.\n' "$version" >&2
    printf 'Add it or pass --notes-file PATH.\n' >&2
    exit 65
  fi
  if [[ ! -s "$generated_notes_file" ]]; then
    printf 'The CHANGELOG.md release section for v%s is empty.\n' "$version" >&2
    exit 65
  fi
  release_args+=(--notes-file "$generated_notes_file")
else
  release_args+=(--notes "Clop for Alfred $version")
fi

if [[ "$publish" != true ]]; then
  release_args+=(--draft)
fi

gh "${release_args[@]}"

printf 'Created GitHub release %s\n' "$tag"
