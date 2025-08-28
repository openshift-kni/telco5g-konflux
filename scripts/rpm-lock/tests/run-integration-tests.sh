#!/usr/bin/env bash

# Master test runner for RPM lock generation integration tests
# This script runs both RHEL 8 and RHEL 9 integration tests

set -uo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test results
RHEL8_RESULT=""
RHEL9_RESULT=""

# Helper function to print section headers
print_section() {
    echo
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}$(printf '=%.0s' $(seq 1 ${#1}))${NC}"
}

# Helper function to print info messages
print_info() {
    echo -e "${BLUE}INFO${NC}: $1"
}

# Helper function to print warnings
print_warning() {
    echo -e "${YELLOW}WARNING${NC}: $1"
}

print_section "RPM Lock Generation Integration Tests"
echo "This test suite validates the full end-to-end functionality of both RHEL 8 and RHEL 9 lock generation scripts."
echo

# Check prerequisites
print_info "Checking test prerequisites..."

if [[ ! -f "$SCRIPT_DIR/rhel8-test/test-rhel8-integration.sh" ]]; then
    echo -e "${RED}ERROR${NC}: RHEL 8 integration test not found"
    exit 1
fi

if [[ ! -f "$SCRIPT_DIR/rhel9-test/test-rhel9-integration.sh" ]]; then
    echo -e "${RED}ERROR${NC}: RHEL 9 integration test not found"
    exit 1
fi

if [[ ! -f "$SCRIPT_DIR/rhel8-test/rpms.in.yaml" ]]; then
    echo -e "${RED}ERROR${NC}: RHEL 8 test input file not found"
    exit 1
fi

if [[ ! -f "$SCRIPT_DIR/rhel9-test/rpms.in.yaml" ]]; then
    echo -e "${RED}ERROR${NC}: RHEL 9 test input file not found"
    exit 1
fi

print_info "All test files found"

# Parse command line arguments
RUN_RHEL8=true
RUN_RHEL9=true
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --rhel8-only)
            RUN_RHEL8=true
            RUN_RHEL9=false
            shift
            ;;
        --rhel9-only)
            RUN_RHEL8=false
            RUN_RHEL9=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Options:"
            echo "  --rhel8-only      Run only RHEL 8 integration tests"
            echo "  --rhel9-only      Run only RHEL 9 integration tests"
            echo "  --verbose, -v     Show verbose test results including info messages"
            echo "  --help, -h        Show this help message"
            echo
            echo "By default, both RHEL 8 and RHEL 9 tests are run with individual test results shown."
            echo "Use --verbose to also see info messages and warnings from the tests."
            exit 0
            ;;
        *)
            echo -e "${RED}ERROR${NC}: Unknown option $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to run a test and capture results
