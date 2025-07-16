#!/usr/bin/env bash

# This script automates the download and installation of operator-sdk from OpenShift mirror.
# It first checks if operator-sdk is already installed on the system. If not, it automatically
# detects the operating system and architecture, then downloads the appropriate
# tar.gz archive from the OpenShift mirror and extracts the binary.
# The operator SDK version is automatically determined based on the OpenShift version.

# Configure shell to exit immediately if a command exits with a non-zero status,
# treat unset variables as an error, and fail a pipeline if any command fails.
set -eou pipefail

# Determine the absolute path of the directory containing this script. This allows
# the script to reliably locate other files relative to its own location.
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Default installation directory relative to the script's location.
DEFAULT_INSTALL_DIR="${SCRIPT_DIR}/../bin"

# Default OpenShift version for operator-sdk download from OpenShift mirror.
# You can find available versions at:
# https://mirror.openshift.com/pub/openshift-v4/
DEFAULT_OPENSHIFT_VERSION="4.12"

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [OPENSHIFT_VERSION]

Downloads and installs operator-sdk from OpenShift mirror.
The operator SDK version is automatically determined based on the OpenShift version.

Arguments:
    OPENSHIFT_VERSION     OpenShift version for mirror path (default: ${DEFAULT_OPENSHIFT_VERSION})
                        Format: X.Y (e.g., 4.12) or X.Y.Z (e.g., 4.12.76)
                        When using X.Y format, the latest release is automatically found

Options:
    -d, --install-dir DIR Install directory (default: ${DEFAULT_INSTALL_DIR})
    -h, --help            Show this help message

Environment Variables:
    INSTALL_DIR           Install directory (overridden by -d/--install-dir)
    OPENSHIFT_VERSION     OpenShift version (overridden by positional argument)

Examples:
    $0                                    # Install for default OpenShift version to default directory
    $0 4.12                              # Install for latest 4.12.x version
    $0 4.12.76                           # Install for specific OpenShift version
    $0 -d /usr/local/bin 4.12            # Install to custom directory
    $0 --install-dir /tmp/tools          # Install for default OpenShift version to custom directory
    INSTALL_DIR=/opt/bin $0              # Install using environment variable
    $0 --help                            # Show help

EOF
}

# Function to find the latest release for a given Major.Minor version
get_latest_release() {
    local major_minor="$1"
    local arch="$2"

    echo "Finding latest release for OpenShift ${major_minor}..." >&2

    # List the directory contents to find available versions
    local base_url="https://mirror.openshift.com/pub/openshift-v4/${arch}/clients/operator-sdk/"

    local listing
    if listing=$(curl -s "${base_url}" 2>/dev/null); then
        # Extract versions that match the Major.Minor pattern and find the latest
        # Use a portable approach that works on both BSD sed (macOS) and GNU sed (Linux)
        local latest_version
        latest_version=$(echo "$listing" | \
                        grep -o "href=\"${major_minor}\.[0-9][0-9]*/" | \
                        cut -d'"' -f2 | \
                        tr -d '/' | \
                        sort -V | \
                        tail -1)

        if [[ -n "$latest_version" ]]; then
            echo "$latest_version"
            return 0
        fi
    fi

    # If we can't discover it, return empty and we'll handle the error in main
    echo ""
    return 1
}

# Function to determine the operator SDK version for a given OpenShift version
get_operator_sdk_version() {
    local openshift_version="$1"
    local arch="$2"
    local os="$3"

    # List the directory contents to find available operator-sdk files
    local base_url="https://mirror.openshift.com/pub/openshift-v4/${arch}/clients/operator-sdk/${openshift_version}/"

    echo "Discovering available operator-sdk version for OpenShift ${openshift_version}..." >&2

    # Try to get directory listing and extract operator SDK version
    local listing
    if listing=$(curl -s "${base_url}" 2>/dev/null); then
        # Look for operator-sdk files and extract version using portable approach
        local operator_sdk_version
        operator_sdk_version=$(echo "$listing" | \
                        grep -o "operator-sdk-v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*-ocp-${os}-${arch}\.tar\.gz" | \
                        head -1 | \
                        cut -d'-' -f3)

        if [[ -n "$operator_sdk_version" ]]; then
            echo "$operator_sdk_version"
            return 0
        fi
    fi

    # If we can't discover it, return empty and we'll handle the error in main
    echo ""
    return 1
}

