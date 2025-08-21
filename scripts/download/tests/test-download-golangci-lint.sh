#!/usr/bin/env bash

# Test script for download-golangci-lint.sh
# This script tests various scenarios for the golangci-lint download script

set -eou pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test directory setup
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DOWNLOAD_SCRIPT="${SCRIPT_DIR}/../download-golangci-lint.sh"
TEST_INSTALL_DIR="${SCRIPT_DIR}/test_bin"
TEST_LOG_FILE="${SCRIPT_DIR}/test_results.log"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test version constants
VALID_VERSION_OLD="v1.64.7"
VALID_VERSION_NEW="v1.64.8"
INVALID_VERSION="v999.999.999"

# Utility functions
log() {
    echo -e "$1" | tee -a "$TEST_LOG_FILE"
}

# Extract version from golangci-lint --version output and normalize it with 'v' prefix
extract_golangci_version() {
    local version_output="$1"
    local version_num
    version_num=$(echo "$version_output" | grep -o -E 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ -n "$version_num" && "$version_num" != v* ]]; then
        echo "v$version_num"
    else
        echo "$version_num"
    fi
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
    echo "golangci-lint Download Script Test Results - $(date)" > "$TEST_LOG_FILE"
    echo "================================================" >> "$TEST_LOG_FILE"
}

cleanup_test_environment() {
    log "Cleaning up test environment..."

    # Remove test directory
    if [[ -d "$TEST_INSTALL_DIR" ]]; then
        rm -rf "$TEST_INSTALL_DIR"
    fi
}

test_download_valid_version() {
    log_test_start "Download valid version to empty directory"

    local test_dir="${TEST_INSTALL_DIR}/valid_version"
    mkdir -p "$test_dir"

    # Test should succeed
    if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$VALID_VERSION_NEW" >> "$TEST_LOG_FILE" 2>&1; then
        # Check if binary was created
        if [[ -x "$test_dir/golangci-lint" ]]; then
            # Verify version
            local version_output
            if version_output=$("$test_dir/golangci-lint" --version 2>&1 | head -1); then
                local extracted_version
                extracted_version=$(extract_golangci_version "$version_output")
                if [[ "$extracted_version" == "$VALID_VERSION_NEW" ]]; then
                    log_test_pass "Download valid version to empty directory"
                else
                    log_test_fail "Download valid version to empty directory" "Wrong version: expected $VALID_VERSION_NEW, got $extracted_version (full output: $version_output)"
                fi
            else
                log_test_fail "Download valid version to empty directory" "Version check failed"
            fi
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

    # First install old version
    if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$VALID_VERSION_OLD" >> "$TEST_LOG_FILE" 2>&1; then
        # Then try to install newer version
        if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$VALID_VERSION_NEW" >> "$TEST_LOG_FILE" 2>&1; then
            # Check if the newer version is now installed
            local version_output
            if version_output=$("$test_dir/golangci-lint" --version 2>&1 | head -1); then
                local extracted_version
                extracted_version=$(extract_golangci_version "$version_output")
                if [[ "$extracted_version" == "$VALID_VERSION_NEW" ]]; then
                    log_test_pass "Download newer version when old version exists"
                else
                    log_test_fail "Download newer version when old version exists" "Expected newer version $VALID_VERSION_NEW, got $extracted_version (full output: $version_output)"
                fi
            else
                log_test_fail "Download newer version when old version exists" "Version check failed"
            fi
        else
            log_test_fail "Download newer version when old version exists" "Second script run failed"
        fi
    else
        log_test_fail "Download newer version when old version exists" "First script run failed"
    fi
}

