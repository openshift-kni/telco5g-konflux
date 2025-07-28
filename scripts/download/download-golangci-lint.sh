#!/usr/bin/env bash

# This script automates the download and installation of golangci-lint, a fast linters runner for Go.
# It first checks if golangci-lint is available in the system PATH or local install directory.
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

# Default version of golangci-lint to be installed.
# You can find the latest version on the golangci-lint GitHub releases page:
# https://github.com/golangci/golangci-lint/releases
DEFAULT_VERSION="v1.64.8"

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [VERSION]

Downloads and installs golangci-lint, a fast linters runner for Go, if necessary.
Checks system PATH and local install directory first, and only downloads
if the existing version doesn't meet the minimum requirement.

Arguments:
    VERSION               Minimum version required (default: ${DEFAULT_VERSION})
                         Format: vX.Y.Z (e.g., v1.57.0)

Options:
    -d, --install-dir DIR Install directory (default: ${DEFAULT_INSTALL_DIR})
    -h, --help            Show this help message

Environment Variables:
    INSTALL_DIR           Install directory (overridden by -d/--install-dir)

Examples:
    $0                                    # Ensure default version is available
    $0 v1.55.0                           # Ensure minimum version v1.55.0 is available
    $0 -d /usr/local/bin v1.55.0         # Install to custom directory if needed
    $0 --install-dir /tmp/tools          # Install to custom directory if needed
    INSTALL_DIR=/opt/bin $0              # Install using environment variable
    $0 --help                            # Show help

EOF
}

# Function to compare version strings
# Returns 0 if version1 >= version2, 1 otherwise
version_compare() {
    local version1="$1"
    local version2="$2"

    # Remove 'v' prefix if present
    version1="${version1#v}"
    version2="${version2#v}"

    # Use sort -V to compare versions
    if [[ "$(printf '%s\n' "$version1" "$version2" | sort -V | head -n1)" == "$version2" ]]; then
        return 0  # version1 >= version2
    else
        return 1  # version1 < version2
    fi
}

