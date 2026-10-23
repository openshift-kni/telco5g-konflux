#!/usr/bin/env bash

# Exercise the YAML substitutions from the generated container scripts without
# requiring Podman, RHSM credentials, or access to the Red Hat CDN.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/podman" <<'EOF'
#!/usr/bin/env bash
set -eu
cp "$TEST_TARGET_DIR/podman_script.sh" "$TEST_TARGET_DIR/generated.sh"
EOF
chmod +x "$TEST_DIR/bin/podman"

export PATH="$TEST_DIR/bin:$PATH"
# Skip RHEL 8's initial repository extraction; only capture the generated RHEL 9
# execution script where both generators substitute the entitlement paths.
export RHEL8_ACTIVATION_KEY="" RHEL8_ORG_ID=""
export RHEL9_ACTIVATION_KEY="test-key" RHEL9_ORG_ID="test-org"
export REGISTRY_AUTH_FILE="$TEST_DIR/no-auth.json"
# These must be resolved inside the container, never from the host environment.
export SSL_CLIENT_CERT="/host/wrong.pem" SSL_CLIENT_KEY="/host/wrong-key.pem"

for version in 8 9; do
    export TEST_TARGET_DIR="$TEST_DIR/rhel$version"
    mkdir -p "$TEST_TARGET_DIR"
    cat > "$TEST_TARGET_DIR/rpms.in.yaml" <<'EOF'
repositories:
  - repoid: variables
    sslclientcert: $SSL_CLIENT_CERT
    sslclientkey: $SSL_CLIENT_KEY
  - repoid: quoted-variables
    sslclientcert: "$SSL_CLIENT_CERT"
    sslclientkey: '$SSL_CLIENT_KEY'
  - repoid: fixed-paths
    sslclientcert: /etc/pki/entitlement/old.pem
    sslclientkey: /etc/pki/entitlement/old-key.pem
  - repoid: custom-paths
    sslclientcert: /custom/client.pem
    sslclientkey: /custom/client-key.pem
EOF

    bash "$SCRIPT_DIR/../generate-rhel${version}-locks.sh" "$TEST_TARGET_DIR" > "$TEST_TARGET_DIR/generate.log" 2>&1
    bash -n "$TEST_TARGET_DIR/generated.sh"
    cp "$TEST_TARGET_DIR/rpms.in.yaml" "$TEST_TARGET_DIR/rpms.out.yaml"

    # Execute the actual generated sed commands, redirecting only the container's
    # output file path into the test directory. This also tests heredoc escaping.
    grep 'sed -i .* /source/rpms.out.yaml$' "$TEST_TARGET_DIR/generated.sh" |
        sed "s|/source/rpms.out.yaml|$TEST_TARGET_DIR/rpms.out.yaml|g" > "$TEST_TARGET_DIR/substitute.sh"
    CERT_FILE=/etc/pki/entitlement/123.pem \
        KEY_FILE=/etc/pki/entitlement/123-key.pem \
        bash -eu "$TEST_TARGET_DIR/substitute.sh"

    cat > "$TEST_TARGET_DIR/expected.yaml" <<'EOF'
repositories:
  - repoid: variables
    sslclientcert: /etc/pki/entitlement/123.pem
    sslclientkey: /etc/pki/entitlement/123-key.pem
  - repoid: quoted-variables
    sslclientcert: "/etc/pki/entitlement/123.pem"
    sslclientkey: '/etc/pki/entitlement/123-key.pem'
  - repoid: fixed-paths
    sslclientcert: /etc/pki/entitlement/123.pem
    sslclientkey: /etc/pki/entitlement/123-key.pem
  - repoid: custom-paths
    sslclientcert: /custom/client.pem
    sslclientkey: /custom/client-key.pem
EOF
    diff -u "$TEST_TARGET_DIR/expected.yaml" "$TEST_TARGET_DIR/rpms.out.yaml"
    echo "PASS: RHEL $version entitlement substitutions"
done
