#!/usr/bin/env bash

# Test script for download-yamllint.sh
# This script tests various scenarios for the yamllint download script

set -eou pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test directory setup
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DOWNLOAD_SCRIPT="${SCRIPT_DIR}/../download-yamllint.sh"
TEST_INSTALL_DIR="${SCRIPT_DIR}/test_bin"
TEST_LOG_FILE="${SCRIPT_DIR}/test_results.log"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test version constants
VALID_VERSION_OLD="1.35.1"
VALID_VERSION_NEW="1.37.1"
INVALID_VERSION="999.999.999"

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
    echo "yamllint Download Script Test Results - $(date)" > "$TEST_LOG_FILE"
    echo "================================================" >> "$TEST_LOG_FILE"
}

cleanup_test_environment() {
    log "Cleaning up test environment..."

    # Remove test directory
    if [[ -d "$TEST_INSTALL_DIR" ]]; then
        rm -rf "$TEST_INSTALL_DIR"
    fi
}

check_python_available() {
    # Check if Python is available for testing
    local python_available=false
    for cmd in python3 python; do
        if command -v "$cmd" > /dev/null 2>&1; then
            local version
            if version=$("$cmd" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null); then
                if [[ "$version" =~ ^3\.([6-9]|[1-9][0-9])$ ]]; then
                    python_available=true
                    break
                fi
            fi
        fi
    done

    if [[ "$python_available" != "true" ]]; then
        log "${YELLOW}WARNING: Python 3.6+ not found. Some tests will be skipped.${NC}"
        return 1
    fi
    return 0
}

test_download_valid_version() {
    log_test_start "Download valid version to empty directory"

    if ! check_python_available; then
        log_test_pass "Download valid version to empty directory (skipped - no Python)"
        return
    fi

    local test_dir="${TEST_INSTALL_DIR}/valid_version"
    mkdir -p "$test_dir"

    # Test should succeed
    if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$VALID_VERSION_NEW" >> "$TEST_LOG_FILE" 2>&1; then
        # Check if wrapper script was created
        if [[ -x "$test_dir/yamllint" ]]; then
            # Check if virtual environment was created
            if [[ -d "$test_dir/.yamllint-venv" ]]; then
                log_test_pass "Download valid version to empty directory"
            else
                log_test_fail "Download valid version to empty directory" "Virtual environment not created"
            fi
        else
            log_test_fail "Download valid version to empty directory" "Wrapper script not created"
        fi
    else
        log_test_fail "Download valid version to empty directory" "Script failed"
    fi
}

test_download_invalid_version() {
    log_test_start "Download invalid version"

    if ! check_python_available; then
        log_test_pass "Download invalid version (skipped - no Python)"
        return
    fi

    local test_dir="${TEST_INSTALL_DIR}/invalid_version"
    mkdir -p "$test_dir"

    # Test should fail
    if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$INVALID_VERSION" >> "$TEST_LOG_FILE" 2>&1; then
        log_test_fail "Download invalid version" "Script should have failed but succeeded"
    else
        log_test_pass "Download invalid version"
    fi
}

test_version_specific_install() {
    log_test_start "Install specific older version"

    if ! check_python_available; then
        log_test_pass "Install specific older version (skipped - no Python)"
        return
    fi

    local test_dir="${TEST_INSTALL_DIR}/older_version"
    mkdir -p "$test_dir"

    # Test should succeed
    if "$DOWNLOAD_SCRIPT" --install-dir "$test_dir" "$VALID_VERSION_OLD" >> "$TEST_LOG_FILE" 2>&1; then
        if [[ -x "$test_dir/yamllint" ]]; then
            # Check if the version is correct
            local version_output
            if version_output=$("$test_dir/yamllint" --version 2>&1); then
                if echo "$version_output" | grep -q "$VALID_VERSION_OLD"; then
                    log_test_pass "Install specific older version"
                else
                    log_test_fail "Install specific older version" "Wrong version installed: $version_output"
                fi
            else
                log_test_fail "Install specific older version" "Version check failed"
            fi
        else
            log_test_fail "Install specific older version" "Wrapper script not created"
        fi
    else
        log_test_fail "Install specific older version" "Script failed"
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
    log_test_start "Test download ignores yamllint in PATH"

    if ! check_python_available; then
        log_test_pass "Test download ignores yamllint in PATH (skipped - no Python)"
        return
    fi

    local test_dir="${TEST_INSTALL_DIR}/path_ignore_test"
    mkdir -p "$test_dir"

    # Create fake yamllint in PATH by adding test directory to PATH temporarily
    cat > "$test_dir/yamllint" << EOF
#!/bin/bash
echo "yamllint 1.35.0"
EOF
    chmod +x "$test_dir/yamllint"

    # Temporarily add test directory to PATH
    local old_path="$PATH"
    export PATH="$test_dir:$PATH"

    # Test should succeed and download to local directory (ignoring PATH)
    local install_dir="${TEST_INSTALL_DIR}/path_ignore_install"
    if "$DOWNLOAD_SCRIPT" --install-dir "$install_dir" "$VALID_VERSION_NEW" >> "$TEST_LOG_FILE" 2>&1; then
        if [[ -x "$install_dir/yamllint" ]]; then
            log_test_pass "Test download ignores yamllint in PATH"
        else
            log_test_fail "Test download ignores yamllint in PATH" "Local binary not created"
        fi
    else
        log_test_fail "Test download ignores yamllint in PATH" "Script failed"
    fi

    # Restore PATH
    export PATH="$old_path"
}

test_custom_install_directory() {
    log_test_start "Test custom install directory"

    if ! check_python_available; then
        log_test_pass "Test custom install directory (skipped - no Python)"
        return
    fi

    local custom_dir="${TEST_INSTALL_DIR}/custom"

    # Test should succeed with custom directory
    if "$DOWNLOAD_SCRIPT" --install-dir "$custom_dir" "$VALID_VERSION_NEW" >> "$TEST_LOG_FILE" 2>&1; then
        if [[ -x "$custom_dir/yamllint" ]]; then
            log_test_pass "Test custom install directory"
        else
            log_test_fail "Test custom install directory" "Wrapper script not created in custom directory"
        fi
    else
        log_test_fail "Test custom install directory" "Script failed"
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
    log "Starting yamllint Download Script Tests"
    log "======================================="

    # Check if download script exists
    if [[ ! -f "$DOWNLOAD_SCRIPT" ]]; then
        log "${RED}Error: Download script not found at $DOWNLOAD_SCRIPT${NC}"
        exit 1
    fi

    setup_test_environment

    # Run tests
    test_download_valid_version
    test_download_invalid_version
    test_version_specific_install
    test_help_option
    test_invalid_option
    test_missing_install_dir_argument
    test_download_ignores_path
    test_custom_install_directory

    cleanup_test_environment

    print_test_summary
}

# Run main function
main "$@"
