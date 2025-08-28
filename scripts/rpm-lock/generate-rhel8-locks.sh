#!/usr/bin/env bash

# Automates the RHEL 8 lock file generation. This script uses a two-stage
# process against a single target directory, which must contain 'rpms.in.yaml'.
# The image to lock can be provided via the IMAGE_TO_LOCK environment variable,
# otherwise it defaults to the UBI8 execution image.
#
# Usage: ./generate-rhel8-locks.sh [PATH_TO_TARGET_DIR]
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

# --- Configuration ---
UBI8_RELEASE="${UBI8_RELEASE:-8.10}"
UBI9_RELEASE="${UBI9_RELEASE:-9.4}"

# The images used to RUN the containers, which need subscription-manager.
UBI8_EXECUTION_IMAGE="${UBI8_EXECUTION_IMAGE:-registry.access.redhat.io/ubi8/ubi:${UBI8_RELEASE}}"
UBI9_EXECUTION_IMAGE="${UBI9_EXECUTION_IMAGE:-registry.access.redhat.io/ubi9/ubi:${UBI9_RELEASE}}"

# The image to generate the lock file FOR. Defaults to the UBI8 execution image if not set.
IMAGE_TO_LOCK="${IMAGE_TO_LOCK:-${UBI8_EXECUTION_IMAGE}}"

# Use environment variables for credentials if set, otherwise prompt for input
RHEL8_ACTIVATION_KEY="${RHEL8_ACTIVATION_KEY:-}"
RHEL8_ORG_ID="${RHEL8_ORG_ID:-}"
RHEL9_ACTIVATION_KEY="${RHEL9_ACTIVATION_KEY:-}"
RHEL9_ORG_ID="${RHEL9_ORG_ID:-}"

# The registry auth file is mounted into the container to allow for private registry pulls.
# This is automatically detected and mounted into the container if it exists on the host.
# If it does not exist, a warning is printed and the registry pulls may fail if not public.
# This can be set from the command line if the default is not correct for your environment.
REGISTRY_AUTH_FILE="${REGISTRY_AUTH_FILE:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/containers/auth.json}"

# Mount the registry auth file into the container if it exists.
AUTH_MOUNT_FLAG=""

# If the registry auth file is not set, use the default path.
if [ -f "${REGISTRY_AUTH_FILE}" ]; then
    echo "Found Podman auth file at ${REGISTRY_AUTH_FILE}. Mounting into container."
    AUTH_MOUNT_FLAG="-v ${REGISTRY_AUTH_FILE}:/root/.config/containers/auth.json:Z"
fi

# Use the first argument as the target directory.
readonly LOCK_SCRIPT_TARGET_DIR="${1:-${SCRIPT_DIR}}"
readonly RHEL8_REPO_FILE="redhat-rhel8.repo.generated"

# --- Main Script ---
# 0. Validate configuration
if [[ ! -d "${LOCK_SCRIPT_TARGET_DIR}" ]]; then
    echo "ERROR: Target directory not found at '${LOCK_SCRIPT_TARGET_DIR}'." >&2
    exit 1
fi
# Resolve to an absolute path for the podman mount
readonly ABS_PROJECT_DIR="$(cd "${LOCK_SCRIPT_TARGET_DIR}" && pwd)"

# 1. Check for podman
if ! command -v podman &> /dev/null; then
    echo "ERROR: podman could not be found. Please install it." >&2
    exit 1
fi

# --- Part 1: Generate RHEL 8 Repo File ---
echo "--- Part 1: Generating RHEL 8 Repository File ---"

# Check if credentials are empty, placeholder values, or not provided
if [[ -z "$RHEL8_ORG_ID" || -z "$RHEL8_ACTIVATION_KEY" ]]; then
    echo "RHEL 8 credentials not provided or are placeholder values. Skipping RHSM registration."
    echo "Using UBI repositories only (no RHEL entitlements)."

    # Create a minimal repo file for UBI repositories
    readonly TEMP_REPO_FILE_PATH="${ABS_PROJECT_DIR}/${RHEL8_REPO_FILE}"
    trap 'rm -f "${TEMP_REPO_FILE_PATH}"' EXIT

    # Generate a basic UBI repo file without RHSM registration
    cat > "${TEMP_REPO_FILE_PATH}" <<EOF
