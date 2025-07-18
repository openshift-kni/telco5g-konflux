# Using telco5g-konflux as a Submodule

This document explains how to integrate the `telco5g-konflux` project as a submodule in your repository to reuse the linting targets, catalog management scripts, and utility scripts.

## Overview

The `telco5g-konflux` project provides:
- **Linting targets**: Standardized linting for YAML files and shell scripts
- **Download scripts**: Parameterizable scripts for downloading common tools (yq, opm, jq, operator-sdk)
- **Catalog management**: Konflux-specific targets for catalog template validation and generation
- **Python virtual environment**: Isolated Python dependencies for linting tools

## Adding as a Submodule

1. **Add the submodule to your repository:**
   ```bash
   git submodule add https://github.com/openshift-kni/telco5g-konflux.git telco5g-konflux
   git submodule update --init --recursive
   ```

2. **Include the Makefile in your root Makefile:**
   ```makefile
   # Include linting targets from submodule
   include scripts/Makefile
   ```

## Available Targets

### Linting Targets
- `lint`: Run all linters (yamllint, shellcheck, bashate)
- `yamllint`: Run YAML linting using yamllint
- `shellcheck`: Run shell script linting using shellcheck-py (errors only)
- `bashate`: Run bash style linting using bashate (ignores E006 line length)
- `venv`: Create Python virtual environment with linting dependencies
- `clean`: Remove virtual environment and generated artifacts

### Catalog Management Targets
- `update-catalog-template`: Update catalog template using bundle builds
- `validate-production-images`: Validate related images for production
- `konflux-validate-catalog-template-bundle`: Validate the last bundle entry on the catalog template file
- `konflux-validate-catalog`: Validate the current catalog file using opm
- `konflux-generate-catalog`: Generate a quay.io catalog from template
- `konflux-generate-catalog-production`: Generate a registry.redhat.io catalog with production overlays

### Utility Targets
- `help`: Display available targets and descriptions

## Linting Configuration

### Python Dependencies
The submodule includes a `requirements.txt` file with pinned versions:
```
bashate==2.1.0
shellcheck-py==0.10.0.1
yamllint==1.35.1
```

### YAML Linting Configuration
Place a `.yamllint.yaml` file in your repository root to configure yamllint:
```yaml
extends: default
rules:
  line-length:
    max: 120
  document-start: disable
  truthy: disable
```

## Download Scripts

The submodule provides parameterizable download scripts for common tools with automatic dependency management:

### Available Scripts
- `scripts/download/download-yq.sh`: Download and install yq (YAML processor)
- `scripts/download/download-opm.sh`: Download and install opm (Operator Package Manager)
- `scripts/download/download-jq.sh`: Download and install jq (JSON processor)
- `scripts/download/download-operator-sdk.sh`: Download and install operator-sdk from OpenShift mirror

### Download Makefile

The `scripts/download/Makefile` provides convenient targets for downloading tools:

```bash
# Download individual tools
make -f scripts/download/Makefile download-yq
make -f scripts/download/Makefile download-opm
make -f scripts/download/Makefile download-jq
make -f scripts/download/Makefile download-operator-sdk

# Download all tools
make -f scripts/download/Makefile download-all

# Clean downloaded tools
make -f scripts/download/Makefile clean
```

### Catalog Makefile

The `scripts/catalog/Makefile` provides targets for catalog management with automatic tool dependency resolution:

```bash
# Run catalog targets (tools are automatically downloaded if needed)
make -f scripts/catalog/Makefile konflux-validate-catalog-template-bundle
make -f scripts/catalog/Makefile konflux-validate-catalog
make -f scripts/catalog/Makefile konflux-generate-catalog
make -f scripts/catalog/Makefile konflux-generate-catalog-production
```

### Script Usage

#### Basic Usage (default versions and install directory)
```bash
./scripts/download/download-yq.sh           # Install yq v4.45.4 to scripts/bin
./scripts/download/download-opm.sh          # Install opm v1.52.0 to scripts/bin
./scripts/download/download-jq.sh           # Install jq 1.7.1 to scripts/bin
./scripts/download/download-operator-sdk.sh # Install operator-sdk for OpenShift 4.12 to scripts/bin
```

#### Custom Versions
```bash
./scripts/download/download-yq.sh v4.44.2            # Install specific yq version
./scripts/download/download-opm.sh v1.51.0           # Install specific opm version
./scripts/download/download-jq.sh 1.6                # Install specific jq version
./scripts/download/download-operator-sdk.sh v1.38.0  # Install operator-sdk for OpenShift 4.13 (latest)
```

