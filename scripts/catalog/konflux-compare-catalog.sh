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

# Check if podman is available
if ! command -v podman >/dev/null 2>&1; then
    echo "ERROR: podman is required but not installed" >&2
    exit 1
fi

# Pull the upstream image
verbose_log "Pulling upstream image: $UPSTREAM_IMAGE"
if ! podman pull "$UPSTREAM_IMAGE" >/dev/null 2>&1; then
    echo "ERROR: Failed to pull upstream image: $UPSTREAM_IMAGE" >&2
    exit 1
fi

# Extract the catalog from the upstream image
verbose_log "Extracting catalog from upstream image"
if ! podman run --rm --entrypoint /bin/sh -v "$EXTRACT_DIR:/tmp/extract" "$UPSTREAM_IMAGE" -c "cp -r /configs/* /tmp/extract/" >/dev/null 2>&1; then
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

# Calculate checksums
GENERATED_CHECKSUM=$(md5sum "$CATALOG_FILE" | cut -d' ' -f1)
UPSTREAM_CHECKSUM=$(md5sum "$UPSTREAM_CATALOG_FILE" | cut -d' ' -f1)

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
