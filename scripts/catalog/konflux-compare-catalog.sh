#!/bin/bash

# konflux-compare-catalog.sh
# Compare a generated catalog with an upstream FBC image catalog

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
CATALOG_PATH=""
UPSTREAM_IMAGE=""
VERBOSE=false
TEMP_DIR=""
CLEANUP=true

# Function to display help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Compare a generated catalog with an upstream FBC image catalog.

OPTIONS:
    --catalog-path PATH        Path to the generated catalog file or directory
    --upstream-image IMAGE     Upstream FBC image to compare against
    --temp-dir DIR            Temporary directory for extraction (default: auto-generated)
    --no-cleanup              Don't cleanup temporary files after comparison
    --verbose                 Enable verbose output
    -h, --help                Show this help message

EXAMPLES:
    $0 --catalog-path .konflux/catalog/lifecycle-agent/catalog.yaml \\
       --upstream-image quay.io/redhat-user-workloads/telco-5g-tenant/lifecycle-agent-fbc-4-20:latest

    $0 --catalog-path .konflux/catalog/lifecycle-agent/ \\
       --upstream-image quay.io/redhat-user-workloads/telco-5g-tenant/lifecycle-agent-fbc-4-20:latest \\
       --verbose
EOF
}

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Function to log verbose messages
verbose_log() {
    if [[ "$VERBOSE" == "true" ]]; then
        log "$@"
    fi
}

# Function to calculate SHA256 checksum in a cross-platform way
calculate_sha256() {
    local file="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        # Linux/Unix systems
        sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        # macOS systems
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        echo "ERROR: Neither sha256sum nor shasum command found. Cannot calculate checksums." >&2
        exit 1
    fi
}

# Function to find container runtime (podman or docker)
find_container_runtime() {
    if command -v podman >/dev/null 2>&1; then
        echo "podman"
    elif command -v docker >/dev/null 2>&1; then
        echo "docker"
    else
        echo "ERROR: Neither podman nor docker is available. A container runtime is required." >&2
        exit 1
    fi
}

# Function to detect current platform and architecture
detect_platform() {
    local os arch

    # Detect OS
    case "$(uname -s)" in
        Darwin)
            os="darwin"
            ;;
        Linux)
            os="linux"
            ;;
        *)
            # Default to linux for unknown systems
            os="linux"
            ;;
    esac

    # Detect architecture
    case "$(uname -m)" in
        x86_64)
            arch="amd64"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
        *)
            # Default to amd64 for unknown architectures
            arch="amd64"
            ;;
    esac

    echo "${os}/${arch}"
}

# Function to try pulling image with platform fallback
pull_image_with_fallback() {
    local image="$1"
    local runtime="$2"
    local current_platform="$3"
    local fallback_platform="linux/amd64"

    verbose_log "Attempting to pull image for platform: $current_platform"

    # Try pulling for current platform first
    if "$runtime" pull --platform "$current_platform" "$image" >/dev/null 2>&1; then
        verbose_log "Successfully pulled image for platform: $current_platform"
        echo "$current_platform"
        return 0
    fi

    # Fall back to linux/amd64 if current platform fails
    if [[ "$current_platform" != "$fallback_platform" ]]; then
        verbose_log "Failed to pull for $current_platform, falling back to: $fallback_platform"

        if "$runtime" pull --platform "$fallback_platform" "$image" >/dev/null 2>&1; then
            verbose_log "Successfully pulled image for fallback platform: $fallback_platform"
            echo "$fallback_platform"
            return 0
        fi
    fi

    # If both attempts fail, return error
    return 1
}

# Function to cleanup temporary files
cleanup() {
    if [[ "$CLEANUP" == "true" && -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        verbose_log "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}

# Set up trap for cleanup
trap cleanup EXIT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --catalog-path)
            CATALOG_PATH="$2"
            shift 2
            ;;
        --upstream-image)
            UPSTREAM_IMAGE="$2"
            shift 2
            ;;
        --temp-dir)
            TEMP_DIR="$2"
            shift 2
            ;;
        --no-cleanup)
            CLEANUP=false
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$CATALOG_PATH" ]]; then
    echo "ERROR: --catalog-path is required" >&2
    show_help
    exit 1
fi

if [[ -z "$UPSTREAM_IMAGE" ]]; then
    echo "ERROR: --upstream-image is required" >&2
    show_help
    exit 1
fi

# Validate catalog path exists
if [[ ! -e "$CATALOG_PATH" ]]; then
    echo "ERROR: Catalog path does not exist: $CATALOG_PATH" >&2
    exit 1
fi

