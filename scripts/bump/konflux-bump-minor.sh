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
  $SCRIPT_NAME --current-version VERSION [--project-root DIR] [--exclude LIST]
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
  --exclude LIST | --exclude PATH
      Exclude files/dirs or extensions. Can be specified multiple times.
      LIST may be a comma- or space-separated list mixing:
        - Paths (relative to repo root or absolute), e.g.: 'docs/,README.md'
        - Extensions in the form '.ext', e.g.: '.png,.gz'
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
  EXCLUDES=()
  EXCLUDE_EXTS=()

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
      --exclude)
        if [[ -z "${2:-}" ]]; then
          echo "Error: --exclude requires a value" >&2
          exit 1
        fi
        val="$2"
        # Support comma or space separated values in a single flag
        # Replace commas with spaces and iterate words
        for _it in ${val//,/ }; do
          # trim surrounding whitespace
          _it="${_it#"${_it%%[![:space:]]*}"}"
          _it="${_it%"${_it##*[![:space:]]}"}"
          [[ -z "$_it" ]] && continue
          if [[ "$_it" =~ ^\*\.(.+)$ ]]; then
            EXCLUDE_EXTS+=("${BASH_REMATCH[1]}")
          elif [[ "$_it" =~ ^\.(.+)$ ]]; then
            EXCLUDE_EXTS+=("${BASH_REMATCH[1]}")
          elif [[ "$_it" =~ ^ext:(.+)$ ]]; then
            EXCLUDE_EXTS+=("${BASH_REMATCH[1]}")
          else
            EXCLUDES+=("$_it")
          fi
        done
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

normalize_excludes() {
  ABS_EXCLUDES=()
  # Only process if EXCLUDES has elements
  if [[ ${#EXCLUDES[@]} -gt 0 ]]; then
    for e in "${EXCLUDES[@]}"; do
      # Skip empty entries
      [[ -z "$e" ]] && continue
      local ex
      if [[ "$e" = /* ]]; then
        ex="$e"
      else
        ex="$PROJECT_ROOT/$e"
      fi
      ex="${ex%/}"
      ABS_EXCLUDES+=("$ex")
    done
  fi
}

is_excluded() {
  local f="$1"
  # If no excludes, nothing is excluded
  if [[ ${#ABS_EXCLUDES[@]} -eq 0 ]]; then
    return 1
  fi
  for ex in "${ABS_EXCLUDES[@]}"; do
    if [[ "$f" == "$ex" ]] || [[ "$f" == "$ex/"* ]]; then
      return 0
    fi
  done
  return 1
}

matches_extension_policy() {
  local f="$1"
  local base ext
  base="$(basename "$f")"
  # Extract extension without dot (supports names with multiple dots: take last segment)
  ext="${base##*.}"
  if [[ "$base" == "$ext" ]]; then
    ext=""  # no extension
  fi

  # If exclude list contains the ext, skip
  if [[ ${#EXCLUDE_EXTS[@]} -gt 0 ]]; then
    for xe in "${EXCLUDE_EXTS[@]}"; do
      if [[ "$ext" == "$xe" ]]; then
        return 1
      fi
    done
  fi

  return 0
}

gather_files() {
  local root="$1"
  FILE_LIST=()

  # Only tracked files, excluding vendor and other common directories
  while IFS= read -r -d '' f; do
    # Skip files in vendor/, node_modules/, telco5g-konflux/, etc.
    if [[ ! "$f" =~ ^(vendor|node_modules|telco5g-konflux|\.git|\.tox|\.venv|\.mypy_cache|\.pytest_cache|dist|build)/ ]]; then
      # Convert relative path to absolute by prepending root
      local fullpath="$root/$f"
      # Only add if it's a regular file (not a directory or symlink to directory)
      if [[ -f "$fullpath" ]]; then
        if is_excluded "$fullpath"; then
          continue
        fi
        if ! matches_extension_policy "$fullpath"; then
          continue
        fi
        FILE_LIST+=("$fullpath")
      fi
    fi
  done < <(git -C "$root" ls-files -z)
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
    if ! grep -Eq --binary-files=without-match "(${OLD_FULL//./\\.}|${OLD_DOT//./\\.}|${OLD_DASH})" "$file"; then
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
      before=$(grep -Eo "(${OLD_FULL//./\\.}|${OLD_DOT//./\\.}|${OLD_DASH})" "$tmp" | wc -l || true)
      after=$(grep -Eo "(${OLD_FULL//./\\.}|${OLD_DOT//./\\.}|${OLD_DASH})" "$file" | wc -l || true)
      if [[ "$before" -gt "$after" ]]; then
        total_replacements+=$((before - after))
      fi
    fi
    rm -f "$tmp"
  done

}

main() {
  parse_args "$@"
  normalize_and_compute_versions "$CURRENT_VERSION"
  detect_sed_inplace_flag
  normalize_excludes
  gather_files "$PROJECT_ROOT"
  perform_replacements
  echo "Version bump completed."
}

main "$@"


