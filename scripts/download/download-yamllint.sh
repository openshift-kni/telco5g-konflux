#!/usr/bin/env bash

# This script automates the download and installation of yamllint, a linter for YAML files.
# It checks if yamllint is available in the local install directory with the exact required version.
# It creates a local Python virtual environment and installs yamllint via pip, then creates
# a wrapper script to execute yamllint from the virtual environment.

set -eou pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Default installation directory relative to the script's location.
DEFAULT_INSTALL_DIR="${SCRIPT_DIR}/../bin"

# The default version of yamllint to install.
# You can find the latest version on the yamllint PyPI page:
# https://pypi.org/project/yamllint/
DEFAULT_VERSION="1.37.1"

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [VERSION]

Downloads and installs yamllint, a linter for YAML files.

Arguments:
    VERSION              Exact version required (default: ${DEFAULT_VERSION})
                         Format: X.Y.Z (e.g. 1.37.1)

Options:
    -d, --install-dir DIR Install directory (default: ${DEFAULT_INSTALL_DIR})
    -h, --help            Show this help message

Environment Variables:
    INSTALL_DIR           Install directory (overridden by -d/--install-dir)

Examples:
    $0                                   # Ensure default version is available locally
    $0 1.35.1                            # Ensure exact version 1.35.1 is available locally
    $0 -d /usr/local/bin 1.35.1          # Install specific version to custom directory
    $0 --install-dir /tmp/tools          # Install default version to custom directory
    INSTALL_DIR=/opt/bin $0              # Install using environment variable
    $0 --help                            # Show help

EOF
}

check_python() {
    local python_cmd=""

    # Try to find a suitable Python interpreter
    for cmd in python3 python; do
        if command -v "$cmd" > /dev/null 2>&1; then
            # Check if it's Python 3.6+
            local version
            if version=$("$cmd" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null); then
                if [[ "$version" =~ ^3\.([6-9]|[1-9][0-9])$ ]]; then
                    python_cmd="$cmd"
                    break
                fi
            fi
        fi
    done

    if [[ -z "$python_cmd" ]]; then
        echo "ERROR: Python 3.6+ is required but not found"
        echo "Please install Python 3.6 or later and ensure it's in your PATH"
        exit 1
    fi

    echo "$python_cmd"
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

    # Define the full path where the yamllint wrapper will be saved.
    local install_path="${install_dir}/yamllint"
    local venv_dir="${install_dir}/.yamllint-venv"

    echo "Checking for yamllint with exact version ${version} in local install directory..."

    # Check if yamllint exists in local install directory with exact version
    if [[ -x "$install_path" && -d "$venv_dir" ]]; then
        echo "Found yamllint in local install directory: $install_path"

        # Check if the version matches exactly
        local local_version
        if local_version=$("$install_path" --version 2>/dev/null | grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' | head -1); then
            echo "Local yamllint version: $local_version"

            if [[ "$local_version" == "$version" ]]; then
                echo "Local yamllint version $local_version matches required version $version"
                return 0
            else
                echo "Local yamllint version $local_version does not match required version $version"
            fi
        else
            echo "Could not determine local yamllint version"
        fi
    else
        echo "yamllint not found in local install directory: $install_path"
    fi

    # No exact version match found, proceed with installation
    echo "Installing yamllint ${version}..."

    # Check for Python
    local python_cmd
    python_cmd=$(check_python)
    echo "Using Python: $python_cmd"

    # Create install directory
    echo "Creating directory '${install_dir}'"
    mkdir -p "${install_dir}"

    # Create virtual environment
    echo "Creating Python virtual environment in '${venv_dir}'"
    "$python_cmd" -m venv "${venv_dir}"

    # Activate virtual environment and install yamllint with specific version
    echo "Installing yamllint version ${version}"
    if ! "${venv_dir}/bin/pip" install "yamllint==${version}" > /dev/null 2>&1; then
        echo "ERROR: Failed to install yamllint version ${version}"
        echo "Available versions can be found at: https://pypi.org/project/yamllint/"
        rm -rf "${venv_dir}"
        exit 1
    fi

    # Create wrapper script
    echo "Creating yamllint wrapper script at '${install_path}'"
    cat > "${install_path}" << EOF
#!/usr/bin/env bash
# yamllint wrapper script generated by download-yamllint.sh
exec "${venv_dir}/bin/yamllint" "\$@"
EOF
    chmod +x "${install_path}"

    # Verify the installation was successful
    local actual_version
    if ! actual_version=$("${install_path}" --version 2>&1 | head -1); then
        echo "ERROR: Failed to install yamllint. Version check failed."
        rm -rf "${venv_dir}"
        rm -f "${install_path}"
        exit 1
    fi

    # Check if the installed version matches what we requested
    if ! echo "$actual_version" | grep -q "${version}"; then
        echo "WARNING: Requested version ${version} but got: ${actual_version}"
    fi

    echo "yamllint version ${version} installed successfully to ${install_path}"
    echo "Installed version: ${actual_version}"
}

# Execute the main function, passing along any script arguments.
main "$@"
