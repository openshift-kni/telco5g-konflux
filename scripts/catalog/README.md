# Catalog Comparison Script

This directory contains the `konflux-compare-catalog.sh` script for comparing generated catalogs with upstream FBC (File-Based Catalog) images.

## Overview

The `konflux-compare-catalog.sh` script validates that a locally generated catalog matches the upstream FBC image catalog exactly. This is crucial for ensuring deployment consistency and catching any discrepancies in the catalog generation process.

## Prerequisites

### Required Tools

- **Container Runtime**: Either `podman` or `docker` must be installed
- **Checksum Tool**: Either `sha256sum` (Linux) or `shasum` (macOS) must be available
- **Standard Unix Tools**: `find`, `diff`, `wc`, `mktemp`, `uname`

### Platform Support

The script automatically detects and supports:
- **Operating Systems**: Linux, macOS (Darwin), and other Unix-like systems
- **Architectures**: AMD64 (x86_64) and ARM64 (aarch64)
- **Container Runtimes**: Podman (preferred) or Docker (fallback)

## Usage

### Recommended: Using Make Target

```bash
make konflux-compare-catalog
```

### Alternative: Direct Script Usage

```bash
./konflux-compare-catalog.sh --catalog-path <path> --upstream-image <image>
```

### Make Target Variables

- `CATALOG_KONFLUX`: Path to the catalog file (default: `catalog.yaml`)
- `UPSTREAM_FBC_IMAGE`: Upstream FBC image to compare against
- `PACKAGE_NAME_KONFLUX`: Package name for image URL construction (default: `telco5g-konflux`)
- `QUAY_TENANT_NAME`: Quay tenant name (default: `telco-5g-tenant`)

### Script Parameters (Direct Usage)

**Required:**
- `--catalog-path PATH`: Path to the generated catalog file or directory
- `--upstream-image IMAGE`: Upstream FBC image to compare against

**Optional:**
- `--temp-dir DIR`: Custom temporary directory for extraction (default: auto-generated)
- `--no-cleanup`: Preserve temporary files after comparison (useful for debugging)
- `--verbose`: Enable detailed logging output
- `--help`: Display help information

## Testing Examples

### Example 1: Using Make Target (Recommended)
```bash
# Use default configuration
make konflux-compare-catalog

# Or with custom variables
make konflux-compare-catalog \
  CATALOG_KONFLUX=../../../.konflux/catalog/topology-aware-lifecycle-manager/catalog.yaml \
  UPSTREAM_FBC_IMAGE=quay.io/redhat-user-workloads/telco-5g-tenant/topology-aware-lifecycle-manager-fbc-4-20:latest
```

### Example 2: Direct Script Usage (Alternative)
```bash
# Basic test
./konflux-compare-catalog.sh \
  --catalog-path ../../../.konflux/catalog/topology-aware-lifecycle-manager/catalog.yaml \
  --upstream-image quay.io/redhat-user-workloads/telco-5g-tenant/topology-aware-lifecycle-manager-fbc-4-20:latest

# Verbose test with debug
./konflux-compare-catalog.sh \
  --catalog-path ../../../.konflux/catalog/topology-aware-lifecycle-manager/catalog.yaml \
  --upstream-image quay.io/redhat-user-workloads/telco-5g-tenant/topology-aware-lifecycle-manager-fbc-4-20:latest \
  --verbose \
  --no-cleanup
```

### Example 3: Package-Specific Configuration
```bash
# For cluster-group-upgrades-operator
make konflux-compare-catalog \
  PACKAGE_NAME_KONFLUX=cluster-group-upgrades-operator \
  CATALOG_KONFLUX=../../../.konflux/catalog/topology-aware-lifecycle-manager/catalog.yaml

# For lifecycle-agent
make konflux-compare-catalog \
  PACKAGE_NAME_KONFLUX=lifecycle-agent \
  CATALOG_KONFLUX=../../../.konflux/catalog/lifecycle-agent/catalog.yaml
```

## How It Works

### Platform Detection and Fallback

1. **Platform Detection**: Automatically detects current OS and architecture
2. **Primary Attempt**: Tries to pull the upstream image for the current platform
3. **Fallback**: If current platform fails, falls back to `linux/amd64`
4. **Consistency**: Uses the same platform for both image pulling and container execution

### Comparison Process

