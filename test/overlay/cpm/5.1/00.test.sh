#!/bin/bash

# Source the common test library
# shellcheck source=test/overlay/common-test-lib.sh
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "${SCRIPT_DIR}"/../../common-test-lib.sh

# Initialize debug mode from command line argument
init_debug_mode "${1:-}"

# Run the CSV overlay test for cluster-power-manager operator
run_csv_overlay_test "cluster-power-manager" "cluster-power-manager CSV overlay test" "00.data"