#### Custom Install Directory
```bash
# Using command line option
./scripts/download/download-yq.sh -d /usr/local/bin v4.44.2
./scripts/download/download-opm.sh --install-dir /opt/tools v1.51.0
./scripts/download/download-operator-sdk.sh -d /opt/tools v1.38.0

# Using environment variable
INSTALL_DIR=/opt/bin ./scripts/download/download-yq.sh v4.44.2
INSTALL_DIR=/usr/local/bin ./scripts/download/download-opm.sh
INSTALL_DIR=/opt/tools ./scripts/download/download-operator-sdk.sh v1.38.0
```

#### Help Information
```bash
./scripts/download/download-yq.sh --help           # Show detailed usage information
./scripts/download/download-opm.sh --help          # Show detailed usage information
./scripts/download/download-jq.sh --help           # Show detailed usage information
./scripts/download/download-operator-sdk.sh --help # Show detailed usage information
```

## Catalog Management

The submodule includes scripts for managing operator catalogs with Konflux:

### Catalog Variables

You can customize catalog operations using these variables:

```makefile
# File paths
CATALOG_TEMPLATE_FILE ?= .konflux/catalog/catalog-template.in.yaml
BUNDLE_BUILDS_FILE ?= .konflux/catalog/bundle.builds.in.yaml
CATALOG_FILE ?= catalog.yaml

# Konflux-specific variables
CATALOG_TEMPLATE_KONFLUX ?= $(CATALOG_TEMPLATE_FILE)
CATALOG_KONFLUX ?= $(CATALOG_FILE)
PACKAGE_NAME_KONFLUX ?= telco5g-konflux

# Bundle image configuration - can be overridden for different operators
QUAY_TENANT_NAME ?= telco-5g-tenant
BUNDLE_NAME_SUFFIX ?= operator-bundle-4-20
PRODUCTION_NAMESPACE ?= openshift4
PRODUCTION_BUNDLE_NAME ?= operator-bundle

# Constructed bundle image names
QUAY_BUNDLE_IMAGE ?= quay.io/redhat-user-workloads/$(QUAY_TENANT_NAME)/$(PACKAGE_NAME_KONFLUX)-$(BUNDLE_NAME_SUFFIX)
PRODUCTION_BUNDLE_IMAGE ?= registry.redhat.io/$(PRODUCTION_NAMESPACE)/$(PACKAGE_NAME_KONFLUX)-$(PRODUCTION_BUNDLE_NAME)

# Tool versions
OPENSHIFT_VERSION ?= 4.12
```

### Catalog Operations

```bash
# Validate catalog template bundle
make -f scripts/catalog/Makefile konflux-validate-catalog-template-bundle

# Generate catalogs
make -f scripts/catalog/Makefile konflux-generate-catalog                  # quay.io catalog
make -f scripts/catalog/Makefile konflux-generate-catalog-production       # registry.redhat.io catalog

# Validate catalog
make -f scripts/catalog/Makefile konflux-validate-catalog

# Custom package name
make -f scripts/catalog/Makefile konflux-generate-catalog PACKAGE_NAME_KONFLUX=my-operator

# Custom OpenShift version for operator-sdk
make -f scripts/catalog/Makefile konflux-validate-catalog-template-bundle OPENSHIFT_VERSION=4.13

# Bundle image customization for different operators
make -f scripts/catalog/Makefile konflux-generate-catalog-production PACKAGE_NAME_KONFLUX=my-operator
make -f scripts/catalog/Makefile konflux-generate-catalog-production QUAY_TENANT_NAME=my-tenant
make -f scripts/catalog/Makefile konflux-generate-catalog-production BUNDLE_NAME_SUFFIX=operator-bundle-4-21
make -f scripts/catalog/Makefile konflux-generate-catalog-production PRODUCTION_NAMESPACE=ubi8
```

## Example Integration

Here's an example of how to integrate in your root `Makefile`:

