#!/usr/bin/env bash

# Integration test for RHEL 8 RPM lock generation
# This test validates the full end-to-end functionality of the generate-rhel8-locks.sh script

set -uo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"
TESTS_DIR="$(dirname "$SCRIPT_DIR")"
PARENT_DIR="$(dirname "$TESTS_DIR")"
TEST_DIR="$SCRIPT_DIR"
RHEL8_SCRIPT="${PARENT_DIR}/generate-rhel8-locks.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to print test results
print_test_result() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"
    if [[ "$result" == "PASS" ]]; then
        echo -e "${GREEN}PASS${NC}: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        if [[ -n "$details" ]]; then
            echo "  $details"
        fi
    else
        echo -e "${RED}FAIL${NC}: $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        if [[ -n "$details" ]]; then
            echo "  $details"
        fi
    fi
}

# Helper function to print info messages
print_info() {
    echo -e "${BLUE}INFO${NC}: $1"
}

# Helper function to print warnings
print_warning() {
    echo -e "${YELLOW}WARNING${NC}: $1"
}

# Cleanup function
cleanup() {
    if [[ -d "$TEST_DIR" ]]; then
        rm -f "$TEST_DIR/redhat.repo" "$TEST_DIR/rpms.lock.yaml" "$TEST_DIR/podman_script.sh"
        rm -f "$TEST_DIR/redhat-rhel8.repo.generated"
        print_info "Cleaned up generated test files"
    fi
}

# Set up cleanup trap
trap cleanup EXIT

echo "=== RHEL 8 RPM Lock Generation Integration Test ==="
echo

# Test 1: Check prerequisites
echo "Test 1: Check prerequisites"
if [[ ! -f "$RHEL8_SCRIPT" ]]; then
    print_test_result "RHEL 8 script exists" "FAIL" "Script not found at $RHEL8_SCRIPT"
    exit 1
else
    print_test_result "RHEL 8 script exists" "PASS"
fi

if [[ ! -f "$TEST_DIR/rpms.in.yaml" ]]; then
    print_test_result "Test input file exists" "FAIL" "Input file not found at $TEST_DIR/rpms.in.yaml"
    exit 1
else
    print_test_result "Test input file exists" "PASS"
fi

# Test 2: Validate input file structure
echo
echo "Test 2: Validate input file structure"
EXPECTED_PACKAGES=("jq" "less" "findutils" "procps-ng")
EXPECTED_REPOS=("ubi-8-baseos" "ubi-8-appstream")

# Check packages
FOUND_PACKAGES=()
while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.+)$ ]]; then
        package_name="${BASH_REMATCH[1]// /}"
        FOUND_PACKAGES+=("$package_name")
    fi
done < "$TEST_DIR/rpms.in.yaml"

