# RPM Lock Generation Tests

This directory contains comprehensive tests for the RPM lock generation scripts.

## Test Structure

```
tests/
├── run-integration-tests.sh       # Master test runner
├── rhel8-test/
│   ├── test-rhel8-integration.sh   # RHEL 8 integration test
│   └── rpms.in.yaml               # RHEL 8 test input file
├── rhel9-test/
│   ├── test-rhel9-integration.sh   # RHEL 9 integration test
│   └── rpms.in.yaml               # RHEL 9 test input file
└── README.md                      # This file
```

## Running Tests

### Quick Start

Run all tests (UBI mode):
```bash
./run-integration-tests.sh
```

Run with verbose output:
```bash
./run-integration-tests.sh --verbose
```

Run only RHEL 9 tests:
```bash
./run-integration-tests.sh --rhel9-only
```

Run only RHEL 8 tests:
```bash
./run-integration-tests.sh --rhel8-only
```

### Using Makefile Targets

Run integration tests (UBI mode):
```bash
make test-integration
```

Run integration tests with RHSM credentials:
```bash
make test-integration-rhsm RHEL8_ACTIVATION_KEY=your-key RHEL8_ORG_ID=your-org RHEL9_ACTIVATION_KEY=your-key RHEL9_ORG_ID=your-org
```

Run individual tests:
```bash
make test-rhel8-only        # RHEL 8 only (UBI mode)
make test-rhel9-only        # RHEL 9 only (UBI mode)
make test-rhel8-rhsm        # RHEL 8 with RHSM credentials
make test-rhel9-rhsm        # RHEL 9 with RHSM credentials
```

### Individual Tests

Run RHEL 9 integration test:
```bash
cd rhel9-test && ./test-rhel9-integration.sh
```

Run RHEL 8 integration test:
```bash
cd rhel8-test && ./test-rhel8-integration.sh
```

## Test Types

### Integration Tests

Full end-to-end tests that validate:
- Script execution with and without RHSM credentials
- Generated file validation (`redhat.repo`, `rpms.lock.yaml`)
- Package inclusion in lock files
- YAML structure validation
- Repository configuration parsing

## Test Input Files

### RHEL 8 Test Input (`rhel8-test/rpms.in.yaml`)
- Configured for RHEL 8 repositories
- Includes standard packages: bash, coreutils, glibc, systemd
- Multi-architecture support (x86_64, aarch64)

### RHEL 9 Test Input (`rhel9-test/rpms.in.yaml`)
- Configured for RHEL 9 repositories
- Same package set as RHEL 8 for consistency
- Multi-architecture support (x86_64, aarch64)

## Prerequisites

### Required Tools
- `bash` (version 4.0+)
- `podman` (for full integration tests)
- `grep`, `sed`, `awk` (standard UNIX tools)

### Optional Tools
- `python3` with `yaml` module (for YAML validation)
- Red Hat subscription credentials (for full RHSM testing)

## Test Behavior

The integration tests automatically detect the execution mode based on environment variables:

### UBI Mode (Default)
When no valid RHSM credentials are provided:
- Uses public UBI repositories (`registry.access.redhat.com`)
- No subscription registration required
- Tests UBI repository configuration in generated files
- Validates that scripts work without subscriptions
- Expected behavior: Scripts should complete successfully using UBI repos

### RHSM Mode (With Credentials)
When valid RHSM credentials are provided:
- Uses subscription-based repositories (`registry.redhat.io`)
- Performs RHSM registration within containers
- Tests repository parsing from `rpms.in.yaml`
- Validates certificate path updates
- Expected behavior: Scripts use repositories specified in input files

### Setting RHSM Credentials
For RHSM mode testing:
```bash
export RHEL8_ACTIVATION_KEY="your-activation-key"
export RHEL8_ORG_ID="your-organization-id"
export RHEL9_ACTIVATION_KEY="your-activation-key"
export RHEL9_ORG_ID="your-organization-id"
```

**Note**: Placeholder values like "placeholder" or "1234567890" are treated as invalid and trigger UBI mode.

## Expected Outputs

### Successful Test Run
- All prerequisite checks pass
- Repository extraction works correctly
- Multi-arch detection functions
- Generated files contain expected content
- YAML structure is valid

### Generated Files
After successful integration tests:
- `rhel8-test/redhat.repo` - Repository configuration
- `rhel8-test/rpms.lock.yaml` - Package lock file
- `rhel9-test/redhat.repo` - Repository configuration
- `rhel9-test/rpms.lock.yaml` - Package lock file

## Troubleshooting

### Container Pull Failures
If podman cannot pull images:
1. Check network connectivity
2. Verify container registry access
3. For private registries, ensure `podman login` was successful

### Script Execution Failures
Common issues:
1. **Path not found**: Ensure scripts are executable (`chmod +x`)
2. **Permission denied**: Check file permissions
3. **Container runtime errors**: Verify podman installation

### Test Failures
1. Check prerequisite tools are installed
2. Verify input files exist and are readable
3. Review test output for specific error messages
4. Run with `--verbose` for detailed output

## Cross-Platform Support

Tests are designed to work on both macOS and Linux:
- Automatic OS detection for `sed` command compatibility
- Portable shell scripting practices
- No platform-specific dependencies

## Contributing

When adding new tests:
1. Follow existing naming conventions
2. Include both positive and negative test cases
3. Add appropriate error handling
4. Update this README with new test descriptions
