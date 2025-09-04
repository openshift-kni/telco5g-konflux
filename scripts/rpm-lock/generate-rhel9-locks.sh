#!/usr/bin/env bash

# Automates the generation of an RPM lock file for a RHEL 9 image.
# This script operates on a single target directory, which must contain
# an 'rpms.in.yaml' file. The image to lock can be provided via the
# RPM_LOCK_IMAGE environment variable, otherwise it defaults to the execution image.
#
# Usage: ./generate-rhel9-locks.sh [PATH_TO_TARGET_DIR]
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

# --- Configuration ---
RHEL9_RELEASE="${RHEL9_RELEASE:-9.4}"

# The image used to RUN the container, which needs subscription-manager and other tools.
UBI9_EXECUTION_IMAGE="${UBI9_EXECUTION_IMAGE:-registry.access.redhat.io/ubi9/ubi:${UBI9_RELEASE}}"

# The image to generate the lock file FOR. Defaults to the execution image if not set.
IMAGE_TO_LOCK="${RPM_LOCK_IMAGE:-${UBI9_EXECUTION_IMAGE}}"

# Use environment variables for credentials if set, otherwise prompt for input
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

# 2. Check credentials and determine if RHSM registration should be used
if [[ -z "$RHEL9_ORG_ID" || -z "$RHEL9_ACTIVATION_KEY" ]]; then
    echo "RHEL 9 credentials not provided or are placeholder values. Skipping RHSM registration."
    echo "Using UBI repositories only for lock file generation."
    USE_RHSM=false
else
    echo "RHEL 9 credentials provided. Will use RHSM registration for enhanced repositories."
    USE_RHSM=true
fi

# 3. Validate existence of input file
if [[ ! -f "${ABS_PROJECT_DIR}/rpms.in.yaml" ]]; then
    echo "ERROR: Input file not found at '${ABS_PROJECT_DIR}/rpms.in.yaml'." >&2
    exit 1
fi

# 4. Determine if multi-arch patch is needed by checking for an 'arches' key in the input file.
APPLY_MULTI_ARCH_PATCH="false"
if grep -q "^arches:" "${ABS_PROJECT_DIR}/rpms.in.yaml"; then
    echo "Multi-arch build detected from 'arches' key in rpms.in.yaml."
    APPLY_MULTI_ARCH_PATCH="true"
else
    echo "Single-arch build detected."
fi

# 5. Detect OS for podman flags
PODMAN_FLAGS=""
case "$(uname -s)" in
    Linux)
        echo "Linux detected. Using --tmpfs /run/secrets."
        PODMAN_FLAGS="--tmpfs /run/secrets"
        ;;
    Darwin)
        echo "macOS detected. Using --platform=linux/amd64."
        PODMAN_FLAGS="--platform=linux/amd64"
        ;;
    *)
        echo "Warning: Unsupported OS '$(uname -s)'. Proceeding without OS-specific flags."
        ;;
esac

# 6. Create a temporary script file to be run inside the container.
readonly SCRIPT_FILE_PATH="${ABS_PROJECT_DIR}/podman_script.sh"
trap 'rm -f "${SCRIPT_FILE_PATH}"' EXIT

cat > "${SCRIPT_FILE_PATH}" <<EOF
#!/usr/bin/env bash
set -eux

# Copy input file to output file for modifications
echo "STEP 0: Copying rpms.in.yaml to rpms.out.yaml..."
cp /source/rpms.in.yaml /source/rpms.out.yaml

# Helper function to extract repository IDs from rpms.out.yaml
extract_repo_ids() {
    if [ -f "/source/rpms.out.yaml" ]; then
        # Extract repoid values from the YAML file
        grep -E '^[[:space:]]*-[[:space:]]*repoid:' /source/rpms.out.yaml | \
            sed 's/^[[:space:]]*-[[:space:]]*repoid:[[:space:]]*//' | \
            tr -d '"'"'"
    fi
}