if [[ ${#FOUND_PACKAGES[@]} -eq ${#EXPECTED_PACKAGES[@]} ]]; then
    print_test_result "Package count validation" "PASS" "Found ${#FOUND_PACKAGES[@]} packages"
else
    print_test_result "Package count validation" "FAIL" "Expected ${#EXPECTED_PACKAGES[@]}, found ${#FOUND_PACKAGES[@]}"
fi

# Check repositories
FOUND_REPOS=()
while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*-[[:space:]]*repoid:[[:space:]]*(.+)$ ]]; then
        repo_id="${BASH_REMATCH[1]// /}"
        FOUND_REPOS+=("$repo_id")
    fi
done < "$TEST_DIR/rpms.in.yaml"

if [[ ${#FOUND_REPOS[@]} -eq ${#EXPECTED_REPOS[@]} ]]; then
    print_test_result "Repository count validation" "PASS" "Found ${#FOUND_REPOS[@]} repositories"
else
    print_test_result "Repository count validation" "FAIL" "Expected ${#EXPECTED_REPOS[@]}, found ${#FOUND_REPOS[@]}"
fi

# Test 3: Check for podman availability
echo
echo "Test 3: Check for podman availability"
if command -v podman &> /dev/null; then
    print_test_result "Podman availability" "PASS" "$(podman --version)"
    PODMAN_AVAILABLE=true
else
    print_test_result "Podman availability" "FAIL" "Podman not found - will run dry-run tests only"
    PODMAN_AVAILABLE=false
fi

# Test 4: Test script execution
echo
echo "Test 4: Script execution validation"

# Determine test mode based on environment variables
if [[ -n "${RHEL8_ACTIVATION_KEY:-}" && -n "${RHEL8_ORG_ID:-}" && \
    -n "${RHEL9_ACTIVATION_KEY:-}" && -n "${RHEL9_ORG_ID:-}" && \
    "${RHEL8_ACTIVATION_KEY}" != "placeholder" && "${RHEL8_ACTIVATION_KEY}" != "1234567890" && \
    "${RHEL8_ORG_ID}" != "placeholder" && "${RHEL8_ORG_ID}" != "1234567890" && \
    "${RHEL9_ACTIVATION_KEY}" != "placeholder" && "${RHEL9_ACTIVATION_KEY}" != "1234567890" && \
    "${RHEL9_ORG_ID}" != "placeholder" && "${RHEL9_ORG_ID}" != "1234567890" ]]; then
    print_info "Running script with RHSM credentials (subscription mode)"
    TEST_MODE="RHSM"
    # Keep existing credentials and use subscription images
    export RHEL8_EXECUTION_IMAGE="${RHEL8_EXECUTION_IMAGE:-registry.redhat.io/ubi8/ubi:8.10}"
    export RHEL9_EXECUTION_IMAGE="${RHEL9_EXECUTION_IMAGE:-registry.redhat.io/ubi9/ubi:9.4}"
    export RHEL8_IMAGE_TO_LOCK="${RHEL8_IMAGE_TO_LOCK:-registry.redhat.io/ubi8/ubi-minimal:8.10}"
else
    print_info "Running script without RHSM credentials (UBI mode)"
    TEST_MODE="UBI"
    # Set environment variables for UBI mode (no credentials)
    export RHEL8_ACTIVATION_KEY=""
    export RHEL8_ORG_ID=""
    export RHEL9_ACTIVATION_KEY=""
    export RHEL9_ORG_ID=""
    export RHEL8_EXECUTION_IMAGE="registry.access.redhat.com/ubi8/ubi:8.10"
    export RHEL9_EXECUTION_IMAGE="registry.access.redhat.com/ubi9/ubi:9.4"
    export RHEL8_IMAGE_TO_LOCK="registry.access.redhat.com/ubi8/ubi-minimal:8.10"
fi

if [[ "$PODMAN_AVAILABLE" == "true" ]]; then
    # Attempt to run the script
    print_info "Executing: $RHEL8_SCRIPT $TEST_DIR"

    # Capture output and exit code
    if OUTPUT=$("$RHEL8_SCRIPT" "$TEST_DIR" 2>&1); then
        SCRIPT_EXIT_CODE=0
    else
        SCRIPT_EXIT_CODE=$?
        print_warning "Script execution failed with exit code $SCRIPT_EXIT_CODE"
    fi

    # Check if expected files were generated
    if [[ -f "$TEST_DIR/redhat.repo" ]]; then
        print_test_result "Generated redhat.repo file" "PASS"

        # Validate repo file content based on test mode
        if [[ "$TEST_MODE" == "UBI" ]]; then
            if grep -q "ubi-8-baseos" "$TEST_DIR/redhat.repo"; then
                print_test_result "UBI repositories in repo file" "PASS" "Found UBI repository configurations"
            else
                print_test_result "UBI repositories in repo file" "FAIL" "UBI repositories not found"
            fi
        else
            # RHSM mode - check for subscription-based repositories
            if grep -q "rhel-8-for-.*-baseos-rpms\|rhel-8-for-.*-appstream-rpms" "$TEST_DIR/redhat.repo"; then
                print_test_result "RHEL repositories in repo file" "PASS" "Found RHEL repository configurations"
            else
                print_test_result "RHEL repositories in repo file" "FAIL" "RHEL repositories not found"
            fi
        fi
    else
        print_test_result "Generated redhat.repo file" "FAIL" "File not created"
    fi

    if [[ -f "$TEST_DIR/rpms.lock.yaml" ]]; then
        print_test_result "Generated rpms.lock.yaml file" "PASS"

        # Validate lock file content
        LOCK_FILE_SIZE=$(wc -l < "$TEST_DIR/rpms.lock.yaml" | tr -d ' ')
        if [[ $LOCK_FILE_SIZE -gt 10 ]]; then
            print_test_result "Lock file has content" "PASS" "File has $LOCK_FILE_SIZE lines"

            # Check for expected packages in lock file
            PACKAGES_FOUND_IN_LOCK=0
            for package in "${EXPECTED_PACKAGES[@]}"; do
                if grep -q "$package" "$TEST_DIR/rpms.lock.yaml"; then
                    PACKAGES_FOUND_IN_LOCK=$((PACKAGES_FOUND_IN_LOCK + 1))
                fi
            done

            if [[ $PACKAGES_FOUND_IN_LOCK -gt 0 ]]; then
                print_test_result "Expected packages in lock file" "PASS" "Found $PACKAGES_FOUND_IN_LOCK/${#EXPECTED_PACKAGES[@]} expected packages"
            else
                print_test_result "Expected packages in lock file" "FAIL" "No expected packages found in lock file"
            fi

            # Validate YAML structure
            PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"

            # Try to use virtual environment if available
            if [[ -f "$PROJECT_ROOT/venv/bin/activate" ]]; then
                # Activate virtual environment and test YAML
                if (source "$PROJECT_ROOT/venv/bin/activate" && python3 -c "import yaml; yaml.safe_load(open('$TEST_DIR/rpms.lock.yaml'))" 2>/dev/null); then
                    print_test_result "Lock file YAML validity" "PASS" "Valid YAML structure"
                else
                    print_test_result "Lock file YAML validity" "FAIL" "Invalid YAML structure"
                fi
            elif command -v python3 &> /dev/null && python3 -c "import yaml" 2>/dev/null; then
                # Fall back to system Python if it has PyYAML
                if python3 -c "import yaml; yaml.safe_load(open('$TEST_DIR/rpms.lock.yaml'))" 2>/dev/null; then
                    print_test_result "Lock file YAML validity" "PASS" "Valid YAML structure"
                else
                    print_test_result "Lock file YAML validity" "FAIL" "Invalid YAML structure"
                fi
            else
                print_warning "Python3 with PyYAML not available - skipping YAML validation"
            fi

        else
            print_test_result "Lock file has content" "FAIL" "File is too small ($LOCK_FILE_SIZE lines)"
        fi
    else
        print_test_result "Generated rpms.lock.yaml file" "FAIL" "File not created"
    fi

else
    print_warning "Skipping full script execution - podman not available"
    print_test_result "Script execution test" "SKIP" "Podman not available"
fi

# Test 5: Validate script behavior with credentials (mock test)
echo
echo "Test 5: Validate repository parsing logic"
print_info "Testing repository ID extraction from input file"

# Extract repository IDs using the same logic as the script
EXTRACTED_REPOS=$(grep -E '^[[:space:]]*-[[:space:]]*repoid:' "$TEST_DIR/rpms.in.yaml" | \
    sed 's/^[[:space:]]*-[[:space:]]*repoid:[[:space:]]*//' | \
    tr -d '"'\''' | sort)

EXPECTED_REPOS_SORTED=$(printf '%s\n' "${EXPECTED_REPOS[@]}" | sort)

if [[ "$EXTRACTED_REPOS" == "$EXPECTED_REPOS_SORTED" ]]; then
    print_test_result "Repository ID extraction" "PASS" "Correctly extracted repository IDs"
    echo "  Extracted repositories:"
    while IFS= read -r repo; do
        echo "    - $repo"
    done <<< "$EXTRACTED_REPOS"
else
    print_test_result "Repository ID extraction" "FAIL" "Repository extraction mismatch"
    echo "  Expected: $EXPECTED_REPOS_SORTED"
    echo "  Extracted: $EXTRACTED_REPOS"
fi

# Test 6: Multi-arch detection
echo
echo "Test 6: Multi-arch detection"
if grep -q "^arches:" "$TEST_DIR/rpms.in.yaml"; then
    print_test_result "Multi-arch detection" "PASS" "Multi-arch configuration detected"
else
    print_test_result "Multi-arch detection" "FAIL" "Multi-arch configuration not detected"
fi

# Final results
echo
echo "=== Test Summary ==="
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
echo -e "Total tests: $((TESTS_PASSED + TESTS_FAILED))"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"

    if [[ -f "$TEST_DIR/rpms.lock.yaml" ]]; then
        echo
        print_info "Generated lock file summary:"
        echo "  Location: $TEST_DIR/rpms.lock.yaml"
        echo "  Size: $(wc -l < "$TEST_DIR/rpms.lock.yaml" | tr -d ' ') lines"
        cat "$TEST_DIR/rpms.lock.yaml" | sed 's/^/    /'
    fi

    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