main() {
    # Parse command line arguments
    local openshift_version="${OPENSHIFT_VERSION:-${DEFAULT_OPENSHIFT_VERSION}}"
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
                # Positional argument is OpenShift version
                # Accept both X.Y and X.Y.Z formats, with or without 'v' prefix
                local version_arg="$1"
                # Remove 'v' prefix if present
                version_arg="${version_arg#v}"

                if [[ "$version_arg" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
                    openshift_version="$version_arg"
                    shift
                else
                    echo "Error: Invalid OpenShift version format: $1 (should be X.Y or X.Y.Z)"
                    usage
                    exit 1
                fi
                ;;
        esac
    done

    # Define the full path where the operator-sdk binary will be saved.
    local install_path="${install_dir}/operator-sdk"

    # Check if the 'operator-sdk' command is not already available in the system's PATH.
    # The 'which' command returns a non-zero exit code if the command is not found.
    if ! which operator-sdk > /dev/null 2>&1; then
        echo "operator-sdk not found. Starting download..."

        # Detect the system's machine architecture (e.g., x86_64, aarch64).
        arch=$(uname -m)
        # Detect the system's operating system name (e.g., Darwin, Linux).
        os=$(uname)

        # Normalize the OS name to match the format used in OpenShift mirror.
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

        # Normalize the architecture name to match the format used in OpenShift mirror.
        # Note: OpenShift mirror uses different architecture naming than GitHub releases
        if [[ "${arch}" == "arm64" ]]; then
            arch="aarch64"
            echo "Normalized architecture to '${arch}'"
        fi
        # x86_64 stays as x86_64 for OpenShift mirror
        if [[ "${arch}" == "x86_64" ]]; then
            echo "Using architecture '${arch}'"
        fi

        # If the version is in Major.Minor format, find the latest release
        local resolved_version="$openshift_version"
        if [[ "$openshift_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
            echo "Resolving latest release for OpenShift ${openshift_version}..."
            if ! resolved_version=$(get_latest_release "$openshift_version" "$arch"); then
                echo "Error: Could not find latest release for OpenShift ${openshift_version}"
                echo "Please check if the OpenShift version is valid and available on the mirror."
                exit 1
            fi

            if [[ -z "$resolved_version" ]]; then
                echo "Error: No releases found for OpenShift ${openshift_version} on ${arch}"
                echo "Available versions can be found at: https://mirror.openshift.com/pub/openshift-v4/${arch}/clients/operator-sdk/"
                exit 1
            fi

            echo "Found latest release: ${resolved_version}"
        fi

        # Automatically determine the operator SDK version for the given OpenShift version
        echo "Determining operator SDK version for OpenShift ${resolved_version}..."
        local operator_sdk_version
        if ! operator_sdk_version=$(get_operator_sdk_version "$resolved_version" "$arch" "$os"); then
            echo "Error: Could not determine operator SDK version for OpenShift ${resolved_version}"
            echo "Please check if the OpenShift version is valid and available on the mirror."
            exit 1
        fi

        if [[ -z "$operator_sdk_version" ]]; then
            echo "Error: No operator SDK found for OpenShift ${resolved_version} on ${os}/${arch}"
            echo "Available versions can be found at: https://mirror.openshift.com/pub/openshift-v4/${arch}/clients/operator-sdk/"
            exit 1
        fi

        echo "Found operator SDK version: ${operator_sdk_version}"

        # Create the installation directory if it doesn't already exist.
        # The '-p' flag ensures that parent directories are also created if needed.
        echo "Creating directory '${install_dir}'"
        mkdir -p "${install_dir}"

        # Construct the download URL for the specified versions, OS, and architecture.
        # Format: https://mirror.openshift.com/pub/openshift-v4/{arch}/clients/operator-sdk/{openshift_version}/operator-sdk-{operator_sdk_version}-ocp-{os}-{arch}.tar.gz
        url="https://mirror.openshift.com/pub/openshift-v4/${arch}/clients/operator-sdk/${resolved_version}/operator-sdk-${operator_sdk_version}-ocp-${os}-${arch}.tar.gz"

        # Download and extract the operator-sdk archive using curl and tar.
        # -L: Follow redirects
        # -v: Verbose output
        # tar flags: --strip-components 2 removes first 2 directory levels, -xz extracts gzipped tar, -C specifies output directory
        echo "Fetching operator-sdk version ${operator_sdk_version} (OpenShift ${resolved_version}) with url '${url}'"
        curl -L "${url}" | tar --strip-components 2 -xz -C "${install_dir}/"

        # Make the downloaded file executable (should already be executable from tar).
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
    else
        echo "operator-sdk is already installed at: $(which operator-sdk)"
        installed_version=$(operator-sdk version | head -1 || echo "version check failed")
        echo "Current version: ${installed_version}"
    fi
}

# Execute the main function, passing along any arguments provided to the script.
main "$@"