1. **Image Pulling**: Downloads the upstream FBC image with platform fallback
2. **Catalog Extraction**: Extracts the catalog from the image's `/configs` directory
3. **File Validation**: Ensures both catalogs exist and are readable
4. **Content Comparison**: Compares line counts and SHA256 checksums
5. **Detailed Diff**: Shows exact differences if catalogs don't match

## Expected Output

### Success Case
```
✅ VALIDATION PASSED: Generated catalog matches upstream FBC catalog exactly
   - Both catalogs have 311 lines
   - Both catalogs have identical checksum: 6915da63b021c5c19f1f1b47f9d8e08e31cd0d848909afce3ab3aa7200f2784e
```

### Failure Case
```
❌ VALIDATION FAILED: Generated catalog differs from upstream FBC catalog
   - Generated catalog: 311 lines, checksum: abc123...
   - Upstream catalog: 310 lines, checksum: def456...

Differences found:
==================
--- upstream-catalog.yaml
+++ generated-catalog.yaml
@@ -1,3 +1,4 @@
 line 1
 line 2
+new line
 line 3
```

## Troubleshooting

### Common Issues

#### 1. Image Pull Failures
**Problem**: Cannot pull upstream image
```
ERROR: Failed to pull upstream image: quay.io/...
ERROR: Tried platforms: darwin/arm64 and linux/amd64
```

**Solutions**:
- Verify image name and tag are correct
- Check network connectivity
- Ensure proper authentication for private registries
- Try manually pulling the image: `podman pull <image>`

#### 2. Container Runtime Issues
**Problem**: No container runtime available
```
ERROR: Neither podman nor docker is available. A container runtime is required.
```

**Solutions**:
- Install Podman: `brew install podman` (macOS) or package manager (Linux)
- Install Docker: Follow official Docker installation guide
- Verify installation: `podman --version` or `docker --version`

#### 3. Checksum Tool Missing
**Problem**: Cannot calculate checksums
```
ERROR: Neither sha256sum nor shasum command found. Cannot calculate checksums.
```

**Solutions**:
- Linux: Install `coreutils` package
- macOS: Should be pre-installed; try `xcode-select --install`
- Verify availability: `which sha256sum` or `which shasum`

#### 4. Catalog File Not Found
**Problem**: Catalog file missing
```
ERROR: Catalog path does not exist: /path/to/catalog.yaml
```

**Solutions**:
- Verify the catalog file path is correct
- Check if the catalog was generated successfully
- Use absolute paths if relative paths cause issues

### Debugging Tips

1. **Use Verbose Mode**: Always use `--verbose` for detailed execution logs
2. **Preserve Temp Files**: Use `--no-cleanup` to inspect extracted files
3. **Manual Inspection**: Check temporary directory contents when debugging
4. **Container Logs**: Run container commands manually to debug extraction issues

## Integration with Build Systems

### Makefile Integration
Use the provided make target for automated testing:

```makefile
.PHONY: test-catalog
test-catalog:
	$(MAKE) -C telco5g-konflux/scripts/catalog konflux-compare-catalog \
		CATALOG_KONFLUX=$(CATALOG_FILE) \
		UPSTREAM_FBC_IMAGE=$(UPSTREAM_FBC_IMAGE)
```

### Make Target Variables
The make target supports these configurable variables:

- `CATALOG_KONFLUX`: Path to the catalog file (default: `catalog.yaml`)
- `UPSTREAM_FBC_IMAGE`: Upstream FBC image to compare against (default: `quay.io/redhat-user-workloads/telco-5g-tenant/telco5g-konflux-fbc-4-20:latest`)
- `PACKAGE_NAME_KONFLUX`: Package name for constructing image URLs (default: `telco5g-konflux`)
- `QUAY_TENANT_NAME`: Quay tenant name (default: `telco-5g-tenant`)

### Direct Script Usage
For advanced use cases, the script can still be called directly:

```bash
./konflux-compare-catalog.sh --catalog-path <path> --upstream-image <image> [options]
```

## Security Considerations

- **SHA256 Checksums**: Uses SHA256 instead of MD5 for better security
- **Container Isolation**: Runs extraction in isolated containers
- **Temporary Files**: Automatically cleans up temporary files (unless `--no-cleanup` is used)
- **Platform Safety**: Validates platform compatibility before execution

## Contributing

When modifying the script:
1. Test on multiple platforms (Linux, macOS)
2. Test with both podman and docker
3. Verify error handling for edge cases
4. Update this README with any new features or requirements
