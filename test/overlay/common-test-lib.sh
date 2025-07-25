#!/bin/bash

# Common test library for CSV overlay tests
# This file should be sourced by individual test scripts

set -euo pipefail

# Common variables setup
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[1]}" )" &> /dev/null && pwd )
RELEASE_DIR=$(basename "$SCRIPT_DIR")
OPERATOR_DIR=$(basename "$(dirname "$SCRIPT_DIR")")
SCRIPT_NAME=$(basename "${BASH_SOURCE[1]}")
SCRIPT_LOG="$OPERATOR_DIR/$RELEASE_DIR/$SCRIPT_NAME"

# Common logging functions
print_log() {
    echo "[$SCRIPT_LOG] $1"
}

print_log_debug() {
    if [[ "$DEBUG_ENABLED" == true ]]; then
        print_log "[DEBUG] $1"
    fi
}

# Initialize debug mode
init_debug_mode() {
    DEBUG_ENABLED=false
    if [[ "${1:-}" == "--debug" ]]; then
        DEBUG_ENABLED=true
        print_log_debug "Debug mode enabled for test operations"
    fi
}

# Setup test description
setup_test_description() {
    local test_description="$1"
    print_log "Test description: $test_description"
    print_log "Test path: $SCRIPT_DIR/$SCRIPT_NAME"
}

# Setup file paths for a given CSV prefix and data directory
setup_file_paths() {
    local csv_prefix="$1"
    local data_dir="$2"

    CSV_INPUT_FILE="$SCRIPT_DIR/$data_dir/${csv_prefix}.clusterserviceversion.in.yaml"
    MAP_INPUT_FILE="$SCRIPT_DIR/$data_dir/map_images.in.yaml"
    PIN_INPUT_FILE="$SCRIPT_DIR/$data_dir/pin_images.in.yaml"
    RELEASE_INPUT_FILE="$SCRIPT_DIR/$data_dir/release.in.yaml"
    CSV_EXPECTED_FILE="$SCRIPT_DIR/$data_dir/expected/${csv_prefix}.clusterserviceversion.yaml"

    # Setup temporary directory and actual output file
    TEMP_DIR=$(mktemp -d)
    CSV_ACTUAL_FILE="$TEMP_DIR/${csv_prefix}.clusterserviceversion.yaml"
    cp "$CSV_INPUT_FILE" "$CSV_ACTUAL_FILE"
}

# Validate all required files exist
validate_input_files() {
    local files=(
        "$CSV_INPUT_FILE:CSV input file"
        "$MAP_INPUT_FILE:Map images input file"
        "$PIN_INPUT_FILE:Pin images input file"
        "$RELEASE_INPUT_FILE:Release input file"
        "$CSV_EXPECTED_FILE:Expected file"
    )

    for file_info in "${files[@]}"; do
        local file_path="${file_info%%:*}"
        local file_desc="${file_info##*:}"
        if [[ ! -f "$file_path" ]]; then
            print_log "Error: $file_desc not found: $file_path"
            exit 1
        fi
    done
}

# Setup cleanup function and trap
setup_cleanup() {
    cleanup() {
        # shellcheck disable=SC2317
        rm -rf "$TEMP_DIR"
    }

    # Only set cleanup trap if debug is NOT enabled
    if [[ "$DEBUG_ENABLED" != true ]]; then
        trap cleanup EXIT
    else
        print_log_debug "Temporary files will be preserved in: $TEMP_DIR"
    fi
}

# Validate overlay script exists
validate_overlay_script() {
    OVERLAY_DIR="$SCRIPT_DIR/../../../../scripts/bundle"
    OVERLAY_SCRIPT="$OVERLAY_DIR/konflux-bundle-overlay.sh"

    if [[ ! -f "$OVERLAY_SCRIPT" ]]; then
        print_log "Error: overlay script not found: $OVERLAY_SCRIPT"
        exit 1
    fi
}

# Execute overlay command
execute_overlay() {
    local overlay_cmd=(
        "$OVERLAY_SCRIPT"
        --set-pinning-file "$PIN_INPUT_FILE"
        --set-mapping-file "$MAP_INPUT_FILE"
        --set-mapping-production
        --set-release-file "$RELEASE_INPUT_FILE"
        --set-csv-file "$CSV_ACTUAL_FILE"
    )

    print_log "Running overlay command: ${overlay_cmd[*]}"
    if ! "${overlay_cmd[@]}"; then
        print_log "FAILURE: Overlay command failed"
        exit 1
    fi
}

# Run diff comparison with optional yq syntax variant
run_diff_comparison() {

    local yq_del_expr="del(.metadata.annotations.createdAt)"

    # Use portable diff options and preprocess files to remove trailing spaces
    # This approach works on both GNU diff (Linux) and BSD diff (macOS)
    local diff_cmd="diff --unified=0 \
        --ignore-space-change \
        --ignore-blank-lines \
        --label=\"actual CSV file: $CSV_ACTUAL_FILE\" <(yq e '$yq_del_expr' \"$CSV_ACTUAL_FILE\" | sed -E '/^[[:space:]]*#.*$/d' | sed -E 's/[[:space:]]+$//') \
        --label=\"expected CSV file: $CSV_EXPECTED_FILE\" <(yq e '$yq_del_expr' \"$CSV_EXPECTED_FILE\" | sed -E '/^[[:space:]]*#.*$/d' | sed -E 's/[[:space:]]+$//')"

    print_log "Running diff command: $diff_cmd"

    if ! eval "$diff_cmd"; then
        print_log "Test output: FAILURE. CSV files differ, see diff output above"
        exit 1
    fi
    print_log "Test output: SUCCESS. CSV files match"
}

# Main test execution function
run_csv_overlay_test() {
    local csv_prefix="$1"
    local test_description="$2"
    local data_dir="$3"

    setup_test_description "$test_description"
    setup_file_paths "$csv_prefix" "$data_dir"
    validate_input_files
    setup_cleanup
    validate_overlay_script
    execute_overlay
    run_diff_comparison
    exit 0
}