# UBI repositories (no RHSM registration required)
[ubi-8-baseos]
name = Red Hat Universal Base Image 8 (RPMs) - BaseOS
baseurl = https://cdn-ubi.redhat.com/content/public/ubi/dist/ubi8/8/\$basearch/baseos/os
enabled = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
gpgcheck = 1

[ubi-8-appstream]
name = Red Hat Universal Base Image 8 (RPMs) - AppStream
baseurl = https://cdn-ubi.redhat.com/content/public/ubi/dist/ubi8/8/\$basearch/appstream/os
enabled = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
gpgcheck = 1
EOF

    echo "Generated basic UBI repo file at '${TEMP_REPO_FILE_PATH}'"
else
    echo "RHEL 8 credentials provided. Proceeding with RHSM registration."

    read -r -d '' UBI8_COMMANDS <<EOF
set -eux

# Helper function to extract repository IDs from rpms.in.yaml
extract_repo_ids() {
    if [ -f "/source/rpms.in.yaml" ]; then
        # Extract repoid values from the YAML file
        grep -E '^[[:space:]]*-[[:space:]]*repoid:' /source/rpms.in.yaml | \
            sed 's/^[[:space:]]*-[[:space:]]*repoid:[[:space:]]*//' | \
            tr -d '"'"'"
    fi
}

echo "[UBI8] Registering system to RHEL 8..."
subscription-manager register --org "${RHEL8_ORG_ID}" --activationkey "${RHEL8_ACTIVATION_KEY}" --force
subscription-manager release --set="${UBI8_RELEASE}"
subscription-manager refresh

# Configure repositories based on rpms.in.yaml if it exists
REPO_IDS=\$(extract_repo_ids)

if [ -n "\$REPO_IDS" ]; then
    echo "[UBI8] Found repository configurations in rpms.in.yaml. Enabling specified repositories..."
    subscription-manager repos --disable='*'
    while IFS= read -r repo_id; do
        if [ -n "\$repo_id" ]; then
            echo "[UBI8] Enabling repository: \$repo_id"
            subscription-manager repos --enable="\$repo_id" || echo "[UBI8] Warning: Could not enable \$repo_id"
        fi
    done <<< "\$REPO_IDS"
else
    echo "[UBI8] No repository configuration found in rpms.in.yaml. Using default repositories..."
    subscription-manager repos \
        --disable='*' \
        --enable=rhel-8-for-x86_64-baseos-rpms \
        --enable=rhel-8-for-x86_64-appstream-rpms \
        --enable=codeready-builder-for-rhel-8-x86_64-rpms
fi

echo "[UBI8] Copying generated repo file to /source..."
cp /etc/yum.repos.d/redhat.repo "/source/${RHEL8_REPO_FILE}"
echo "[UBI8] Process complete."
EOF

    echo "Running UBI8 container to extract RHEL 8 repo file into '${ABS_PROJECT_DIR}'..."
    echo "Using UBI8 execution image: ${UBI8_EXECUTION_IMAGE}"
    podman run --rm -it ${AUTH_MOUNT_FLAG} -v "${ABS_PROJECT_DIR}:/source:Z" --entrypoint sh "${UBI8_EXECUTION_IMAGE}" -c "${UBI8_COMMANDS}"

    if [ ! -f "${TEMP_REPO_FILE_PATH}" ]; then
        echo "ERROR: Failed to generate RHEL 8 repo file." >&2
        exit 1
    fi
    echo "Successfully generated '${TEMP_REPO_FILE_PATH}'"
fi
echo "----------------------------------------------------"

# --- Part 2: Generate Lock Files using UBI 9 Container ---
echo -e "\n--- Part 2: Generating Lock Files using UBI 9 ---"