```makefile
# Your existing Makefile content...

# Include linting targets from submodule
include scripts/Makefile

# Custom target that depends on linting
.PHONY: ci
ci: lint
	@echo "Running CI after linting passes..."
	go test ./...
	go build ./...

# Custom linting that extends the base linting
.PHONY: lint-extended
lint-extended: lint
	@echo "Running additional linting..."
	golangci-lint run
	hadolint Dockerfile

# Download tools to a custom directory
.PHONY: install-tools
install-tools:
	$(MAKE) -f scripts/download/Makefile download-all DOWNLOAD_INSTALL_DIR=./bin

# Use tools with specific versions
.PHONY: install-legacy-tools
install-legacy-tools:
	$(MAKE) -f scripts/download/Makefile download-yq DOWNLOAD_YQ_VERSION=v4.35.2 DOWNLOAD_INSTALL_DIR=./bin
	$(MAKE) -f scripts/download/Makefile download-jq DOWNLOAD_JQ_VERSION=1.6.0 DOWNLOAD_INSTALL_DIR=./bin

# Catalog management integration
.PHONY: validate-catalog
validate-catalog:
	$(MAKE) -f scripts/catalog/Makefile konflux-validate-catalog-template-bundle
	$(MAKE) -f scripts/catalog/Makefile konflux-validate-catalog

.PHONY: generate-catalog
generate-catalog:
	$(MAKE) -f scripts/catalog/Makefile konflux-generate-catalog PACKAGE_NAME_KONFLUX=my-operator
```

## Directory Structure

When using as a submodule, the directory structure should look like:

```
your-repo/
├── Makefile                 # Your root Makefile
├── .yamllint.yaml          # YAML linting configuration (optional)
├── scripts/                # Submodule directory
│   ├── Makefile            # Main linting Makefile
│   ├── requirements.txt    # Python linting dependencies
│   ├── venv/               # Virtual environment (created automatically)
│   ├── bin/                # Default tool installation directory
│   │   ├── yq              # Downloaded tools (if using scripts)
│   │   ├── opm
│   │   ├── jq
│   │   └── operator-sdk
│   ├── catalog/            # Catalog management scripts
│   │   ├── Makefile        # Catalog-specific Makefile
│   │   ├── konflux-update-catalog-template.sh
│   │   ├── konflux-validate-related-images-production.sh
│   │   └── ...
│   └── download/           # Download scripts
│       ├── Makefile        # Download-specific Makefile
│       ├── download-yq.sh
│       ├── download-opm.sh
│       ├── download-jq.sh
│       └── download-operator-sdk.sh
└── .konflux/               # Konflux configuration (if using catalog features)
    └── catalog/
        ├── catalog-template.in.yaml
        ├── bundle.builds.in.yaml
        └── ...
```

## Environment Variables

### Linting Environment Variables
The linting targets use these environment variables (automatically configured):
- `TELCO5G_KONFLUX_DIR`: Submodule directory path
- `TELCO5G_KONFLUX_VENV`: Python virtual environment path
- `TELCO5G_KONFLUX_BIN`: Virtual environment bin directory

### Download Script Environment Variables
Download scripts and Makefiles support:
- `DOWNLOAD_INSTALL_DIR`: Custom installation directory for all tools
- `DOWNLOAD_YQ_VERSION`: Custom yq version (default: v4.45.4)
- `DOWNLOAD_OPM_VERSION`: Custom opm version (default: v1.52.0)
- `DOWNLOAD_JQ_VERSION`: Custom jq version (default: 1.7.1)
- `DOWNLOAD_OPENSHIFT_VERSION`: Custom OpenShift version for operator-sdk (default: 4.12)

### Catalog Environment Variables
Catalog scripts support:
- `CATALOG_TEMPLATE_FILE`: Path to catalog template file
- `BUNDLE_BUILDS_FILE`: Path to bundle builds file
- `CATALOG_FILE`: Path to catalog file
- `PACKAGE_NAME_KONFLUX`: Package name for Konflux operations
- `OPENSHIFT_VERSION`: OpenShift version for operator-sdk downloads
- `TOOL_DIR`: Directory for downloaded tools

#### Bundle Image Configuration Variables
- `QUAY_TENANT_NAME`: Quay tenant name (default: telco-5g-tenant)
- `BUNDLE_NAME_SUFFIX`: Bundle name suffix (default: operator-bundle-4-20)
- `PRODUCTION_NAMESPACE`: Production namespace (default: openshift4)
- `PRODUCTION_BUNDLE_NAME`: Production bundle name (default: operator-bundle)
- `QUAY_BUNDLE_IMAGE`: Full quay bundle image (constructed from above variables)
- `PRODUCTION_BUNDLE_IMAGE`: Full production bundle image (constructed from above variables)

## Benefits of Using as a Submodule

