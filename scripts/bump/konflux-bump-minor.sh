#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

print_usage() {
cat << EOF
NAME
  $SCRIPT_NAME - bump the minor version across a project
SYNOPSIS
  $SCRIPT_NAME --current-version VERSION [--project-root DIR]
EXAMPLES
  - Bump from 4.21.0 to 4.22.0 across the repo:
    $ $SCRIPT_NAME --current-version 4.21.0
  - Bump for a specific directory:
    $ $SCRIPT_NAME --current-version 4.21.0 --project-root /path/to/project
DESCRIPTION
  This script increments the minor version of a semantic-like version and replaces occurrences across the project.
  It updates these forms:
    - MAJOR.MINOR.0 -> (MINOR+1) as MAJOR.MINOR_NEW.0
    - MAJOR.MINOR   -> (MINOR+1) as MAJOR.MINOR_NEW
    - MAJOR-MINOR   -> (MINOR+1) as MAJOR-MINOR_NEW
ARGS
  --current-version VERSION
      Current version (e.g., 4.21.0 or 4.21). Patch is normalized to .0 when computing the new version.
  --project-root DIR
      Project root directory. Defaults to the current git repository root or current working directory if not a git repo.
  --help
      Display this help and exit.
EOF
}

parse_args() {
  if [[ $# -eq 0 ]]; then
    print_usage
    exit 1
  fi

  CURRENT_VERSION=""
  PROJECT_ROOT=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        print_usage
        exit 0
        ;;
      --current-version)
        if [[ -z "${2:-}" ]]; then
          echo "Error: --current-version requires a value" >&2
          exit 1
        fi
        CURRENT_VERSION="$2"
        shift 2
        ;;
      --project-root)
        if [[ -z "${2:-}" ]]; then
          echo "Error: --project-root requires a directory" >&2
          exit 1
        fi
        PROJECT_ROOT="$2"
        shift 2
        ;;
      *)
        echo "Error: unexpected argument: $1" >&2
        print_usage
        exit 1
        ;;
    esac
  done

  if [[ -z "$CURRENT_VERSION" ]]; then
    echo "Error: --current-version is required" >&2
    exit 1
  fi

  if [[ -z "$PROJECT_ROOT" ]]; then
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
      PROJECT_ROOT="$(git rev-parse --show-toplevel)"
    else
      PROJECT_ROOT="$(pwd)"
    fi
  fi

  if [[ ! -d "$PROJECT_ROOT" ]]; then
    echo "Error: project root '$PROJECT_ROOT' does not exist or is not a directory" >&2
    exit 1
  fi
}

normalize_and_compute_versions() {
  local ver="$1"

  # Accept 4.XX or 4.XX.0
  if [[ ! "$ver" =~ ^([0-9]+)\.([0-9]+)(\.([0-9]+))?$ ]]; then
    echo "Error: invalid version format '$ver' (expected MAJOR.MINOR or MAJOR.MINOR.PATCH)" >&2
    exit 1
  fi

  MAJOR="${BASH_REMATCH[1]}"
  MINOR="${BASH_REMATCH[2]}"

  # Compute new minor
  NEW_MINOR=$((10#$MINOR + 1))

  # Old variants (what to search)
  OLD_DOT="${MAJOR}.${MINOR}"
  OLD_FULL="${MAJOR}.${MINOR}.0"
  OLD_DASH="${MAJOR}-${MINOR}"

  # New variants (what to replace with)
  NEW_DOT="${MAJOR}.${NEW_MINOR}"
  NEW_FULL="${MAJOR}.${NEW_MINOR}.0"
  NEW_DASH="${MAJOR}-${NEW_MINOR}"
}

detect_sed_inplace_flag() {
  # Linux vs macOS sed -i
  if [[ "$OSTYPE" == "darwin"* ]]; then
    SED_INPLACE=(-i '')
  else
    SED_INPLACE=(-i)
  fi
}

gather_files() {
  local root="$1"
  FILE_LIST=()

  if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Only tracked files
    while IFS= read -r -d '' f; do
      FILE_LIST+=("$f")
    done < <(git -C "$root" ls-files -z)
  else
    # Fallback to find; exclude common dirs
    while IFS= read -r -d '' f; do
      FILE_LIST+=("$f")
    done < <(find "$root" \
      -type d \( -name .git -o -name .svn -o -name .hg -o -name node_modules -o -name vendor -o -name .tox -o -name .venv -o -name .mypy_cache -o -name .pytest_cache -o -name dist -o -name build \) -prune -false -o \
      -type f -print0)
  fi
}

perform_replacements() {
  local -i changed_files=0
  local -i total_replacements=0

  for file in "${FILE_LIST[@]}"; do
    # Skip binary files quickly
    if grep -Iq . "$file"; then
      :
    else
      continue
    fi

    # Quick pre-check to avoid invoking sed unnecessarily
    if ! grep -Eq --binary-files=without-match "(${OLD_FULL//./\\.}|${OLD_DOT//./\\.}|${OLD_DASH//-/\\-})" "$file"; then
      continue
    fi

    # Make a temp copy to compute diff in replacements
    local tmp
    tmp="$(mktemp)"
    cp "$file" "$tmp"

    # Order matters to avoid partial overlaps:
    # 1) full form X.Y.0
    sed -E "${SED_INPLACE[@]}" "s/(^|[^0-9])${MAJOR}\.${MINOR}\.0([^0-9]|$)/\1${NEW_FULL}\2/g" "$file"
    # 2) dashed X-Y
    sed -E "${SED_INPLACE[@]}" "s/(^|[^0-9])${MAJOR}-${MINOR}([^0-9]|$)/\1${NEW_DASH}\2/g" "$file"
    # 3) dot short X.Y (ensure we didn't already match .0 in step 1)
    sed -E "${SED_INPLACE[@]}" "s/(^|[^0-9])${MAJOR}\.${MINOR}([^0-9]|$)/\1${NEW_DOT}\2/g" "$file"

    if ! cmp -s "$tmp" "$file"; then
      changed_files+=1
      # Count simple occurrence deltas (best-effort)
      local before after
      before=$(grep -Eo "(${OLD_FULL//./\\.}|${OLD_DOT//./\\.}|${OLD_DASH//-/\\-})" "$tmp" | wc -l || true)
      after=$(grep -Eo "(${OLD_FULL//./\\.}|${OLD_DOT//./\\.}|${OLD_DASH//-/\\-})" "$file" | wc -l || true)
      if [[ "$before" -gt "$after" ]]; then
        total_replacements+=$((before - after))
      fi
    fi
    rm -f "$tmp"
  done

  echo "Files changed: $changed_files"
  echo "Estimated occurrences replaced: $total_replacements"
}

main() {
  parse_args "$@"
  normalize_and_compute_versions "$CURRENT_VERSION"
  detect_sed_inplace_flag
  echo "Project root: $PROJECT_ROOT"
  echo "Current versions to replace:"
  echo "  DOT:  $OLD_DOT"
  echo "  FULL: $OLD_FULL"
  echo "  DASH: $OLD_DASH"
  echo "New versions:"
  echo "  DOT:  $NEW_DOT"
  echo "  FULL: $NEW_FULL"
  echo "  DASH: $NEW_DASH"
  gather_files "$PROJECT_ROOT"
  perform_replacements
  echo "Version bump completed."
}

main "$@"


