#!/usr/bin/env bash

# Test script for download-bashate.sh
# This script tests various scenarios for the bashate download script

set -eou pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test directory setup
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DOWNLOAD_SCRIPT="${SCRIPT_DIR}/../download-bashate.sh"
TEST_INSTALL_DIR="${SCRIPT_DIR}/test_bin"
TEST_LOG_FILE="${SCRIPT_DIR}/test_results.log"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test version constants
VALID_VERSION_OLD="2.1.0"
VALID_VERSION_NEW="2.1.1"
INVALID_VERSION="999.999.999"

# Utility functions
log() {
    echo -e "$1" | tee -a "$TEST_LOG_FILE"
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    log "\n${YELLOW}[TEST $TOTAL_TESTS]${NC} $test_name"
    log "Command: $test_command"

    # Clean up test directory before each test
    rm -rf "$TEST_INSTALL_DIR"
    mkdir -p "$TEST_INSTALL_DIR"

    # Run the test command
    if eval "$test_command" >> "$TEST_LOG_FILE" 2>&1; then
        actual_exit_code=0
    else
        actual_exit_code=$?
    fi

    # Check if exit code matches expected
    if [[ $actual_exit_code -eq $expected_exit_code ]]; then
        log "${GREEN}✓ PASSED${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        log "${RED}✗ FAILED${NC} (Expected exit code: $expected_exit_code, Actual: $actual_exit_code)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

verify_installation() {
    local binary_path="$1"
    local expected_version="$2"
    local venv_path="$3"

    if [[ ! -x "$binary_path" ]]; then
        log "Binary not found or not executable: $binary_path"
        return 1
    fi

    if [[ ! -d "$venv_path" ]]; then
        log "Virtual environment directory not found: $venv_path"
        return 1
    fi

    local actual_version
    if ! actual_version=$("$binary_path" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1); then
        log "Failed to get version from $binary_path"
        return 1
    fi

    if [[ "$actual_version" == "$expected_version" ]]; then
        log "Version verification passed: $actual_version"
        log "Virtual environment verified: $venv_path"
        return 0
    else
        log "Version mismatch. Expected: $expected_version, Actual: $actual_version"
        return 1
    fi
}

check_python() {
    if ! command -v python3 >/dev/null 2>&1; then
        log "${YELLOW}Warning: Python 3 not found. Some tests may fail.${NC}"
        return 1
    fi
    return 0
}

# Initialize test log
echo "bashate Download Script Test Results" > "$TEST_LOG_FILE"
echo "Test started at: $(date)" >> "$TEST_LOG_FILE"
echo "========================================" >> "$TEST_LOG_FILE"

log "${YELLOW}Starting bashate download script tests...${NC}"

# Check Python availability
if ! check_python; then
    log "${RED}Python 3 is required for bashate installation. Skipping tests.${NC}"
    exit 1
fi

# Test 1: Help message
run_test "Help message display" \
    "'$DOWNLOAD_SCRIPT' --help"

# Test 2: Download with default version
run_test "Download default version" \
    "'$DOWNLOAD_SCRIPT' --install-dir '$TEST_INSTALL_DIR'"

if [[ $? -eq 0 ]]; then
    # Verify the installation
    if verify_installation "$TEST_INSTALL_DIR/bashate" "2.1.1" "$TEST_INSTALL_DIR/.bashate-venv"; then
        log "${GREEN}Installation verification passed${NC}"
    else
        log "${RED}Installation verification failed${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
fi

# Test 3: Download specific older version
run_test "Download specific version ($VALID_VERSION_OLD)" \
    "'$DOWNLOAD_SCRIPT' --install-dir '$TEST_INSTALL_DIR' '$VALID_VERSION_OLD'"

if [[ $? -eq 0 ]]; then
    if verify_installation "$TEST_INSTALL_DIR/bashate" "$VALID_VERSION_OLD" "$TEST_INSTALL_DIR/.bashate-venv"; then
        log "${GREEN}Installation verification passed${NC}"
    else
        log "${RED}Installation verification failed${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
fi

# Test 4: Download with force flag (should reinstall)
run_test "Force reinstall" \
    "'$DOWNLOAD_SCRIPT' --install-dir '$TEST_INSTALL_DIR' --force '$VALID_VERSION_NEW'"

if [[ $? -eq 0 ]]; then
    if verify_installation "$TEST_INSTALL_DIR/bashate" "$VALID_VERSION_NEW" "$TEST_INSTALL_DIR/.bashate-venv"; then
        log "${GREEN}Force installation verification passed${NC}"
    else
        log "${RED}Force installation verification failed${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
fi

# Test 5: Skip download if compatible version exists
TOTAL_TESTS=$((TOTAL_TESTS + 1))

log "\n${YELLOW}[TEST $TOTAL_TESTS]${NC} Skip download for existing compatible version"
log "Command: '$DOWNLOAD_SCRIPT' --install-dir '$TEST_INSTALL_DIR' '$VALID_VERSION_OLD'"

# Run the test command without cleaning up the directory first
# This should skip installation since Test 4 installed a newer version (2.1.1) and we're requesting an older one (2.1.0)
if "$DOWNLOAD_SCRIPT" --install-dir "$TEST_INSTALL_DIR" "$VALID_VERSION_OLD" >> "$TEST_LOG_FILE" 2>&1; then
    actual_exit_code=0
else
    actual_exit_code=$?
fi

# Check if exit code matches expected (0)
if [[ $actual_exit_code -eq 0 ]]; then
    log "${GREEN}✓ PASSED${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))

    # Verify that it actually skipped installation by checking if the output contains the skip message
    if tail -n 10 "$TEST_LOG_FILE" | grep -q "is already installed.*and meets the required version"; then
        log "${GREEN}Successfully skipped installation for compatible version${NC}"
    else
        log "${YELLOW}Warning: Installation may not have been skipped as expected${NC}"
    fi
else
    log "${RED}✗ FAILED${NC} (Expected exit code: 0, Actual: $actual_exit_code)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Test 6: Invalid version format
run_test "Invalid version format" \
    "'$DOWNLOAD_SCRIPT' --install-dir '$TEST_INSTALL_DIR' 'invalid-version'" 1

# Test 7: Non-existent version (should fail)
run_test "Non-existent version" \
    "'$DOWNLOAD_SCRIPT' --install-dir '$TEST_INSTALL_DIR' '$INVALID_VERSION'" 1

# Test 8: Invalid option
run_test "Invalid command line option" \
    "'$DOWNLOAD_SCRIPT' --invalid-option" 1

# Test 9: Verbose mode
run_test "Verbose mode" \
    "'$DOWNLOAD_SCRIPT' --install-dir '$TEST_INSTALL_DIR' --verbose --force '$VALID_VERSION_NEW'"

# Test 10: Test wrapper script functionality
if [[ -x "$TEST_INSTALL_DIR/bashate" && -d "$TEST_INSTALL_DIR/.bashate-venv" ]]; then
    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    log "\n${YELLOW}[TEST $TOTAL_TESTS]${NC} Wrapper script execution test"
    log "Command: '$TEST_INSTALL_DIR/bashate' --help"

    # Run the test command without cleaning up the directory first
    if "$TEST_INSTALL_DIR/bashate" --help >> "$TEST_LOG_FILE" 2>&1; then
        actual_exit_code=0
    else
        actual_exit_code=$?
    fi

    # Check if exit code matches expected (0)
    if [[ $actual_exit_code -eq 0 ]]; then
        log "${GREEN}✓ PASSED${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log "${RED}✗ FAILED${NC} (Expected exit code: 0, Actual: $actual_exit_code)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
fi

# Clean up test directory
log "\n${YELLOW}Cleaning up test directory...${NC}"
rm -rf "$TEST_INSTALL_DIR"

# Test results summary
log "\n========================================="
log "${YELLOW}TEST SUMMARY${NC}"
log "========================================="
log "Total tests: $TOTAL_TESTS"
log "${GREEN}Passed: $PASSED_TESTS${NC}"
log "${RED}Failed: $FAILED_TESTS${NC}"

if [[ $FAILED_TESTS -eq 0 ]]; then
    log "\n${GREEN}🎉 All tests passed!${NC}"
    exit 0
else
    log "\n${RED}❌ Some tests failed. Check the log for details.${NC}"
    log "Full test log: $TEST_LOG_FILE"
    exit 1
fi