# Determine the actual catalog file path
if [[ -d "$CATALOG_PATH" ]]; then
    CATALOG_FILE="$CATALOG_PATH/catalog.yaml"
    if [[ ! -f "$CATALOG_FILE" ]]; then
        echo "ERROR: catalog.yaml not found in directory: $CATALOG_PATH" >&2
        exit 1
    fi
else
    CATALOG_FILE="$CATALOG_PATH"
fi

# Create temporary directory if not provided
if [[ -z "$TEMP_DIR" ]]; then
    TEMP_DIR=$(mktemp -d)
    verbose_log "Created temporary directory: $TEMP_DIR"
fi

# Ensure temp directory exists
mkdir -p "$TEMP_DIR"

EXTRACT_DIR="$TEMP_DIR/upstream-fbc-extract"
mkdir -p "$EXTRACT_DIR"

log "Comparing catalog: $CATALOG_FILE"
log "Against upstream image: $UPSTREAM_IMAGE"

# Find available container runtime
CONTAINER_RUNTIME=$(find_container_runtime)
verbose_log "Using container runtime: $CONTAINER_RUNTIME"

# Detect current platform and architecture
CURRENT_PLATFORM=$(detect_platform)
verbose_log "Detected current platform: $CURRENT_PLATFORM"

# Pull the upstream image with platform fallback
verbose_log "Pulling upstream image: $UPSTREAM_IMAGE"
if ! USED_PLATFORM=$(pull_image_with_fallback "$UPSTREAM_IMAGE" "$CONTAINER_RUNTIME" "$CURRENT_PLATFORM"); then
    echo "ERROR: Failed to pull upstream image: $UPSTREAM_IMAGE" >&2
    echo "ERROR: Tried platforms: $CURRENT_PLATFORM and linux/amd64" >&2
    exit 1
fi

log "Using platform: $USED_PLATFORM for image: $UPSTREAM_IMAGE"

# Extract the catalog from the upstream image
verbose_log "Extracting catalog from upstream image"
if ! "$CONTAINER_RUNTIME" run --rm --platform "$USED_PLATFORM" --entrypoint /bin/sh -v "$EXTRACT_DIR:/tmp/extract" "$UPSTREAM_IMAGE" -c "cp -r /configs/* /tmp/extract/" >/dev/null 2>&1; then
    echo "ERROR: Failed to extract catalog from upstream image" >&2
    exit 1
fi

# Find the upstream catalog file
UPSTREAM_CATALOG_FILE=$(find "$EXTRACT_DIR" -name "catalog.yaml" | head -1)
if [[ -z "$UPSTREAM_CATALOG_FILE" ]]; then
    echo "ERROR: No catalog.yaml found in upstream image" >&2
    exit 1
fi

verbose_log "Found upstream catalog: $UPSTREAM_CATALOG_FILE"

# Get file sizes
GENERATED_SIZE=$(wc -l < "$CATALOG_FILE")
UPSTREAM_SIZE=$(wc -l < "$UPSTREAM_CATALOG_FILE")

log "Generated catalog lines: $GENERATED_SIZE"
log "Upstream catalog lines: $UPSTREAM_SIZE"

# Calculate checksums using cross-platform function
GENERATED_CHECKSUM=$(calculate_sha256 "$CATALOG_FILE")
UPSTREAM_CHECKSUM=$(calculate_sha256 "$UPSTREAM_CATALOG_FILE")

log "Generated catalog checksum: $GENERATED_CHECKSUM"
log "Upstream catalog checksum: $UPSTREAM_CHECKSUM"

# Compare the catalogs
if [[ "$GENERATED_CHECKSUM" == "$UPSTREAM_CHECKSUM" ]]; then
    echo "✅ VALIDATION PASSED: Generated catalog matches upstream FBC catalog exactly"
    echo "   - Both catalogs have $GENERATED_SIZE lines"
    echo "   - Both catalogs have identical checksum: $GENERATED_CHECKSUM"
    exit 0
else
    echo "❌ VALIDATION FAILED: Generated catalog differs from upstream FBC catalog"
    echo "   - Generated catalog: $GENERATED_SIZE lines, checksum: $GENERATED_CHECKSUM"
    echo "   - Upstream catalog: $UPSTREAM_SIZE lines, checksum: $UPSTREAM_CHECKSUM"

    # Show differences
    echo ""
    echo "Differences found:"
    echo "=================="
    if ! diff -u "$UPSTREAM_CATALOG_FILE" "$CATALOG_FILE"; then
        echo "=================="
    fi

    if [[ "$CLEANUP" == "false" ]]; then
        echo ""
        echo "Temporary files preserved at: $TEMP_DIR"
        echo "Generated catalog: $CATALOG_FILE"
        echo "Upstream catalog: $UPSTREAM_CATALOG_FILE"
    fi

    exit 1
fi