1. **Standardized Linting**: Consistent linting rules and tools across repositories
2. **Dependency Management**: Isolated Python environment with pinned linting tool versions
3. **Tool Management**: Parameterizable scripts for downloading common tools with automatic dependency resolution
4. **Catalog Management**: Konflux-specific targets for catalog operations
5. **Intelligent Version Discovery**: Automatic latest release detection for operator-sdk
6. **Cross-Platform Support**: Works on both macOS and Linux
7. **Easy Updates**: Centralized updates to linting configurations and tool versions
8. **Flexibility**: Customize install directories and tool versions per project
9. **No Conflicts**: Isolated virtual environment prevents conflicts with system tools

## Updating the Submodule

To update the submodule to the latest version:

```bash
git submodule update --remote scripts
git add scripts
git commit -m "Update scripts submodule to latest version"
```

## Customization

### Custom Linting Rules
Create a `.yamllint.yaml` file in your repository root to customize YAML linting:
```yaml
extends: default
rules:
  line-length:
    max: 150
  comments:
    min-spaces-from-content: 1
```

### Tool Versions
Pin specific tool versions using Makefile variables:
```makefile
.PHONY: install-pinned-tools
install-pinned-tools:
	$(MAKE) -f scripts/download/Makefile download-all \
		DOWNLOAD_YQ_VERSION=v4.35.2 \
		DOWNLOAD_OPM_VERSION=v1.50.0 \
		DOWNLOAD_JQ_VERSION=1.6.0 \
		DOWNLOAD_OPENSHIFT_VERSION=4.12.76 \
		DOWNLOAD_INSTALL_DIR=./tools
```

### Custom Install Locations
Install tools to project-specific directories:
```makefile
TOOL_DIR := $(PWD)/tools

.PHONY: install-project-tools
install-project-tools:
	mkdir -p $(TOOL_DIR)
	$(MAKE) -f scripts/download/Makefile download-all DOWNLOAD_INSTALL_DIR=$(TOOL_DIR)
```

### Catalog Customization
Customize catalog operations:
```makefile
.PHONY: custom-catalog-validation
custom-catalog-validation:
	$(MAKE) -f scripts/catalog/Makefile konflux-validate-catalog-template-bundle \
		CATALOG_TEMPLATE_KONFLUX=./custom-catalog-template.yaml \
		PACKAGE_NAME_KONFLUX=my-custom-operator \
		OPENSHIFT_VERSION=4.13

.PHONY: custom-catalog-production
custom-catalog-production:
	$(MAKE) -f scripts/catalog/Makefile konflux-generate-catalog-production \
		PACKAGE_NAME_KONFLUX=my-custom-operator \
		QUAY_TENANT_NAME=my-tenant \
		BUNDLE_NAME_SUFFIX=operator-bundle-4-21 \
		PRODUCTION_NAMESPACE=ubi8 \
		PRODUCTION_BUNDLE_NAME=my-operator-bundle

.PHONY: custom-bundle-images
custom-bundle-images:
	$(MAKE) -f scripts/catalog/Makefile konflux-generate-catalog-production \
		QUAY_BUNDLE_IMAGE=quay.io/my-org/my-operator-bundle:v1.0.0 \
		PRODUCTION_BUNDLE_IMAGE=registry.redhat.io/my-namespace/my-operator-bundle:v1.0.0
```

## Troubleshooting

### Linting Failures
If linting fails:
1. Check the specific linter output for details
2. Fix the reported issues in your YAML or shell scripts
3. Customize linting rules if needed (e.g., `.yamllint.yaml`)

### Virtual Environment Issues
If the Python virtual environment has issues:
```bash
make clean  # Remove the virtual environment
make venv   # Recreate it
```

### Download Script Issues
If download scripts fail:
1. Check internet connectivity
2. Verify the version exists on the project's releases or mirror
3. Ensure you have write permissions to the install directory
4. Use `--help` to verify correct usage
5. For operator-sdk, check OpenShift mirror availability

### Catalog Issues
If catalog operations fail:
1. Ensure required files exist (catalog template, bundle builds)
2. Check that tools are available (yq, opm, operator-sdk)
3. Verify OpenShift version is supported
4. Use `make help` to see available targets and variables

### Version Discovery Issues
If operator-sdk version discovery fails:
1. Check internet connectivity to OpenShift mirror
2. Verify the OpenShift version exists on the mirror
3. Try using a full version (X.Y.Z) instead of Major.Minor (X.Y)
4. Check the mirror URL: https://mirror.openshift.com/pub/openshift-v4/
