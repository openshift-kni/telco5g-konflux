# Using telco5g-konflux as a Submodule

This document explains how to integrate the `telco5g-konflux` project as a submodule in your operator repository to reuse the Konflux CI/CD targets.

## Adding as a Submodule

1. **Add the submodule to your repository:**
   ```bash
   git submodule add https://github.com/openshift-kni/telco5g-konflux.git konflux
   git submodule update --init --recursive
   ```

2. **Include the Makefile in your root Makefile:**
   ```makefile
   # Include konflux targets from submodule
   include konflux/Makefile
   ```

## Configuration Variables

The following variables can be configured in your root Makefile to customize the behavior:

### Required Variables
- `TELCO5G_KONFLUX_PACKAGE_NAME`: Your package name (default: `telco5g-konflux`)

### Optional Variables
- `TELCO5G_KONFLUX_CATALOG_TEMPLATE`: Path to catalog template file
- `TELCO5G_KONFLUX_CATALOG`: Path to generated catalog file
- `TELCO5G_KONFLUX_BUNDLE_BUILDS`: Path to bundle builds file
- `TELCO5G_KONFLUX_BUILD_PIPELINE`: Path to build pipeline file
- `TELCO5G_KONFLUX_FBC_PIPELINE`: Path to FBC pipeline file

### Bundle Naming Variables
- `TELCO5G_KONFLUX_DEV_BUNDLE_NAME`: Development bundle image name (default: `$(TELCO5G_KONFLUX_PACKAGE_NAME)-operator-bundle-4-20`)
- `TELCO5G_KONFLUX_PROD_BUNDLE_NAME`: Production bundle image name (default: `$(TELCO5G_KONFLUX_PACKAGE_NAME)-operator-bundle`)

#### Bundle Naming Examples

Different operators may use different naming conventions for their bundle images. Here are some common patterns:

```makefile
# Default naming (telco5g-konflux style)
TELCO5G_KONFLUX_DEV_BUNDLE_NAME = $(TELCO5G_KONFLUX_PACKAGE_NAME)-operator-bundle-4-20
TELCO5G_KONFLUX_PROD_BUNDLE_NAME = $(TELCO5G_KONFLUX_PACKAGE_NAME)-operator-bundle

# Version-based naming
TELCO5G_KONFLUX_DEV_BUNDLE_NAME = $(TELCO5G_KONFLUX_PACKAGE_NAME)-bundle-v1.2.3
TELCO5G_KONFLUX_PROD_BUNDLE_NAME = $(TELCO5G_KONFLUX_PACKAGE_NAME)-bundle

# OpenShift version specific naming  
TELCO5G_KONFLUX_DEV_BUNDLE_NAME = $(TELCO5G_KONFLUX_PACKAGE_NAME)-operator-bundle-4.15
TELCO5G_KONFLUX_PROD_BUNDLE_NAME = $(TELCO5G_KONFLUX_PACKAGE_NAME)-operator-bundle

# Custom naming without "operator" suffix
TELCO5G_KONFLUX_DEV_BUNDLE_NAME = $(TELCO5G_KONFLUX_PACKAGE_NAME)-bundle-dev
TELCO5G_KONFLUX_PROD_BUNDLE_NAME = $(TELCO5G_KONFLUX_PACKAGE_NAME)-bundle-prod
```

## Example Integration

Here's an example of how to integrate in your root `Makefile`:

```makefile
# Your existing Makefile content...

# Configure konflux for your project
TELCO5G_KONFLUX_PACKAGE_NAME = my-operator
TELCO5G_KONFLUX_CATALOG_TEMPLATE = .konflux/catalog/my-catalog-template.yaml
TELCO5G_KONFLUX_CATALOG = .konflux/catalog/my-operator/catalog.yaml

# Customize bundle naming if your operator uses different naming conventions
TELCO5G_KONFLUX_DEV_BUNDLE_NAME = my-operator-bundle-v1.0
TELCO5G_KONFLUX_PROD_BUNDLE_NAME = my-operator-bundle

# Include konflux targets
include konflux/Makefile

# Your custom targets that may depend on konflux targets
.PHONY: my-custom-build
my-custom-build: konflux-generate-catalog
	@echo "Building with generated catalog..."
	# Your build commands here

.PHONY: my-custom-lint
my-custom-lint: telco5g-konflux-lint
	@echo "Running additional linting..."
	# Your additional linting commands here
```

## Available Targets

### Prefixed Targets (Recommended for submodule usage)
- `telco5g-konflux-lint`: Run all linters
- `telco5g-konflux-yamllint`: Run YAML linting
- `telco5g-konflux-shellcheck`: Run shell script linting
- `telco5g-konflux-bashate`: Run bash style linting
- `telco5g-konflux-filter-unused-repos`: Filter unused yum repositories
- `telco5g-konflux-clean`: Clean generated artifacts
- `telco5g-konflux-opm`: Download OPM tool
- `telco5g-konflux-yq`: Download YQ tool

### Konflux CI/CD Targets
- `konflux-update-task-refs`: Update task image references
- `konflux-validate-catalog-template-bundle`: Validate catalog template bundle
- `konflux-validate-catalog`: Validate catalog file
- `konflux-generate-catalog`: Generate catalog for quay.io
- `konflux-generate-catalog-production`: Generate catalog for registry.redhat.io

### Legacy Targets (For backward compatibility)
- `lint`, `yamllint`, `shellcheck`, `bashate`, `clean`, `opm`, `yq`

## Directory Structure

When using as a submodule, the directory structure should look like:

```
your-operator-repo/
├── Makefile                 # Your root Makefile
├── konflux/                 # Submodule directory
│   ├── Makefile            # Konflux Makefile
│   ├── hack/               # Konflux scripts
│   ├── requirements.txt    # Python dependencies
│   └── venv/               # Virtual environment (created automatically)
├── .konflux/               # Your Konflux configuration
│   └── catalog/
│       ├── catalog-template.yaml
│       └── bundle.builds.yaml
└── .tekton/                # Your Tekton pipelines
    ├── build-pipeline.yaml
    └── fbc-pipeline.yaml
```

## Benefits of Using as a Submodule

1. **Reusability**: Share common Konflux CI/CD targets across multiple operator repositories
2. **Maintainability**: Updates to the konflux targets are centralized
3. **Consistency**: Ensures all operators use the same CI/CD patterns
4. **Isolation**: Each project can customize variables without affecting others
5. **Version Control**: Pin to specific versions of the konflux targets

## Updating the Submodule

To update the submodule to the latest version:

```bash
git submodule update --remote konflux
git add konflux
git commit -m "Update konflux submodule to latest version"
```

## Troubleshooting

### Path Issues
If you encounter path-related issues, ensure that:
- All paths use the `TELCO5G_KONFLUX_DIR` variable
- Scripts are called with `cd $(TELCO5G_KONFLUX_DIR)` prefix
- File paths are absolute or relative to the submodule directory

### Variable Conflicts
If you have variable naming conflicts:
- Use the prefixed targets (`telco5g-konflux-*`) instead of legacy targets
- Override variables in your root Makefile before including the submodule

### Tool Dependencies
Tools (opm, yq) are installed in the submodule's `bin/` directory to avoid conflicts with your project's tools.
