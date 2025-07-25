#!/usr/bin/env bash

# This script automates the download and installation of bashate, a code style enforcement tool for bash programs.
# It creates a local Python virtual environment and installs bashate via pip, then creates
# a wrapper script to execute bashate from the virtual environment.

set -eou pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Default installation directory relative to the script's location.
DEFAULT_INSTALL_DIR="${SCRIPT_DIR}/../bin"

# The default version of bashate to install.
# You can find the latest version on the bashate PyPI page:
# https://pypi.org/project/bashate/
DEFAULT_VERSION="2.1.1"

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [VERSION]

Downloads and installs bashate, a code style enforcement tool for bash programs.

Arguments:
  VERSION                     The bashate version to install (default: $DEFAULT_VERSION)
                             Must be in format X.Y.Z (e.g., 2.1.1)
                             Available versions: https://pypi.org/project/bashate/#history

Options:
  --install-dir DIR          Directory to install bashate wrapper script (default: $DEFAULT_INSTALL_DIR)
  --force                    Force download even if a compatible version exists
  --help                     Show this help message and exit
  --verbose                  Enable verbose output for debugging

Examples:
  $0                                    # Install default version ($DEFAULT_VERSION)
  $0 2.1.0                             # Install specific version
  $0 --install-dir /usr/local/bin      # Install to custom directory
  $0 --force 2.1.1                    # Force install even if already present

For more information about bashate, visit: https://github.com/openstack/bashate
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

    # Use sort -V for version comparison
    if printf '%s\n%s\n' "$version2" "$version1" | sort -V | head -n1 | grep -q "^$version2$"; then
        return 0
    else
        return 1
    fi
}

# Function to check if a command exists and get its version
check_existing_version() {
    local binary_path="$1"

    if [[ -x "$binary_path" ]]; then
        local existing_version
        if existing_version=$("$binary_path" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1); then
            echo "$existing_version"
            return 0
        fi
    fi
    return 1
}

# Function to validate version format
validate_version() {
    local version="$1"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        error "Invalid version format: $version. Expected format: X.Y.Z (e.g., 2.1.1)"
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

WRAPPER_PATH="$INSTALL_DIR/bashate"
VENV_DIR="$INSTALL_DIR/.bashate-venv"

log "Checking for existing bashate installation"

# Check if bashate already exists and meets version requirement
if [[ "$FORCE_INSTALL" != "true" ]]; then
    # Check local installation first
    if existing_version=$(check_existing_version "$WRAPPER_PATH"); then
        log "Found existing bashate at $WRAPPER_PATH (version: $existing_version)"
        if version_gte "$existing_version" "$VERSION"; then
            echo "bashate $existing_version is already installed at $WRAPPER_PATH and meets the required version ($VERSION)"
            exit 0
        else
            log "Existing version $existing_version is older than required $VERSION, will upgrade"
        fi
    fi

    # Check system PATH
    if command -v bashate >/dev/null 2>&1; then
        if existing_version=$(check_existing_version "$(command -v bashate)"); then
            log "Found existing bashate in PATH (version: $existing_version)"
            if version_gte "$existing_version" "$VERSION"; then
                echo "bashate $existing_version is already available in PATH and meets the required version ($VERSION)"
                exit 0
            else
                log "Existing version $existing_version in PATH is older than required $VERSION, will install to $INSTALL_DIR"
            fi
        fi
    fi
fi

# Check if Python 3 is available
if ! command -v python3 >/dev/null 2>&1; then
    error "Python 3 is required but not found. Please install Python 3 and try again."
fi

log "Creating Python virtual environment for bashate"

# Remove existing virtual environment if doing a forced install
if [[ "$FORCE_INSTALL" == "true" && -d "$VENV_DIR" ]]; then
    log "Removing existing virtual environment"
    rm -rf "$VENV_DIR"
fi

# Create virtual environment if it doesn't exist
if [[ ! -d "$VENV_DIR" ]]; then
    if ! python3 -m venv "$VENV_DIR"; then
        error "Failed to create Python virtual environment at $VENV_DIR"
    fi
fi

# Activate virtual environment and install bashate
log "Installing bashate $VERSION in virtual environment"
if ! "$VENV_DIR/bin/pip" install --upgrade pip setuptools wheel; then
    error "Failed to upgrade pip in virtual environment"
fi

if ! "$VENV_DIR/bin/pip" install "bashate==$VERSION"; then
    error "Failed to install bashate $VERSION. Please check if the version exists."
fi

log "Creating wrapper script at $WRAPPER_PATH"

# Create wrapper script
cat > "$WRAPPER_PATH" << 'WRAPPER_EOF'
#!/usr/bin/env bash
# Auto-generated bashate wrapper script
# This script activates the bashate virtual environment and runs bashate

set -eou pipefail

# Get the directory containing this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.bashate-venv"

# Check if virtual environment exists
if [[ ! -d "$VENV_DIR" ]]; then
    echo "Error: bashate virtual environment not found at $VENV_DIR" >&2
    echo "Please run the bashate installation script again." >&2
    exit 1
fi

# Execute bashate with all provided arguments
exec "$VENV_DIR/bin/bashate" "$@"
WRAPPER_EOF

chmod +x "$WRAPPER_PATH"

# Verify the installation
if ! INSTALLED_VERSION=$(check_existing_version "$WRAPPER_PATH"); then
    error "Failed to verify bashate installation"
fi

echo "Successfully installed bashate $INSTALLED_VERSION to $WRAPPER_PATH"
echo "Virtual environment located at: $VENV_DIR"

# Show usage tip if install directory is not in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo ""
    echo "Note: $INSTALL_DIR is not in your PATH."
    echo "To use bashate, either:"
    echo "  1. Add $INSTALL_DIR to your PATH"
    echo "  2. Use the full path: $WRAPPER_PATH"
fi