# Shared Test Framework for CSV Overlay Tests

## Overview

This directory uses a test framework that eliminates code duplication across multiple `XY.test.sh` 

## Architecture

### 1. Common Test Library (`common-test-lib.sh`)

**Location**: `test/overlay/common-test-lib.sh`

**Purpose**: Contains all shared functionality for CSV overlay testing, including:
- Directory and logging setup
- Debug mode handling
- File path configuration
- Input file validation
- Cleanup management
- Overlay script execution
- Diff comparison with variant support

### 2. Individual Test Files

```bash
#!/bin/bash

# Source the common test library
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"/../../common-test-lib.sh

# Initialize debug mode from command line argument
init_debug_mode "${1:-}"

# Run the CSV overlay test for <operator-name>
run_csv_overlay_test "<csv-prefix>" "<description>" "<data-dir>"
```

## Usage

### Basic Test Execution
```bash
./00.test.sh              # Run test normally
./00.test.sh --debug      # Run test with debug output
```

### Main Function Parameters

```bash
run_csv_overlay_test "<csv-prefix>" "<description>" "<data-dir>"
```

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `csv-prefix` | Yes | - | Operator CSV filename prefix (e.g., `lifecycle-agent`) |
| `description` | Yes | `- | A test description |
| `data-dir` | Yes | `00.data` | Data directory (e.g., `00.data` for some tests) |

### Examples

```bash
# Test using 01.data directory
run_csv_overlay_test "cluster-group-upgrades-operator" "standard" "01.data"
```

## Benefits

### Maintainability
- **Single source of truth** for test logic
- **Consistent behavior** across all tests
- **Easy updates** - modify shared library once instead of 6+ files
- **Better error handling** and logging

### Functionality
- **Preserved all existing functionality**
- **Debug mode support** maintained
- **Flexible data directory** support
- **yq syntax variants** handled gracefully

## File Structure

```
test/overlay/
├── common-test-lib.sh              # Shared test framework
├── lca/4.20/00.test.sh
├── nrop/4.20/00.test.sh
├── ocloud/4.20/00.test.sh
├── talm/4.20/00.test.sh
├── talm/4.20/01.test.sh
└── talm/4.21/00.test.sh
```

## Future Considerations

### Adding New Tests
1. Create test data directory (`XX.data/`)
2. Create minimal test script calling `run_csv_overlay_test`
3. No duplicated code needed

### Modifying Test Logic
- Modify only `common-test-lib.sh`
- All tests automatically inherit changes
- No need to update multiple files

### Custom Test Variants
The framework is extensible. Add new functions to `common-test-lib.sh` for specialized test cases while maintaining the shared foundation.