# Check if RHEL9 credentials are empty, placeholder values, or not provided
if [[ -z "$RHEL9_ORG_ID" || -z "$RHEL9_ACTIVATION_KEY" || "$RHEL9_ORG_ID" == "placeholder" || "$RHEL9_ACTIVATION_KEY" == "placeholder" || "$RHEL9_ORG_ID" == "1234567890" ]]; then
    echo "RHEL 9 credentials not provided or are placeholder values. Skipping RHSM registration."
    echo "Using UBI repositories only for lock file generation."
    USE_RHSM_RHEL9=false

    # Convert registry.redhat.io URLs to registry.access.redhat.com for public access
    if [[ "${IMAGE_TO_LOCK}" == *"registry.redhat.io"* ]]; then
        PUBLIC_IMAGE_TO_LOCK=$(echo "${IMAGE_TO_LOCK}" | sed 's|registry\.redhat\.io|registry.access.redhat.com|g')
        echo "Converting image URL for public access: ${IMAGE_TO_LOCK} -> ${PUBLIC_IMAGE_TO_LOCK}"
        IMAGE_TO_LOCK="${PUBLIC_IMAGE_TO_LOCK}"
    fi
else
    echo "RHEL 9 credentials provided. Will use RHSM registration for enhanced repositories."
    USE_RHSM_RHEL9=true
fi

# Validate existence of input file
if [[ ! -f "${ABS_PROJECT_DIR}/rpms.in.yaml" ]]; then
    echo "ERROR: Input file not found at '${ABS_PROJECT_DIR}/rpms.in.yaml'." >&2
    exit 1
fi

# Determine if multi-arch patch is needed by checking for an 'arches' key in the input file.
APPLY_MULTI_ARCH_PATCH="false"
if grep -q "^arches:" "${ABS_PROJECT_DIR}/rpms.in.yaml"; then
    echo "Multi-arch build detected from 'arches' key in rpms.in.yaml."
    APPLY_MULTI_ARCH_PATCH="true"
else
    echo "Single-arch build detected."
fi

# Create a temporary script file to be run inside the UBI9 container.
readonly SCRIPT_FILE_PATH="${ABS_PROJECT_DIR}/podman_script_ubi9.sh"
trap 'rm -f "${SCRIPT_FILE_PATH}"' EXIT

cat > "${SCRIPT_FILE_PATH}" <<EOF
#!/usr/bin/env bash
set -eux

# Helper function to extract repository IDs from rpms.in.yaml
extract_repo_ids() {
    if [ -f "/source/rpms.in.yaml" ]; then
        # Extract repoid values from the YAML file
        grep -E '^[[:space:]]*-[[:space:]]*repoid:' /source/rpms.in.yaml | \
            sed 's/^[[:space:]]*-[[:space:]]*repoid:[[:space:]]*//' | \
            tr -d '"'"'"
    fi
}

if [ "${USE_RHSM_RHEL9}" = "true" ]; then
    echo "[UBI9] Registering system to RHEL 9 to get valid certs..."
    subscription-manager register --org "${RHEL9_ORG_ID}" --activationkey "${RHEL9_ACTIVATION_KEY}" --force
    subscription-manager release --set="${UBI9_RELEASE}"
    subscription-manager refresh

    # Configure repositories based on rpms.in.yaml if it exists
    REPO_IDS=\$(extract_repo_ids)

    if [ -n "\$REPO_IDS" ]; then
        echo "[UBI9] Found repository configurations in rpms.in.yaml. Enabling specified repositories..."
        subscription-manager repos --disable='*'
        while IFS= read -r repo_id; do
            if [ -n "\$repo_id" ]; then
                echo "[UBI9] Enabling repository: \$repo_id"
                subscription-manager repos --enable="\$repo_id" || echo "[UBI9] Warning: Could not enable \$repo_id"
            fi
        done <<< "\$REPO_IDS"
    else
        echo "[UBI9] No repository configuration found in rpms.in.yaml. Using default repositories..."
        subscription-manager repos \
            --disable='*' \
            --enable=rhel-9-for-x86_64-baseos-rpms \
            --enable=rhel-9-for-x86_64-appstream-rpms \
            --enable=codeready-builder-for-rhel-9-x86_64-rpms
    fi

    echo "[UBI9] Finding RHEL 9 entitlement certificates..."
    CERT_FILE=\$(find /etc/pki/entitlement/ -type f -name "*.pem" ! -name "*-key.pem" | head -1)
    KEY_FILE=\$(find /etc/pki/entitlement/ -type f -name "*-key.pem" | head -1)

    echo "[UBI9] Modifying the RHEL 8 repo file with RHEL 9 certificates..."
    # The temporary repo file is copied to the final name 'redhat.repo'
    cp "/source/${RHEL8_REPO_FILE}" /source/redhat.repo

    if [ -n "\$CERT_FILE" ] && [ -n "\$KEY_FILE" ]; then
        echo "[UBI9] Found certificates: \$CERT_FILE and \$KEY_FILE"
        sed -i "s|^sslclientcert.*|sslclientcert = \$CERT_FILE|" "/source/redhat.repo"
        sed -i "s|^sslclientkey.*|sslclientkey = \$KEY_FILE|" "/source/redhat.repo"

        # Also update rpms.in.yaml with the actual certificate paths
        echo "[UBI9] Updating SSL certificate paths in rpms.in.yaml..."
        sed -i "s|sslclientcert: /etc/pki/entitlement/[^[:space:]]*\.pem|sslclientcert: \$CERT_FILE|g" /source/rpms.in.yaml
        sed -i "s|sslclientkey: /etc/pki/entitlement/[^[:space:]]*-key\.pem|sslclientkey: \$KEY_FILE|g" /source/rpms.in.yaml
    else
        echo "[UBI9] WARNING: Could not find entitlement certificates"
    fi
