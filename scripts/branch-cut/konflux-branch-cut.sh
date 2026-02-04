#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

print_usage() {
cat << EOF
NAME
  $SCRIPT_NAME - perform branch cut operations for a new release
SYNOPSIS
  $SCRIPT_NAME --current-version VERSION [--project-root DIR] [--exclude LIST]
EXAMPLES
  - Perform full branch cut from 4.21.0:
    $ $SCRIPT_NAME --current-version 4.21.0
DESCRIPTION
  This script performs the complete branch cut workflow:
  
  1. On main branch - Version bump:
     - Increments the minor version: MAJOR.MINOR -> MAJOR.(MINOR+1)
     - Updates all version references in the project
     - Renames Tekton pipeline files in .tekton/ directory
  
  2. On release-X.Y branch - Prepare release:
     - Checks out the release branch (release-MAJOR.MINOR)
     - Replaces 'main' with 'release-X.Y' in YAML files
  
  The script automatically switches between branches and performs both operations.
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

  # Compute release branch name (release-X.Y)
  RELEASE_BRANCH="release-${MAJOR}.${MINOR}"
}

detect_os_and_set_flags() {
  # Detect OS and set appropriate flags for commands
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    SED_INPLACE=(-i '')
    IS_MACOS=true
  else
    # Linux
    SED_INPLACE=(-i)
    IS_MACOS=false
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
    # Use -I to ignore binary files (compatible with both GNU and BSD grep)
    if ! grep -EIq "(${OLD_FULL//./\\.}|${OLD_DOT//./\\.}|${OLD_DASH})" "$file"; then
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
      # Use xargs to trim whitespace from wc output (macOS adds leading spaces)
      local before after
      before=$(grep -Eo "(${OLD_FULL//./\\.}|${OLD_DOT//./\\.}|${OLD_DASH})" "$tmp" | wc -l | xargs || true)
      after=$(grep -Eo "(${OLD_FULL//./\\.}|${OLD_DOT//./\\.}|${OLD_DASH})" "$file" | wc -l | xargs || true)
      if [[ "$before" -gt "$after" ]]; then
        total_replacements+=$((before - after))
      fi
    fi
    rm -f "$tmp"
  done

}

rename_tekton_pipelines() {
  local tekton_dir="$PROJECT_ROOT/.tekton"
  
  # Check if .tekton directory exists
  if [[ ! -d "$tekton_dir" ]]; then
    echo "Note: No .tekton directory found, skipping pipeline renaming"
    return 0
  fi

  local -i renamed_files=0
  
  # Find files matching pattern: *-MAJOR-MINOR-*.yaml
  # e.g., o-cloud-manager-4-22-pull-request.yaml -> o-cloud-manager-4-23-pull-request.yaml
  while IFS= read -r -d '' file; do
    local filename basename_only dirname_part
    filename="$(basename "$file")"
    dirname_part="$(dirname "$file")"
    
    # Check if filename contains the old version pattern (with dashes)
    if [[ "$filename" =~ -${MAJOR}-${MINOR}- ]]; then
      # Replace old version with new version in filename
      local new_filename
      new_filename="${filename//-${MAJOR}-${MINOR}-/-${MAJOR}-${NEW_MINOR}-}"
      
      if [[ "$filename" != "$new_filename" ]]; then
        local old_path="$dirname_part/$filename"
        local new_path="$dirname_part/$new_filename"
        
        if [[ -e "$new_path" ]]; then
          echo "Warning: Target file already exists: $new_path"
          echo "  Skipping rename of: $old_path"
        else
          echo "Renaming: $filename -> $new_filename"
          mv "$old_path" "$new_path"
          renamed_files+=1
        fi
      fi
    fi
  done < <(find "$tekton_dir" -maxdepth 1 -type f -name "*.yaml" -print0)
  
  if [[ $renamed_files -gt 0 ]]; then
    echo "Renamed $renamed_files Tekton pipeline file(s)"
  else
    echo "No Tekton pipeline files needed renaming"
  fi
}

