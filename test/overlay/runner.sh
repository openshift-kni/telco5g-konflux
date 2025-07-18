#!/bin/bash

# Test Runner Framework
# Usage: ./runner.sh <operator> <release> [--debug]
# Example: ./runner.sh lca 4.20 --debug

set -euo pipefail

SCRIPT_NAME=$(basename "$(readlink -f "${BASH_SOURCE[0]}")")

# Global counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Array to track failed test files
FAILED_TEST_FILES=()

# Debug flag
DEBUG_FLAG=""

print_log() {
    echo "[$SCRIPT_NAME] $1"
}

# Function to find and run tests for an operator/release
run_tests_for_operator() {
    local operator=$1
    local release=$2
    local test_path="$operator/$release"

    if [[ ! -d "$test_path" ]]; then
        print_log "Error: test directory not found: $test_path"
        return 0
    fi

    print_log "Running tests for operator: $operator, release: $release"

    # Find all test files
    mapfile -t test_files < <(find "$test_path" -name "*.test.sh" -type f 2>/dev/null | sort)

    if [[ ${#test_files[@]} -eq 0 ]]; then
        print_log "Error: no test files found in $test_path"
        return 0
    fi

    # Run tests
    for test_file in "${test_files[@]}"; do

        # Add DEBUG_FLAG if it is set
        if [[ -n "$DEBUG_FLAG" ]]; then
            test_cmd=("$test_file" "$DEBUG_FLAG")
        else
            test_cmd=("$test_file")
        fi

        # Run test
        print_log "Running test command: ${test_cmd[*]}"
        if "${test_cmd[@]}"; then
            print_log "Test SUCCESS: $test_file"
            PASSED_TESTS=$((PASSED_TESTS+1))
        else
            print_log "Test FAILURE: $test_file"
            FAILED_TESTS=$((FAILED_TESTS+1))
            FAILED_TEST_FILES+=("$test_file")
        fi
        TOTAL_TESTS=$((TOTAL_TESTS+1))
    done
}

# Function to display usage
usage() {
    echo "Usage: $0 <operator> <release> [--debug]"
    echo "       $0 --help             # Show this help"
    echo ""
    echo "Operators: lca, nrop, ocloud, talm"
    echo "Options:"
    echo "  --debug    Enable debug output for test operations"
    echo ""
    echo "Examples:"
    echo "  $0 lca 4.20"
    echo "  $0 lca 4.20 --debug"
}

# Main execution
main() {
    # Change to the directory where this script is located
    cd "$(dirname "${BASH_SOURCE[0]}")"

    # Parse arguments
    if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        usage
        exit 0
    fi

    # Check for debug flag
    local operator=""
    local release=""

    for arg in "$@"; do
        case $arg in
            --debug)
                DEBUG_FLAG="--debug"
                ;;
            *)
                if [[ -z "$operator" ]]; then
                    operator="$arg"
                elif [[ -z "$release" ]]; then
                    release="$arg"
                fi
                ;;
        esac
    done

    if [[ -z "$operator" ]] || [[ -z "$release" ]]; then
        echo "[${SCRIPT_NAME}] Error: both operator and release parameters are required"
        usage
        exit 1
    fi

    # Validate operator
    case $operator in
        lca|nrop|ocloud|talm)
            ;;
        *)
            echo "[${SCRIPT_NAME}] Error: Invalid operator '$operator'. Must be one of: lca, nrop, ocloud, talm"
            exit 1
            ;;
    esac

    if [[ -n "$DEBUG_FLAG" ]]; then
        print_log "Debug mode enabled for tests"
    fi

    run_tests_for_operator "$operator" "$release"

    # Print summary
    local global_status
    if [[ $FAILED_TESTS -gt 0 ]]; then
        global_status="FAILURE"
    else
        global_status="SUCCESS"
    fi
    print_log "Test summary for $operator/$release: Status=$global_status, Total=$TOTAL_TESTS, Passed=$PASSED_TESTS, Failed=$FAILED_TESTS"

    # List failed test files if any
    if [[ $FAILED_TESTS -gt 0 ]]; then
        print_log "Failed test files:"
        for failed_test in "${FAILED_TEST_FILES[@]}"; do
            print_log "- $failed_test"
        done
    fi

}

# Run main function with all arguments
main "$@"
