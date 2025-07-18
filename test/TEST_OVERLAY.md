
# Test Overlay Framework Documentation

This document explains the test code structure and usage for the Telco5G Konflux overlay testing framework.

## Test Code Structure

The test framework is organized hierarchically to support multiple operators, releases, and individual test scenarios. See this layout, highlighting a 4.20 release:

```markdown:test/TEST_OVERLAY.md
<code_block_to_apply_changes_from>
test/overlay/
├── runner.sh                     # Main test runner script
├── lca/                          # Lifecycle Agent operator tests
│   └── 4.20/                     # Release-specific tests
│       ├── 00.test.sh            # Individual test script
│       └── 00.data/              # Test data directory
│           ├── expected/         # Expected output files
│           ├── *.in.yaml         # Input files
│          
├── nrop/                         # NUMA Resources operator tests
│   └── 4.20/
│       ├── 00.test.sh
│       └── 00.data/
├── ocloud/                       # O-Cloud manager operator tests
│   └── 4.20/
│       ├── 00.test.sh
│       └── 00.data/
└── talm/                         # Topology Aware Lifecycle Manager tests
    └── 4.20/
        ├── 00.test.sh
        └── 00.data/
```

### Directory Structure Explained

- **`test/overlay/`**: Root directory for all overlay tests
- **`<operator>/`**: Operator-specific test directories (`lca`, `nrop`, `ocloud`, `talm`)
- **`<release>/`**: Release-specific test directories (e.g., `4.20`, `4.21`)
- **`XX.test.sh`**: Individual test scripts (e.g., `00.test.sh`, `01.test.sh`)
- **`XX.data/`**: Test data directory containing input files and expected outputs

### Test Script Naming Convention

Test scripts follow the pattern `XX.test.sh` where `XX` is a zero-padded number:
- `00.test.sh` – Primary or basic test scenario
- `01.test.sh`  Additional test scenario (if needed)
- `02.test.sh` - Further test scenarios, etc.

### Test Data Organization

Each test has a corresponding data directory:
- **Input files**: `map_images.in.yaml`, `pin_images.in.yaml`, `release.in.yaml`, `X.clusterserviceversion.in.yaml`, 
- **Expected outputs**: `expected/` directory containing expected result files

## Test Framework Components

### 1. Main Test Runner (`runner.sh`)

The central test execution script that:
- Finds and executes all `*.test.sh` files in a given operator/release directory
- Provides debug output capabilities
- Reports test results and statistics
- Handles test failures gracefully

### 2. Individual Test Scripts (`XX.test.sh`)

Each test script:
- Sets up temporary directories for test execution
- Validates input files exist
- Executes the overlay transformation scripts
- Compares actual output with expected results
- Cleans up temporary files (unless debug mode is enabled)
- Supports debug mode for troubleshooting and manually diff the files involved

### 3. Overlay Scripts Integration

Tests integrate with the main overlay scripts located in `scripts/bundle/`:
- `konflux-bundle-overlay.sh` - Main overlay script
- Tests validate the overlay process produces expected CSV modifications

## Makefile Integration

The test framework integrates with the project Makefile, providing multiple execution options:

### Available Test Targets

- `test-overlay` - Run all tests for all operators
- `test-overlay-lca` - Run tests for Lifecycle Agent operator
- `test-overlay-nrop` - Run tests for NUMA Resources operator  
- `test-overlay-ocloud` - Run tests for O-Cloud manager operator
- `test-overlay-talm` - Run tests for TALM operator

### Makefile Parameters

- **`RELEASE`**: Specify a particular release (e.g., `4.20`)
- **`TEST`**: Specify a particular test file (e.g., `00.test.sh`)
- **`DEBUG`**: Enable debug output (`DEBUG=1`)

## Usage Examples

