#!/usr/bin/env bash

# This script automates the download and installation of yq, a command-line YAML processor.
# It checks if yq is available in the local install directory with the exact required version.
# It downloads and installs yq to the local directory if not found or if the version
# doesn't exactly match the specified version.

# Configure shell to exit immediately if a command exits with a non-zero status,
# treat unset variables as an error, and fail a pipeline if any command fails.
set -eou pipefail

# Determine the absolute path of the directory containing this script. This allows
# the script to reliably locate other files relative to its own location.
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Default installation directory relative to the script's location.
DEFAULT_INSTALL_DIR="${SCRIPT_DIR}/../bin"

# Default version of yq to be installed.
# You can find the latest version on the yq GitHub releases page:
# https://github.com/mikefarah/yq/releases
DEFAULT_VERSION="v4.45.4"

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [VERSION]

Downloads and installs yq, a command-line YAML processor, if necessary.
Checks local install directory first, and only downloads if the existing
version doesn't exactly match the specified version.

Arguments:
    VERSION               Exact version required (default: ${DEFAULT_VERSION})
                         Format: vX.Y.Z (e.g., v4.45.4)

Options:
    -d, --install-dir DIR Install directory (default: ${DEFAULT_INSTALL_DIR})
    -h, --help            Show this help message

Environment Variables:
    INSTALL_DIR           Install directory (overridden by -d/--install-dir)

Examples:
    $0                                   # Ensure default version is available locally
    $0 v4.44.2                           # Ensure exact version v4.44.2 is available locally
    $0 -d /usr/local/bin v4.44.2         # Install to custom directory if needed
    $0 --install-dir /tmp/tools          # Install to custom directory if needed
    INSTALL_DIR=/opt/bin $0              # Install using environment variable
    $0 --help                            # Show help

EOF
}

# Function to check if two version strings are exactly equal
# Returns 0 if version1 == version2, 1 otherwise
version_exact_match() {
    local version1="$1"
    local version2="$2"

    # Remove 'v' prefix if present
    version1="${version1#v}"
    version2="${version2#v}"

    # Check for exact match
    if [[ "$version1" == "$version2" ]]; then
        return 0  # versions match exactly
    else
        return 1  # versions don't match
    fi
}

# Function to get yq version from a binary path
get_yq_version() {
    local binary_path="$1"

    if [[ -x "$binary_path" ]]; then
        # Try to get version, extract just the version number
        local version_output
        if version_output=$(bash -c "$binary_path --version" 2>/dev/null); then
            echo "$version_output" | grep -o 'v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' | head -1
        fi
    fi
}

