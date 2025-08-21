#!/usr/bin/env bash

# Test script for download-shellcheck.sh
# This script tests various scenarios for the shellcheck download script

set -eou pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test directory setup
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DOWNLOAD_SCRIPT="${SCRIPT_DIR}/../download-shellcheck.sh"
TEST_INSTALL_DIR="${SCRIPT_DIR}/test_bin"
TEST_LOG_FILE="${SCRIPT_DIR}/test_results.log"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test version constants
VALID_VERSION_OLD="v0.10.0"
VALID_VERSION_NEW="v0.11.0"
INVALID_VERSION="v999.999.999"

# Utility functions
log() {
    echo -e "$1" | tee -a "$TEST_LOG_FILE"
}

log_test_start() {
    local test_name="$1"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log "${YELLOW}[TEST ${TOTAL_TESTS}] Starting: $test_name${NC}"
}

log_test_pass() {
    local test_name="$1"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    log "${GREEN}[PASS] $test_name${NC}"
}

log_test_fail() {
    local test_name="$1"
    local error_msg="$2"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    log "${RED}[FAIL] $test_name${NC}"
    log "${RED}       Error: $error_msg${NC}"
}

setup_test_environment() {
    log "Setting up test environment..."

    # Remove test directory if it exists
    if [[ -d "$TEST_INSTALL_DIR" ]]; then
        rm -rf "$TEST_INSTALL_DIR"
    fi

    # Create fresh test directory
    mkdir -p "$TEST_INSTALL_DIR"

    # Initialize log file
    echo "shellcheck Download Script Test Results - $(date)" > "$TEST_LOG_FILE"
    echo "================================================" >> "$TEST_LOG_FILE"
}

cleanup_test_environment() {
    log "Cleaning up test environment..."

    # Remove test directory
    if [[ -d "$TEST_INSTALL_DIR" ]]; then
        rm -rf "$TEST_INSTALL_DIR"
    fi
}

create_fake_shellcheck_binary() {
    local version="$1"
    local install_path="$2"

    # Create fake shellcheck binary that returns the specified version
    cat > "$install_path" << EOF
#!/bin/bash
echo "ShellCheck - shell script analysis tool"
echo "version: $version"
echo "license: GNU General Public License, version 3"
echo "website: https://www.shellcheck.net"
EOF
    chmod +x "$install_path"
}

verify_installation() {
    local binary_path="$1"
    local expected_version="$2"

    if [[ ! -x "$binary_path" ]]; then
        return 1
    fi

    local actual_version
    if ! actual_version=$("$binary_path" --version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -n1); then
        return 1
    fi

    # Remove 'v' prefix for comparison
    expected_version="${expected_version#v}"
    actual_version="${actual_version#v}"

    if [[ "$actual_version" == "$expected_version" ]]; then
        return 0
    else
        return 1
    fi
}

test_help_message() {
    log_test_start "Help message display"

    local test_dir="${TEST_INSTALL_DIR}/help_test"
    mkdir -p "$test_dir"

    if "$DOWNLOAD_SCRIPT" --help >> "$TEST_LOG_FILE" 2>&1; then
        log_test_pass "Help message display"
        return 0
    else
        log_test_fail "Help message display" "Help command failed"
        return 1
    fi
}

test_download_valid_version() {
    log_test_start "Download valid version to empty directory"

    local test_dir="${TEST_INSTALL_DIR}/valid_version"
    mkdir -p "$test_dir"

    # Test should succeed
    if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$VALID_VERSION_NEW" >> "$TEST_LOG_FILE" 2>&1; then
        # Check if binary was created and has correct version
        if verify_installation "$test_dir/shellcheck" "$VALID_VERSION_NEW"; then
            log_test_pass "Download valid version to empty directory"
            return 0
        else
            log_test_fail "Download valid version to empty directory" "Installation verification failed"
            return 1
        fi
    else
        log_test_fail "Download valid version to empty directory" "Download command failed"
        return 1
    fi
}