else
    echo "[UBI9] Skipping RHSM registration. Using basic repo file..."
    # Just copy the repo file without certificate modifications
    cp "/source/${RHEL8_REPO_FILE}" /source/redhat.repo
fi

echo "[UBI9] Installing tools..."
dnf install -y skopeo python3-pip &>/dev/null
python3 -m pip install --user https://github.com/konflux-ci/rpm-lockfile-prototype/archive/refs/heads/main.zip &>/dev/null

if [ "${APPLY_MULTI_ARCH_PATCH}" = "true" ]; then
    echo '[UBI9] Applying multi-arch patch to repo file...'
    sed -i "s/\$(uname -m)/\\\$basearch/g" /source/redhat.repo
fi

echo "[UBI9] Setting up repository configuration for rpm-lockfile-prototype..."
# The rpm-lockfile-prototype tool uses system repositories, so we need to set them up properly
if [ "${USE_RHSM_RHEL9}" = "true" ]; then
    # RHSM registration already configured the system repos, just copy for output
    cp /etc/yum.repos.d/redhat.repo /source/redhat.repo
else
    # No RHSM registration, so we need to manually set up the system repositories
    # Copy our custom UBI repo file to the system location
    cp /source/redhat.repo /etc/yum.repos.d/redhat.repo
fi

echo "[UBI9] Generating lock file for image: ${IMAGE_TO_LOCK}"
/root/.local/bin/rpm-lockfile-prototype \
    --image "${IMAGE_TO_LOCK}" \
    --outfile="/source/rpms.lock.yaml" \
    /source/rpms.in.yaml

echo "[UBI9] Lock file generation complete."
EOF

# Ensure the temporary script is executable
chmod +x "${SCRIPT_FILE_PATH}"

echo "Running UBI9 container to perform certificate swap and generate lock files..."
echo "Using UBI9 execution image: ${UBI9_EXECUTION_IMAGE}"
podman run --rm -it ${AUTH_MOUNT_FLAG} -v "${ABS_PROJECT_DIR}:/source:Z" --entrypoint /source/podman_script_ubi9.sh "${UBI9_EXECUTION_IMAGE}"

echo -e "\n--- Success! ---"
echo "Generated files for RHEL 8 are located in '${ABS_PROJECT_DIR}'."
echo "Please review and commit the following files:"
echo "  - redhat.repo"
echo "  - rpms.lock.yaml"

# Clean up temporary files
if [ -f "${ABS_PROJECT_DIR}/${RHEL8_REPO_FILE}" ]; then
    echo "Cleaning up temporary file: ${RHEL8_REPO_FILE}"
    rm -f "${ABS_PROJECT_DIR}/${RHEL8_REPO_FILE}"
fi

echo "--------------------"