main() {
    # Parse command line arguments
    local version="${DEFAULT_VERSION}"
    local install_dir="${INSTALL_DIR:-${DEFAULT_INSTALL_DIR}}"

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--install-dir)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --install-dir requires a directory argument"
                    usage
                    exit 1
                fi
                install_dir="$2"
                shift 2
                ;;
            -*)
                echo "Error: Unknown option $1"
                usage
                exit 1
                ;;
            *)
                # Positional argument is version
                if [[ "$1" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    version="$1"
                    # Add 'v' prefix if not present
                    if [[ "$version" != v* ]]; then
                        version="v$version"
                    fi
                    shift
                else
                    echo "Error: Invalid version format: $1 (should be vX.Y.Z or X.Y.Z)"
                    usage
                    exit 1
                fi
                ;;
        esac
    done

    # Define the full path where the yq binary will be saved.
    local install_path="${install_dir}/yq"

    echo "Checking for yq with exact version ${version} in local install directory..."

    # Check if yq exists in local install directory
    if [[ -x "$install_path" ]]; then
        echo "Found yq in local install directory: $install_path"

        local local_version
        if local_version=$(get_yq_version "$install_path"); then
            echo "Local yq version: $local_version"

            if version_exact_match "$local_version" "$version"; then
                echo "Local yq version $local_version matches required version $version"
                return 0
            else
                echo "Local yq version $local_version does not match required version $version"
            fi
        else
            echo "Could not determine local yq version"
        fi
    else
        echo "yq not found in local install directory: $install_path"
    fi

    # No exact version match found, proceed with download
    echo "Downloading yq ${version}..."

    # Detect the system's machine architecture (e.g., x86_64, arm64, aarch64).
    local arch
    arch=$(uname -m)

    # Detect the system's operating system name (e.g., Darwin, Linux).
    local os
    os=$(uname)

    # Normalize the OS name to match the format used in yq releases.
    # 'Darwin', the name for macOS, is normalized to 'darwin'.
    if [[ "${os}" == "Darwin" ]]; then
        os="darwin"
        echo "Normalized OS name to '${os}'"
    fi
    # 'Linux' is normalized to 'linux'.
    if [[ "${os}" == "Linux" ]]; then
        os="linux"
        echo "Normalized OS name to '${os}'"
    fi

    # Normalize the architecture name to match the format used in yq releases.
    # 'x86_64' is normalized to 'amd64'.
    if [[ "${arch}" == "x86_64" ]]; then
        arch="amd64"
        echo "Normalized architecture to '${arch}'"
    fi
    # 'aarch64' is normalized to 'arm64'.
    if [[ "${arch}" == "aarch64" ]]; then
        arch="arm64"
        echo "Normalized architecture to '${arch}'"
    fi
    # 'arm64' stays as 'arm64'.
    if [[ "${arch}" == "arm64" ]]; then
        echo "Using architecture '${arch}'"
    fi

    # Create the installation directory if it doesn't already exist.
    # The '-p' flag ensures that parent directories are also created if needed.
    echo "Creating directory '${install_dir}'"
    mkdir -p "${install_dir}"

    # Construct the download URL for the specified version, OS, and architecture.
    # Format: https://github.com/mikefarah/yq/releases/download/{version}/yq_{os}_{arch}
    local url="https://github.com/mikefarah/yq/releases/download/${version}/yq_${os}_${arch}"

    # Create a temporary file for the download
    local temp_file="${install_path}.tmp"

    # Download the yq binary using curl. The binary is directly executable, so we
    # don't need to extract it from an archive.
    # -L: Follow redirects
    # -s: Silent mode (don't show progress)
    # -o: Output to specific file
    # --write-out: Output HTTP response code
    echo "Fetching yq ${version} with url '${url}'"

    local http_code
    http_code=$(curl -L -s -o "${temp_file}" --write-out "%{http_code}" "${url}" 2>/dev/null)
    local curl_exit_code=$?

    if [[ $curl_exit_code -ne 0 ]]; then
        # Clean up temporary file if it exists
        [[ -f "$temp_file" ]] && rm -f "$temp_file"
        echo "Error: Failed to download yq version ${version} (curl failed with exit code ${curl_exit_code})"
        exit 1
    fi

    if [[ "$http_code" -ne 200 ]]; then
        # Clean up temporary file if it exists
        [[ -f "$temp_file" ]] && rm -f "$temp_file"

        if [[ "$http_code" -eq 404 ]]; then
            echo "Error: yq version ${version} not found for ${os}/${arch}"
            echo "Available versions can be found at: https://github.com/mikefarah/yq/releases"
        else
            echo "Error: Failed to download yq version ${version} (HTTP ${http_code})"
        fi
        exit 1
    fi

    # Verify the downloaded file is not empty and appears to be a binary
    if [[ ! -s "$temp_file" ]]; then
        echo "Error: Downloaded file is empty"
        rm -f "$temp_file"
        exit 1
    fi

    # Check if the file starts with common error messages (case-insensitive)
    local first_line
    first_line=$(head -n 1 "$temp_file" 2>/dev/null || echo "")
    if [[ "$first_line" =~ ^[[:space:]]*(Not[[:space:]]+Found|404|Error|<html|<HTML) ]]; then
        echo "Error: Downloaded file appears to be an error message, not a binary"
        echo "First line: $first_line"
        rm -f "$temp_file"
        exit 1
    fi

    # Move the temporary file to the final location
    mv "$temp_file" "$install_path"

    # Make the downloaded file executable.
    chmod +x "${install_path}"

    # Verify that the downloaded binary runs and reports a version.
    # This confirms the download and installation were successful.
    if ! bash -c "${install_path} --version" > /dev/null 2>&1; then
        echo "Failed to install tool - binary doesn't execute properly"
        exit 1
    fi

    # Get the actual version for confirmation
    actual_version=$(bash -c "${install_path} --version" | head -1 || echo "version check failed")
    echo "yq version ${version} installed successfully to ${install_path}"
    echo "Installed version: ${actual_version}"
}

# Execute the main function, passing along any arguments provided to the script.
main "$@"