if [ "${USE_RHSM}" = "true" ]; then
    echo "STEP 1: Registering system..."
    subscription-manager register --org "${RHEL9_ORG_ID}" --activationkey "${RHEL9_ACTIVATION_KEY}" --force
    subscription-manager release --set="${RHEL9_RELEASE}"
    subscription-manager refresh

    echo "STEP 3: Configuring repositories..."
    # Extract repository IDs from rpms.in.yaml if it exists
    REPO_IDS=\$(extract_repo_ids)

    if [ -n "\$REPO_IDS" ]; then
        echo "Found repository configurations in rpms.in.yaml. Enabling specified repositories..."
        subscription-manager repos --disable='*'
        while IFS= read -r repo_id; do
            if [ -n "\$repo_id" ]; then
                echo "Enabling repository: \$repo_id"
                subscription-manager repos --enable="\$repo_id" || echo "Warning: Could not enable \$repo_id"
            fi
        done <<< "\$REPO_IDS"
    else
        echo "No repository configuration found in rpms.in.yaml. Using default repositories..."
        subscription-manager repos \
            --disable='*' \
            --enable=rhel-9-for-x86_64-baseos-rpms \
            --enable=rhel-9-for-x86_64-appstream-rpms \
            --enable=codeready-builder-for-rhel-9-x86_64-rpms
    fi

    echo "STEP 5: Copying repo file..."
    cp /etc/yum.repos.d/redhat.repo /source/redhat.repo

    echo "STEP 5b: Updating SSL certificate paths in rpms.out.yaml..."
    # Find the actual certificate files created by RHSM registration
    CERT_FILE=\$(find /etc/pki/entitlement/ -type f -name "*.pem" ! -name "*-key.pem" | head -1)
    KEY_FILE=\$(find /etc/pki/entitlement/ -type f -name "*-key.pem" | head -1)

    if [ -n "\$CERT_FILE" ] && [ -n "\$KEY_FILE" ]; then
        echo "Found certificates: \$CERT_FILE and \$KEY_FILE"
        # Update rpms.out.yaml with the actual certificate paths
        # Handle both sslclientcert and sslclientkey patterns
        sed -i "s|sslclientcert: /etc/pki/entitlement/[^[:space:]]*\.pem|sslclientcert: \$CERT_FILE|g" /source/rpms.out.yaml
        sed -i "s|sslclientkey: /etc/pki/entitlement/[^[:space:]]*-key\.pem|sslclientkey: \$KEY_FILE|g" /source/rpms.out.yaml

        # Also update any repository file that might have been generated
        if [ -f "/source/redhat.repo" ]; then
            sed -i "s|^sslclientcert.*|sslclientcert = \$CERT_FILE|" /source/redhat.repo
            sed -i "s|^sslclientkey.*|sslclientkey = \$KEY_FILE|" /source/redhat.repo
        fi
    else
        echo "WARNING: Could not find entitlement certificates"
    fi
else
    echo "STEP 1: Skipping RHSM registration..."
    echo "STEP 3: Setting up UBI repositories..."
    cat > /etc/yum.repos.d/redhat.repo <<REPOS_EOF
# UBI repositories (no RHSM registration required)
[ubi-9-baseos]
name = Red Hat Universal Base Image 9 (RPMs) - BaseOS
baseurl = https://cdn-ubi.redhat.com/content/public/ubi/dist/ubi9/9/\\\$basearch/baseos/os
enabled = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
gpgcheck = 1

[ubi-9-appstream]
name = Red Hat Universal Base Image 9 (RPMs) - AppStream
baseurl = https://cdn-ubi.redhat.com/content/public/ubi/dist/ubi9/9/\\\$basearch/appstream/os
enabled = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
gpgcheck = 1
REPOS_EOF

    echo "STEP 5: Copying repo file..."
    cp /etc/yum.repos.d/redhat.repo /source/redhat.repo
fi

echo "STEP 2: Installing tools (skopeo, python3-pip)..."
dnf install -y skopeo python3-pip

echo "STEP 4: Installing rpm-lockfile-prototype tool..."
python3 -m pip install --user https://github.com/konflux-ci/rpm-lockfile-prototype/archive/refs/heads/main.zip

if [ "${APPLY_MULTI_ARCH_PATCH}" = "true" ]; then
    echo "STEP 5a: Applying multi-arch patch to repo file..."
    sed -i "s/\$(uname -m)/\\\$basearch/g" /source/redhat.repo
fi

echo "STEP 6: Generating lock file for image: ${IMAGE_TO_LOCK}"
/root/.local/bin/rpm-lockfile-prototype \
    --image "${IMAGE_TO_LOCK}" \
    --outfile="/source/rpms.lock.yaml" \
    /source/rpms.out.yaml

echo "Lock file generation complete inside the container."
EOF

# Ensure the temporary script is executable
chmod +x "${SCRIPT_FILE_PATH}"

# --- Execution ---
echo -e "\n--- Starting RHEL 9 Lock File Generation for '${ABS_PROJECT_DIR}' ---"
echo "Using execution image: ${UBI9_EXECUTION_IMAGE}"
echo "PREREQUISITE: You must be logged into registry.redhat.io via 'podman login'."
echo "----------------------------------------------"

podman run --rm -it ${AUTH_MOUNT_FLAG} ${PODMAN_FLAGS} -v "${ABS_PROJECT_DIR}:/source:Z" --entrypoint /source/podman_script.sh "${UBI9_EXECUTION_IMAGE}"

echo -e "\n--- Success! ---"
echo "Generated files are located in '${ABS_PROJECT_DIR}'."
echo "Please review and commit the following files:"
echo "  - redhat.repo"
echo "  - rpms.out.yaml (modified input file with runtime changes)"
echo "  - rpms.lock.yaml"
echo "--------------------"