replace_main_with_release_branch() {
  local release_branch="$1"
  local tekton_dir="$PROJECT_ROOT/.tekton"
  
  echo "==> Replacing 'main' with '$release_branch' in YAML files..."
  
  local -i changed_files=0
  
  # Process .tekton directory YAML files
  if [[ -d "$tekton_dir" ]]; then
    while IFS= read -r -d '' file; do
      # Check if file contains 'main' that should be replaced
      # We target specific patterns to avoid replacing unintended occurrences
      if grep -Eq "(target_branch == \"main\"|target_branch == 'main'|target_branch: main|branch: main)" "$file"; then
        echo "Updating: $(basename "$file")"
        
        # Replace target_branch references
        sed -E "${SED_INPLACE[@]}" "s/(target_branch == )\"main\"/\1\"${release_branch}\"/g" "$file"
        sed -E "${SED_INPLACE[@]}" "s/(target_branch == )'main'/\1'${release_branch}'/g" "$file"
        sed -E "${SED_INPLACE[@]}" "s/(target_branch: )main$/\1${release_branch}/g" "$file"
        sed -E "${SED_INPLACE[@]}" "s/(branch: )main$/\1${release_branch}/g" "$file"
        
        changed_files+=1
      fi
    done < <(find "$tekton_dir" -type f -name "*.yaml" -print0)
  fi
  
  if [[ $changed_files -gt 0 ]]; then
    echo "Updated $changed_files YAML file(s) with release branch name"
  else
    echo "No YAML files needed branch name updates"
  fi
}

main() {
  parse_args "$@"
  normalize_and_compute_versions "$CURRENT_VERSION"
  detect_os_and_set_flags
  
  # Pre-check: Verify release branch exists before doing anything
  echo "==> Verifying release branch '$RELEASE_BRANCH' exists..."
  if ! git -C "$PROJECT_ROOT" show-ref --verify --quiet "refs/heads/$RELEASE_BRANCH" 2>/dev/null && \
     ! git -C "$PROJECT_ROOT" show-ref --verify --quiet "refs/remotes/origin/$RELEASE_BRANCH" 2>/dev/null; then
    echo "Error: Release branch '$RELEASE_BRANCH' does not exist locally or remotely." >&2
    echo "       Cannot continue without the release branch." >&2
    echo "       Please ensure the release branch is created before running branch-cut." >&2
    exit 1
  fi
  echo "    Release branch '$RELEASE_BRANCH' found."
  
  # Step 1: On main branch - bump version and rename pipelines
  echo ""
  echo "=========================================="
  echo "Step 1: Version bump on main branch"
  echo "=========================================="
  normalize_excludes
  gather_files "$PROJECT_ROOT"
  perform_replacements
  rename_tekton_pipelines
  echo "Version bump completed: ${OLD_DOT} -> ${NEW_DOT}"
  
  # Step 2: Checkout to release branch and prepare it
  echo ""
  echo "=========================================="
  echo "Step 2: Prepare release branch ($RELEASE_BRANCH)"
  echo "=========================================="
  
  # Create a new branch from release branch (cannot modify release directly)
  local PREPARE_BRANCH="prepare-${RELEASE_BRANCH}"
  
  echo "==> Fetching latest from remote..."
  git -C "$PROJECT_ROOT" fetch origin "$RELEASE_BRANCH" 2>/dev/null || true
  
  echo "==> Creating branch '$PREPARE_BRANCH' from '$RELEASE_BRANCH'..."
  
  # Check if prepare branch already exists
  if git -C "$PROJECT_ROOT" show-ref --verify --quiet "refs/heads/$PREPARE_BRANCH" 2>/dev/null; then
    echo "Warning: Branch '$PREPARE_BRANCH' already exists locally. Checking it out..."
    git -C "$PROJECT_ROOT" checkout "$PREPARE_BRANCH"
  else
    # Create new branch from release branch (prefer remote if available)
    if git -C "$PROJECT_ROOT" show-ref --verify --quiet "refs/remotes/origin/$RELEASE_BRANCH" 2>/dev/null; then
      git -C "$PROJECT_ROOT" checkout -b "$PREPARE_BRANCH" "origin/$RELEASE_BRANCH"
    else
      git -C "$PROJECT_ROOT" checkout -b "$PREPARE_BRANCH" "$RELEASE_BRANCH"
    fi
  fi
  
  echo "==> Replacing 'main' with '$RELEASE_BRANCH' in YAML files..."
  replace_main_with_release_branch "$RELEASE_BRANCH"
  echo "Release branch preparation completed on '$PREPARE_BRANCH'."
  
  echo ""
  echo "=========================================="
  echo "Branch cut completed!"
  echo "=========================================="
  echo ""
  echo "Next steps:"
  echo "  1. Review changes and push the branches"
  echo "  2. Create PRs for both branches"
}

main "$@"