test_old_version_when_newer_exists() {
    log_test_start "Request old version when newer version exists"

    local test_dir="${TEST_INSTALL_DIR}/old_when_newer"
    mkdir -p "$test_dir"

    # First install newer version
    if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$VALID_VERSION_NEW" >> "$TEST_LOG_FILE" 2>&1; then
        # Then try to request older version (should download exact version requested)
        if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$VALID_VERSION_OLD" >> "$TEST_LOG_FILE" 2>&1; then
            # Check that older version is now installed (replaced newer version)
            local version_output
            if version_output=$("$test_dir/golangci-lint" --version 2>&1 | head -1); then
                local extracted_version
                extracted_version=$(extract_golangci_version "$version_output")
                if [[ "$extracted_version" == "$VALID_VERSION_OLD" ]]; then
                    log_test_pass "Request old version when newer version exists"
                else
                    log_test_fail "Request old version when newer version exists" "Version not replaced: expected $VALID_VERSION_OLD, got $extracted_version (full output: $version_output)"
                fi
            else
                log_test_fail "Request old version when newer version exists" "Version check failed"
            fi
        else
            log_test_fail "Request old version when newer version exists" "Second script run failed"
        fi
    else
        log_test_fail "Request old version when newer version exists" "First script run failed"
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

test_missing_install_dir_argument() {
    log_test_start "Test missing install directory argument"

    # Test missing install directory argument should fail
    if "$DOWNLOAD_SCRIPT" --install-dir >> "$TEST_LOG_FILE" 2>&1; then
        log_test_fail "Test missing install directory argument" "Script should have failed but succeeded"
    else
        log_test_pass "Test missing install directory argument"
    fi
}

test_download_ignores_path() {
    log_test_start "Test download ignores golangci-lint in PATH"

    local test_dir="${TEST_INSTALL_DIR}/path_ignore_test"
    mkdir -p "$test_dir"

    # Create fake golangci-lint in PATH by adding test directory to PATH temporarily
    cat > "$test_dir/golangci-lint" << EOF
#!/bin/bash
echo "golangci-lint has version ${VALID_VERSION_OLD} built from 12345 on 2023-01-01T00:00:00Z"
EOF
    chmod +x "$test_dir/golangci-lint"

    # Temporarily add test directory to PATH
    local old_path="$PATH"
    export PATH="$test_dir:$PATH"

    # Test should succeed and download to local directory (ignoring PATH)
    local install_dir="${TEST_INSTALL_DIR}/path_ignore_install"
    if "$DOWNLOAD_SCRIPT" --install-dir "$install_dir" "$VALID_VERSION_NEW" >> "$TEST_LOG_FILE" 2>&1; then
        if [[ -x "$install_dir/golangci-lint" ]]; then
            log_test_pass "Test download ignores golangci-lint in PATH"
        else
            log_test_fail "Test download ignores golangci-lint in PATH" "Local binary not created"
        fi
    else
        log_test_fail "Test download ignores golangci-lint in PATH" "Script failed"
    fi

    # Restore PATH
    export PATH="$old_path"
}

test_custom_install_directory() {
    log_test_start "Test custom install directory"

    local custom_dir="${TEST_INSTALL_DIR}/custom"

    # Test should succeed with custom directory
    if "$DOWNLOAD_SCRIPT" --install-dir "$custom_dir" "$VALID_VERSION_NEW" >> "$TEST_LOG_FILE" 2>&1; then
        if [[ -x "$custom_dir/golangci-lint" ]]; then
            log_test_pass "Test custom install directory"
        else
            log_test_fail "Test custom install directory" "Binary not created in custom directory"
        fi
    else
        log_test_fail "Test custom install directory" "Script failed"
    fi
}

test_version_format_validation() {
    log_test_start "Test version format validation"

    local test_dir="${TEST_INSTALL_DIR}/version_format"
    mkdir -p "$test_dir"

    # Test with invalid version format
    if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "invalid-version" >> "$TEST_LOG_FILE" 2>&1; then
        log_test_fail "Test version format validation" "Script should have failed with invalid version format"
    else
        log_test_pass "Test version format validation"
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
    log "Starting golangci-lint Download Script Tests"
    log "============================================"

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
    test_help_option
    test_invalid_option
    test_missing_install_dir_argument
    test_download_ignores_path
    test_custom_install_directory
    test_version_format_validation

    cleanup_test_environment

    print_test_summary
}

# Run main function
main "$@"
