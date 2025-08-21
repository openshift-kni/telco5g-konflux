#!/usr/bin/env bash

# Test script for download-yq.sh
# This script tests various scenarios for the yq download script

set -eou pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test directory setup
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DOWNLOAD_SCRIPT="${SCRIPT_DIR}/../download-yq.sh"
TEST_INSTALL_DIR="${SCRIPT_DIR}/test_bin"
TEST_LOG_FILE="${SCRIPT_DIR}/test_results.log"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test version constants
VALID_VERSION_OLD="v4.44.2"
VALID_VERSION_NEW="v4.45.4"
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
    echo "yq Download Script Test Results - $(date)" > "$TEST_LOG_FILE"
    echo "================================================" >> "$TEST_LOG_FILE"
}

cleanup_test_environment() {
    log "Cleaning up test environment..."

    # Remove test directory
    if [[ -d "$TEST_INSTALL_DIR" ]]; then
        rm -rf "$TEST_INSTALL_DIR"
    fi
}

create_fake_yq_binary() {
    local version="$1"
    local install_path="$2"

    # Create fake yq binary that returns the specified version
    cat > "$install_path" << EOF
#!/bin/bash
echo "yq (https://github.com/mikefarah/yq/) version $version"
EOF
    chmod +x "$install_path"
}

test_download_valid_version() {
    log_test_start "Download valid version to empty directory"

    local test_dir="${TEST_INSTALL_DIR}/valid_version"
    mkdir -p "$test_dir"

    # Test should succeed
    if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$VALID_VERSION_NEW" >> "$TEST_LOG_FILE" 2>&1; then
        # Check if binary was created
        if [[ -x "$test_dir/yq" ]]; then
            log_test_pass "Download valid version to empty directory"
        else
            log_test_fail "Download valid version to empty directory" "Binary not created"
        fi
    else
        log_test_fail "Download valid version to empty directory" "Script failed"
    fi
}

test_download_invalid_version() {
    log_test_start "Download invalid version"

    local test_dir="${TEST_INSTALL_DIR}/invalid_version"
    mkdir -p "$test_dir"

    # Test should fail
    if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$INVALID_VERSION" >> "$TEST_LOG_FILE" 2>&1; then
        log_test_fail "Download invalid version" "Script should have failed but succeeded"
    else
        log_test_pass "Download invalid version"
    fi
}

test_newer_version_when_old_exists() {
    log_test_start "Download newer version when old version exists"

    local test_dir="${TEST_INSTALL_DIR}/newer_when_old"
    mkdir -p "$test_dir"

    # Create fake old version
    create_fake_yq_binary "$VALID_VERSION_OLD" "$test_dir/yq"

    # Test should succeed and replace old version
    if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$VALID_VERSION_NEW" >> "$TEST_LOG_FILE" 2>&1; then
        if [[ -x "$test_dir/yq" ]]; then
            log_test_pass "Download newer version when old version exists"
        else
            log_test_fail "Download newer version when old version exists" "Binary not created"
        fi
    else
        log_test_fail "Download newer version when old version exists" "Script failed"
    fi
}

test_old_version_when_newer_exists() {
    log_test_start "Request old version when newer version exists"

    local test_dir="${TEST_INSTALL_DIR}/old_when_newer"
    mkdir -p "$test_dir"

    # Create fake newer version
    create_fake_yq_binary "$VALID_VERSION_NEW" "$test_dir/yq"

    # Test should succeed and download exact version requested (replaces newer version)
    if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$VALID_VERSION_OLD" >> "$TEST_LOG_FILE" 2>&1; then
        if [[ -x "$test_dir/yq" ]]; then
            log_test_pass "Request old version when newer version exists"
        else
            log_test_fail "Request old version when newer version exists" "Binary not found"
        fi
    else
        log_test_fail "Request old version when newer version exists" "Script failed"
    fi
}

test_version_without_v_prefix() {
    log_test_start "Test version without v prefix"

    local test_dir="${TEST_INSTALL_DIR}/no_v_prefix"
    mkdir -p "$test_dir"

    # Test should succeed without v prefix (script should add it)
    local version_no_v="${VALID_VERSION_NEW#v}"
    if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$version_no_v" >> "$TEST_LOG_FILE" 2>&1; then
        # Check if binary was created
        if [[ -x "$test_dir/yq" ]]; then
            log_test_pass "Test version without v prefix"
        else
            log_test_fail "Test version without v prefix" "Binary not created"
        fi
    else
        log_test_fail "Test version without v prefix" "Script failed"
    fi
}

test_help_option() {
    log_test_start "Test help option"

    # Test help option should succeed
    if "$DOWNLOAD_SCRIPT" --help >> "$TEST_LOG_FILE" 2>&1; then
        log_test_pass "Test help option"
    else
        log_test_fail "Test help option" "Help option failed"
    fi
}

test_invalid_option() {
    log_test_start "Test invalid option"

    # Test invalid option should fail
    if "$DOWNLOAD_SCRIPT" --invalid-option >> "$TEST_LOG_FILE" 2>&1; then
        log_test_fail "Test invalid option" "Script should have failed but succeeded"
    else
        log_test_pass "Test invalid option"
    fi
}

test_version_format_validation() {
    log_test_start "Test version format validation"

    local test_dir="${TEST_INSTALL_DIR}/version_format"
    mkdir -p "$test_dir"

    # Test invalid version format should fail
    if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "invalid-version" >> "$TEST_LOG_FILE" 2>&1; then
        log_test_fail "Test version format validation" "Script should have failed but succeeded"
    else
        log_test_pass "Test version format validation"
    fi
}

test_missing_install_dir_argument() {
    log_test_start "Test missing install directory argument"

    # Test missing install directory argument should fail
    if "$DOWNLOAD_SCRIPT" --install-dir >> "$TEST_LOG_FILE" 2>&1; then
        log_test_fail "Test missing install directory argument" "Script should have failed but succeeded"
    else
        log_test_pass "Test missing install directory argument"
    fi
}

print_test_summary() {
    log ""
    log "================================================"
    log "Test Summary:"
    log "Total tests: $TOTAL_TESTS"
    log "Passed: $PASSED_TESTS"
    log "Failed: $FAILED_TESTS"
    log "================================================"

    if [[ $FAILED_TESTS -gt 0 ]]; then
        log "${RED}Some tests failed. See $TEST_LOG_FILE for details.${NC}"
        return 1
    else
        log "${GREEN}All tests passed!${NC}"
        return 0
    fi
}

main() {
    log "Starting yq Download Script Tests"
    log "================================="

    # Check if download script exists
    if [[ ! -f "$DOWNLOAD_SCRIPT" ]]; then
        log "${RED}Error: Download script not found at $DOWNLOAD_SCRIPT${NC}"
        exit 1
    fi

    setup_test_environment

    # Run tests
    test_download_valid_version
    test_download_invalid_version
    test_newer_version_when_old_exists
    test_old_version_when_newer_exists
    test_version_without_v_prefix
    test_help_option
    test_invalid_option
    test_version_format_validation
    test_missing_install_dir_argument

    cleanup_test_environment

    print_test_summary
}

# Run main function
main "$@"
