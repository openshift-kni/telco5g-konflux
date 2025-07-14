#!/usr/bin/env bash

# This script automates the download and installation of jq, a lightweight and
# flexible command-line JSON processor.
# It checks if jq is already installed and, if not, fetches the correct binary
# for the system's architecture and operating system from the official GitHub releases.

set -eou pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Default installation directory relative to the script's location.
DEFAULT_INSTALL_DIR="${SCRIPT_DIR}/../bin"

# The default version of jq to install.
# You can find the latest version on the jq GitHub releases page:
# https://github.com/jqlang/jq/releases
DEFAULT_VERSION="1.7.1"

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [VERSION]

Downloads and installs jq, a command-line JSON processor.

Arguments:
    VERSION               Version to install (default: ${DEFAULT_VERSION})
                         Format: X.Y.Z (e.g., 1.7.1)

Options:
    -d, --install-dir DIR Install directory (default: ${DEFAULT_INSTALL_DIR})
    -h, --help            Show this help message

Environment Variables:
    INSTALL_DIR           Install directory (overridden by -d/--install-dir)

Examples:
    $0                                    # Install default version to default directory
    $0 1.6.0                             # Install specific version to default directory
    $0 -d /usr/local/bin 1.6.0           # Install specific version to custom directory
    $0 --install-dir /tmp/tools          # Install default version to custom directory
    INSTALL_DIR=/opt/bin $0              # Install using environment variable
    $0 --help                            # Show help

EOF
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
                version="$1"
                shift
                ;;
        esac
    done

    # Define the full path where the jq binary will be saved.
    local install_path="${install_dir}/jq"

    # Check if jq is not already available in the system's PATH.
    if ! which jq > /dev/null 2>&1; then
        echo "Downloading jq tool"
        arch=$(uname -m)
        os=$(uname)

        # Normalize architecture to the values used by the jq github page
        if [[ "${arch}" == "x86_64" ]]; then
            arch="amd64"
            echo "Normalizing architecture to '${arch}'"
        elif [[ "${arch}" == "aarch64" ]]; then
            arch="arm64"
            echo "Normalizing architecture to '${arch}'"
        fi

        # Normalize os name to the values used by the jq github page
        if [[ "${os}" == "Darwin" ]]; then
            os="macos"
            echo "Normalizing os name to '${os}'"
        elif [[ "${os}" == "Linux" ]]; then
            os="linux"
            echo "Normalizing os name to '${os}'"
        fi

        # Create install directory
        echo "Creating directory '${install_dir}'"
        mkdir -p "${install_dir}"

        # Download binary
        url="https://github.com/jqlang/jq/releases/download/jq-${version}/jq-${os}-${arch}"
        echo "Fetching jq version ${version} with url '${url}'"
        curl -sL -o "${install_path}" "${url}"
        chmod +x "${install_path}"

        # Verify the installation was successful
        if ! bash -c "${install_path} --version | grep '${version}'"; then
            echo "ERROR: Failed to install jq. Version check failed."
            exit 1
        fi
        echo "jq version ${version} installed successfully to ${install_path}"
    else
        echo "jq is already installed at: $(which jq)"
    fi
}

# Execute the main function, passing along any script arguments.
main "$@"
