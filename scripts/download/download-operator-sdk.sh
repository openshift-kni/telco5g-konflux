#!/usr/bin/env bash

# This script automates the download and installation of operator-sdk from GitHub releases.
# It first checks if operator-sdk is available in the system PATH or local install directory.
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

# Default operator-sdk version for download from GitHub releases.
# You can find available versions at:
# https://github.com/operator-framework/operator-sdk/releases
DEFAULT_OPERATOR_SDK_VERSION="1.40.0"

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [OPERATOR_SDK_VERSION]

Downloads and installs operator-sdk from GitHub releases if necessary.
Checks system PATH and local install directory first, and only downloads
if the existing version doesn't meet the minimum requirement.

Arguments:
    OPERATOR_SDK_VERSION  Minimum operator SDK version required (default: ${DEFAULT_OPERATOR_SDK_VERSION})
                         Format: X.Y.Z (e.g., 1.40.0) or vX.Y.Z (e.g., v1.40.0)

Options:
    -d, --install-dir DIR Install directory (default: ${DEFAULT_INSTALL_DIR})
    -h, --help            Show this help message

Environment Variables:
    INSTALL_DIR             Install directory (overridden by -d/--install-dir)
    OPERATOR_SDK_VERSION    Minimum operator SDK version (overridden by positional argument)

Examples:
    $0                                    # Ensure default version is available
    $0 1.40.0                            # Ensure minimum version 1.40.0 is available
    $0 v1.40.0                           # Ensure minimum version 1.40.0 is available (with v prefix)
    $0 -d /usr/local/bin 1.40.0          # Install to custom directory if needed
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

# Function to get operator-sdk version from a binary path
get_operator_sdk_version() {
    local binary_path="$1"

    if [[ -x "$binary_path" ]]; then
        # Try to get version, extract just the version number
        local version_output
        if version_output=$(bash -c "$binary_path version" 2>/dev/null); then
            echo "$version_output" | head -1 | grep -o 'v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' | head -1
        fi
    fi
}

main() {
    # Parse command line arguments
    local operator_sdk_version="${OPERATOR_SDK_VERSION:-${DEFAULT_OPERATOR_SDK_VERSION}}"
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
                # Positional argument is operator SDK version
                # Accept both X.Y.Z and vX.Y.Z formats
                local version_arg="$1"
                # Remove 'v' prefix if present
                version_arg="${version_arg#v}"

                if [[ "$version_arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    operator_sdk_version="$version_arg"
                    shift
                else
                    echo "Error: Invalid operator SDK version format: $1 (should be X.Y.Z)"
                    usage
                    exit 1
                fi
                ;;
        esac
    done

    # Define the full path where the operator-sdk binary will be saved.
    local install_path="${install_dir}/operator-sdk"

    echo "Checking for operator-sdk with minimum version v${operator_sdk_version}..."

    # Check if operator-sdk is available in system PATH
    local system_binary=""
    if system_binary=$(command -v operator-sdk 2>/dev/null); then
        echo "Found operator-sdk in system PATH: $system_binary"

        local system_version
        if system_version=$(get_operator_sdk_version "$system_binary"); then
            echo "System operator-sdk version: $system_version"

            if version_compare "$system_version" "v$operator_sdk_version"; then
                echo "System operator-sdk version $system_version meets minimum requirement v$operator_sdk_version"
                return 0
            else
                echo "System operator-sdk version $system_version is below minimum requirement v$operator_sdk_version"
            fi
        else
            echo "Could not determine system operator-sdk version"
        fi
    else
        echo "operator-sdk not found in system PATH"
    fi

    # Check if operator-sdk exists in local install directory
    if [[ -x "$install_path" ]]; then
        echo "Found operator-sdk in local install directory: $install_path"

        local local_version
        if local_version=$(get_operator_sdk_version "$install_path"); then
            echo "Local operator-sdk version: $local_version"

            if version_compare "$local_version" "v$operator_sdk_version"; then
                echo "Local operator-sdk version $local_version meets minimum requirement v$operator_sdk_version"
                return 0
            else
                echo "Local operator-sdk version $local_version is below minimum requirement v$operator_sdk_version"
            fi
        else
            echo "Could not determine local operator-sdk version"
        fi
    else
        echo "operator-sdk not found in local install directory: $install_path"
    fi

    # No suitable version found, proceed with download
    echo "Downloading operator-sdk v$operator_sdk_version..."

    # Detect the system's machine architecture (e.g., x86_64, aarch64).
    arch=$(uname -m)
    # Detect the system's operating system name (e.g., Darwin, Linux).
    os=$(uname)

    # Normalize the OS name to match the format used in GitHub releases.
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

    # Normalize the architecture name to match the format used in GitHub releases.
    # Note: GitHub releases use different architecture naming than OpenShift mirror
    if [[ "${arch}" == "aarch64" ]]; then
        arch="arm64"
        echo "Normalized architecture to '${arch}'"
    elif [[ "${arch}" == "x86_64" ]]; then
        arch="amd64"
        echo "Normalized architecture to '${arch}'"
    fi

    # Create the installation directory if it doesn't already exist.
    # The '-p' flag ensures that parent directories are also created if needed.
    echo "Creating directory '${install_dir}'"
    mkdir -p "${install_dir}"

    # Construct the download URL for the specified version, OS, and architecture.
    # Format: https://github.com/operator-framework/operator-sdk/releases/download/v{version}/operator-sdk_{os}_{arch}
    url="https://github.com/operator-framework/operator-sdk/releases/download/v${operator_sdk_version}/operator-sdk_${os}_${arch}"

    # Create a temporary file for the download
    local temp_file="${install_path}.tmp"

    # Download the operator-sdk binary using curl.
    # -L: Follow redirects
    # -s: Silent mode (don't show progress)
    # -o: Output to specific file
    # --write-out: Output HTTP response code
    echo "Fetching operator-sdk version v${operator_sdk_version} with url '${url}'"

    local http_code
    http_code=$(curl -L -s -o "${temp_file}" --write-out "%{http_code}" "${url}" 2>/dev/null)
    local curl_exit_code=$?

    if [[ $curl_exit_code -ne 0 ]]; then
        # Clean up temporary file if it exists
        [[ -f "$temp_file" ]] && rm -f "$temp_file"
        echo "Error: Failed to download operator-sdk version v${operator_sdk_version} (curl failed with exit code ${curl_exit_code})"
        exit 1
    fi

    if [[ "$http_code" -ne 200 ]]; then
        # Clean up temporary file if it exists
        [[ -f "$temp_file" ]] && rm -f "$temp_file"

        if [[ "$http_code" -eq 404 ]]; then
            echo "Error: operator-sdk version v${operator_sdk_version} not found for ${os}/${arch}"
            echo "Available versions can be found at: https://github.com/operator-framework/operator-sdk/releases"
        else
            echo "Error: Failed to download operator-sdk version v${operator_sdk_version} (HTTP ${http_code})"
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
    if ! bash -c "${install_path} version" > /dev/null 2>&1; then
        echo "Failed to install tool - binary doesn't execute properly"
        exit 1
    fi

    # Get the actual version for confirmation
    actual_version=$(bash -c "${install_path} version" | head -1 || echo "version check failed")
    echo "operator-sdk installed successfully to ${install_path}"
    echo "Installed version: ${actual_version}"
}

# Execute the main function, passing along any arguments provided to the script.
main "$@"