# Function to get golangci-lint version from a binary path
get_golangci_lint_version() {
    local binary_path="$1"

    if [[ -x "$binary_path" ]]; then
        # Try to get version, extract just the version number (with or without 'v' prefix)
        local version_output
        if version_output=$(bash -c "$binary_path --version" 2>/dev/null); then
            # Extract version number, add 'v' prefix if not present
            local version_num
            version_num=$(echo "$version_output" | grep -o -E 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            if [[ -n "$version_num" && "$version_num" != v* ]]; then
                echo "v$version_num"
            else
                echo "$version_num"
            fi
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

    # Define the full path where the golangci-lint binary will be saved.
    local install_path="${install_dir}/golangci-lint"

    echo "Checking for golangci-lint with minimum version ${version}..."

    # Check if golangci-lint is available in system PATH
    local system_binary=""
    if system_binary=$(command -v golangci-lint 2>/dev/null); then
        echo "Found golangci-lint in system PATH: $system_binary"

        local system_version
        if system_version=$(get_golangci_lint_version "$system_binary"); then
            echo "System golangci-lint version: $system_version"

            if version_compare "$system_version" "$version"; then
                echo "System golangci-lint version $system_version meets minimum requirement $version"
                return 0
            else
                echo "System golangci-lint version $system_version is below minimum requirement $version"
            fi
        else
            echo "Could not determine system golangci-lint version"
        fi
    else
        echo "golangci-lint not found in system PATH"
    fi

    # Check if golangci-lint exists in local install directory
    if [[ -x "$install_path" ]]; then
        echo "Found golangci-lint in local install directory: $install_path"

        local local_version
        if local_version=$(get_golangci_lint_version "$install_path"); then
            echo "Local golangci-lint version: $local_version"

            if version_compare "$local_version" "$version"; then
                echo "Local golangci-lint version $local_version meets minimum requirement $version"
                return 0
            else
                echo "Local golangci-lint version $local_version is below minimum requirement $version"
            fi
        else
            echo "Could not determine local golangci-lint version"
        fi
    else
        echo "golangci-lint not found in local install directory: $install_path"
    fi

    # No suitable version found, proceed with download
    echo "Downloading golangci-lint ${version}..."

    # Detect the system's machine architecture (e.g., x86_64, arm64, aarch64).
    local arch
    arch=$(uname -m)

    # Detect the system's operating system name (e.g., Darwin, Linux).
    local os
    os=$(uname)

    # Normalize the OS name to match the format used in golangci-lint releases.
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

    # Normalize the architecture name to match the format used in golangci-lint releases.
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
    # Format: https://github.com/golangci/golangci-lint/releases/download/{version}/golangci-lint-{version_no_v}-{os}-{arch}.tar.gz
    # Note: The filename uses version without 'v' prefix, but the download path uses the full version
    local version_no_v="${version#v}"  # Remove 'v' prefix if present
    local url="https://github.com/golangci/golangci-lint/releases/download/${version}/golangci-lint-${version_no_v}-${os}-${arch}.tar.gz"

    # Create a temporary directory for extraction
    local temp_dir="${install_dir}/.golangci-lint-tmp"
    mkdir -p "$temp_dir"

    # Download the golangci-lint binary using curl. The binary is packaged in a tar.gz archive.
    # -L: Follow redirects
    # -s: Silent mode (don't show progress)
    # -o: Output to specific file
    # --write-out: Output HTTP response code
    echo "Fetching golangci-lint ${version} with url '${url}'"

    local temp_file="${temp_dir}/golangci-lint.tar.gz"
    local http_code
    http_code=$(curl -L -s -o "${temp_file}" --write-out "%{http_code}" "${url}" 2>/dev/null)
    local curl_exit_code=$?

    if [[ $curl_exit_code -ne 0 ]]; then
        # Clean up temporary directory if it exists
        [[ -d "$temp_dir" ]] && rm -rf "$temp_dir"
        echo "Error: Failed to download golangci-lint version ${version} (curl failed with exit code ${curl_exit_code})"
        exit 1
    fi

    if [[ "$http_code" -ne 200 ]]; then
        # Clean up temporary directory if it exists
        [[ -d "$temp_dir" ]] && rm -rf "$temp_dir"

        if [[ "$http_code" -eq 404 ]]; then
            echo "Error: golangci-lint version ${version} not found for ${os}/${arch}"
            echo "Available versions can be found at: https://github.com/golangci/golangci-lint/releases"
        else
            echo "Error: Failed to download golangci-lint version ${version} (HTTP ${http_code})"
        fi
        exit 1
    fi

    # Verify the downloaded file is not empty and appears to be a binary
    if [[ ! -s "$temp_file" ]]; then
        echo "Error: Downloaded file is empty"
        rm -rf "$temp_dir"
        exit 1
    fi

    # Check if the file starts with common error messages (case-insensitive)
    local first_line
    first_line=$(head -n 1 "$temp_file" 2>/dev/null || echo "")
    if [[ "$first_line" =~ ^[[:space:]]*(Not[[:space:]]+Found|404|Error|<html|<HTML) ]]; then
        echo "Error: Downloaded file appears to be an error message, not a binary"
        echo "First line: $first_line"
        rm -rf "$temp_dir"
        exit 1
    fi

    # Extract the tar.gz file
    echo "Extracting golangci-lint archive"
    if ! tar -xzf "${temp_file}" -C "${temp_dir}" > /dev/null 2>&1; then
        echo "Error: Failed to extract golangci-lint archive"
        rm -rf "$temp_dir"
        exit 1
    fi

    # Find the extracted binary (it should be in a subdirectory)
    local extracted_binary=""
    if [[ -f "${temp_dir}/golangci-lint-${version_no_v}-${os}-${arch}/golangci-lint" ]]; then
        extracted_binary="${temp_dir}/golangci-lint-${version_no_v}-${os}-${arch}/golangci-lint"
    else
        # Try to find it anywhere in the temp directory
        extracted_binary=$(find "$temp_dir" -name "golangci-lint" -type f | head -n 1)
    fi

    if [[ -z "$extracted_binary" || ! -f "$extracted_binary" ]]; then
        echo "Error: Could not find golangci-lint binary in extracted archive"
        rm -rf "$temp_dir"
        exit 1
    fi

    # Move the binary to the final location
    mv "$extracted_binary" "$install_path"

    # Clean up temporary directory
    rm -rf "$temp_dir"

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
    echo "golangci-lint version ${version} installed successfully to ${install_path}"
    echo "Installed version: ${actual_version}"
}

# Execute the main function, passing along any arguments provided to the script.
main "$@"