test_download_invalid_version() {
    log_test_start "Download invalid version (should fail)"

    local test_dir="${TEST_INSTALL_DIR}/invalid_version"
    mkdir -p "$test_dir"

    # Test should fail
    if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$INVALID_VERSION" >> "$TEST_LOG_FILE" 2>&1; then
        log_test_fail "Download invalid version (should fail)" "Command succeeded when it should have failed"
        return 1
    else
        log_test_pass "Download invalid version (should fail)"
        return 0
    fi
}

test_reinstall_same_version() {
    log_test_start "Reinstall same version"

    local test_dir="${TEST_INSTALL_DIR}/reinstall_same"
    mkdir -p "$test_dir"

    # First install
    if ! "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$VALID_VERSION_NEW" >> "$TEST_LOG_FILE" 2>&1; then
        log_test_fail "Reinstall same version" "First installation failed"
        return 1
    fi

    # Second install of same version - should reinstall
    if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$VALID_VERSION_NEW" >> "$TEST_LOG_FILE" 2>&1; then
        if verify_installation "$test_dir/shellcheck" "$VALID_VERSION_NEW"; then
            log_test_pass "Reinstall same version"
            return 0
        else
            log_test_fail "Reinstall same version" "Second installation verification failed"
            return 1
        fi
    else
        log_test_fail "Reinstall same version" "Second installation failed"
        return 1
    fi
}

test_download_exact_version() {
    log_test_start "Download exact version (replaces existing different version)"

    local test_dir="${TEST_INSTALL_DIR}/exact_version"
    mkdir -p "$test_dir"

    # First install newer version
    if ! "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$VALID_VERSION_NEW" >> "$TEST_LOG_FILE" 2>&1; then
        log_test_fail "Download exact version (replaces existing different version)" "First installation failed"
        return 1
    fi

    # Install older version - should download and replace
    if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$VALID_VERSION_OLD" >> "$TEST_LOG_FILE" 2>&1; then
        if verify_installation "$test_dir/shellcheck" "$VALID_VERSION_OLD"; then
            log_test_pass "Download exact version (replaces existing different version)"
            return 0
        else
            log_test_fail "Download exact version (replaces existing different version)" "Version replacement verification failed"
            return 1
        fi
    else
        log_test_fail "Download exact version (replaces existing different version)" "Version replacement failed"
        return 1
    fi
}

test_download_ignores_path() {
    log_test_start "Download ignores system PATH"

    local test_dir="${TEST_INSTALL_DIR}/ignores_path"
    mkdir -p "$test_dir"

    # Create a fake shellcheck in a temporary directory and add it to PATH
    local fake_path_dir="${TEST_INSTALL_DIR}/fake_path"
    mkdir -p "$fake_path_dir"
    create_fake_shellcheck_binary "v9.9.9" "$fake_path_dir/shellcheck"
    export PATH="$fake_path_dir:$PATH"

    # The script should ignore the PATH version and download to the specified directory
    if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$VALID_VERSION_NEW" >> "$TEST_LOG_FILE" 2>&1; then
        if verify_installation "$test_dir/shellcheck" "$VALID_VERSION_NEW"; then
            log_test_pass "Download ignores system PATH"
            return 0
        else
            log_test_fail "Download ignores system PATH" "Downloaded version verification failed"
            return 1
        fi
    else
        log_test_fail "Download ignores system PATH" "Download failed"
        return 1
    fi
}

# Main execution
main() {
    log "${YELLOW}Starting shellcheck download script tests...${NC}"

    # Setup test environment
    setup_test_environment

    # Run tests
    test_help_message
    test_download_valid_version
    test_download_invalid_version
    test_reinstall_same_version
    test_download_exact_version
    test_download_ignores_path

    # Cleanup
    cleanup_test_environment

    # Print summary
    log ""
    log "=========================================="
    log "Test Summary:"
    log "Total tests: $TOTAL_TESTS"
    log "${GREEN}Passed: $PASSED_TESTS${NC}"
    log "${RED}Failed: $FAILED_TESTS${NC}"
    log "=========================================="

    if [[ $FAILED_TESTS -eq 0 ]]; then
        log "${GREEN}All tests passed!${NC}"
        exit 0
    else
        log "${RED}Some tests failed. Check the log for details.${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
