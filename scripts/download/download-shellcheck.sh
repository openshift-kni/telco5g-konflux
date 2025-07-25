#!/usr/bin/env bash

# This script automates the download and installation of shellcheck, a static analysis tool for shell scripts.
# It first checks if shellcheck is available in the system PATH or local install directory.
# If found, it compares the version to ensure it meets the minimum requirement.
# It only downloads if no suitable version is found.

# Configure shell to exit immediately if a command exits with a non-zero status,
# treat unset variables as an error, and fail a pipeline if any command fails.
set -eou pipefail

# Determine the absolute path of the directory containing this script. This allows
# the script to reliably locate other files relative to its own location.
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Default installation directory relative to the script's location.
DEFAULT_INSTALL_DIR="${SCRIPT_DIR}/../bin"

# The default version of shellcheck to install.
# You can find the latest version on the shellcheck GitHub releases page:
# https://github.com/koalaman/shellcheck/releases
DEFAULT_VERSION="v0.10.0"

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [VERSION]

Downloads and installs shellcheck, a static analysis tool for shell scripts.

Arguments:
  VERSION                     The shellcheck version to install (default: $DEFAULT_VERSION)
                             Must be in format vX.Y.Z (e.g., v0.10.0)
                             Available versions: https://github.com/koalaman/shellcheck/releases

Options:
  --install-dir DIR          Directory to install shellcheck binary (default: $DEFAULT_INSTALL_DIR)
  --force                    Force download even if a compatible version exists
  --help                     Show this help message and exit
  --verbose                  Enable verbose output for debugging

Examples:
  $0                                    # Install default version ($DEFAULT_VERSION)
  $0 v0.9.0                            # Install specific version
  $0 --install-dir /usr/local/bin      # Install to custom directory
  $0 --force v0.10.0                   # Force install even if already present

For more information about shellcheck, visit: https://github.com/koalaman/shellcheck
EOF
}

log() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2
    fi
}

error() {
    echo "Error: $1" >&2
    exit 1
}

# Function to compare semantic versions
# Returns 0 if version1 >= version2, 1 otherwise
version_gte() {
    local version1="$1"
    local version2="$2"

    # Remove 'v' prefix if present
    version1="${version1#v}"
    version2="${version2#v}"

    # Use sort -V for version comparison
    if printf '%s\n%s\n' "$version2" "$version1" | sort -V | head -n1 | grep -q "^$version2$"; then
        return 0
    else
        return 1
    fi
}

# Function to detect the current platform and architecture
detect_platform() {
    local os arch

    case "$(uname -s)" in
        Linux*)     os="linux" ;;
        Darwin*)    os="darwin" ;;
        CYGWIN*|MINGW*|MSYS*) os="windows" ;;
        *)          error "Unsupported operating system: $(uname -s)" ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64)   arch="x86_64" ;;
        arm64|aarch64)  arch="aarch64" ;;
        armv6l)         arch="armv6hf" ;;
        *)              error "Unsupported architecture: $(uname -m)" ;;
    esac

    echo "${os}.${arch}"
}

# Function to check if a command exists and get its version
check_existing_version() {
    local binary_path="$1"

    if [[ -x "$binary_path" ]]; then
        local existing_version
        if existing_version=$("$binary_path" --version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -n1); then
            # Add 'v' prefix if not present to ensure consistent format
            if [[ "$existing_version" != v* ]]; then
                existing_version="v$existing_version"
            fi
            echo "$existing_version"
            return 0
        fi
    fi
    return 1
}

# Function to validate version format
validate_version() {
    local version="$1"
    if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        error "Invalid version format: $version. Expected format: vX.Y.Z (e.g., v0.10.0)"
    fi
}

# Parse command line arguments
INSTALL_DIR="$DEFAULT_INSTALL_DIR"
VERSION="$DEFAULT_VERSION"
FORCE_INSTALL=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --force)
            FORCE_INSTALL=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            VERSION="$1"
            shift
            ;;
    esac
done

# Validate the version format
validate_version "$VERSION"

# Create install directory if it doesn't exist
mkdir -p "$INSTALL_DIR"

# Make install directory absolute
INSTALL_DIR=$(cd "$INSTALL_DIR" && pwd)

BINARY_PATH="$INSTALL_DIR/shellcheck"

log "Checking for existing shellcheck installation"

# Check if shellcheck already exists and meets version requirement
if [[ "$FORCE_INSTALL" != "true" ]]; then
    # Check local installation first
    if existing_version=$(check_existing_version "$BINARY_PATH"); then
        log "Found existing shellcheck at $BINARY_PATH (version: $existing_version)"
        if version_gte "$existing_version" "$VERSION"; then
            echo "shellcheck $existing_version is already installed at $BINARY_PATH and meets the required version ($VERSION)"
            exit 0
        else
            log "Existing version $existing_version is older than required $VERSION, will upgrade"
        fi
    fi

    # Check system PATH
    if command -v shellcheck >/dev/null 2>&1; then
        if existing_version=$(check_existing_version "$(command -v shellcheck)"); then
            log "Found existing shellcheck in PATH (version: $existing_version)"
            if version_gte "$existing_version" "$VERSION"; then
                echo "shellcheck $existing_version is already available in PATH and meets the required version ($VERSION)"
                exit 0
            else
                log "Existing version $existing_version in PATH is older than required $VERSION, will install to $INSTALL_DIR"
            fi
        fi
    fi
fi

# Detect platform and architecture
PLATFORM=$(detect_platform)
log "Detected platform: $PLATFORM"

# Construct download URL
DOWNLOAD_URL="https://github.com/koalaman/shellcheck/releases/download/${VERSION}/shellcheck-${VERSION}.${PLATFORM}.tar.xz"

log "Download URL: $DOWNLOAD_URL"

# Create temporary directory for download
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

log "Downloading shellcheck $VERSION for $PLATFORM"

# Download the archive
if ! curl -sSL "$DOWNLOAD_URL" -o "$TEMP_DIR/shellcheck.tar.xz"; then
    error "Failed to download shellcheck $VERSION for $PLATFORM. Please check if the version and platform are supported."
fi

log "Extracting shellcheck binary"

# Extract the archive
cd "$TEMP_DIR"
if ! tar -xf shellcheck.tar.xz; then
    error "Failed to extract shellcheck archive"
fi

# Find the extracted binary (it should be in a subdirectory)
EXTRACTED_BINARY=$(find . -name "shellcheck" -type f -executable | head -n1)
if [[ -z "$EXTRACTED_BINARY" ]]; then
    error "Could not find shellcheck binary in extracted archive"
fi

log "Installing shellcheck to $BINARY_PATH"

# Copy the binary to the installation directory
cp "$EXTRACTED_BINARY" "$BINARY_PATH"
chmod +x "$BINARY_PATH"

# Verify the installation
if ! INSTALLED_VERSION=$(check_existing_version "$BINARY_PATH"); then
    error "Failed to verify shellcheck installation"
fi

echo "Successfully installed shellcheck $INSTALLED_VERSION to $BINARY_PATH"

# Show usage tip if install directory is not in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo ""
    echo "Note: $INSTALL_DIR is not in your PATH."
    echo "To use shellcheck, either:"
    echo "  1. Add $INSTALL_DIR to your PATH"
    echo "  2. Use the full path: $BINARY_PATH"
fi