Notice that depending on the number of tests run, the logs might be excessive.
See [Debug Tip #0](#debug-tip-0) for advice on minimizing log output when running many tests.


### Basic Usage - Run All Tests

```bash
# Run all tests for all operators and releases
make test-overlay

# Run all tests for a specific operator
make test-overlay-lca
make test-overlay-nrop
make test-overlay-ocloud
make test-overlay-talm
```

### Release-Specific Testing

```bash
# Run all tests for a specific operator and release
make test-overlay-lca RELEASE=4.20
make test-overlay-nrop RELEASE=4.20
make test-overlay-ocloud RELEASE=4.20
make test-overlay-talm RELEASE=4.20
```

### Specific Test Execution

```bash
# Run a specific test for a specific operator and release
make test-overlay-lca RELEASE=4.20 TEST=00.test.sh
make test-overlay-nrop RELEASE=4.20 TEST=00.test.sh
make test-overlay-ocloud RELEASE=4.20 TEST=00.test.sh
make test-overlay-talm RELEASE=4.20 TEST=00.test.sh

# Run a specific test across ALL releases for an operator
make test-overlay-lca TEST=00.test.sh
make test-overlay-nrop TEST=00.test.sh
make test-overlay-ocloud TEST=00.test.sh
make test-overlay-talm TEST=00.test.sh

# Run a specific test across ALL operators and releases
make test-overlay TEST=00.test.sh
```

### Debug Mode Testing

Debug mode preserves temporary files and shows detailed output.
When a test is run with DEBUG=1, the logs will show a tmp file indicating that file(s) involved in the test can be checked there for troubleshooting.

```
[talm/4.21/00.test.sh] [DEBUG] Debug mode enabled for test operations 
[talm/4.21/00.test.sh] [DEBUG] Temporary files will be preserved in: /tmp/tmp.N5Q2jTR8E5
```

Examples:

```bash
# Run with debug output for a specific test
make test-overlay-lca RELEASE=4.20 TEST=00.test.sh DEBUG=1

# Run with debug output for a complete release
make test-overlay-lca RELEASE=4.20 DEBUG=1

# Run with debug output for all tests
make test-overlay DEBUG=1
```

### Cross-Release Testing

These examples show how a specific test can be run across all releases

```bash
# Test a specific scenario across all LCA releases
make test-overlay-lca TEST=00.test.sh

# Test a specific scenario across all OCLOUD releases
make test-overlay-ocloud TEST=00.test.sh

# Test a specific scenario across all NROP releases
make test-overlay-nrop TEST=00.test.sh

# Test a specific scenario across all TALM releases
make test-overlay-talm TEST=00.test.sh
```

### Advanced Combination Examples

These examples show misc combos

```bash
# Test all scenarios for OCLOUD 4.20 with debug output
make test-overlay-ocloud RELEASE=4.20 DEBUG=1

# Test a specific scenario across all operators and releases
make test-overlay TEST=00.test.sh

# Quick validation of a specific operator/release/test combination
make test-overlay-lca RELEASE=4.20 TEST=00.test.sh DEBUG=1
make test-overlay-talm RELEASE=4.20 TEST=00.test.sh DEBUG=1

# Cross-operator testing with debug for troubleshooting
make test-overlay-lca TEST=00.test.sh DEBUG=1
make test-overlay-nrop TEST=00.test.sh DEBUG=1
make test-overlay-ocloud TEST=00.test.sh DEBUG=1
make test-overlay-talm TEST=00.test.sh DEBUG=1
```

## Direct Script Usage

You can also run the test framework directly without make:

```bash
# Navigate to test directory
cd test/overlay

# Run tests for specific operator and release
./runner.sh lca 4.20
./runner.sh ocloud 4.20 --debug

# Run individual test script directly
./lca/4.20/00.test.sh
./lca/4.20/00.test.sh --debug
```

## Test Behavior

### Success Criteria

A test passes when:
- The overlay script executes successfully
- The actual output matches the expected output 
- No errors occur during execution

### Failure Handling

Tests fail when:
- The overlay script fails to execute
- Output differs from expected results
- Any validation step encounters an error

### Cross-Release Testing Behavior

When using `TEST=XX.test.sh` without `RELEASE`:
- The framework searches all available releases for the specified operator
- Runs the test for each release where the test file exists
- Shows warnings for releases missing the test file
- Fails if the test doesn't exist in ANY release
- Stops execution if any test fails

### Debug Mode Benefits

When `DEBUG=1` is specified:
- Temporary files are preserved for inspection
- Detailed command output is shown
- Test execution steps are logged
- Easier troubleshooting of test failures

## Adding New Tests

### Creating a New Test Scenario

1. **Copy existing test structure**:
   ```bash
   cp test/overlay/lca/4.20/00.test.sh test/overlay/lca/4.20/01.test.sh
   cp -r test/overlay/lca/4.20/00.data test/overlay/lca/4.20/01.data
   ```

2. **Update test script references**:
   ```bash
   sed -i 's/00\.data/01.data/g' test/overlay/lca/4.20/01.test.sh
   ```
   And modify the input files and expected file accordingly.

3. **Test the new scenario**:
   ```bash
   make test-overlay-lca RELEASE=4.20 TEST=01.test.sh DEBUG=1
   ```

### Adding a New Operator to test

1. **Create operator directory structure**:
   ```bash
   mkdir -p test/overlay/newoperator/4.20/{00.data/expected}
   ```

2. **Create test script** following the existing pattern

3. **Add to Makefile** - create new test target following existing pattern

4. **Test the new operator**:
   ```bash
   make test-overlay-newoperator RELEASE=4.20 DEBUG=1
   ```

## Best Practices

1. **Consistent Naming**: Follow the `XX.test.sh` and `XX.data/` naming pattern
2. **Comprehensive Coverage**: Test both success and failure scenarios
3. **Use Debug Mode**: Always test with `DEBUG=1` during development
4. **Cross-Release Testing**: Use `TEST=XX.test.sh` to validate across releases
5. **Clear Test Data**: Use descriptive file names and maintain clean test data
6. **Expected Results**: Keep expected output files up to date
7. **Incremental Testing**: Test specific changes before running full test suite

## Troubleshooting

### Common Issues

1. **Test file not found**: Ensure test script exists and follows naming convention
2. **Permission errors**: Ensure test scripts are executable (`chmod +x *.test.sh`)
3. **Missing dependencies**: Ensure `yq` and other required tools are installed
4. **Path issues**: Run tests from the repository root or use Makefile targets

### Debug Tips

<a id="debug-tip-0"></a>

0. **Minimize log output with grep**: When running all tests for an operator or all operators, logs can be excessive. Pipe the output through `grep runner.sh` to see a concise summary from the runner script and quickly check overall status.

Example: run all 4.20 tests for all operators

```bash
$ make test-overlay RELEASE=4.20 | grep 'runner.sh'
[runner.sh] Running tests for operator: lca, release: 4.20
[runner.sh] Running test command: lca/4.20/00.test.sh
[runner.sh] Test SUCCESS: lca/4.20/00.test.sh
[runner.sh] Test summary for lca/4.20: Status=SUCCESS, Total=1, Passed=1, Failed=0
[runner.sh] Running tests for operator: nrop, release: 4.20
[runner.sh] Running test command: nrop/4.20/00.test.sh
[runner.sh] Test SUCCESS: nrop/4.20/00.test.sh
[runner.sh] Test summary for nrop/4.20: Status=SUCCESS, Total=1, Passed=1, Failed=0
[runner.sh] Running tests for operator: ocloud, release: 4.20
[runner.sh] Running test command: ocloud/4.20/00.test.sh
[runner.sh] Test SUCCESS: ocloud/4.20/00.test.sh
[runner.sh] Test summary for ocloud/4.20: Status=SUCCESS, Total=1, Passed=1, Failed=0
[runner.sh] Running tests for operator: talm, release: 4.20
[runner.sh] Running test command: talm/4.20/00.test.sh
[runner.sh] Test SUCCESS: talm/4.20/00.test.sh
[runner.sh] Running test command: talm/4.20/01.test.sh
[runner.sh] Test SUCCESS: talm/4.20/01.test.sh
[runner.sh] Test summary for talm/4.20: Status=SUCCESS, Total=2, Passed=2, Failed=0
```

1. **Use Debug Mode**: `DEBUG=1` preserves temporary files and shows detailed output
2. **Run Individual Tests**: Use specific `RELEASE` and `TEST` parameters for focused debugging
3. **Check Input Files**: Verify all input files exist and have correct content
4. **Verify Scripts**: Ensure overlay scripts are accessible and executable
5. **Compare Outputs**: Manually compare actual vs expected output files when tests fail
6. **Incremental Approach**: Test one operator/release/test combination at a time when troubleshooting

### Example Debug Workflow

```bash
# Start with specific test in debug mode
make test-overlay-ocloud RELEASE=4.20 TEST=00.test.sh DEBUG=1

# If that passes, test across releases
make test-overlay-ocloud TEST=00.test.sh DEBUG=1

# Then test all scenarios for that release
make test-overlay-ocloud RELEASE=4.20 DEBUG=1

# Test all tests across all releases
make test-overlay-ocloud

# Finally, test all 
make test-overlay
```