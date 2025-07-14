#!/usr/bin/env bash

# This script automates the download and installation of yq, a command-line YAML processor.
# It first checks if yq is already installed on the system. If not, it automatically
# detects the operating system and architecture, then downloads the appropriate
# binary from the official yq GitHub releases.

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

Downloads and installs yq, a command-line YAML processor.

Arguments:
    VERSION               Version to install (default: ${DEFAULT_VERSION})
                         Format: vX.Y.Z (e.g., v4.45.4)

Options:
    -d, --install-dir DIR Install directory (default: ${DEFAULT_INSTALL_DIR})
    -h, --help            Show this help message

Environment Variables:
    INSTALL_DIR           Install directory (overridden by -d/--install-dir)

Examples:
    $0                                    # Install default version to default directory
    $0 v4.44.2                           # Install specific version to default directory
    $0 -d /usr/local/bin v4.44.2         # Install specific version to custom directory
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

    # Define the full path where the yq binary will be saved.
    local install_path="${install_dir}/yq"

    # Check if the 'yq' command is not already available in the system's PATH.
    # The 'which' command returns a non-zero exit code if the command is not found.
    if ! which yq > /dev/null 2>&1; then
        echo "yq not found. Starting download..."

        # Detect the system's machine architecture (e.g., x86_64, aarch64).
        arch=$(uname -m)
        # Detect the system's operating system name (e.g., Darwin, Linux).
        os=$(uname)

        # Normalize the architecture name to match the format used in yq release artifacts.
        # For example, the common 'x86_64' is referred to as 'amd64' in the releases.
        if [[ "${arch}" == "x86_64" ]]; then
            arch="amd64"
            echo "Normalized architecture to '${arch}'"
        fi
        # 'aarch64' is normalized to 'arm64'.
        if [[ "${arch}" == "aarch64" ]]; then
            arch="arm64"
            echo "Normalized architecture to '${arch}'"
        fi

        # Normalize the OS name to match the format used in yq release artifacts.
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

        # Create the installation directory if it doesn't already exist.
        # The '-p' flag ensures that parent directories are also created if needed.
        echo "Creating directory '${install_dir}'"
        mkdir -p "${install_dir}"

        # Construct the download URL for the specified version, OS, and architecture.
        url="https://github.com/mikefarah/yq/releases/download/${version}/yq_${os}_${arch}"

        # Download the yq binary using curl.
        # -sL: Silent mode to suppress progress meter, and -L to follow redirects.
        # -o: Specify the output file path.
        echo "Fetching yq version ${version} with url '${url}'"
        curl -sL -o "${install_path}" "${url}"

        # Make the downloaded file executable.
        chmod +x "${install_path}"

        # Verify that the downloaded binary runs and reports the correct version.
        # This confirms the download and installation were successful.
        if ! bash -c "${install_path} --version | grep '${version}'"; then
            echo "Failed to install tool"
            exit 1
        fi
        echo "yq version ${version} installed successfully to ${install_path}"
    else
        echo "yq is already installed at: $(which yq)"
    fi
}

# Execute the main function, passing along any arguments provided to the script.
main "$@"