run_test() {
    local test_name="$1"
    local test_script="$2"

    print_section "Running $test_name Integration Test"

    # Capture output and show detailed results
    local output
    if output=$("$test_script" 2>&1); then
        echo -e "${GREEN}$test_name test PASSED${NC}"

        # Show individual test results (strip ANSI codes for pattern matching)
        if [[ "$VERBOSE" == "true" ]]; then
            # Show all test results with details
            echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep -E "^PASS:|^FAIL:|^INFO:|^WARNING:" | while IFS= read -r line; do
                if [[ $line == *"PASS:"* ]]; then
                    echo -e "  ${GREEN}$line${NC}"
                elif [[ $line == *"FAIL:"* ]]; then
                    echo -e "  ${RED}$line${NC}"
                elif [[ $line == *"INFO:"* ]]; then
                    echo -e "  ${BLUE}$line${NC}"
                elif [[ $line == *"WARNING:"* ]]; then
                    echo -e "  ${YELLOW}$line${NC}"
                fi
            done
        else
            # Show only pass/fail results
            echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep -E "^PASS:|^FAIL:" | while IFS= read -r line; do
                if [[ $line == *"PASS:"* ]]; then
                    echo -e "  ${GREEN}$line${NC}"
                else
                    echo -e "  ${RED}$line${NC}"
                fi
            done
        fi

        # Extract and show summary
        if echo "$output" | grep -q "=== Test Summary ==="; then
            echo "$output" | sed -n '/=== Test Summary ===/,/^$/p' | head -10
        fi

        # Show generated files info if available
        if echo "$output" | grep -q "Generated lock file summary:"; then
            echo
            echo "$output" | sed -n '/Generated lock file summary:/,/^$/p'
        fi

        return 0
    else
        echo -e "${RED}$test_name test FAILED${NC}"

        # Show individual test results for failed tests (strip ANSI codes for pattern matching)
        if [[ "$VERBOSE" == "true" ]]; then
            # Show all test results with details
            echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep -E "^PASS:|^FAIL:|^INFO:|^WARNING:" | while IFS= read -r line; do
                if [[ $line == *"PASS:"* ]]; then
                    echo -e "  ${GREEN}$line${NC}"
                elif [[ $line == *"FAIL:"* ]]; then
                    echo -e "  ${RED}$line${NC}"
                elif [[ $line == *"INFO:"* ]]; then
                    echo -e "  ${BLUE}$line${NC}"
                elif [[ $line == *"WARNING:"* ]]; then
                    echo -e "  ${YELLOW}$line${NC}"
                fi
            done
        else
            # Show only pass/fail results
            echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep -E "^PASS:|^FAIL:" | while IFS= read -r line; do
                if [[ $line == *"PASS:"* ]]; then
                    echo -e "  ${GREEN}$line${NC}"
                else
                    echo -e "  ${RED}$line${NC}"
                fi
            done
        fi

        # Show error summary
        if echo "$output" | grep -q "=== Test Summary ==="; then
            echo "$output" | sed -n '/=== Test Summary ===/,/^$/p' | head -10
        else
            # Show last few lines of output if no summary
            echo "$output" | tail -10
        fi

        return 1
    fi
}

# Run tests
TOTAL_TESTS=0
PASSED_TESTS=0

if [[ "$RUN_RHEL8" == "true" ]]; then
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if run_test "RHEL 8" "$SCRIPT_DIR/rhel8-test/test-rhel8-integration.sh"; then
        RHEL8_RESULT="PASSED"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        RHEL8_RESULT="FAILED"
    fi
fi

if [[ "$RUN_RHEL9" == "true" ]]; then
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if run_test "RHEL 9" "$SCRIPT_DIR/rhel9-test/test-rhel9-integration.sh"; then
        RHEL9_RESULT="PASSED"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        RHEL9_RESULT="FAILED"
    fi
fi

# Final summary
print_section "Final Test Results"

if [[ "$RUN_RHEL8" == "true" ]]; then
    if [[ "$RHEL8_RESULT" == "PASSED" ]]; then
        echo -e "RHEL 8 Integration Test: ${GREEN}PASSED${NC}"
    else
        echo -e "RHEL 8 Integration Test: ${RED}FAILED${NC}"
    fi
fi

if [[ "$RUN_RHEL9" == "true" ]]; then
    if [[ "$RHEL9_RESULT" == "PASSED" ]]; then
        echo -e "RHEL 9 Integration Test: ${GREEN}PASSED${NC}"
    else
        echo -e "RHEL 9 Integration Test: ${RED}FAILED${NC}"
    fi
fi

echo
echo -e "Tests passed: ${GREEN}$PASSED_TESTS${NC}/$TOTAL_TESTS"

if [[ $PASSED_TESTS -eq $TOTAL_TESTS ]]; then
    echo -e "${GREEN}All integration tests passed!${NC}"

    # Show generated files
    echo
    print_info "Generated test files:"
    if [[ "$RUN_RHEL8" == "true" && -f "$SCRIPT_DIR/rhel8-test/rpms.lock.yaml" ]]; then
        echo "  - RHEL 8: $SCRIPT_DIR/rhel8-test/rpms.lock.yaml"
        echo "  - RHEL 8: $SCRIPT_DIR/rhel8-test/redhat.repo"
    fi
    if [[ "$RUN_RHEL9" == "true" && -f "$SCRIPT_DIR/rhel9-test/rpms.lock.yaml" ]]; then
        echo "  - RHEL 9: $SCRIPT_DIR/rhel9-test/rpms.lock.yaml"
        echo "  - RHEL 9: $SCRIPT_DIR/rhel9-test/redhat.repo"
    fi

    exit 0
else
    echo -e "${RED}Some integration tests failed.${NC}"
    exit 1
fi
