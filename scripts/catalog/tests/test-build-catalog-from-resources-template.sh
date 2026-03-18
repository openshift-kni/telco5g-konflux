#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
CATALOG_DIR="${SCRIPT_DIR}/.."
BUILD_SCRIPT="${CATALOG_DIR}/konflux-build-catalog-from-resources-template.sh"
DATA_DIR="${SCRIPT_DIR}/data"
TEST_DIR=""
OPM_DIR=""

cleanup() {
    rm -rf "${TEST_DIR:-}" "${OPM_DIR:-}"
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $message" >&2
        echo "  expected: $expected" >&2
        echo "  actual:   $actual" >&2
        exit 1
    fi
}

check_dependencies() {
    command -v yq >/dev/null 2>&1 || { echo "Error: yq is required for this test." >&2; exit 1; }
    command -v opm >/dev/null 2>&1 || { echo "Error: opm is required for this test." >&2; exit 1; }
    [[ -x "$BUILD_SCRIPT" ]] || { echo "Error: build script not found or not executable: $BUILD_SCRIPT" >&2; exit 1; }
}

run_test() {
    local default_channel="pre-ga-0.2"
    TEST_DIR="$(mktemp -d)"
    trap cleanup EXIT

    cp "${DATA_DIR}/openshift-4-20-template.in.yaml" "$TEST_DIR/"
    cp "${DATA_DIR}/o-cloud-manager-fbc-base.yaml" "$TEST_DIR/"
    cp "${DATA_DIR}/o-cloud-manager-channel-0-1.yaml" "$TEST_DIR/"
    cp "${DATA_DIR}/o-cloud-manager-channel-0-2.yaml" "$TEST_DIR/"
    cp "${DATA_DIR}/o-cloud-manager-deprecated-channels-4-20.yaml" "$TEST_DIR/"

    "$BUILD_SCRIPT" \
        --set-template-input-file "$TEST_DIR/openshift-4-20-template.in.yaml" \
        --set-template-output-file "$TEST_DIR/openshift-4-20.yaml" \
        --set-default-channel "$default_channel"

    [[ -f "$TEST_DIR/openshift-4-20.yaml" ]] || { echo "FAIL: output file was not created." >&2; exit 1; }

    local entries_count
    entries_count="$(yq e '.entries | length' "$TEST_DIR/openshift-4-20.yaml")"
    assert_eq "14" "$entries_count" "entries count should be 14"

    local schema
    schema="$(yq e -r '.schema' "$TEST_DIR/openshift-4-20.yaml")"
    assert_eq "olm.template.basic" "$schema" "schema should be olm.template.basic"

    local first_entry_schema
    first_entry_schema="$(yq e -r '.entries[0].schema' "$TEST_DIR/openshift-4-20.yaml")"
    assert_eq "olm.package" "$first_entry_schema" "first entry should be package metadata"

    local default_channel_value
    default_channel_value="$(yq e -r '.entries[0].defaultChannel' "$TEST_DIR/openshift-4-20.yaml")"
    assert_eq "$default_channel" "$default_channel_value" "default channel placeholder should be replaced"

    local placeholder_count
    placeholder_count="$(yq e '[.entries[] | select(.defaultChannel == "${default_channel}")] | length' "$TEST_DIR/openshift-4-20.yaml")"
    assert_eq "0" "$placeholder_count" "default channel placeholder should not remain in output"

    local has_deprecations
    has_deprecations="$(yq e '[.entries[] | select(.schema == "olm.deprecations")] | length' "$TEST_DIR/openshift-4-20.yaml")"
    assert_eq "1" "$has_deprecations" "catalog should contain exactly one olm.deprecations entry"

    OPM_DIR="$(mktemp -d)"
    cp "$TEST_DIR/openshift-4-20.yaml" "$OPM_DIR/catalog.yaml"
    opm validate "$OPM_DIR"

    echo "PASS: test-build-catalog-from-resources-template"
}

main() {
    check_dependencies
    run_test
}

main "$@"
